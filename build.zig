const std = @import("std");
const raylib = @import("lib/raylib/build.zig");
const raygui = @import("lib/raygui/build.zig");

pub fn build(b: *std.Build) !void {
    var target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const win_target = try std.zig.CrossTarget.parse(.{ .arch_os_abi = "x86_64-windows-gnu" });
    target = win_target;

    const exe = b.addExecutable(.{
        .name = "mv-widgets",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });
    raylib.addTo(b, exe, target, optimize);
    raygui.addTo(b, exe, target, optimize);
    exe.addAnonymousModule("primary_font.ttf", .{ .source_file = .{ .path = "data/Manrope-Regular.ttf" } });
    exe.addAnonymousModule("mono_font.ttf", .{ .source_file = .{ .path = "data/RobotoMono-Regular.ttf" } });

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
