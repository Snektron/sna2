const std = @import("std");
const Builder = std.build.Builder;

const FutharkBackend = enum {
    c,
    opencl,
    multicore,
};

fn addFutharkSrc(b: *Builder, exe: *std.build.LibExeObjStep, backend: FutharkBackend) void {
    const cache_root = std.fs.path.join(b.allocator, &[_][]const u8{
        b.build_root,
        b.cache_root
    }) catch unreachable;

    const futhark_output = std.fs.path.join(b.allocator, &[_][]const u8{
        cache_root,
        "futhark"
    }) catch unreachable;

    const futhark_gen = b.addSystemCommand(&[_][]const u8{
        "futhark",
        switch (backend) {
            .c => "c",
            .opencl => "opencl",
            .multicore => "multicore"
        },
        "--library",
        "src/main.fut",
        "-o",
        futhark_output
    });

    exe.step.dependOn(&futhark_gen.step);

    const futhark_c_output = std.mem.concat(b.allocator, u8, &[_][]const u8{futhark_output, ".c"}) catch unreachable;
    exe.addCSourceFile(futhark_c_output, &[_][]const u8{ "-march=native" });
    exe.addIncludeDir(cache_root);
}

pub fn build(b: *Builder) void {
    const target = b.standardTargetOptions(.{});
    const mode = b.standardReleaseOptions();
    const backend = b.option(FutharkBackend, "futhark-backend", "Set futhark backend") orelse .c;
    const ocl_inc = b.option([]const u8, "opencl-include", "opencl include path") orelse "/usr/include";
    const ocl_lib = b.option([]const u8, "opencl-lib", "opencl library path") orelse "/usr/lib";

    const exe = b.addExecutable("sna-asg2", "src/main.zig");
    exe.setTarget(target);
    exe.setBuildMode(mode);
    exe.install();
    exe.linkLibC();
    if (backend == .opencl) {
        exe.addSystemIncludeDir(ocl_inc);
        exe.addLibPath(ocl_lib);
        exe.linkSystemLibraryName("OpenCL");
    }
    addFutharkSrc(b, exe, backend);

    const run_cmd = exe.run();
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}
