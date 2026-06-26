const std = @import("std");
const testing = std.testing;
const Io = std.Io;
const layer4 = @import("examples").layer4;

const allocator = std.testing.allocator;
const io = std.Io.Threaded.global_single_threaded.*.io();

test "95 - worker finish signal via mailbox return" {
    std.testing.log_level = .debug;
    layer4.mailbox_as_item.run(allocator, io) catch |err| {
        std.log.err("example failed: {s}", .{@errorName(err)});
        return err;
    };
}

test "96 - pool holds pools at teardown" {
    std.testing.log_level = .debug;
    layer4.pool_as_item.run(allocator, io) catch |err| {
        std.log.err("example failed: {s}", .{@errorName(err)});
        return err;
    };
}

test "17 - minimal master" {
    std.testing.log_level = .debug;
    var threaded: std.Io.Threaded = std.Io.Threaded.init(testing.allocator, .{});
    defer threaded.deinit();
    const tio: Io = threaded.io();
    layer4.minimal_master.run(testing.allocator, tio) catch |err| {
        std.log.err("example failed: {s}", .{@errorName(err)});
        return err;
    };
}

test "18 - master with pool" {
    std.testing.log_level = .debug;
    var threaded: std.Io.Threaded = std.Io.Threaded.init(testing.allocator, .{});
    defer threaded.deinit();
    const tio: Io = threaded.io();
    layer4.master_with_pool.run(testing.allocator, tio) catch |err| {
        std.log.err("example failed: {s}", .{@errorName(err)});
        return err;
    };
}

test "19 - multi-worker master" {
    std.testing.log_level = .debug;
    var threaded: std.Io.Threaded = std.Io.Threaded.init(testing.allocator, .{});
    defer threaded.deinit();
    const tio: Io = threaded.io();
    layer4.multi_worker_master.run(testing.allocator, tio) catch |err| {
        std.log.err("example failed: {s}", .{@errorName(err)});
        return err;
    };
}

test "20 - pipeline of masters" {
    std.testing.log_level = .debug;
    var threaded: std.Io.Threaded = std.Io.Threaded.init(testing.allocator, .{});
    defer threaded.deinit();
    const tio: Io = threaded.io();
    layer4.pipeline_masters.run(testing.allocator, tio) catch |err| {
        std.log.err("example failed: {s}", .{@errorName(err)});
        return err;
    };
}

test "21 - request-response between masters" {
    std.testing.log_level = .debug;
    var threaded: std.Io.Threaded = std.Io.Threaded.init(testing.allocator, .{});
    defer threaded.deinit();
    const tio: Io = threaded.io();
    layer4.request_response.run(testing.allocator, tio) catch |err| {
        std.log.err("example failed: {s}", .{@errorName(err)});
        return err;
    };
}

test "22 - timer via mailbox" {
    std.testing.log_level = .debug;
    var threaded: std.Io.Threaded = std.Io.Threaded.init(testing.allocator, .{});
    defer threaded.deinit();
    const tio: Io = threaded.io();
    layer4.timer_via_mailbox.run(testing.allocator, tio) catch |err| {
        std.log.err("example failed: {s}", .{@errorName(err)});
        return err;
    };
}

test "23 - OOB signal via send_oob" {
    std.testing.log_level = .debug;
    var threaded: std.Io.Threaded = std.Io.Threaded.init(testing.allocator, .{});
    defer threaded.deinit();
    const tio: Io = threaded.io();
    layer4.oob_signal.run(testing.allocator, tio) catch |err| {
        std.log.err("example failed: {s}", .{@errorName(err)});
        return err;
    };
}

test "24 - multiple event sources one mailbox" {
    std.testing.log_level = .debug;
    var threaded: std.Io.Threaded = std.Io.Threaded.init(testing.allocator, .{});
    defer threaded.deinit();
    const tio: Io = threaded.io();
    layer4.multi_source_mailbox.run(testing.allocator, tio) catch |err| {
        std.log.err("example failed: {s}", .{@errorName(err)});
        return err;
    };
}
