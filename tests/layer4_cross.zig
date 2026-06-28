const layer4 = @import("examples").layer4;
const std = @import("std");
const testing = std.testing;
const Io = std.Io;

test "32 - Pool mailbox pool roundtrip same pointer" {
    std.testing.log_level = .debug;
    var threaded: Io.Threaded = Io.Threaded.init(testing.allocator, .{});
    defer threaded.deinit();
    const tio: Io = threaded.io();
    layer4.cross_layer_pool_mailbox_roundtrip.run(testing.allocator, tio) catch |err| {
        std.log.err("example failed: {s}", .{@errorName(err)});
        return err;
    };
}

test "33 - Mixed types Event and Sensor through shared mailbox" {
    std.testing.log_level = .debug;
    var threaded: Io.Threaded = Io.Threaded.init(testing.allocator, .{});
    defer threaded.deinit();
    const tio: Io = threaded.io();
    layer4.cross_layer_mixed_types_mailbox.run(testing.allocator, tio) catch |err| {
        std.log.err("example failed: {s}", .{@errorName(err)});
        return err;
    };
}

test "34 - Batch receive and pool put_all" {
    std.testing.log_level = .debug;
    var threaded: Io.Threaded = Io.Threaded.init(testing.allocator, .{});
    defer threaded.deinit();
    const tio: Io = threaded.io();
    layer4.cross_layer_batch_receive_pool_return.run(testing.allocator, tio) catch |err| {
        std.log.err("example failed: {s}", .{@errorName(err)});
        return err;
    };
}

test "35 - Pool hooks on_get on_put decide mailbox flow" {
    std.testing.log_level = .debug;
    var threaded: Io.Threaded = Io.Threaded.init(testing.allocator, .{});
    defer threaded.deinit();
    const tio: Io = threaded.io();
    layer4.cross_layer_pool_hooks_mailbox_flow.run(testing.allocator, tio) catch |err| {
        std.log.err("example failed: {s}", .{@errorName(err)});
        return err;
    };
}

test "36 - Close ordering pool then mailbox" {
    std.testing.log_level = .debug;
    var threaded: Io.Threaded = Io.Threaded.init(testing.allocator, .{});
    defer threaded.deinit();
    const tio: Io = threaded.io();
    layer4.cross_layer_close_pool_then_mailbox.run(testing.allocator, tio) catch |err| {
        std.log.err("example failed: {s}", .{@errorName(err)});
        return err;
    };
}

test "37 - Close ordering mailbox then pool" {
    std.testing.log_level = .debug;
    var threaded: Io.Threaded = Io.Threaded.init(testing.allocator, .{});
    defer threaded.deinit();
    const tio: Io = threaded.io();
    layer4.cross_layer_close_mailbox_then_pool.run(testing.allocator, tio) catch |err| {
        std.log.err("example failed: {s}", .{@errorName(err)});
        return err;
    };
}

test "38 - Pool mailbox flow single thread" {
    std.testing.log_level = .debug;
    var threaded: Io.Threaded = Io.Threaded.init(testing.allocator, .{});
    defer threaded.deinit();
    const tio: Io = threaded.io();
    layer4.cross_layer_pool_mailbox_flow.run(testing.allocator, tio) catch |err| {
        std.log.err("example failed: {s}", .{@errorName(err)});
        return err;
    };
}

test "39 - Master shutdown stdlib walk free both layers" {
    std.testing.log_level = .debug;
    var threaded: Io.Threaded = Io.Threaded.init(testing.allocator, .{});
    defer threaded.deinit();
    const tio: Io = threaded.io();
    layer4.master_shutdown_stdlib_cleanup.run(testing.allocator, tio) catch |err| {
        std.log.err("example failed: {s}", .{@errorName(err)});
        return err;
    };
}

test "40 - Master batch collect receive_batch to put_all" {
    std.testing.log_level = .debug;
    var threaded: Io.Threaded = Io.Threaded.init(testing.allocator, .{});
    defer threaded.deinit();
    const tio: Io = threaded.io();
    layer4.master_batch_drain_receive_to_pool.run(testing.allocator, tio) catch |err| {
        std.log.err("example failed: {s}", .{@errorName(err)});
        return err;
    };
}

test "41 - Master pre-shutdown collect multiple mailboxes" {
    std.testing.log_level = .debug;
    var threaded: Io.Threaded = Io.Threaded.init(testing.allocator, .{});
    defer threaded.deinit();
    const tio: Io = threaded.io();
    layer4.master_multi_mailbox_collect.run(testing.allocator, tio) catch |err| {
        std.log.err("example failed: {s}", .{@errorName(err)});
        return err;
    };
}

test "57 - Mailbox-less Pool and Future simple worker" {
    std.testing.log_level = .debug;
    var threaded: Io.Threaded = Io.Threaded.init(testing.allocator, .{});
    defer threaded.deinit();
    const tio: Io = threaded.io();
    layer4.mailbox_less_pool_future_worker.run(testing.allocator, tio) catch |err| {
        std.log.err("example failed: {s}", .{@errorName(err)});
        return err;
    };
}

test "58 - Mailbox-less Pool and Select job scheduler" {
    std.testing.log_level = .debug;
    var threaded: Io.Threaded = Io.Threaded.init(testing.allocator, .{});
    defer threaded.deinit();
    const tio: Io = threaded.io();
    layer4.mailbox_less_pool_select_scheduler.run(testing.allocator, tio) catch |err| {
        std.log.err("example failed: {s}", .{@errorName(err)});
        return err;
    };
}

test "59 - Mailbox-less Pool and Group worker pool" {
    std.testing.log_level = .debug;
    var threaded: Io.Threaded = Io.Threaded.init(testing.allocator, .{});
    defer threaded.deinit();
    const tio: Io = threaded.io();
    layer4.mailbox_less_pool_group_workers.run(testing.allocator, tio) catch |err| {
        std.log.err("example failed: {s}", .{@errorName(err)});
        return err;
    };
}

test "60 - Mailbox-less Pool and Select with network" {
    std.testing.log_level = .debug;
    var threaded: Io.Threaded = Io.Threaded.init(testing.allocator, .{});
    defer threaded.deinit();
    const tio: Io = threaded.io();
    layer4.mailbox_less_pool_select_network.run(testing.allocator, tio) catch |err| {
        std.log.err("example failed: {s}", .{@errorName(err)});
        return err;
    };
}

test "61 - Mailbox-less to mailbox transition for fan-in" {
    std.testing.log_level = .debug;
    var threaded: Io.Threaded = Io.Threaded.init(testing.allocator, .{});
    defer threaded.deinit();
    const tio: Io = threaded.io();
    layer4.mailbox_less_to_mailbox_transition.run(testing.allocator, tio) catch |err| {
        std.log.err("example failed: {s}", .{@errorName(err)});
        return err;
    };
}
