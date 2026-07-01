// SPDX-FileCopyrightText: Copyright (c) 2026 g41797
// SPDX-License-Identifier: MIT

// Ownership (mailbox-less):
//
//  pool (N_WORKERS empty containers seeded — code=0)
//  │ Io.Group (N_WORKERS workers, each with own task index at spawn time)
//  ├──► worker 0 ──pool.get──► slot (empty) ──► ev.code = 0 ──► pool.put ──► pool
//  ├──► worker 1 ──pool.get──► slot (empty) ──► ev.code = 1 ──► pool.put ──► pool
//  └──► worker 2 ──pool.get──► slot (empty) ──► ev.code = 2 ──► pool.put ──► pool
//  │
//  group.cancel ──► any worker that has not yet returned exits (all likely done)
//  pool.close ──► on_close ──► freeList (remaining items freed)
//
//  Work input: task index passed at spawn time. Pool item is an empty container.
//  Each worker gets its own container, writes its index, returns it. No mailbox needed.

const N_WORKERS: usize = 3;

const WorkerCtx = struct {
    ph: PoolHandle,
    id: usize, // spawn-time task index
};

fn workerFn(ctx: *WorkerCtx) error{Canceled}!void {
    var slot: Slot = null;
    defer pool.put(ctx.ph, &slot); // null-safe: no-op if slot still null
    pool.get(ctx.ph, types.EventPolyHelper.TAG, .available_or_new, &slot) catch return;
    const ev: *types.Event = types.EventPolyHelper.cast(slot.?).?;
    ev.code = @intCast(ctx.id); // write spawn-time task index into empty container
    std.log.info("worker {d}: wrote task index into empty container (code={d})", .{ ctx.id, ev.code });
}

pub fn run(allocator: std.mem.Allocator, io: std.Io) !void {
    const ph: PoolHandle = try pool.new(io, allocator);
    var pool_ctx: helpers.AlwaysCreateCtx = .{ .alloc = allocator };
    const tags = [_]*const anyopaque{types.EventPolyHelper.TAG};
    try pool.init(ph, pool_ctx.poolHooks(&tags));

    // Seed N_WORKERS empty containers — one per worker, so each gets one immediately.
    for (0..N_WORKERS) |_| {
        var slot: Slot = null;
        try pool.get(ph, types.EventPolyHelper.TAG, .new_only, &slot);
        pool.put(ph, &slot);
    }

    var ctx0: WorkerCtx = .{ .ph = ph, .id = 0 };
    var ctx1: WorkerCtx = .{ .ph = ph, .id = 1 };
    var ctx2: WorkerCtx = .{ .ph = ph, .id = 2 };

    var group: Io.Group = .init;
    try group.concurrent(io, workerFn, .{&ctx0});
    try group.concurrent(io, workerFn, .{&ctx1});
    try group.concurrent(io, workerFn, .{&ctx2});

    std.log.info("master: {d} workers running, {d} empty containers in pool", .{ N_WORKERS, N_WORKERS });

    // Cancel any workers that have not yet returned.
    group.cancel(io);
    std.log.info("master: all workers stopped via group.cancel", .{});

    // All workers done — safe to close and destroy pool.
    pool.close(ph);
    pool.destroy(ph, allocator);
    std.log.info("pool closed: on_close freed any remaining containers — no mailbox needed", .{});
}

const helpers = @import("helpers");
const matryoshka = @import("matryoshka");
const std = @import("std");
const pool = matryoshka.pool;
const polynode = matryoshka.polynode;
const Slot = polynode.Slot;
const PoolHandle = pool.PoolHandle;
const Io = std.Io;
const types = helpers.types;
