const Builder = @import("std").build.Builder;

pub fn build(b: *Builder) void {
    const mode = b.standardReleaseOptions();
    const lib = b.addStaticLibrary("resp3.zig", "src/main.zig");
    lib.setBuildMode(mode);

    var main_tests = b.addTest("src/main.zig");
    main_tests.setBuildMode(mode);

    var hash_tests = b.addTest("src/hash.zig");
    hash_tests.setBuildMode(mode);

    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&main_tests.step);
    test_step.dependOn(&hash_tests.step);

    b.default_step.dependOn(&lib.step);
    b.installArtifact(lib);
}
