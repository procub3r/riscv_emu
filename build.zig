const std = @import("std");

pub fn build(b: *std.Build) void {
    // standard target and optimize options
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // build sandbox
    const sandbox = b.addExecutable(.{
        .name = "sandbox",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(sandbox);

    // run sandbox
    const run_cmd = b.addRunArtifact(sandbox);
    run_cmd.step.dependOn(b.getInstallStep());

    // take cmdline arguments
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    // create the run step
    const run_step = b.step("run", "Run the sandbox");
    run_step.dependOn(&run_cmd.step);

    // run unit tests
    const unit_tests = b.addTest(.{
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });
    const run_unit_tests = b.addRunArtifact(unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);
}
