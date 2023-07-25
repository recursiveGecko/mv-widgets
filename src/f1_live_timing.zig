const std = @import("std");
const ArenaAllocator = std.heap.ArenaAllocator;
const Allocator = std.mem.Allocator;
const json = std.json;
const fmt = std.fmt;
const mecha = @import("mecha");
const raylib = @import("raylib");
const parser = @import("parser.zig");
const multiviewer = @import("multiviewer.zig");

pub const MsOrLaps = union(enum) {
    ms: i32,
    laps: i32,

    pub fn parse(allocator: Allocator, text: ?[:0]const u8) ?MsOrLaps {
        if (text == null) return null;

        const lap_parser = comptime mecha.combine(.{
            mecha.int(i32, .{ .base = 10, .parse_sign = true }),
            mecha.ascii.whitespace.many(.{}).opt().discard(),
            mecha.ascii.char('L').discard(),
            mecha.eos,
        });

        const sec: f64 = fmt.parseFloat(f64, text.?) catch {
            const parsed_laps = lap_parser.parse(allocator, text.?) catch return null;
            return .{ .laps = parsed_laps.value };
        };

        return .{ .ms = @intFromFloat(sec * 1000) };
    }
};

pub const TyreCompound = enum {
    soft,
    medium,
    hard,
    inter,
    wet,
    unknown,

    pub fn fromString(str: []const u8) @This() {
        const map = .{
            .{ "SOFT", .soft },
            .{ "MEDIUM", .medium },
            .{ "HARD", .hard },
            .{ "INTERMEDIATE", .inter },
            .{ "WET", .wet },
        };

        inline for (map) |pair| {
            if (std.mem.eql(u8, pair[0], str)) return pair[1];
        }

        return .unknown;
    }

    pub fn toColor(this: @This()) raylib.Color {
        return switch (this) {
            .soft => raylib.RED,
            .medium => raylib.YELLOW,
            .hard => raylib.WHITE,
            .inter => raylib.GREEN,
            .wet => raylib.BLUE,
            .unknown => raylib.GRAY,
        };
    }
};

pub const State = struct {
    arena: ?ArenaAllocator,

    clock: ?SessionClock,
    timing_data: ?TimingData,
    timing_app_data: ?TimingAppData,
    driver_list: ?DriverList,
    session_info: ?SessionInfo,
    lap_number: ?u32,
    target_lap_count: ?u32,

    pub fn getInfoForDriver(state: *const State, driver_number: u32) ?*const DriverList.DriverInfo {
        if (state.driver_list) |list| {
            for (list.drivers) |*driver| {
                if (driver.driver_number == driver_number) return driver;
            }
            return null;
        } else {
            return null;
        }
    }

    pub fn getTimingAppDataForDriver(state: *const State, driver_number: u32) ?*const TimingAppData.Driver {
        if (state.timing_app_data) |data| {
            for (data.drivers) |*driver| {
                if (driver.driver_number == driver_number) return driver;
            }
            return null;
        } else {
            return null;
        }
    }

    pub fn deinit(state: *State) void {
        if (state.arena) |arena| {
            arena.deinit();
        } else {
            std.log.err("F1LiveTiming.State.deinit() called but arena is missing", .{});
        }
    }
};

