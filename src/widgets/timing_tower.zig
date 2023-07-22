const std = @import("std");
const fmt = std.fmt;
const Allocator = std.mem.Allocator;
const raylib = @import("raylib");
const raygui = @import("raygui");
const Window = @import("../Window.zig");
const config = @import("../config.zig");
const fonts = @import("../fonts.zig");

pub const ColumnType = enum { position, tla, best_lap, next_gap, lead_gap };

pub const Column = struct {
    col_type: ColumnType,
    x_pos: f32,
    label: ?[:0]const u8,
    label_x_pos: ?f32,
};

pub const RenderOpts = struct {
    columns: []const Column,
    offset_y: i32,
    el_index: i32,
    el_count: i32,
    row_height: i32,
    content_height: i32,
    content_height_f: f32,
    padding_top: i32,
    padding_bottom: i32,
    font: raylib.Font,
    char_width: f32,
};

pub const TyreCompound = enum {
    soft,
    medium,
    hard,
    inter,
    wet,

    pub fn toColor(this: @This()) raylib.Color {
        return switch (this) {
            .soft => raylib.RED,
            .medium => raylib.YELLOW,
            .hard => raylib.WHITE,
            .inter => raylib.GREEN,
            .wet => raylib.BLUE,
        };
    }
};

pub const DriverData = struct {
    position: u32,
    tla: [:0]const u8,
    next_gap_ms: ?i32 = null,
    lead_gap_ms: ?i32 = null,
    best_lap_time_ms: ?i32 = null,
    in_pit: bool = false,
    fastest_lap: bool = false,
    current_tyre: TyreCompound,
};

pub const SessionData = struct {
    drivers: []const DriverData,
    lap_number: ?u32,
    target_lap_count: ?u32,
    session_clock_ms: ?i32,
};

var off_white: raylib.Color = raylib.Color{ .r = 220, .g = 220, .b = 220, .a = 255 };

const mock_drivers = val: {
    var _drivers: [20]DriverData = undefined;
    var rand = std.rand.Xoroshiro128.init(0);

    for (&_drivers, 1..) |*driver, pos| {
        driver.* = DriverData{
            .position = pos,
            .tla = "AAA",
            .lead_gap_ms = @rem(rand.next(), 60_000),
            .next_gap_ms = @rem(rand.next(), 13_000),
            .best_lap_time_ms = 80_000 + @rem(rand.next(), 3_000),
            .fastest_lap = pos == 5,
            .current_tyre = @enumFromInt(@rem(rand.next(), 3)),
        };
    }

    break :val _drivers;
};

const column_configs = .{
    .quali = &[_]Column{
        .{ .col_type = .position, .label = null, .label_x_pos = null, .x_pos = 1 },
        .{ .col_type = .tla, .label = "Driver", .label_x_pos = 1.5, .x_pos = 4.5 },
        .{ .col_type = .best_lap, .label = "Best", .label_x_pos = 10, .x_pos = 10 },
        .{ .col_type = .next_gap, .label = "Delta", .label_x_pos = 19, .x_pos = 19 },
    },
    .race = &[_]Column{
        .{ .col_type = .position, .label = null, .label_x_pos = null, .x_pos = 1 },
        .{ .col_type = .tla, .label = "Driver", .label_x_pos = 1.5, .x_pos = 4.5 },
        .{ .col_type = .next_gap, .label = "Gap", .label_x_pos = 12, .x_pos = 10 },
        .{ .col_type = .lead_gap, .label = "Lead", .label_x_pos = 17, .x_pos = 17 },
    },
};

