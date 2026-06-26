pub const types = @import("types.zig");

pub fn expect(comptime err: anyerror, ok: bool, comptime msg: []const u8) anyerror!void {
    if (!ok) {
        log.err("{s}", .{msg});
        return err;
    }
}

pub fn clearList(list: *std.DoublyLinkedList) void {
    while (list.popFirst()) |_| {}
}

pub fn freeItem(poly: *polynode.PolyNode, alloc: std.mem.Allocator) void {
    if (types.EventPolyHelper.cast(poly)) |ev| {
        alloc.destroy(ev);
    } else if (types.SensorPolyHelper.cast(poly)) |sn| {
        alloc.destroy(sn);
    }
}

pub fn freeList(list: *std.DoublyLinkedList, alloc: std.mem.Allocator) void {
    while (list.popFirst()) |node| {
        freeItem(@fieldParentPtr("node", node), alloc);
    }
}

const std = @import("std");
const log = std.log;
const polynode = @import("matryoshka").polynode;
