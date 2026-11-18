const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const nanoui = b.dependency("nanoui", .{ .target = target, .optimize = optimize }).module("nanoui");
    const options = b.addOptions();
    options.addOption([]const u8, "version", @import("build.zig.zon").version);
    const build_options = options.createModule();

    const exe = b.addExecutable(.{ .name = "wslpanel", .root_module = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "nanoui", .module = nanoui },
            .{ .name = "build_options", .module = build_options },
        },
    }) });
    if (target.result.os.tag == .windows) exe.subsystem = .windows;
    b.installArtifact(exe);
    const run = b.addRunArtifact(exe);
    run.addPassthruArgs();
    b.step("run", "Open the wslpanel window").dependOn(&run.step);

    const tests = b.addTest(.{ .root_module = b.createModule(.{
        .root_source_file = b.path("src/tests.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "nanoui", .module = nanoui },
            .{ .name = "build_options", .module = build_options },
        },
    }) });
    b.step("test", "Run the tests").dependOn(&b.addRunArtifact(tests).step);
}
