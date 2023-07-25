const std = @import("std");
const Allocator = std.mem.Allocator;
const raylib = @import("raylib");
const shapes = @import("shapes.zig");
const fonts = @import("fonts.zig");
const Triangle = shapes.Triangle;

var instance: ?@This() = null;

target_rect: raylib.RectangleI,

hover_over_drag: bool = false,
is_dragging: bool = false,
hover_over_resize: bool = false,
is_resizing: bool = false,
mouse_origin: raylib.Vector2 = undefined,

const decoration_size = 20;
const decoration_color_default = raylib.Color{ .a = 220, .r = 150, .g = 150, .b = 150 };
const decoration_color_hover = raylib.Color{ .a = 250, .r = 200, .g = 200, .b = 200 };

pub fn init(allocator: Allocator, target_rect: raylib.RectangleI, title: [:0]const u8) !@This() {
    if (instance != null) return error.AlreadyInitialized;

    fonts.init(allocator);
    raylib.SetConfigFlags(.{
        .FLAG_WINDOW_RESIZABLE = true,
        // .FLAG_WINDOW_MAXIMIZED = true,
        .FLAG_MSAA_4X_HINT = true,
        .FLAG_WINDOW_ALWAYS_RUN = true,
        // .FLAG_WINDOW_MOUSE_PASSTHROUGH = true,
        .FLAG_WINDOW_UNDECORATED = true,
        .FLAG_WINDOW_TOPMOST = true,
        .FLAG_VSYNC_HINT = true,
        .FLAG_WINDOW_TRANSPARENT = true,
        .FLAG_WINDOW_HIGHDPI = true,
    });
    raylib.InitWindow(
        target_rect.width,
        target_rect.height,
        title,
    );
    raylib.SetWindowPosition(
        target_rect.x,
        target_rect.y,
    );
    raylib.SetTargetFPS(60);

    var this = @This(){
        .target_rect = target_rect,
    };

    instance = this;
    return this;
}

pub fn deinitAndClose(this: *@This()) void {
    _ = this;
    raylib.CloseWindow();
    fonts.deinit();
}

pub fn moveTo(this: *@This(), position: raylib.Vector2i) void {
    this.target_rect.x = position.x;
    this.target_rect.y = position.y;
    raylib.SetWindowPosition(position.x, position.y);
    this.syncTargetRect();
}

pub fn resize(this: *@This(), size: raylib.Vector2i, min_x: i32, min_y: i32) void {
    this.target_rect.width = @max(size.x, min_x);
    this.target_rect.height = @max(size.y, min_y);
    raylib.SetWindowSize(this.target_rect.width, this.target_rect.height);
    this.syncTargetRect();
}

// Sync actual position & size to target
pub fn syncTargetRect(this: *@This()) void {
    const pos = raylib.GetWindowPosition();
    this.target_rect.x = @intFromFloat(pos.x);
    this.target_rect.y = @intFromFloat(pos.y);
    this.target_rect.width = raylib.GetRenderWidth();
    this.target_rect.height = raylib.GetRenderHeight();
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
    this.syncPositionAndDimension();
}

pub fn handleDrag(this: *@This()) void {
    const mouse_pos = raylib.GetMousePosition();

    this.hover_over_drag = raylib.CheckCollisionPointRec(
        mouse_pos,
        this.getDragRectangle().toF32(),
    );

    // Dragging
    if (this.hover_over_drag and raylib.IsMouseButtonDown(.MOUSE_BUTTON_LEFT) and !this.is_dragging and !this.is_resizing) {
        this.is_dragging = true;
        this.mouse_origin = mouse_pos;
    } else if (this.is_dragging and !raylib.IsMouseButtonDown(.MOUSE_BUTTON_LEFT)) {
        this.is_dragging = false;
        // window.fixWindow();
    }
    if (this.is_dragging) {
        const target_window_pos = this.target_rect.pos().float().add(mouse_pos).sub(this.mouse_origin).int();
        this.moveTo(target_window_pos);
    }
}

pub fn handleResize(this: *@This()) void {
    const mouse_pos = raylib.GetMousePosition();
    const mouse_delta = raylib.GetMouseDelta();

    const resize_triangle = this.getResizeTriangle().toF32();
    this.hover_over_resize = raylib.CheckCollisionPointTriangle(
        mouse_pos,
        resize_triangle.a,
        resize_triangle.b,
        resize_triangle.c,
    );

    // Resizing
    if (this.hover_over_resize and raylib.IsMouseButtonDown(.MOUSE_BUTTON_LEFT) and !this.is_resizing and !this.is_dragging) {
        this.is_resizing = true;
        this.mouse_origin = mouse_pos;
    } else if (this.is_resizing and !raylib.IsMouseButtonDown(.MOUSE_BUTTON_LEFT)) {
        this.is_resizing = false;
        // this.fixWindow();
    }
    if (this.is_resizing) {
        var target_window_size = this.target_rect.toF32().size().add(mouse_delta).int();
        this.resize(target_window_size, decoration_size, 2 * decoration_size);
    }

    if (!this.is_resizing and !this.is_dragging) {
        this.syncTargetRect();
        // this.fixWindow();
    }
}

pub fn drawDecorations(this: *@This()) void {
    if (raylib.IsCursorOnScreen()) {
        const drag_rect_color =
            if (this.hover_over_drag or this.is_dragging) decoration_color_hover else decoration_color_default;

        raylib.DrawRectangleRec(this.getDragRectangle().toF32(), drag_rect_color);

        const resize_triangle_color =
            if (this.hover_over_resize or this.is_resizing) decoration_color_hover else decoration_color_default;

        var resize_triangle = this.getResizeTriangle().toF32();

        raylib.DrawTriangle(
            resize_triangle.a,
            resize_triangle.b,
            resize_triangle.c,
            resize_triangle_color,
        );
    }

    // Draw window border when hovering or actively manipulating the window
    const hovering_over_decorations = this.hover_over_resize or this.hover_over_drag;
    const any_decorations_active = this.is_dragging or this.is_resizing;

    if ((raylib.IsCursorOnScreen() and hovering_over_decorations) or any_decorations_active) {
        raylib.DrawRectangleLines(0, 0, this.target_rect.width, this.target_rect.height, decoration_color_hover);
    }
}

pub fn setMouseCursor(this: *@This()) void {
    if (this.is_resizing or this.hover_over_resize) {
        raylib.SetMouseCursor(raylib.MouseCursor.MOUSE_CURSOR_RESIZE_NWSE);
    } else if(this.is_dragging or this.hover_over_drag) {
        raylib.SetMouseCursor(raylib.MouseCursor.MOUSE_CURSOR_RESIZE_ALL);
    } else {
        raylib.SetMouseCursor(raylib.MouseCursor.MOUSE_CURSOR_DEFAULT);
    }
}

pub fn getResizeTriangle(this: *@This()) Triangle(i32) {
    const r = this.target_rect;
    var a = raylib.Vector2i{ .x = r.width - decoration_size, .y = r.height };
    var b = raylib.Vector2i{ .x = r.width, .y = r.height };
    var c = raylib.Vector2i{ .x = r.width, .y = r.height - decoration_size };

    return Triangle(i32).fromPoints(a, b, c);
}

pub fn getDragRectangle(this: *@This()) raylib.RectangleI {
    const r = this.target_rect;
    return raylib.RectangleI{ .x = 0, .y = 0, .width = r.width, .height = decoration_size };
}
