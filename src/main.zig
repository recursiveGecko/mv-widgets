const std = @import("std");
const builtin = @import("builtin");
const raylib = @import("raylib");
const Window = @import("Window.zig");
const widgets = @import("widgets.zig");
const multiviewer = @import("multiviewer.zig");
const f1_lt = @import("f1_live_timing.zig");

const SharedState = struct {
    active_state: ?f1_lt.State,
    mutex: std.Thread.Mutex = .{},
    should_exit: bool = false,

    pub fn lock(this: *@This()) void {
        this.mutex.lock();
    }

    pub fn unlock(this: *@This()) void {
        this.mutex.unlock();
    }

    pub fn swapState(this: *@This(), new_state: f1_lt.State) void {
        this.lock();
        defer this.unlock();

        if (this.active_state) |*current| {
            current.deinit();
        }

        this.active_state = new_state;
    }
};

var shared_state = SharedState{
    .active_state = null,
};

pub fn main() !void {
    if (builtin.os.tag == .windows) {
        try std.os.windows.SetConsoleCtrlHandler(&windowsHandleConsoleCtrl, true);
    }

    var widget_gpa = std.heap.GeneralPurposeAllocator(.{ .stack_trace_frames = 0 }){};
    var widget = try widget_gpa.allocator().create(widgets.Widget);
    widget.* = .{
        .timing_tower = try widgets.TimingTower.init(widget_gpa.allocator()),
    };
    
    var ui_thread = try std.Thread.spawn(.{}, uiLoop, .{widget});
    var update_thread = try std.Thread.spawn(.{}, stateUpdateLoop, .{});

    ui_thread.join();
    update_thread.join();
}

fn windowsHandleConsoleCtrl(ctrl_type: u32) callconv(.C) c_int {
    if (ctrl_type == std.os.windows.CTRL_C_EVENT) {
        shared_state.should_exit = true;
        return 1;
    }
    return 0;
}

fn stateUpdateLoop() void {
    // stack_trace_frames >0 causes a panic during leak detection for some reason
    var gpa = std.heap.GeneralPurposeAllocator(.{ .stack_trace_frames = 0 }){};
    defer {
        if (shared_state.active_state != null) {
            shared_state.lock();
            shared_state.active_state.?.deinit();
            shared_state.active_state = null;
            shared_state.unlock();
        }

        shared_state.should_exit = true;
        _ = gpa.deinit();
    }

    while (true) {
        if (shared_state.should_exit) return;

        const ms = 1_000_000;
        std.time.sleep(100 * ms);

        var lt_state = multiviewer.fetchStateLeaky(gpa.allocator()) catch |err| {
            std.log.err("Failed to update state: {any}", .{err});
            continue;
        };

        shared_state.swapState(lt_state);
    }
}

fn uiLoop(widget: *widgets.Widget) !void {
    // stack_trace_frames >0 causes a panic during leak detection for some reason
    var gpa = std.heap.GeneralPurposeAllocator(.{ .stack_trace_frames = 0 }){};
    var frame_arena = std.heap.ArenaAllocator.init(gpa.allocator());
    defer {
        frame_arena.deinit();
        _ = gpa.deinit();
        shared_state.should_exit = true;
    }

    var window = try Window.init(
        gpa.allocator(),
        widget.initialDimensions(),
        widget.windowTitle(),
    );
    defer window.deinitAndClose();

    while (!raylib.WindowShouldClose() and !shared_state.should_exit) {
        raylib.BeginDrawing();
        // Sync actual window position and size to target in case it was moved without our knowledge
        window.syncTargetRect();

        defer {
            _ = frame_arena.reset(.retain_capacity);
            // This is called last, it ensures our TargetFPS is met
            raylib.EndDrawing();
        }

        const bg_color = raylib.Color{ .r = 20, .g = 20, .b = 20, .a = 255 };
        // const bg_color = raylib.Color{ .r = 0, .g = 0, .b = 0, .a = 110 };
        raylib.ClearBackground(bg_color);

        window.handleDrag();
        window.handleResize();

        // Lock the shared state to prevent memory corruption or mid-render changes
        shared_state.lock();
        defer shared_state.unlock();

        // Window contents
        if (shared_state.active_state != null) {
            widget.render(frame_arena.allocator(), &window, &shared_state.active_state.?) catch |err| {
                std.log.err("Failed to render widget: {any}", .{err});
            };
        }

        window.drawDecorations();
        window.setMouseCursor();
        // raylib.DrawFPS(0, 0);
    }
}
