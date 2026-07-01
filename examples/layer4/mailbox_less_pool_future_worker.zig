// SPDX-FileCopyrightText: Copyright (c) 2026 g41797
// SPDX-License-Identifier: MIT

// Ownership (mailbox-less):
//
//  pool (1 empty container seeded — code=0)
//  │ io.concurrent (n=3 passed at spawn time)
//  ▼
//  worker loop (n cycles):
//    pool.get ──► slot (empty) ──► ev.code = worker counter ──► pool.put ──► pool
//  │
//  fut.await ──► master reads ctx.counter (= n after all cycles)
//  pool.close ──► on_close ──► freed
//
//  Work input: spawn-time arg n + worker's own counter.
//  Pool item is an empty container — a processing slot, not a data carrier.
//  No mailbox needed for simple single-worker coordination.

const N: usize = 3; // iteration count passed to worker at spawn time

const WorkerCtx = struct {
    ph: PoolHandle,
    tag: *const anyopaque,
    n: usize,
    counter: usize = 0,
};

fn workerFn(ctx: *WorkerCtx) anyerror!void {
    for (0..ctx.n) |_| {
        var slot: Slot = null;
        try pool.get_wait(ctx.ph, ctx.tag, &slot, null);
        defer pool.put(ctx.ph, &slot);
        const ev: *types.Event = types.EventPolyHelper.cast(slot.?).?;
        ev.code = @intCast(ctx.counter); // write counter into empty container
        ctx.counter += 1;
        std.log.info("worker: cycle {d} — wrote counter into empty container (code={d})", .{ ctx.counter, ev.code });
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

    // Seed 1 empty container — code=0, no work data.
    {
        var slot: Slot = null;
        try pool.get(ph, types.EventPolyHelper.TAG, .new_only, &slot);
        pool.put(ph, &slot);
    }

    var ctx: WorkerCtx = .{ .ph = ph, .tag = types.EventPolyHelper.TAG, .n = N };
    var fut: std.Io.Future(anyerror!void) = try io.concurrent(workerFn, .{&ctx});
    try fut.await(io);

    try helpers.expect(error.MailboxLessPoolFutureFailed, ctx.counter == N, "wrong cycle count");
    std.log.info("done: worker completed {d} cycles — counter={d}, pool item was empty container, no mailbox needed", .{ N, ctx.counter });
}

const helpers = @import("helpers");
const matryoshka = @import("matryoshka");
const std = @import("std");
const pool = matryoshka.pool;
const polynode = matryoshka.polynode;
const Slot = polynode.Slot;
const PoolHandle = pool.PoolHandle;
const types = helpers.types;
