const std = @import("std");
const Allocator = std.mem.Allocator;
const json = std.json;
const fmt = std.fmt;
const http = std.http;
const parser = @import("parser.zig");
const f1_lt = @import("f1_live_timing.zig");

pub fn fetchStateLeaky(parent_allocator: Allocator) !f1_lt.State {
    var arena = std.heap.ArenaAllocator.init(parent_allocator);
    var allocator = arena.allocator();

    var client = http.Client{ .allocator = allocator };
    defer client.deinit();

    var uri = try std.Uri.parse("http://127.0.0.1:10101/api/graphql");
    var headers = http.Headers.init(allocator);
    defer headers.deinit();
    try headers.append("content-type", "application/json");
    // try headers.append("connection", "close");

    const query =
        \\ query {
        \\   liveTimingState {
        \\     ExtrapolatedClock
        \\     TimingData
        \\     DriverList
        \\     LapCount
        \\     TimingAppData
        \\   }
        \\   liveTimingClock {
        \\     trackTime
        \\     systemTime
        \\     paused
        \\   }
        \\ }
    ;

    var req = try client.request(.POST, uri, headers, .{});
    defer req.deinit();
    req.transfer_encoding = .chunked;

    try req.start();

    var buffered_req_writer = std.io.bufferedWriter(req.writer());
    try json.stringify(.{ .query = query }, .{}, buffered_req_writer.writer());
    try buffered_req_writer.flush();

    try req.finish();
    try req.wait();

    const resp_body = try req.reader().readAllAlloc(allocator, 10_000_000);
    defer allocator.free(resp_body);

    // std.debug.print("\n\n{s}\n\n", .{resp_body});

    const resp_parsed = try json.parseFromSliceLeaky(
        MVResponse,
        allocator,
        resp_body,
        .{ .ignore_unknown_fields = true },
    );

    var live_timing = try parseResultLeaky(allocator, resp_parsed);
    live_timing.arena = arena;
    return live_timing;
}

pub const MVResponse = struct {
    data: struct {
        liveTimingState: ?MVLiveTimingState,
        liveTimingClock: ?MVLiveTimingClock,
    },
};

const MVLiveTimingState = struct {
    ExtrapolatedClock: ?f1_lt.SessionClock.ExtrapolatedClockRaw,
    TimingData: ?struct {
        Lines: json.Value,
    },
    TimingAppData: ?struct {
        Lines: json.Value,
    },
    DriverList: json.Value,
    LapCount: ?struct {
        CurrentLap: u32,
        TotalLaps: u32,
    },
};

pub const MVLiveTimingClock = struct {
    systemTime: [:0]const u8,
    trackTime: [:0]const u8,
    /// indicates whether the client-side live timing is paused
    paused: bool,
};

fn parseResultLeaky(allocator: Allocator, resp: MVResponse) !f1_lt.State {
    const liveTimingState = resp.data.liveTimingState;

    const maybe_clock: ?f1_lt.SessionClock = val: {
        if (liveTimingState == null) break :val null;
        if (resp.data.liveTimingClock == null) break :val null;
        const liveTimingClock = resp.data.liveTimingClock.?;

        if (liveTimingState.?.ExtrapolatedClock == null) break :val null;
        const ExtrapolatedClock = liveTimingState.?.ExtrapolatedClock.?;

        const clock = f1_lt.SessionClock.parse(
            allocator,
            ExtrapolatedClock,
            liveTimingClock,
        ) catch |err| {
            std.log.err(
                "Failed to parse session clock (Remaining = {s}, Utc = {s}): {any}",
                .{ ExtrapolatedClock.Remaining, ExtrapolatedClock.Utc, err },
            );
            break :val null;
        };

        break :val clock;
    };

    const maybe_timing_data: ?f1_lt.TimingData = val: {
        if (liveTimingState == null) break :val null;
        if (liveTimingState.?.TimingData == null) break :val null;
        const Lines = liveTimingState.?.TimingData.?.Lines;
        if (Lines != .object) break :val null;

        const timing_data = f1_lt.TimingData.parseLeaky(allocator, Lines) catch |err| {
            std.log.err("Failed to parse timing data", .{});
            return err;
        };

        break :val timing_data;
    };

    const maybe_driver_list: ?f1_lt.DriverList = val: {
        if (liveTimingState == null) break :val null;
        const DriverList = liveTimingState.?.DriverList;
        if (DriverList != .object) break :val null;

        const driver_list = f1_lt.DriverList.parseLeaky(allocator, DriverList) catch |err| {
            std.log.err("Failed to parse driver list", .{});
            return err;
        };

        break :val driver_list;
    };

    const maybe_timing_app_data: ?f1_lt.TimingAppData = val: {
        if (liveTimingState == null) break :val null;
        if (liveTimingState.?.TimingAppData == null) break :val null;
        const Lines = liveTimingState.?.TimingAppData.?.Lines;
        if (Lines != .object) break :val null;

        const timing_app_data = f1_lt.TimingAppData.parseLeaky(allocator, Lines) catch |err| {
            std.log.err("Failed to parse timing app data", .{});
            return err;
        };

        break :val timing_app_data;
    };

    const LapCount = liveTimingState.?.LapCount;

    return f1_lt.State{
        .arena = null,
        .clock = maybe_clock,
        .timing_data = maybe_timing_data,
        .driver_list = maybe_driver_list,
        .lap_number = if (LapCount) |lc| lc.CurrentLap else null,
        .target_lap_count = if (LapCount) |lc| lc.TotalLaps else null,
        .timing_app_data = maybe_timing_app_data,
    };
}
