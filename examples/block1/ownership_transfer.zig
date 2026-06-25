pub fn run() !void {
    const alloc: std.mem.Allocator = testing.allocator;

    const ev: *types.Event = try alloc.create(types.Event);
    errdefer alloc.destroy(ev);
    ev.* = .{ .code = 42 };
    types.EventPolyHelper.init(ev);

    var slot: polynode.Slot = &ev.*.poly;
    try testing.expect(slot != null);

    var list: std.DoublyLinkedList = .{};
    list.append(&ev.*.poly.node);
    slot = null;
    try testing.expectEqual(@as(polynode.Slot, null), slot);

    const node: *std.DoublyLinkedList.Node = list.popFirst() orelse return error.EmptyList;
    const poly: *polynode.PolyNode = @fieldParentPtr("node", node);
    slot = poly;
    try testing.expect(slot != null);

    const recovered: *types.Event = types.EventPolyHelper.cast(poly) orelse return error.CastFailed;
    try testing.expectEqual(@as(i32, 42), recovered.*.code);

    alloc.destroy(recovered);
    slot = null;
    try testing.expectEqual(@as(polynode.Slot, null), slot);
}

const std = @import("std");
const testing = std.testing;
const polynode = @import("matryoshka").polynode;
const types = @import("helpers").types;