pub fn render(allocator: Allocator, window: *Window) !void {
    _ = window;

    const session_data = SessionData{
        .drivers = &mock_drivers,
        .lap_number = 15,
        .target_lap_count = 65,
        .session_clock_ms = 3854_000,
    };

    const render_height_f: f32 = @floatFromInt(raylib.GetRenderHeight());
    const rows_offset_y: i32 = @intFromFloat(render_height_f * 0.1);

    const columns = column_configs.race;

    // Pre-calculate the layout for rows
    const total_h = raylib.GetRenderHeight() - rows_offset_y;
    const count_i32: i32 = @intCast(session_data.drivers.len);
    const row_height: i32 = @divFloor(total_h, count_i32);
    const row_height_f: f32 = @floatFromInt(row_height);

    const padding_top_f: f32 = row_height_f * 0.2;
    const padding_bottom_f: f32 = row_height_f * 0.2;
    const padding_bottom: i32 = @intFromFloat(padding_bottom_f);
    const content_height: i32 = @intFromFloat(row_height_f - padding_top_f - padding_bottom_f);
    const content_height_f: f32 = @floatFromInt(content_height);

    const font = fonts.getFont(.mono, content_height);
    const char_width = raylib.MeasureTextEx(font, "X", @floatFromInt(content_height), 0).x;

    // Render header
    for (columns) |col| {
        if (col.label != null and col.label_x_pos != null) {
            const x_pos_f: f32 = char_width * col.label_x_pos.?;
            const y_pos_f: f32 = @floatFromInt(rows_offset_y - content_height - padding_bottom);

            raylib.DrawTextEx(
                font,
                col.label.?.ptr,
                .{ .x = x_pos_f, .y = y_pos_f },
                @floatFromInt(content_height),
                0,
                off_white,
            );
        }
    }

    var first_top_el = true;
    // Render lap counter and clock
    if (session_data.lap_number != null and session_data.target_lap_count != null) {
        first_top_el = false;

        const x_pos_f: f32 = char_width;
        const y_pos_f: f32 = char_width;

        const lap_text = fmt.allocPrintZ(
            allocator,
            "Lap {d}/{d}",
            .{ session_data.lap_number.?, session_data.target_lap_count.? },
        ) catch unreachable;

        const large_content_height: f32 = 1.3 * content_height_f;
        const large_font = fonts.getFont(.mono, @intFromFloat(large_content_height));

        raylib.DrawTextEx(
            large_font,
            lap_text.ptr,
            .{ .x = x_pos_f, .y = y_pos_f },
            large_content_height,
            0,
            off_white,
        );
    }

    if (session_data.session_clock_ms != null and (first_top_el or session_data.session_clock_ms.? < 3600_000)) {
        const x_pos_f: f32 = if (first_top_el) char_width else char_width * 13 * 1.3;
        const y_pos_f: f32 = if (first_top_el) char_width else char_width * 1.3;

        const clock_text = allocPrintClock(allocator, session_data.session_clock_ms);

        const large_content_height: f32 = if (first_top_el) 1.3 * content_height_f else 1.2 * content_height_f;
        const large_font = fonts.getFont(.mono, @intFromFloat(large_content_height));

        raylib.DrawTextEx(
            large_font,
            clock_text.ptr,
            .{ .x = x_pos_f, .y = y_pos_f },
            large_content_height,
            0,
            off_white,
        );
    }

    // Render drivers

    for (session_data.drivers, 0..) |driver, i| {
        const render_opts = RenderOpts{
            .columns = columns,
            .el_index = @intCast(i),
            .el_count = session_data.drivers.len,
            .offset_y = rows_offset_y,
            .row_height = row_height,
            .content_height = content_height,
            .content_height_f = content_height_f,
            .padding_top = @intFromFloat(padding_top_f),
            .padding_bottom = @intFromFloat(padding_bottom_f),
            .font = font,
            .char_width = char_width,
        };
        try renderDriver(allocator, driver, render_opts);
    }
}

