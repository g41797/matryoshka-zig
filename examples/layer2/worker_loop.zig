// SPDX-FileCopyrightText: Copyright (c) 2026 g41797
// SPDX-License-Identifier: MIT

const WorkerCtx = struct {
    mbh: MailboxHandle,
    alloc: std.mem.Allocator,
    event_sum: i32 = 0,
    sensor_sum: f64 = 0.0,
    count: usize = 0,
};

fn workerFn(ctx: *WorkerCtx) void {
    while (true) {
        var out: Slot = null;
        mailbox.receive(ctx.mbh, &out, null) catch return;
        const poly: *PolyNode = out.?;
        if (types.EventPolyHelper.cast(poly)) |ev| {
            std.log.debug("worker: Event code={d}", .{ev.code});
            ctx.event_sum += ev.code;
            ctx.count += 1;
            ctx.alloc.destroy(ev);
        } else if (types.SensorPolyHelper.cast(poly)) |sn| {
            std.log.debug("worker: Sensor value={d:.1}", .{sn.value});
            ctx.sensor_sum += sn.value;
            ctx.count += 1;
            ctx.alloc.destroy(sn);
        }
    }
}

pub fn run(allocator: std.mem.Allocator, io: std.Io) !void {
    const mbh: MailboxHandle = try mailbox.new(io, allocator);
    defer mailbox.destroy(mbh, allocator);

    var ctx: WorkerCtx = .{ .mbh = mbh, .alloc = allocator };
    const t = try std.Thread.spawn(.{}, workerFn, .{&ctx});

    const codes = [_]i32{ 1, 2, 3 };
    for (codes) |code| {
        const ev: *types.Event = try allocator.create(types.Event);
        ev.* = .{ .code = code };
        types.EventPolyHelper.init(ev);
        var slot: Slot = &ev.poly;
        try mailbox.send(mbh, &slot);
    }

    const values = [_]f64{ 1.5, 2.5 };
    for (values) |value| {
        const sn: *types.Sensor = try allocator.create(types.Sensor);
        sn.* = .{ .value = value };
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
    t.join();

    std.log.info("worker loop: processed={d} remaining={d} event_sum={d} sensor_sum={d:.1}", .{
        ctx.count, remaining, ctx.event_sum, ctx.sensor_sum,
    });
    try helpers.expect(error.WorkerLoopFailed, ctx.count + remaining == 5, "wrong total");
}

const std = @import("std");
const helpers = @import("helpers");
const matryoshka = @import("matryoshka");
const polynode = matryoshka.polynode;
const mailbox = matryoshka.mailbox;
const PolyNode = polynode.PolyNode;
const Slot = polynode.Slot;
const MailboxHandle = mailbox.MailboxHandle;
const types = helpers.types;
