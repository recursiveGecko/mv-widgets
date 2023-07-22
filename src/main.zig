const std = @import("std");
const raylib = @import("raylib");
const raygui = @import("raygui");
const Window = @import("./Window.zig");
const widgets = @import("./widgets.zig");
const fonts = @import("./fonts.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var arena = std.heap.ArenaAllocator.init(gpa.allocator());
    var frame_allocator = arena.allocator();

    fonts.initMaps(gpa.allocator());

    var window = Window.init(.{
        .x = 1800,
        .y = 300,
        .width = 300,
        .height = 800,
    });

    raylib.SetConfigFlags(.{
        // .FLAG_WINDOW_RESIZABLE = true,
        // .FLAG_WINDOW_MAXIMIZED = true,
        .FLAG_MSAA_4X_HINT = true,
        .FLAG_WINDOW_ALWAYS_RUN = true,
        // .FLAG_WINDOW_MOUSE_PASSTHROUGH = true,
        .FLAG_WINDOW_UNDECORATED = true,
        .FLAG_WINDOW_TOPMOST = true,
        // .FLAG_WINDOW_TRANSPARENT = true,
        .FLAG_WINDOW_HIGHDPI = true,
    });
    raylib.InitWindow(@intFromFloat(window.target_rect.width), @intFromFloat(window.target_rect.height), "Widget");
    raylib.SetTargetFPS(60);

    defer raylib.CloseWindow();

    var is_dragging = false;
    var is_resizing = false;
    var mouse_origin: raylib.Vector2 = undefined;

    const decoration_size = 20;
    const decoration_color_default = raylib.Color{ .a = 220, .r = 150, .g = 150, .b = 150 };
    const decoration_color_hover = raylib.Color{ .a = 250, .r = 200, .g = 200, .b = 200 };

    raylib.SetWindowPosition(@intFromFloat(window.target_rect.x), @intFromFloat(window.target_rect.y));

    while (!raylib.WindowShouldClose()) {
        window.updateProps();
        raylib.BeginDrawing();
        defer raylib.EndDrawing();
        defer _ = arena.reset(.retain_capacity);

        const bg_color = raylib.Color{ .r = 20, .g = 20, .b = 20, .a = 255 };
        raylib.ClearBackground(bg_color);
        // raylib.DrawFPS(0, 0);

        const mouse_pos = raylib.GetMousePosition();
        const mouse_delta = raylib.GetMouseDelta();

        // Drag window rectangle

        // Triangles for resize handle
        var resize_triangle = window.getResizeTriangle(decoration_size);
        const hover_over_resize = raylib.CheckCollisionPointTriangle(mouse_pos, resize_triangle.a, resize_triangle.b, resize_triangle.c);
        const hover_over_drag = raylib.CheckCollisionPointRec(mouse_pos, window.getDragRectangle(decoration_size));

        // Dragging
        if (hover_over_drag and raylib.IsMouseButtonDown(.MOUSE_BUTTON_LEFT) and !is_dragging and !is_resizing) {
            is_dragging = true;
            mouse_origin = mouse_pos;
        } else if (is_dragging and !raylib.IsMouseButtonDown(.MOUSE_BUTTON_LEFT)) {
            is_dragging = false;
            // window.fixWindow();
        }
        if (is_dragging) {
            const target_window_pos = window.target_rect.pos().add(mouse_pos).sub(mouse_origin);
            window.moveTo(target_window_pos);
        }

        // Resizing
        if (hover_over_resize and raylib.IsMouseButtonDown(.MOUSE_BUTTON_LEFT) and !is_resizing and !is_dragging) {
            is_resizing = true;
            mouse_origin = mouse_pos;
        } else if (is_resizing and !raylib.IsMouseButtonDown(.MOUSE_BUTTON_LEFT)) {
            is_resizing = false;
            // window.fixWindow();
        }
        if (is_resizing) {
            var target_window_size = window.target_rect.size().add(mouse_delta);
            window.resize(target_window_size, decoration_size, 2 * decoration_size);
            resize_triangle = window.getResizeTriangle(decoration_size);
        }

        if (!is_resizing and !is_dragging) {
            window.syncTargetRect();
            // window.fixWindow();
        }

        // Window contents
        try widgets.timing_tower.render(frame_allocator, &window);

        // Draw decorations
        if (raylib.IsCursorOnScreen()) {
            const drag_rect_color = if (hover_over_drag or is_dragging) decoration_color_hover else decoration_color_default;
            raylib.DrawRectangleRec(window.getDragRectangle(decoration_size), drag_rect_color);

            const resize_triangle_color = if (hover_over_resize or is_resizing) decoration_color_hover else decoration_color_default;
            raylib.DrawTriangle(resize_triangle.a, resize_triangle.b, resize_triangle.c, resize_triangle_color);
        }

        // Draw window border when hovering or actively manipulating the window
        if ((raylib.IsCursorOnScreen() and (hover_over_resize or hover_over_drag)) or is_dragging or is_resizing) {
            raylib.DrawRectangleLines(0, 0, window.width, window.height, decoration_color_hover);
        }
    }
}
