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

pub fn run(allocator: std.mem.Allocator, io: std.Io) !void {
    _ = io;
    const b: Builder = .{ .alloc = allocator };

    const ev: *types.Event = try b.createEvent(100);
    errdefer b.destroyByTag(&ev.*.poly);

    const sn: *types.Sensor = try b.createSensor(9.8);
    defer b.destroyByTag(&sn.*.poly);

    try helpers.expect(error.BuilderFailed, ev.*.code == 100, "wrong event code");
    try helpers.expect(error.BuilderFailed, sn.*.value == 9.8, "wrong sensor value");

    b.destroyByTag(&ev.*.poly);
}

const std = @import("std");
const helpers = @import("helpers");
const polynode = @import("matryoshka").polynode;
const types = helpers.types;
