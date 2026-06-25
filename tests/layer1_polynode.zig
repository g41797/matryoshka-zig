// --- Scenario 1: Tag uniqueness ---
test "1 - tag uniqueness" {
    try testing.expect(EventPolyHelper.TAG != SensorPolyHelper.TAG);

    const tag1: *const anyopaque = EventPolyHelper.TAG;
    const tag2: *const anyopaque = EventPolyHelper.TAG;
    try testing.expectEqual(tag1, tag2);
}

// --- Scenario 2: Tag init ---
test "2 - tag init" {
    var ev: Event = .{};
    EventPolyHelper.init(&ev);
    try testing.expectEqual(EventPolyHelper.TAG, ev.poly.tag);
}

// --- Scenario 3: Tag identity check ---
test "3 - tag identity check" {
    var ev: Event = .{};
    EventPolyHelper.init(&ev);
    try testing.expect(EventPolyHelper.isIt(ev.poly.tag));
    try testing.expect(!SensorPolyHelper.isIt(ev.poly.tag));
}

// --- Scenario 4: @fieldParentPtr cast success ---
test "4 - fieldParentPtr cast success" {
    var ev: Event = .{ .code = 42 };
    EventPolyHelper.init(&ev);

    const poly: *PolyNode = &ev.poly;
    const recovered: *Event = EventPolyHelper.cast(poly) orelse unreachable;
    try testing.expectEqual(@as(i32, 42), recovered.*.code);
}

// --- Scenario 5: @fieldParentPtr cast wrong tag ---
test "5 - fieldParentPtr cast wrong tag" {
    var ev: Event = .{ .code = 42 };
    EventPolyHelper.init(&ev);

    const poly: *PolyNode = &ev.poly;
    const result: ?*Sensor = SensorPolyHelper.cast(poly);
    try testing.expectEqual(@as(?*Sensor, null), result);
}

// --- Scenario 6: Two-level @fieldParentPtr chain ---
test "6 - two-level fieldParentPtr chain" {
    var ev: Event = .{ .code = 99 };
    EventPolyHelper.init(&ev);

    const dll_node: *std.DoublyLinkedList.Node = &ev.poly.node;
    const poly: *PolyNode = @fieldParentPtr("node", dll_node);
    const recovered: *Event = EventPolyHelper.cast(poly) orelse unreachable;
    try testing.expectEqual(@as(i32, 99), recovered.*.code);
}

// --- Scenario 7: polynode.reset clears links ---
test "7 - polynode.reset clears links" {
    var ev: Event = .{};
    EventPolyHelper.init(&ev);

    ev.poly.node.prev = &ev.poly.node;
    ev.poly.node.next = &ev.poly.node;
    try testing.expect(polynode.is_linked(&ev.poly));

    polynode.reset(&ev.poly);
    try testing.expectEqual(@as(?*std.DoublyLinkedList.Node, null), ev.poly.node.prev);
    try testing.expectEqual(@as(?*std.DoublyLinkedList.Node, null), ev.poly.node.next);
}

// --- Scenario 8: polynode.is_linked detection ---
test "8 - polynode.is_linked detection" {
    var ev: Event = .{};
    EventPolyHelper.init(&ev);

    try testing.expect(!polynode.is_linked(&ev.poly));

    ev.poly.node.prev = &ev.poly.node;
    try testing.expect(polynode.is_linked(&ev.poly));

    polynode.reset(&ev.poly);
    try testing.expect(!polynode.is_linked(&ev.poly));
}

// --- Scenario 9: Slot null semantics ---
test "9 - slot null semantics" {
    var ev: Event = .{};
    EventPolyHelper.init(&ev);

    var slot: Slot = &ev.poly;
    try testing.expect(slot != null);

    slot = null;
    try testing.expectEqual(@as(Slot, null), slot);
}

