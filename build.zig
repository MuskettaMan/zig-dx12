const std = @import("std");
const builtin = @import("builtin");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});

    const optimize = b.standardOptimizeOption(.{});

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const exe = b.addExecutable(.{
        .name = "zig-dx12",
        .root_module = exe_mod,
    });

    const zwindows_dependency = b.dependency("zwindows", .{
        .zxaudio2_debug_layer = (builtin.mode == .Debug),
        .zd3d12_debug_layer = (builtin.mode == .Debug),
        .zd3d12_gbv = b.option(bool, "zd3d12_gbv", "Enable GPU-Based Validation") orelse false,
    });

    const zwindows_module = zwindows_dependency.module("zwindows");
    const zd3d12_module = zwindows_dependency.module("zd3d12");
    const zxaudio2_module = zwindows_dependency.module("zxaudio2");

    exe.root_module.addImport("zwindows", zwindows_module);
    exe.root_module.addImport("zd3d12", zd3d12_module);
    exe.root_module.addImport("zxaudio2", zxaudio2_module);

    //const lib = b.addStaticLibrary(.{ .name = "common", .target = exe.root_module.resolved_target.?, .optimize = optimize });

    //lib.linkLibC();
    //if (target.result.abi != .msvc)
    //    lib.linkLibCpp();
    //lib.linkSystemLibrary("imm32");

    //lib.addIncludePath(b.path("libs"));

    //const module = b.createModule(.{ .imports = &.{
    //    .{ .name = "zwindows", .module = zwindows_module },
    //    .{ .name = "zd3d12", .module = zd3d12_module },
    //    .{ .name = "zxaudio2", .module = zxaudio2_module },
    //} });

    //exe.root_module.addImport("common", module);
    //exe.linkLibrary(lib);

    const zwindows = @import("zwindows");
    zwindows.install_xaudio2(&exe.step, zwindows_dependency, .bin);
    zwindows.install_d3d12(&exe.step, zwindows_dependency, .bin);
    zwindows.install_directml(&exe.step, zwindows_dependency, .bin);

    exe.rdynamic = true;

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);

    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const exe_unit_tests = b.addTest(.{
        .root_module = exe_mod,
    });

    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_exe_unit_tests.step);
}
