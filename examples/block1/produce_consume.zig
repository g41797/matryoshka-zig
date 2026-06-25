pub fn run() !void {
    const alloc: std.mem.Allocator = testing.allocator;
    var list: std.DoublyLinkedList = .{};

    defer freeRemaining(&list, alloc);

    var i: i32 = 0;
    while (i < 5) : (i += 1) {
        const ev: *types.Event = try alloc.create(types.Event);
        ev.* = .{ .code = i };
        types.EventPolyHelper.init(ev);
        list.append(&ev.*.poly.node);
    }

    var sum: i32 = 0;
    while (list.popFirst()) |node| {
        const poly: *polynode.PolyNode = @fieldParentPtr("node", node);
        const ev: *types.Event = types.EventPolyHelper.cast(poly) orelse return error.CastFailed;
        sum += ev.*.code;
        alloc.destroy(ev);
    }

    try testing.expectEqual(@as(i32, 0 + 1 + 2 + 3 + 4), sum);
}

fn freeRemaining(list: *std.DoublyLinkedList, alloc: std.mem.Allocator) void {
    while (list.popFirst()) |node| {
        const poly: *polynode.PolyNode = @fieldParentPtr("node", node);
        if (types.EventPolyHelper.cast(poly)) |ev| {
            alloc.destroy(ev);
        }
    }
}

const std = @import("std");
const testing = std.testing;
const polynode = @import("matryoshka").polynode;
const types = @import("helpers").types;