// --- Scenario 10: Multiple types in one list ---
test "10 - multiple types in one list" {
    var ev: Event = .{ .code = 10 };
    EventPolyHelper.init(&ev);
    var sn: Sensor = .{ .value = 3.14 };
    SensorPolyHelper.init(&sn);

    var list: std.DoublyLinkedList = .{};
    list.append(&ev.poly.node);
    list.append(&sn.poly.node);

    var count_event: usize = 0;
    var count_sensor: usize = 0;

    while (list.popFirst()) |node| {
        const poly: *PolyNode = @fieldParentPtr("node", node);
        if (EventPolyHelper.cast(poly)) |recovered_ev| {
            try testing.expectEqual(@as(i32, 10), recovered_ev.*.code);
            count_event += 1;
        } else if (SensorPolyHelper.cast(poly)) |recovered_sn| {
            try testing.expectEqual(@as(f64, 3.14), recovered_sn.*.value);
            count_sensor += 1;
        } else {
            return error.UnexpectedTag;
        }
    }

    try testing.expectEqual(@as(usize, 1), count_event);
    try testing.expectEqual(@as(usize, 1), count_sensor);
}

// --- Scenario 11: FREE → IN_FLIGHT ---
test "11 - FREE to IN_FLIGHT" {
    var ev: Event = .{ .code = 1 };
    EventPolyHelper.init(&ev);

    const slot: Slot = &ev.poly;
    try testing.expect(slot != null);
    try testing.expect(!polynode.is_linked(&ev.poly));
}

// --- Scenario 12: IN_FLIGHT → HELD (list) ---
test "12 - IN_FLIGHT to HELD via list" {
    var ev1: Event = .{};
    EventPolyHelper.init(&ev1);
    var ev2: Event = .{};
    EventPolyHelper.init(&ev2);

    var slot: Slot = &ev1.poly;
    var list: std.DoublyLinkedList = .{};
    list.append(&ev1.poly.node);
    list.append(&ev2.poly.node);
    slot = null;

    try testing.expectEqual(@as(Slot, null), slot);
    try testing.expect(polynode.is_linked(&ev1.poly));
}

// --- Scenario 13: HELD → IN_FLIGHT (list) ---
test "13 - HELD to IN_FLIGHT via list pop" {
    var ev: Event = .{};
    EventPolyHelper.init(&ev);

    var list: std.DoublyLinkedList = .{};
    list.append(&ev.poly.node);

    const node: *std.DoublyLinkedList.Node = list.popFirst() orelse unreachable;
    const poly: *PolyNode = @fieldParentPtr("node", node);
    const slot: Slot = poly;

    try testing.expect(slot != null);
    try testing.expect(!polynode.is_linked(poly));
}

// --- Scenario 14: IN_FLIGHT → FREE ---
test "14 - IN_FLIGHT to FREE" {
    const alloc: std.mem.Allocator = testing.allocator;
    const ev: *Event = try alloc.create(Event);
    EventPolyHelper.init(ev);

    var slot: Slot = &ev.*.poly;
    try testing.expect(slot != null);

    const poly: *PolyNode = slot.?;
    const recovered: *Event = EventPolyHelper.cast(poly) orelse unreachable;
    alloc.destroy(recovered);
    slot = null;

    try testing.expectEqual(@as(Slot, null), slot);
}

// --- Scenario 17: Use after nil-out ---
test "17 - slot is null after nil-out" {
    var ev: Event = .{};
    EventPolyHelper.init(&ev);

    var slot: Slot = &ev.poly;
    slot = null;
    try testing.expectEqual(@as(Slot, null), slot);
}

const std = @import("std");
const testing = std.testing;

const types = @import("helpers").types;
const Event = types.Event;
const Sensor = types.Sensor;
const EventPolyHelper = types.EventPolyHelper;
const SensorPolyHelper = types.SensorPolyHelper;


const polynode = @import("matryoshka").polynode;
const PolyNode = polynode.PolyNode;
const Slot = polynode.Slot;
