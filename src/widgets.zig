const std = @import("std");
const Allocator = std.mem.Allocator;
const raylib = @import("raylib");
const Window = @import("Window.zig");
const f1_lt = @import("f1_live_timing.zig");

pub const TimingTower = @import("widgets/timing_tower.zig");

pub const Widget = union(enum) {
    timing_tower: *TimingTower,

    pub fn render(
        this: *const Widget,
        frame_allocator: Allocator,
        window: *Window,
        lt_state: *f1_lt.State,
    ) !void {
        return switch (this.*) {
            .timing_tower => |m| m.render(frame_allocator, window, lt_state),
        };
    }

    pub fn initialDimensions(
        this: *const Widget,
    ) raylib.RectangleI {
        return switch (this.*) {
            .timing_tower => |m| m.initialDimensions(),
        };
    }

    pub fn windowTitle(
        this: *const Widget,
    ) [:0]const u8 {
        return switch (this.*) {
            .timing_tower => |m| m.windowTitle(),
        };
    }

    pub fn deinit(
        this: *const Widget,
    ) void {
        return switch (this.*) {
            .timing_tower => |m| m.deinit(),
        };
    }
};