pub const TimingData = struct {
    drivers: []Driver,

    pub const TimingDataRaw = struct {
        Lines: json.Value,
        SessionPart: ?u32 = null,
    };

    pub const Driver = struct {
        driver_number: u32,
        position: u32,
        gap_to_leader: ?MsOrLaps,
        gap_ahead: ?MsOrLaps,
        best_lap_time_ms: ?u32,
        has_fastest_lap: bool = false,
        in_pit: bool,
    };

    const DriverRaw = struct {
        RacingNumber: [:0]const u8,
        Line: u32,
        GapToLeader: ?[:0]const u8 = null,
        TimeDiffToPositionAhead: ?[:0]const u8 = null,
        TimeDiffToFastest: ?[:0]const u8 = null,
        IntervalToPositionAhead: ?struct {
            Value: [:0]const u8,
        } = null,
        BestLapTime: ?struct {
            Value: [:0]const u8,
        } = null,
        Stats: ?[]struct {
            TimeDiffToFastest: [:0]const u8,
            TimeDifftoPositionAhead: [:0]const u8,
        } = null,
        InPit: bool,
    };

    const Sort = struct {
        pub fn byPositionAsc(ctx: void, lhs: Driver, rhs: Driver) bool {
            _ = ctx;
            return lhs.position < rhs.position;
        }
    };

    pub fn sortByPosition(this: *@This()) void {
        std.mem.sort(Driver, this.drivers, {}, Sort.byPositionAsc);
    }

    /// Parses the timing data which is a JSON object with driver numbers as keys
    /// Caller should call this function with an Arena allocator or similar and free
    /// the memory afterwards.
    pub fn parseLeaky(allocator: Allocator, timing_data: TimingDataRaw) !@This() {
        const Lines = timing_data.Lines;
        if (Lines != .object) return error.InvalidDataFormat;

        const items_raw: []json.Value = Lines.object.values();
        var drivers: []Driver = try allocator.alloc(Driver, items_raw.len);

        for (items_raw, 0..) |raw, i| {
            const raw_parsed = json.parseFromValueLeaky(DriverRaw, allocator, raw, .{ .ignore_unknown_fields = true }) catch |err| {
                const json_str = try json.stringifyAlloc(allocator, raw, .{});
                defer allocator.free(json_str);

                std.log.err("Failed to parse TimingData entry: {s}", .{json_str});
                return err;
            };

            const gap_to_leader = val: {
                // race
                if (raw_parsed.GapToLeader != null) {
                    const gap = MsOrLaps.parse(allocator, raw_parsed.GapToLeader);
                    if (gap != null) break :val gap;
                }
                // practice
                if (raw_parsed.TimeDiffToFastest != null) {
                    const gap = MsOrLaps.parse(allocator, raw_parsed.TimeDiffToFastest);
                    if (gap != null) break :val gap;
                }
                // qualifying
                if (timing_data.SessionPart == null or raw_parsed.Stats == null) break :val null;
                if (raw_parsed.Stats.?.len < timing_data.SessionPart.?) break :val null;
                const index = timing_data.SessionPart.? - 1;
                break :val MsOrLaps.parse(allocator, raw_parsed.Stats.?[index].TimeDiffToFastest);
            };
            const gap_ahead = val: {
                // race
                if (raw_parsed.IntervalToPositionAhead != null) {
                    const interval_ahead = MsOrLaps.parse(allocator, raw_parsed.IntervalToPositionAhead.?.Value);
                    if (interval_ahead != null) break :val interval_ahead;
                }
                // practice
                if (raw_parsed.TimeDiffToPositionAhead != null) {
                    const gap = MsOrLaps.parse(allocator, raw_parsed.TimeDiffToPositionAhead);
                    if (gap != null) break :val gap;
                }
                // qualifying
                if (timing_data.SessionPart == null or raw_parsed.Stats == null) break :val null;
                if (raw_parsed.Stats.?.len < timing_data.SessionPart.?) break :val null;
                const index = timing_data.SessionPart.? - 1;
                break :val MsOrLaps.parse(allocator, raw_parsed.Stats.?[index].TimeDifftoPositionAhead);
            };

            const best_lap_time_ms = val: {
                if (raw_parsed.BestLapTime == null) break :val null;
                break :val parser.parseLapTime(allocator, raw_parsed.BestLapTime.?.Value) catch null;
            };

            drivers[i] = Driver{
                .driver_number = try fmt.parseInt(u32, raw_parsed.RacingNumber, 10),
                .position = raw_parsed.Line,
                .in_pit = raw_parsed.InPit,
                .gap_to_leader = gap_to_leader,
                .gap_ahead = gap_ahead,
                .best_lap_time_ms = best_lap_time_ms,
            };
        }

        return .{
            .drivers = drivers,
        };
    }
};

pub const TimingAppData = struct {
    drivers: []Driver,

    const Driver = struct {
        driver_number: u32,
        current_tyre: TyreCompound,
    };

    const DriverRaw = struct {
        RacingNumber: [:0]const u8,
        Stints: []const StintRaw,
    };

    const StintRaw = struct {
        Compound: []const u8,
    };

    /// Parses the tyre data list which is a JSON object with driver numbers as keys
    /// Caller should call this function with an Arena allocator or similar and free
    /// the memory afterwards.
    pub fn parseLeaky(allocator: Allocator, json_data: json.Value) !@This() {
        if (json_data != .object) return error.InvalidDataFormat;

        const items_raw = json_data.object.values();
        var drivers: []Driver = try allocator.alloc(Driver, items_raw.len);

        for (items_raw, 0..) |raw, i| {
            const raw_parsed = json.parseFromValueLeaky(DriverRaw, allocator, raw, .{ .ignore_unknown_fields = true }) catch |err| {
                const json_str = try json.stringifyAlloc(allocator, raw, .{});
                defer allocator.free(json_str);

                std.log.err("Failed to parse TimingAppData entry: {s}", .{json_str});
                return err;
            };

            const last_stint: ?StintRaw = if (raw_parsed.Stints.len > 0) raw_parsed.Stints[raw_parsed.Stints.len - 1] else null;
            const current_tyre: TyreCompound = if (last_stint) |s| TyreCompound.fromString(s.Compound) else .unknown;

            drivers[i] = Driver{
                .driver_number = try fmt.parseInt(u32, raw_parsed.RacingNumber, 10),
                .current_tyre = current_tyre,
            };
        }

        return .{
            .drivers = drivers,
        };
    }
};

