const std = @import("std");
const raygui = @import("lib/raygui/build.zig");

const sep = std.fs.path.sep;

inline fn projDir() []const u8 {
    const dir = comptime std.fs.path.dirname(@src().file) orelse unreachable;
    return comptime dir ++ .{sep};
}

pub fn build(b: *std.Build) !void {
    var target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const name_suffix = b.option([]const u8, "filename-suffix", "Filename suffix");

    const exe_name = if (name_suffix) |suffix|
        try std.fmt.allocPrintZ(b.allocator, "mv-widgets-{s}", .{suffix})
    else
        "mv-widgets";

    const exe = b.addExecutable(.{
        .name = exe_name,
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });
    addRaylibBindings(b, exe, target, optimize);
    raygui.addTo(b, exe, target, optimize);
    exe.addAnonymousModule(
        "mecha",
        .{ .source_file = .{ .path = projDir() ++ "lib/mecha/mecha.zig" } },
    );
    exe.addAnonymousModule(
        "zig-datetime",
        .{ .source_file = .{ .path = projDir() ++ "lib/zig-datetime/src/datetime.zig" } },
    );
    exe.addAnonymousModule("primary_font.ttf", .{ .source_file = .{ .path = "data/Manrope-Regular.ttf" } });
    exe.addAnonymousModule("mono_font.ttf", .{ .source_file = .{ .path = "data/RobotoMono-Regular.ttf" } });

    // Compile and link Win32 resources (icon, properties)
    if (target.getOsTag() == .windows) {
        var res_path = b.fmt("{s}/win.res", .{b.cache_root.path.?});
        var resources = b.addSystemCommand(&.{ "x86_64-w64-mingw32-windres", "-i", projDir() ++ "data/win.rc", "-o", res_path });
        exe.step.dependOn(&resources.step);
        exe.addObjectFile(res_path);
    }

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const unit_tests = b.addTest(.{
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    const run_unit_tests = b.addRunArtifact(unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);
}

// Taken from raylib.zig's build.zig and modified to `addFrameworkPath` for cross-compiled MacOS builds
pub fn addRaylibBindings(
    b: *std.Build,
    exe: *std.build.LibExeObjStep,
    target: std.zig.CrossTarget,
    optimize: std.builtin.Mode,
) void {
    const raylib_upstream = @import("lib/raylib/raylib/src/build.zig");
    const raylib_bindings_dir = projDir() ++ "lib/raylib/";
    const raylib_upstream_dir = raylib_bindings_dir ++ "raylib/";

    exe.addAnonymousModule("raylib", .{ .source_file = .{ .path = raylib_bindings_dir ++ "raylib.zig" } });
    exe.addIncludePath(raylib_upstream_dir ++ "src");
    exe.addIncludePath(raylib_bindings_dir);

    const bindings_lib = b.addStaticLibrary(.{ .name = "raylib-zig", .target = target, .optimize = optimize });
    bindings_lib.addIncludePath(raylib_upstream_dir ++ "src");
    bindings_lib.addIncludePath(raylib_bindings_dir);
    bindings_lib.linkLibC();
    bindings_lib.addCSourceFile(raylib_bindings_dir ++ "marshal.c", &.{});
    exe.linkLibrary(bindings_lib);

    const upstream_lib = raylib_upstream.addRaylib(b, target, optimize, .{});
    exe.linkLibrary(upstream_lib);

    b.installArtifact(bindings_lib);
    b.installArtifact(upstream_lib);

    switch (target.getOsTag()) {
        .macos => {
            upstream_lib.addFrameworkPath("/System/Library/Frameworks");
            upstream_lib.addSystemIncludePath("/usr/include");
            upstream_lib.addLibraryPath("/usr/lib");
            exe.addFrameworkPath("/System/Library/Frameworks");
        },
        else => {},
    }
}
