pub fn run() !void {
    const alloc: std.mem.Allocator = testing.allocator;
    var list: std.DoublyLinkedList = .{};

    defer freeRemaining(&list, alloc);

    const ev: *types.Event = try alloc.create(types.Event);
    ev.* = .{ .code = 7 };
    types.EventPolyHelper.init(ev);
    list.append(&ev.*.poly.node);

    const sn: *types.Sensor = try alloc.create(types.Sensor);
    sn.* = .{ .value = 2.71 };
    types.SensorPolyHelper.init(sn);
    list.append(&sn.*.poly.node);

    var processed_events: usize = 0;
    var processed_sensors: usize = 0;

    while (list.popFirst()) |node| {
        const poly: *polynode.PolyNode = @fieldParentPtr("node", node);

        if (types.EventPolyHelper.cast(poly)) |recovered_ev| {
            try testing.expectEqual(@as(i32, 7), recovered_ev.*.code);
            processed_events += 1;
            alloc.destroy(recovered_ev);
        } else if (types.SensorPolyHelper.cast(poly)) |recovered_sn| {
            try testing.expectEqual(@as(f64, 2.71), recovered_sn.*.value);
            processed_sensors += 1;
            alloc.destroy(recovered_sn);
        } else {
            return error.UnknownTag;
        }
    }

    try testing.expectEqual(@as(usize, 1), processed_events);
    try testing.expectEqual(@as(usize, 1), processed_sensors);
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
const testing = std.testing;
const polynode = @import("matryoshka").polynode;
const types = @import("helpers").types;
