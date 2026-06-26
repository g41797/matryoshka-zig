const std = @import("std");

pub fn build(b: *std.Build) void {
    const target: std.Build.ResolvedTarget = b.standardTargetOptions(.{});
    const optimize: std.builtin.OptimizeMode = b.standardOptimizeOption(.{});

    const use_lld = target.result.os.tag != .macos and
        target.result.os.tag != .freebsd and
        target.result.os.tag != .openbsd and
        target.result.os.tag != .netbsd;

    const mod: *std.Build.Module = b.addModule("matryoshka", .{
        .root_source_file = b.path("src/matryoshka.zig"),
        .target = target,
        .optimize = optimize,
        .single_threaded = false,
    });

    const lib: *std.Build.Step.Compile = b.addLibrary(.{
        .name = "matryoshka",
        .linkage = .static,
        .root_module = mod,
        .use_llvm = true,
        .use_lld = use_lld,
    });

    b.installArtifact(lib);

    const helpers: *std.Build.Module = b.createModule(.{
        .root_source_file = b.path("helpers/helpers.zig"),
        .target = target,
        .optimize = optimize,
    });

    helpers.addImport("matryoshka", mod);

    const tmod: *std.Build.Module = b.createModule(.{
        .root_source_file = b.path("tests/matryoshka_tests.zig"),
        .target = target,
        .optimize = optimize,
    });

    const emod: *std.Build.Module = b.addModule("examples", .{
        .root_source_file = b.path("examples/examples.zig"),
        .target = target,
        .optimize = optimize,
    });

    emod.addImport("matryoshka", mod);
    emod.addImport("helpers", helpers);

    tmod.addImport("matryoshka", mod);
    tmod.addImport("helpers", helpers);
    tmod.addImport("examples", emod);

    const lib_unit_tests: *std.Build.Step.Compile = b.addTest(.{
        .root_module = tmod,
        .use_llvm = true,
        .use_lld = use_lld,
    });

    b.installArtifact(lib_unit_tests);

    const run_lib_unit_tests: *std.Build.Step.Run = b.addRunArtifact(lib_unit_tests);

    const test_step: *std.Build.Step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_lib_unit_tests.step);
}
