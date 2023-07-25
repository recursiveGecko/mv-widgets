const std = @import("std");
const Allocator = std.mem.Allocator;
const mem = std.mem;
const mecha = @import("mecha");
const raylib = @import("raylib");
const DateTime = @import("zig-datetime").Datetime;
const Timezone = @import("zig-datetime").Timezone;
const timezones = @import("zig-datetime").timezones;

pub fn parseISO8601(allocator: Allocator, iso: []const u8) !DateTime {
    const iso_parser = comptime val: {
        const num = mecha.int(u32, .{ .parse_sign = false });
        const date_sep = mecha.ascii.char('-').discard();
        const time_sep = mecha.ascii.char(':').discard();

        break :val mecha.combine(.{
            num, //year
            date_sep,
            num, //month
            date_sep,
            num, //day
            mecha.ascii.char('T').discard(),
            num, //hour
            time_sep,
            num, //minute
            time_sep,
            num, //second
            mecha.combine(.{
                mecha.ascii.char('.').discard(),
                mecha.int(u32, .{ .parse_sign = false, .max_digits = 3 }), // millisecond
            }).opt(),
            mecha.rest, //UTC offset
        });
    };

    const result = try iso_parser.parse(allocator, iso);
    const fields = result.value;
    const f = fields;

    const nanosecond = if (f[6]) |ms| ms * 1_000_000 else 0;
    const timezone: *const Timezone = val: {
        const parsed_tz: []const u8 = f[7];

        if (mem.eql(u8, parsed_tz, "Z")) break :val &timezones.UTC;
        if (mem.eql(u8, parsed_tz, "+00")) break :val &timezones.UTC;
        if (mem.eql(u8, parsed_tz, "+00:00")) break :val &timezones.UTC;
        if (mem.eql(u8, parsed_tz, "+0000")) break :val &timezones.UTC;

        return error.InvalidTimezone;
    };

    return DateTime.create(f[0], f[1], f[2], f[3], f[4], f[5], nanosecond, timezone);
}

pub const Clock = struct {
    hours: u32,
    minutes: u32,
    seconds: u32,

    pub fn totalSeconds(this: @This()) u32 {
        return this.seconds + this.minutes * 60 + this.hours * 3600;
    }
};

/// Parse colon-delimited clock, either `mm:ss` or `hh:mm:ss`
pub fn parseClock(allocator: Allocator, clock_str: []const u8) !Clock {
    const clock_parser = comptime mecha.many(
        mecha.int(u32, .{ .base = 10, .max_digits = 2, .parse_sign = false }),
        .{ .min = 1, .max = 3, .separator = mecha.ascii.char(':').discard() },
    );

    const clock_parse_result = (try clock_parser.parse(allocator, clock_str)).value;
    var n_slots = clock_parse_result.len;

    var seconds = if (n_slots >= 1) clock_parse_result[n_slots - 1] else 0;
    var minutes = if (n_slots >= 2) clock_parse_result[n_slots - 2] else 0;
    var hours = if (n_slots >= 3) clock_parse_result[n_slots - 3] else 0;

    return .{
        .hours = hours,
        .minutes = minutes,
        .seconds = seconds,
    };
}

/// Parser F1-formatted lap time, e.g. 1:08.124
pub fn parseLapTime(allocator: Allocator, time_str: []const u8) !u32 {
    const lap_time_parser = comptime mecha.combine(.{
        mecha.int(u32, .{.parse_sign = false}),
        mecha.ascii.char(':').discard(),
        mecha.int(u32, .{.parse_sign = false}),
        mecha.ascii.char('.').discard(),
        mecha.ascii.digit(10).many(.{}),
        mecha.eos,
    });

    const clock_parse_result = (try lap_time_parser.parse(allocator, time_str)).value;

    const minutes = clock_parse_result[0];
    const seconds = clock_parse_result[1];
    const ms_str = try std.fmt.allocPrint(allocator, "0.{s}", .{clock_parse_result[2]});
    defer allocator.free(ms_str);
    
    const ms_f = (try std.fmt.parseFloat(f64, ms_str)) * 1000.0;
    const ms: u32 = @intFromFloat(ms_f);

    return minutes * 60_000 + seconds * 1000 + ms;
}

pub fn parseHexColor(allocator: Allocator, color_str: []const u8) !raylib.Color {
    const color_parser = comptime mecha.combine(.{
        mecha.ascii.char('#').opt().discard(),
        mecha.int(u8, .{ .base = 16, .max_digits = 2 }),
        mecha.int(u8, .{ .base = 16, .max_digits = 2 }),
        mecha.int(u8, .{ .base = 16, .max_digits = 2 }),
        mecha.int(u8, .{ .base = 16, .max_digits = 2 }).opt(),
        mecha.eos,
    });

    const result = (try color_parser.parse(allocator, color_str)).value;

    return raylib.Color{
        .r = result[0],
        .g = result[1],
        .b = result[2],
        .a = result[3] orelse 0xFF,
    };
}