fn renderDriver(
    allocator: Allocator,
    driver: DriverData,
    render_opts: RenderOpts,
) !void {
    const padding_top_f: f32 = @floatFromInt(render_opts.padding_top);

    const y = render_opts.offset_y + render_opts.el_index * render_opts.row_height;
    const y_f: f32 = @floatFromInt(y);
    const y_content: f32 = y_f + padding_top_f;

    for (render_opts.columns) |col| {
        const col_type = col.col_type;

        const text: [:0]const u8 = switch (col_type) {
            .position => fmt.allocPrintZ(allocator, "{d:>2}.", .{driver.position}) catch unreachable,
            .tla => driver.tla,
            .best_lap => allocPrintLap(allocator, driver.best_lap_time_ms),
            .next_gap => allocPrintDelta(allocator, driver.next_gap_ms, false),
            .lead_gap => allocPrintDelta(allocator, driver.lead_gap_ms, true),
        };

        // Change color depending on the column and the data contained
        var color: raylib.Color = off_white;
        if (col_type == .next_gap and driver.next_gap_ms != null) {
            if (driver.next_gap_ms.? < 2_000) {
                color = raylib.GOLD;
            }
            if (driver.next_gap_ms.? < 1_000) {
                color = raylib.RED;
            }
        }
        if (col_type == .position) {
            color = raylib.GRAY;
        }
        if (driver.fastest_lap and (col_type == .tla or col_type == .position)) {
            color = raylib.Color{ .r = 190, .g = 0, .b = 255 };
        }

        const x_pos_f: f32 = render_opts.char_width * col.x_pos;

        raylib.DrawTextEx(
            render_opts.font,
            text.ptr,
            .{ .x = x_pos_f, .y = y_content },
            @floatFromInt(render_opts.content_height),
            0,
            color,
        );

        if (col_type == .position) {
            raylib.DrawRectangle(
                @intFromFloat(@max(0, x_pos_f - 1 * render_opts.char_width)),
                @intFromFloat(y_content + 0.6 * render_opts.char_width),
                @intFromFloat(@max(3, 0.4 * render_opts.char_width)),
                @intFromFloat(render_opts.content_height_f - 1.2 * render_opts.char_width),
                driver.current_tyre.toColor(),
            );
        }
    }
}

fn allocPrintDelta(allocator: Allocator, ms_or_null: ?i32, only_tenths: bool) [:0]const u8 {
    if (ms_or_null != null) {
        var ms: i32 = ms_or_null.?;
        ms = if (ms < 0) -ms else ms;

        const full: u32 = @intCast(@divTrunc(ms, 1000));

        if (only_tenths) {
            const frac: u32 = @intCast(@rem(@divTrunc(ms, 100), 10));
            return std.fmt.allocPrintZ(allocator, "{d: >2}.{d:0>1}", .{ full, frac }) catch unreachable;
        } else {
            const frac: u32 = @intCast(@rem(@divTrunc(ms, 10), 100));
            return std.fmt.allocPrintZ(allocator, "{d: >2}.{d:0>2}", .{ full, frac }) catch unreachable;
        }
    } else {
        return "/";
    }
}

fn allocPrintLap(allocator: Allocator, ms_or_null: ?i32) [:0]const u8 {
    if (ms_or_null != null) {
        var ms: i32 = ms_or_null.?;
        ms = if (ms < 0) -ms else ms;

        const min: u32 = @intCast(@divTrunc(ms, 60_000));
        const sec: u32 = @intCast(@divTrunc(@rem(ms, 60_000), 1000));
        const frac: u32 = @intCast(@rem(@divTrunc(ms, 10), 100));

        return std.fmt.allocPrintZ(allocator, "{d}:{d:0>2}.{d:0>2}", .{ min, sec, frac }) catch unreachable;
    } else {
        return "N/A";
    }
}

fn allocPrintClock(allocator: Allocator, ms_or_null: ?i32) [:0]const u8 {
    if (ms_or_null != null) {
        var ms: i32 = ms_or_null.?;
        ms = if (ms < 0) 0 else ms;

        const min: u32 = @intCast(@divTrunc(ms, 60_000));
        const sec: u32 = @intCast(@divTrunc(@rem(ms, 60_000), 1000));

        return std.fmt.allocPrintZ(allocator, "{d: >2}:{d:0>2}", .{ min, sec }) catch unreachable;
    } else {
        return "?:??";
    }
}
