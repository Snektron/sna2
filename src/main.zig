const std = @import("std");
const c = @cImport({ @cInclude("futhark.h"); });

pub const log_level = .debug;

// Keep in sync with main.fut
const username_max_length = 15;

const Args = struct {
    in_path: []const u8,
    graph_path: ?[]const u8,
    users_path: ?[]const u8,
    debug: bool,
};

fn parseArgs() !Args {
    var in_path: ?[]const u8 = null;
    var graph_path: ?[]const u8 = null;
    var users_path: ?[]const u8 = null;
    var debug = false;

    var it = std.process.args();
    const process_name = it.nextPosix().?;
    while (it.nextPosix()) |arg| {
        if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            std.log.info("Usage: {} [--help] [--debug] [--save-edges <output.tsv>] [--save-users <output.txt>] [--opencl-device <device>] <input.tsv>", .{ process_name });
            return error.Help;
        } else if (std.mem.eql(u8, arg, "--debug")) {
            debug = true;
        } else if (std.mem.eql(u8, arg, "--save-edges")) {
            graph_path = it.nextPosix() orelse {
                std.log.crit("Missing argument <output.tsv> for switch --save-edges", .{});
                return error.InvalidArgs;
            };
        } else if (std.mem.eql(u8, arg, "--save-users")) {
            users_path = it.nextPosix() orelse {
                std.log.crit("Missing argument <output.txt> for switch --save-users", .{});
                return error.InvalidArgs;
            };
        } else if (in_path == null) {
            in_path = arg;
        } else {
            std.log.crit("Invalid positional argument: '{}'", .{ arg });
            return error.InvalidArgs;
        }
    }

    if (in_path == null) {
        std.log.crit("Missing positional argument <input.tsv>", .{});
        return error.InvalidArgs;
    }

    return Args{
        .in_path = in_path.?,
        .graph_path = graph_path,
        .users_path = users_path,
        .debug = debug,
    };
}

pub fn main() !void {
    const args = parseArgs() catch return;

    std.log.info("Initializing Futhark context", .{});
    const cfg = c.futhark_context_config_new() orelse return error.OutOfMemory;
    defer c.futhark_context_config_free(cfg);
    c.futhark_context_config_set_logging(cfg, 1);

    if (args.debug) {
        c.futhark_context_config_set_debugging(cfg, 1);
    }

    const ctx = c.futhark_context_new(cfg) orelse return error.OutOfMemory;
    defer c.futhark_context_free(ctx);

    if (@hasDecl(c, "futhark_context_get_num_threads")) {
        const threads = c.futhark_context_get_num_threads(ctx);
        std.log.info("Using {} threads", .{ threads });
    }

    const tsv_size = blk: {
        const tsv_file = try std.fs.cwd().openFile(args.in_path, .{});
        defer tsv_file.close();

        break :blk (try tsv_file.stat()).size;
    };

    std.log.info("Loading {} MiB input", .{ tsv_size / 1024 / 1024 });

    var timer = try std.time.Timer.start();

    var in = blk: {
        const tsv = try std.fs.cwd().readFileAlloc(std.heap.page_allocator, args.in_path, tsv_size);
        defer std.heap.page_allocator.free(tsv);

        // const tsv = try std.os.mmap(null, tsv_size, std.os.PROT_READ, std.os.MAP_PRIVATE | std.os.MAP_POPULATE, tsv_file.handle, 0);
        // defer std.os.munmap(tsv);

        std.log.info("Input loaded (took {} ms)", .{ timer.read() / std.time.ns_per_ms });

        std.log.info("Loading input to Futhark", .{});
        break :blk c.futhark_new_u8_1d(ctx, tsv.ptr, @intCast(i64, tsv.len)) orelse return error.OutOfMemory;
    };
    defer _ = c.futhark_free_u8_1d(ctx, in);

    var srcs: ?*c.futhark_i64_1d = null;
    defer if (srcs != null) {
        _ = c.futhark_free_i64_1d(ctx, srcs);
    };

    var dsts: ?*c.futhark_i64_1d = null;
    defer if (dsts != null) {
        _ = c.futhark_free_i64_1d(ctx, dsts);
    };

    var users: ?*c.futhark_u8_2d = null;
    defer if (users != null) {
        _ = c.futhark_free_u8_2d(ctx, users);
    };

    std.log.info("Launching Futhark kernel", .{});

    timer.reset();
    const rv = c.futhark_entry_main(ctx, &srcs, &dsts, &users, in);
    if (rv != 0 or c.futhark_context_sync(ctx) != 0) {
        const text: [*:0]const u8 = c.futhark_context_get_error(ctx);
        const msg: []const u8 = std.mem.spanZ(text);
        std.log.crit("Kernel error: {}", .{ if (msg.len != 0) msg else "(no diagnostic)" });
        return;
    }

    std.log.info("Kernel finished (took {} ms)", .{ timer.read() / std.time.ns_per_ms });
    const srcs_dim = c.futhark_shape_i64_1d(ctx, srcs)[0];
    const dsts_dim = c.futhark_shape_i64_1d(ctx, dsts)[0];
    const users_dim = c.futhark_shape_u8_2d(ctx, users);
    const n_users = @intCast(usize, users_dim[0]);

    std.log.info("Kernel returned {} edges, {} unique users", .{ srcs_dim, n_users });

    if (srcs_dim != dsts_dim) {
        std.log.crit("Kernel returned invalid edge list: {} src edges and {} dst edges", .{  srcs_dim, dsts_dim });
        std.debug.assert(srcs_dim == dsts_dim);
    }

    std.debug.assert(users_dim[1] == username_max_length);

    if (args.graph_path) |graph_path| {
        const dim = srcs_dim;
        std.log.info("Saving edge list to {}", .{ graph_path });

        const srcs_data = try std.heap.page_allocator.alloc(i64, @intCast(usize, dim));
        defer std.heap.page_allocator.free(srcs_data);
        _ = c.futhark_values_i64_1d(ctx, srcs, srcs_data.ptr);

        const dsts_data = try std.heap.page_allocator.alloc(i64, @intCast(usize, dim));
        defer std.heap.page_allocator.free(dsts_data);
        _ = c.futhark_values_i64_1d(ctx, dsts, dsts_data.ptr);

        const out = try std.fs.cwd().createFile(graph_path, .{});
        defer out.close();
        const file_writer = out.writer();

        var buffered_writer = std.io.bufferedWriter(file_writer);
        const writer = buffered_writer.writer();

        for (srcs_data) |src, i| {
            const dst = dsts_data[i];
            try writer.print("{}\t{}\n", .{ src, dst });
        }
    }

    if (args.users_path) |users_path| {
        std.log.info("Saving user list to {}", .{ users_path });

        const total_size = n_users * username_max_length;

        const users_data = try std.heap.page_allocator.alloc(u8, @intCast(usize, total_size));
        defer std.heap.page_allocator.free(users_data);
        _ = c.futhark_values_u8_2d(ctx, users, users_data.ptr);

        const out = try std.fs.cwd().createFile(users_path, .{});
        defer out.close();
        const file_writer = out.writer();

        var buffered_writer = std.io.bufferedWriter(file_writer);
        const writer = buffered_writer.writer();

        const users_arr = @ptrCast([*]const [username_max_length]u8, users_data.ptr)[0 .. n_users];

        for (users_arr) |user| {
            for (user) |v| {
                if (v != 0) {
                    try writer.writeByte(v);
                }
            }

            try writer.writeByte('\n');
        }

        try buffered_writer.flush();
    }

    std.log.info("Done", .{});
}
