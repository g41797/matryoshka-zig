// SPDX-FileCopyrightText: Copyright (c) 2026 g41797
// SPDX-License-Identifier: MIT

const WorkerCtx = struct {
    mbh: MailboxHandle,
    ph: PoolHandle,
};

fn workerFn(ctx: *WorkerCtx) anyerror!void {
    while (true) {
        var slot: Slot = null;
        mailbox.receive(ctx.mbh, &slot, null) catch return;
        // Return item to pool for recycling.
        pool.put(ctx.ph, &slot);
    }
}

pub fn run(allocator: std.mem.Allocator, io: std.Io) !void {
    const ph: PoolHandle = try pool.new(io, allocator);
    var pool_ctx: helpers.AlwaysCreateCtx = .{ .alloc = allocator };
    const tags = [_]*const anyopaque{types.EventPolyHelper.TAG};
    try pool.init(ph, pool_ctx.poolHooks(&tags));
    defer {
        pool.close(ph);
        pool.destroy(ph, allocator);
    }

    const mbh: MailboxHandle = try mailbox.new(io, allocator);
    defer {
        var rem: std.DoublyLinkedList = mailbox.close(mbh);
        helpers.freeList(&rem, allocator);
        mailbox.destroy(mbh, allocator);
    }

    // Seed mailbox: acquire Events from pool, send each to worker via mailbox.
    for (0..3) |i| {
        var slot: Slot = null;
        try pool.get(ph, types.EventPolyHelper.TAG, .available_or_new, &slot);
        const ev: *types.Event = types.EventPolyHelper.cast(slot.?).?;
        ev.code = @intCast(i + 1);
        std.log.info("master: sending Event code={d}", .{ev.code});
        try mailbox.send(mbh, &slot);
    }

    var ctx: WorkerCtx = .{ .mbh = mbh, .ph = ph };
    var fut = try io.concurrent(workerFn, .{&ctx});

    // cancel stops the worker at its next mailbox.receive.
    fut.cancel(io) catch {};

    std.log.info("master: worker stopped", .{});
}

const std = @import("std");
const helpers = @import("helpers");
const matryoshka = @import("matryoshka");
const mailbox = matryoshka.mailbox;
const pool = matryoshka.pool;
const polynode = matryoshka.polynode;
const Slot = polynode.Slot;
const MailboxHandle = mailbox.MailboxHandle;
const PoolHandle = pool.PoolHandle;
const types = helpers.types;
