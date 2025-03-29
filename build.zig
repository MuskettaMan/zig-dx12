const std = @import("std");
const builtin = @import("builtin");

pub fn pathResolve(b: *std.Build, paths: []const []const u8) []u8 {
    return std.fs.path.resolve(b.allocator, paths) catch @panic("OOM");
}

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

    const compile_shaders = @import("zwindows").addCompileShaders(b, "Main", zwindows_dependency, .{ .shader_ver = "6_5" });
    const root_path = pathResolve(b, &.{ @src().file, ".."});

    const hlsl_path = b.pathJoin(&.{ root_path, "src", "shaders", "main.hlsl" });
    compile_shaders.addVsShader(hlsl_path, "vsMain", b.pathJoin(&.{ root_path, "src", "shaders", "main.vs.cso" }), "");
    compile_shaders.addPsShader(hlsl_path, "psMain", b.pathJoin(&.{ root_path, "src", "shaders", "main.ps.cso" }), "");

    exe.step.dependOn(compile_shaders.step);

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
