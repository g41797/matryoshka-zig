const std = @import("std");
const block1 = @import("examples").block1;

const allocator = std.testing.allocator;
const io = std.Io.Threaded.global_single_threaded.*.io();

test "21 - define a PolyNode type" {
    std.testing.log_level = .debug;
    block1.define_type.run(allocator, io) catch |err| {
        std.log.err("example failed: {s}", .{@errorName(err)});
        return err;
    };
}

test "22 - ownership transfer via Slot" {
    std.testing.log_level = .debug;
    block1.ownership_transfer.run(allocator, io) catch |err| {
        std.log.err("example failed: {s}", .{@errorName(err)});
        return err;
    };
}

test "23 - tag-dispatch consume loop" {
    std.testing.log_level = .debug;
    block1.tag_dispatch.run(allocator, io) catch |err| {
        std.log.err("example failed: {s}", .{@errorName(err)});
        return err;
    };
}

test "24 - builder pattern" {
    std.testing.log_level = .debug;
    block1.builder.run(allocator, io) catch |err| {
        std.log.err("example failed: {s}", .{@errorName(err)});
        return err;
    };
}

test "25 - produce-consume with defer cleanup" {
    std.testing.log_level = .debug;
    block1.produce_consume.run(allocator, io) catch |err| {
        std.log.err("example failed: {s}", .{@errorName(err)});
        return err;
    };
}
