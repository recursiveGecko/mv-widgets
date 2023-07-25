const std = @import("std");
const fmt = std.fmt;
const Allocator = std.mem.Allocator;
const raylib = @import("raylib");
const raygui = @import("raygui");
const Window = @import("../Window.zig");
const config = @import("../config.zig");
const fonts = @import("../fonts.zig");
const f1_lt = @import("../f1_live_timing.zig");

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

var off_white: raylib.Color = raylib.Color{ .r = 220, .g = 220, .b = 220, .a = 255 };

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

const This = @This();
allocator: Allocator,

pub fn init(allocator: Allocator) !*This {
    var this = try allocator.create(This);
    this.* = .{
        .allocator = allocator,
    };
    return this;
}

pub fn deinit(this: *This) void {
    this.allocator.destroy(this);
}

pub fn initialDimensions(this: *This) raylib.RectangleI {
    _ = this;
    return .{
        .x = 0,
        .y = 0,
        .width = 300,
        .height = 800,
    };
}

pub fn windowTitle(this: *This) [:0]const u8 {
    _ = this;
    return "Timing Tower";
}

pub fn render(this: *This, frame_allocator: Allocator, window: *Window, lt_state: *f1_lt.State) !void {
    _ = this;
    _ = window;
    if (lt_state.timing_data == null or lt_state.driver_list == null) return;

    lt_state.timing_data.?.sortByPosition();

    const render_height_f: f32 = @floatFromInt(raylib.GetRenderHeight());
    const rows_offset_y: i32 = @intFromFloat(render_height_f * 0.1);

    const columns = column_configs.race;

    // Pre-calculate the layout for rows
    const total_h = raylib.GetRenderHeight() - rows_offset_y;
    const driver_count_i32: i32 = @intCast(lt_state.timing_data.?.drivers.len);
    const row_height: i32 = @divFloor(total_h, driver_count_i32);
    const row_height_f: f32 = @floatFromInt(row_height);

    const padding_top_f: f32 = row_height_f * 0.2;
    const padding_bottom_f: f32 = row_height_f * 0.2;
    const padding_bottom: i32 = @intFromFloat(padding_bottom_f);
    const content_height: i32 = @intFromFloat(row_height_f - padding_top_f - padding_bottom_f);
    const content_height_f: f32 = @floatFromInt(content_height);

    const font = fonts.getFont(.mono, content_height);
    const char_width = raylib.MeasureTextEx(font, "X", @floatFromInt(content_height), 0).x;

    const xl_scale: f32 = 1.3;
    const lg_scale: f32 = 1.15;

    // Render lap counter and clock
    var first_top_el = true;
    if (lt_state.lap_number != null and lt_state.target_lap_count != null) {
        first_top_el = false;

        const x_pos_f: f32 = char_width;
        const y_pos_f: f32 = char_width;

        const lap_text = fmt.allocPrintZ(
            frame_allocator,
            "Lap {d}/{d}",
            .{ lt_state.lap_number.?, lt_state.target_lap_count.? },
        ) catch unreachable;

        const large_content_height: f32 = xl_scale * content_height_f;
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
    if (lt_state.clock != null and (first_top_el or lt_state.clock.?.remainingMs() < 3600_000)) {
        const x_pos_f: f32 = if (first_top_el) char_width else char_width * 12 * xl_scale;
        const y_pos_f: f32 = if (first_top_el) char_width else char_width * xl_scale;

        const clock_text = try lt_state.clock.?.formatClock(frame_allocator);

        const large_content_height: f32 = if (first_top_el) xl_scale * content_height_f else lg_scale * content_height_f;
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

    // Render drivers
    for (lt_state.timing_data.?.drivers, 0..) |driver, i| {
        const render_opts = RenderOpts{
            .columns = columns,
            .el_index = @intCast(i),
            .el_count = driver_count_i32,
            .offset_y = rows_offset_y,
            .row_height = row_height,
            .content_height = content_height,
            .content_height_f = content_height_f,
            .padding_top = @intFromFloat(padding_top_f),
            .padding_bottom = @intFromFloat(padding_bottom_f),
            .font = font,
            .char_width = char_width,
        };
        try renderDriver(frame_allocator, driver, lt_state, render_opts);
    }
}

fn renderDriver(
    frame_allocator: Allocator,
    driver: f1_lt.TimingData.Driver,
    lt_state: *f1_lt.State,
    render_opts: RenderOpts,
) !void {
    const padding_top_f: f32 = @floatFromInt(render_opts.padding_top);

    const driver_info = lt_state.getInfoForDriver(driver.driver_number);
    const driver_stint_data = lt_state.getTimingAppDataForDriver(driver.driver_number);

    const y = render_opts.offset_y + render_opts.el_index * render_opts.row_height;
    const y_f: f32 = @floatFromInt(y);
    const y_content: f32 = y_f + padding_top_f;

    for (render_opts.columns) |col| {
        const col_type = col.col_type;

        var text: [:0]const u8 = switch (col_type) {
            .position => fmt.allocPrintZ(frame_allocator, "{d:>2}.", .{driver.position}) catch unreachable,
            .tla => if (driver_info) |x| x.tla else "?",
            .best_lap => allocPrintLap(frame_allocator, driver.best_lap_time_ms),
            .next_gap => allocPrintDelta(frame_allocator, driver.gap_ahead, false),
            .lead_gap => allocPrintDelta(frame_allocator, driver.gap_to_leader, true),
        };

        // Change color depending on the column and the data contained
        var text_color: raylib.Color = off_white;
        if (col_type == .next_gap and driver.gap_ahead != null and driver.gap_ahead.? == .ms) {
            if (driver.gap_ahead.?.ms < 2_000) {
                text_color = raylib.GOLD;
            }
            if (driver.gap_ahead.?.ms < 1_000) {
                text_color = raylib.RED;
            }
        }
        if (col_type == .position) {
            text_color = raylib.GRAY;
        }
        if (driver.has_fastest_lap and col_type == .position) {
            text_color = raylib.Color{ .r = 190, .g = 0, .b = 255 };
        }
        if (col_type == .tla) {
            text_color = raylib.ColorContrast(driver_info.?.team_color, -0.15);
        }
        if (col_type == .next_gap and driver.in_pit) {
            text = "  Pit";
            text_color = raylib.ColorFromHSV(195, 0.4, 1);
        }

        const x_pos_f: f32 = render_opts.char_width * col.x_pos;

        raylib.DrawTextEx(
            render_opts.font,
            text.ptr,
            .{ .x = x_pos_f, .y = y_content },
            @floatFromInt(render_opts.content_height),
            0,
            text_color,
        );

        if (col_type == .position) {
            const current_compound = if (driver_stint_data) |d| d.current_tyre else f1_lt.TyreCompound.unknown;

            raylib.DrawRectangle(
                @intFromFloat(@max(0, x_pos_f - 1 * render_opts.char_width)),
                @intFromFloat(y_content + 0.6 * render_opts.char_width),
                @intFromFloat(@max(3, 0.4 * render_opts.char_width)),
                @intFromFloat(render_opts.content_height_f - 1.2 * render_opts.char_width),
                current_compound.toColor(),
            );
        }
    }
}

fn allocPrintDelta(allocator: Allocator, ms_or_laps_opt: ?f1_lt.MsOrLaps, only_tenths: bool) [:0]const u8 {
    if (ms_or_laps_opt != null) {
        switch (ms_or_laps_opt.?) {
            .ms => |ms_orig| {
                const ms = if (ms_orig < 0) -ms_orig else ms_orig;
                const full: u32 = @intCast(@divTrunc(ms, 1000));

                if (only_tenths) {
                    const frac: u32 = @intCast(@rem(@divTrunc(ms, 100), 10));
                    return std.fmt.allocPrintZ(allocator, "{d: >2}.{d:0>1}", .{ full, frac }) catch unreachable;
                } else {
                    const frac: u32 = @intCast(@rem(@divTrunc(ms, 10), 100));
                    return std.fmt.allocPrintZ(allocator, "{d: >2}.{d:0>2}", .{ full, frac }) catch unreachable;
                }
            },
            .laps => |laps| {
                return std.fmt.allocPrintZ(allocator, " {d} L", .{laps}) catch unreachable;
            },
        }
    } else {
        return " -";
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