pub const DriverList = struct {
    drivers: []DriverInfo,

    const DriverInfo = struct {
        driver_number: u32,
        // position: u32,
        tla: [:0]const u8,
        team_color: raylib.Color,
    };

    const ItemRaw = struct {
        RacingNumber: [:0]const u8,
        Tla: [:0]const u8,
        TeamColour: [:0]const u8,
    };

    /// Parses the driver list which is a JSON object with driver numbers as keys
    /// Caller should call this function with an Arena allocator or similar and free
    /// the memory afterwards.
    pub fn parseLeaky(allocator: Allocator, json_data: json.Value) !@This() {
        if (json_data != .object) return error.InvalidDataFormat;

        const items_raw = json_data.object.values();
        var drivers: []DriverInfo = try allocator.alloc(DriverInfo, items_raw.len);

        for (items_raw, 0..) |raw, i| {
            const raw_parsed = try json.parseFromValueLeaky(ItemRaw, allocator, raw, .{ .ignore_unknown_fields = true });

            drivers[i] = DriverInfo{
                .driver_number = try fmt.parseInt(u32, raw_parsed.RacingNumber, 10),
                .tla = raw_parsed.Tla,
                .team_color = parser.parseHexColor(allocator, raw_parsed.TeamColour) catch raylib.BEIGE,
            };
        }

        return .{
            .drivers = drivers,
        };
    }
};

pub const SessionInfo = struct {
    name: [:0]const u8,
    session_type: Type,

    pub const Type = enum {
        practice,
        qualifying,
        race,
        unknown,

        pub fn parse(str: [:0]const u8) @This() {
            const map = .{
                .{ "Practice", .practice },
                .{ "Qualifying", .qualifying },
                .{ "Race", .race },
            };
            inline for (map) |pair| {
                if (std.mem.eql(u8, pair[0], str)) return pair[1];
            }
            return .unknown;
        }
    };

    pub const Raw = struct {
        Type: [:0]const u8,
        Meeting: struct {
            Name: [:0]const u8,
        },
    };

    pub fn parse(allocator: Allocator, data: Raw) !@This() {
        _ = allocator;

        return .{
            .name = data.Meeting.Name,
            .session_type = Type.parse(data.Type),
        };
    }
};

pub const SessionClock = struct {
    remaining_ms: i64,
    /// Track time when the clock came into effect (e.g. start of extrapolation)
    track_time_start: i64,
    /// Track time at given `system_time`
    track_time: i64,
    system_time: i64,
    /// The session is active, clock should be extrapolated from `track_time_now`
    is_extrapolating: bool,
    /// Whether track_time should NOT be extrapolated from system_time (MV LiveTiming is paused)
    system_paused: bool,

    pub const ExtrapolatedClockRaw = struct {
        Utc: [:0]const u8,
        Remaining: [:0]const u8,
        Extrapolating: bool,
    };

    pub fn parse(
        allocator: Allocator,
        extrapolated_clock_raw: ExtrapolatedClockRaw,
        mv_live_timing_clock: multiviewer.MVLiveTimingClock,
    ) !@This() {
        // Parse the remaining clock, e.g. 01:49:41
        const remaining = try parser.parseClock(allocator, extrapolated_clock_raw.Remaining);
        var remaining_sec: u32 = remaining.totalSeconds();

        // Parse the track time associated with remaining_ms (ISO-8601)
        const track_time_start: i64 = val: {
            const date_time = try parser.parseISO8601(allocator, extrapolated_clock_raw.Utc);
            break :val @intCast(date_time.toTimestamp());
        };

        // Parse the track time
        const track_time: i64 = @intFromFloat(
            try fmt.parseFloat(f64, mv_live_timing_clock.trackTime),
        );
        // local system time that corresponds to track_time
        const system_time: i64 = @intFromFloat(
            try fmt.parseFloat(f64, mv_live_timing_clock.systemTime),
        );

        return @This(){
            .remaining_ms = remaining_sec * 1000,
            .is_extrapolating = extrapolated_clock_raw.Extrapolating,
            .track_time_start = track_time_start,
            .track_time = track_time,
            .system_time = system_time,
            .system_paused = mv_live_timing_clock.paused,
        };
    }

    pub fn remainingMs(this: @This()) u64 {
        const track_time_now = val: {
            if (this.system_paused) break :val this.track_time;
            break :val this.track_time + std.time.milliTimestamp() - this.system_time;
        };
        if (this.is_extrapolating) {
            const track_time_elapsed = track_time_now - this.track_time_start;
            return @intCast(@max(0, this.remaining_ms - track_time_elapsed));
        } else {
            return @intCast(@max(0, this.remaining_ms));
        }
    }

    pub fn formatClock(this: @This(), allocator: Allocator) ![:0]const u8 {
        const ms = this.remainingMs();
        const hours = @divTrunc(ms, 3600 * 1000);
        const minutes = @divTrunc(ms, 60 * 1000) - hours * 60;
        const rem_ms: f64 = @floatFromInt(@rem(ms, 60 * 1000));
        const frac_seconds: f64 = rem_ms / 1000.0;
        const seconds: u32 = @intFromFloat(@ceil(frac_seconds));

        if (hours <= 0) {
            return fmt.allocPrintZ(allocator, "{d:0>2}:{d:0>2}", .{ minutes, seconds });
        } else {
            return fmt.allocPrintZ(allocator, "{d: >2}:{d:0>2}:{d:0>2}", .{ hours, minutes, seconds });
        }
    }
};
