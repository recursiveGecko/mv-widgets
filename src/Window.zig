const raylib = @import("raylib");
const shapes = @import("./shapes.zig");
const Triangle = shapes.Triangle;

x: i32 = 0,
x_f: f32 = 0,
y: i32 = 0,
y_f: f32 = 0,
width: i32 = 0,
width_f: f32 = 0,
height: i32 = 0,
height_f: f32 = 0,
target_rect: raylib.Rectangle,

pub fn init(target_rect: raylib.Rectangle) @This() {
    var this = @This(){
        .target_rect = target_rect,
    };
    return this;
}

pub fn moveTo(this: *@This(), position: raylib.Vector2) void {
    this.target_rect.x = position.x;
    this.target_rect.y = position.y;
    raylib.SetWindowPosition(@intFromFloat(position.x), @intFromFloat(position.y));
    this.updateProps();
}

pub fn resize(this: *@This(), size: raylib.Vector2, min_x: f32, min_y: f32) void {
    this.target_rect.width = @max(size.x, min_x);
    this.target_rect.height = @max(size.y, min_y);
    raylib.SetWindowSize(@intFromFloat(this.target_rect.width), @intFromFloat(this.target_rect.height));
    this.updateProps();
}

pub fn updateProps(this: *@This()) void {
    this.width = raylib.GetRenderWidth();
    this.width_f = @floatFromInt(this.width);
    this.height = raylib.GetRenderHeight();
    this.height_f = @floatFromInt(this.height);

    const pos = raylib.GetWindowPosition();
    this.x_f = pos.x;
    this.y_f = pos.y;
    this.x = @intFromFloat(pos.x);
    this.y = @intFromFloat(pos.y);
}

pub fn fixWindow(this: *@This()) void {
    const monitor = raylib.GetCurrentMonitor();
    const monitor_height_f: f32 = @floatFromInt(raylib.GetMonitorHeight(monitor));
    const monitor_width_f: f32 = @floatFromInt(raylib.GetMonitorWidth(monitor));

    const new_height = @min(monitor_height_f, this.target_rect.height);
    const new_width = @min(monitor_width_f, this.target_rect.width);

    if (new_height != this.target_rect.height or new_width != this.target_rect.width) {
        this.target_rect.height = new_height;
        this.target_rect.width = new_width;
        raylib.SetWindowSize(@intFromFloat(this.target_rect.width), @intFromFloat(this.target_rect.height));
    }

    const max_y = monitor_height_f - this.target_rect.height;
    const max_x = monitor_width_f - this.target_rect.width;

    const new_x = @min(max_x, @max(0, this.target_rect.x));
    const new_y = @min(max_y, @max(0, this.target_rect.y));

    if (new_x != this.target_rect.x or new_y != this.target_rect.y) {
        this.target_rect.x = new_x;
        this.target_rect.y = new_y;
        raylib.SetWindowPosition(@intFromFloat(this.target_rect.x), @intFromFloat(this.target_rect.y));
    }
    this.updateProps();
}

// Sync actual position & size to target
pub fn syncTargetRect(this: *@This()) void {
    const pos = raylib.GetWindowPosition();
    this.target_rect.x = pos.x;
    this.target_rect.y = pos.y;
    this.target_rect.width = @floatFromInt(raylib.GetRenderWidth());
    this.target_rect.height = @floatFromInt(raylib.GetRenderHeight());
    this.updateProps();
}

pub fn getResizeTriangle(this: *@This(), decoration_size: i32) Triangle {
    const decoration_size_f: f32 = @floatFromInt(decoration_size);
    var a = raylib.Vector2{ .x = this.width_f - decoration_size_f, .y = this.height_f };
    var b = raylib.Vector2{ .x = this.width_f, .y = this.height_f };
    var c = raylib.Vector2{ .x = this.width_f, .y = this.height_f - decoration_size_f };

    return Triangle.fromPoints(a, b, c);
}

pub fn getDragRectangle(this: *@This(), decoration_size: i32) raylib.Rectangle {
    const decoration_size_f: f32 = @floatFromInt(decoration_size);
    return raylib.Rectangle{ .x = 0, .y = 0, .width = this.width_f, .height = decoration_size_f };
}
