// SPDX-FileCopyrightText: Copyright (c) 2026 g41797
// SPDX-License-Identifier: MIT

// Ownership (mailbox-less):
//
//  pool (1 item seeded)
//  │ io.concurrent
//  ▼
//  worker ──pool.get_wait──► slot (code += 1) ──pool.put──► pool
//  │
//  fut.await ──► master verifies pool has 1 item
//  pool.close ──► on_close ──► freed
//
//  No mailbox. Pool + Future is sufficient for simple single-worker coordination.

const WorkerCtx = struct {
    ph: PoolHandle,
    tag: *const anyopaque,
};

fn workerFn(ctx: *WorkerCtx) anyerror!void {
    var slot: Slot = null;
    try pool.get_wait(ctx.ph, ctx.tag, &slot, null);
    defer pool.put(ctx.ph, &slot);
    const ev: *types.Event = types.EventPolyHelper.cast(slot.?).?;
    ev.code += 1;
    std.log.info("worker: got slot from pool, code now {d} — putting back", .{ev.code});
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

    // Seed pool with 1 item (code=0).
    {
        var slot: Slot = null;
        try pool.get(ph, types.EventPolyHelper.TAG, .new_only, &slot);
        types.EventPolyHelper.cast(slot.?).?.code = 0;
        pool.put(ph, &slot);
    }
    std.log.info("master: seeded pool, spawning worker", .{});

    var ctx: WorkerCtx = .{ .ph = ph, .tag = types.EventPolyHelper.TAG };
    var fut = try io.concurrent(workerFn, .{&ctx});
    try fut.await(io);
    std.log.info("master: worker done", .{});

    // Verify pool has the item back (code incremented by worker).
    {
        var slot: Slot = null;
        defer pool.put(ph, &slot);
        try pool.get(ph, types.EventPolyHelper.TAG, .available_only, &slot);
        const ev: *types.Event = types.EventPolyHelper.cast(slot.?).?;
        try helpers.expect(error.MailboxLessPoolFutureFailed, ev.code == 1, "worker did not process item");
        std.log.info("done: pool item code={d} — Pool+Future, no mailbox", .{ev.code});
    }
}

const helpers = @import("helpers");
const matryoshka = @import("matryoshka");
const std = @import("std");
const pool = matryoshka.pool;
const polynode = matryoshka.polynode;
const Slot = polynode.Slot;
const PoolHandle = pool.PoolHandle;
const types = helpers.types;
