const std = @import("std");
const layer2 = @import("examples").layer2;

const allocator = std.testing.allocator;
const io = std.Io.Threaded.global_single_threaded.*.io();

test "53 - simple send-receive" {
    std.testing.log_level = .debug;
    layer2.simple_send_receive.run(allocator, io) catch |err| {
        std.log.err("example failed: {s}", .{@errorName(err)});
        return err;
    };
}

test "54 - worker loop pattern" {
    std.testing.log_level = .debug;
    layer2.worker_loop.run(allocator, io) catch |err| {
        std.log.err("example failed: {s}", .{@errorName(err)});
        return err;
    };
}

test "55 - OOB via send_oob" {
    std.testing.log_level = .debug;
    layer2.oob_signal.run(allocator, io) catch |err| {
        std.log.err("example failed: {s}", .{@errorName(err)});
        return err;
    };
}

test "56 - pipeline" {
    std.testing.log_level = .debug;
    layer2.pipeline.run(allocator, io) catch |err| {
        std.log.err("example failed: {s}", .{@errorName(err)});
        return err;
    };
}

test "57 - request-response" {
    std.testing.log_level = .debug;
    layer2.request_response.run(allocator, io) catch |err| {
        std.log.err("example failed: {s}", .{@errorName(err)});
        return err;
    };
}

test "58 - fan-in" {
    std.testing.log_level = .debug;
    layer2.fan_in.run(allocator, io) catch |err| {
        std.log.err("example failed: {s}", .{@errorName(err)});
        return err;
    };
}

test "59 - shutdown with remaining item cleanup" {
    std.testing.log_level = .debug;
    layer2.shutdown_cleanup.run(allocator, io) catch |err| {
        std.log.err("example failed: {s}", .{@errorName(err)});
        return err;
    };
}

test "60 - batch processing" {
    std.testing.log_level = .debug;
    layer2.batch_processing.run(allocator, io) catch |err| {
        std.log.err("example failed: {s}", .{@errorName(err)});
        return err;
    };
}

test "61 - fan-out" {
    std.testing.log_level = .debug;
    layer2.fan_out.run(allocator, io) catch |err| {
        std.log.err("example failed: {s}", .{@errorName(err)});
        return err;
    };
}

test "62 - shutdown via ShutdownCommand" {
    std.testing.log_level = .debug;
    layer2.shutdown_exit.run(allocator, io) catch |err| {
        std.log.err("example failed: {s}", .{@errorName(err)});
        return err;
    };
}
