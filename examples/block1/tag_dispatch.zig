pub fn run(allocator: std.mem.Allocator, io: std.Io) !void {
    _ = io;
    var list: std.DoublyLinkedList = .{};

    defer freeRemaining(&list, allocator);

    const ev: *types.Event = try allocator.create(types.Event);
    ev.* = .{ .code = 7 };
    types.EventPolyHelper.init(ev);
    list.append(&ev.*.poly.node);

    const sn: *types.Sensor = try allocator.create(types.Sensor);
    sn.* = .{ .value = 2.71 };
    types.SensorPolyHelper.init(sn);
    list.append(&sn.*.poly.node);

    var processed_events: usize = 0;
    var processed_sensors: usize = 0;

    while (list.popFirst()) |node| {
        const poly: *polynode.PolyNode = @fieldParentPtr("node", node);

        if (types.EventPolyHelper.cast(poly)) |recovered_ev| {
            try helpers.expect(error.TagDispatchFailed, recovered_ev.*.code == 7, "wrong event code");
            processed_events += 1;
            allocator.destroy(recovered_ev);
        } else if (types.SensorPolyHelper.cast(poly)) |recovered_sn| {
            try helpers.expect(error.TagDispatchFailed, recovered_sn.*.value == 2.71, "wrong sensor value");
            processed_sensors += 1;
            allocator.destroy(recovered_sn);
        } else {
            return error.UnknownTag;
        }
    }

    try helpers.expect(error.TagDispatchFailed, processed_events == 1, "wrong event count");
    try helpers.expect(error.TagDispatchFailed, processed_sensors == 1, "wrong sensor count");
}

fn freeRemaining(list: *std.DoublyLinkedList, alloc: std.mem.Allocator) void {
    while (list.popFirst()) |node| {
        const poly: *polynode.PolyNode = @fieldParentPtr("node", node);
        if (types.EventPolyHelper.cast(poly)) |ev| {
            alloc.destroy(ev);
        } else if (types.SensorPolyHelper.cast(poly)) |sn| {
            alloc.destroy(sn);
        }
    }
}

const std = @import("std");
const helpers = @import("helpers");
const polynode = @import("matryoshka").polynode;
const types = helpers.types;
