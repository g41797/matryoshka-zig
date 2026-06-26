const WorkerCtx = struct {
    mbh: MailboxHandle,
    alloc: std.mem.Allocator,
    received: usize = 0,
};

fn fanOutWorkerFn(ctx: *WorkerCtx) void {
    while (true) {
        var out: Slot = null;
        mailbox.receive(ctx.mbh, &out, null) catch return;
        helpers.freeItem(out.?, ctx.alloc);
        ctx.received += 1;
    }
}

pub fn run(allocator: std.mem.Allocator, io: std.Io) !void {
    const mbh: MailboxHandle = try mailbox.new(io, allocator);
    defer mailbox.destroy(mbh, allocator);

    var ctx_a: WorkerCtx = .{ .mbh = mbh, .alloc = allocator };
    var ctx_b: WorkerCtx = .{ .mbh = mbh, .alloc = allocator };
    var ctx_c: WorkerCtx = .{ .mbh = mbh, .alloc = allocator };

    const ta = try std.Thread.spawn(.{}, fanOutWorkerFn, .{&ctx_a});
    const tb = try std.Thread.spawn(.{}, fanOutWorkerFn, .{&ctx_b});
    const tc = try std.Thread.spawn(.{}, fanOutWorkerFn, .{&ctx_c});

    const n_events: usize = 5;
    const n_sensors: usize = 4;

    var i: usize = 0;
    while (i < n_events) : (i += 1) {
        const ev: *types.Event = try allocator.create(types.Event);
        ev.* = .{ .code = @intCast(i) };
        types.EventPolyHelper.init(ev);
        var slot: Slot = &ev.poly;
        try mailbox.send(mbh, &slot);
    }

    i = 0;
    while (i < n_sensors) : (i += 1) {
        const sn: *types.Sensor = try allocator.create(types.Sensor);
        sn.* = .{ .value = @as(f64, @floatFromInt(i)) };
        types.SensorPolyHelper.init(sn);
        var slot: Slot = &sn.poly;
        try mailbox.send(mbh, &slot);
    }

    var rem: std.DoublyLinkedList = mailbox.close(mbh);
    var remaining: usize = 0;
    while (rem.popFirst()) |node| {
        helpers.freeItem(@fieldParentPtr("node", node), allocator);
        remaining += 1;
    }

    ta.join();
    tb.join();
    tc.join();

    const total: usize = ctx_a.received + ctx_b.received + ctx_c.received;
    std.log.info("fan-out: a={d} b={d} c={d} remaining={d}", .{ ctx_a.received, ctx_b.received, ctx_c.received, remaining });
    try helpers.expect(error.FanOutFailed, total + remaining == n_events + n_sensors, "wrong total");
}

const std = @import("std");
const helpers = @import("helpers");
const matryoshka = @import("matryoshka");
const polynode = matryoshka.polynode;
const mailbox = matryoshka.mailbox;
const Slot = polynode.Slot;
const MailboxHandle = mailbox.MailboxHandle;
const types = helpers.types;
