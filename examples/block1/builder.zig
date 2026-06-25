pub const Builder = struct {
    alloc: std.mem.Allocator,

    pub fn createEvent(self: Builder, code: i32) !*types.Event {
        const ev: *types.Event = try self.alloc.create(types.Event);
        ev.* = .{ .code = code };
        types.EventPolyHelper.init(ev);
        return ev;
    }

    pub fn createSensor(self: Builder, value: f64) !*types.Sensor {
        const sn: *types.Sensor = try self.alloc.create(types.Sensor);
        sn.* = .{ .value = value };
        types.SensorPolyHelper.init(sn);
        return sn;
    }

    pub fn destroyByTag(self: Builder, poly: *polynode.PolyNode) void {
        if (types.EventPolyHelper.cast(poly)) |ev| {
            self.alloc.destroy(ev);
        } else if (types.SensorPolyHelper.cast(poly)) |sn| {
            self.alloc.destroy(sn);
        }
    }
};

pub fn run() !void {
    const b: Builder = .{ .alloc = testing.allocator };

    const ev: *types.Event = try b.createEvent(100);
    errdefer b.destroyByTag(&ev.*.poly);

    const sn: *types.Sensor = try b.createSensor(9.8);
    defer b.destroyByTag(&sn.*.poly);

    try testing.expectEqual(@as(i32, 100), ev.*.code);
    try testing.expectEqual(@as(f64, 9.8), sn.*.value);

    b.destroyByTag(&ev.*.poly);
}

const std = @import("std");
const testing = std.testing;
const polynode = @import("matryoshka").polynode;
const types = @import("helpers").types;
