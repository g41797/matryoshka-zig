// SPDX-FileCopyrightText: Copyright (c) 2026 g41797
// SPDX-License-Identifier: MIT

// Ownership (mailbox-less):
//
//  pool (1 item seeded)
//  │ Io.Group (3 workers; 1 item → 1 worker processes, 2 block in get_wait)
//  ├──► worker 0 ──pool.get_wait──► slot ──process──► pool.put ──► pool (exits)
//  ├──► worker 1 ──pool.get_wait──► (blocked — no more items)
//  └──► worker 2 ──pool.get_wait──► (blocked — no more items)
//  │
//  group.cancel ──► blocked workers get error.Canceled ──► exit
//  pool.close ──► on_close ──► freeList (recycled item freed)
//
//  No mailbox. Pool + Group controls worker lifecycle.

const N_WORKERS: usize = 3;
const N_ITEMS: usize = 1;

const WorkerCtx = struct {
    ph: PoolHandle,
    alloc: std.mem.Allocator,
    id: usize,
};

fn workerFn(ctx: *WorkerCtx) error{Canceled}!void {
    var slot: Slot = null;
    defer helpers.freeSlot(&slot, ctx.alloc); // fallback: frees if pool.put saw closed pool
    defer pool.put(ctx.ph, &slot);            // primary: recycles (clears slot when open)
    // Single get_wait — worker processes one item and exits.
    // Blocked workers get error.Canceled from group.cancel.
    pool.get_wait(ctx.ph, types.EventPolyHelper.TAG, &slot, null) catch |err| switch (err) {
        error.Canceled => return error.Canceled,
        error.Closed, error.NotAvailable, error.NotCreated, error.Timeout => return,
    };
    const ev: *types.Event = types.EventPolyHelper.cast(slot.?).?;
    ev.code += 1;
    std.log.info("worker {d}: processed code={d}", .{ ctx.id, ev.code });
}

pub fn run(allocator: std.mem.Allocator, io: std.Io) !void {
    const ph: PoolHandle = try pool.new(io, allocator);
    var pool_ctx: helpers.AlwaysCreateCtx = .{ .alloc = allocator };
    const tags = [_]*const anyopaque{types.EventPolyHelper.TAG};
    try pool.init(ph, pool_ctx.poolHooks(&tags));

    // Seed pool with N_ITEMS — fewer than workers; others block in get_wait.
    for (0..N_ITEMS) |i| {
        var slot: Slot = null;
        try pool.get(ph, types.EventPolyHelper.TAG, .new_only, &slot);
        types.EventPolyHelper.cast(slot.?).?.code = @intCast(i + 1);
        pool.put(ph, &slot);
    }

    var ctx0: WorkerCtx = .{ .ph = ph, .alloc = allocator, .id = 0 };
    var ctx1: WorkerCtx = .{ .ph = ph, .alloc = allocator, .id = 1 };
    var ctx2: WorkerCtx = .{ .ph = ph, .alloc = allocator, .id = 2 };

    var group: Io.Group = .init;

    try group.concurrent(io, workerFn, .{&ctx0});
    try group.concurrent(io, workerFn, .{&ctx1});
    try group.concurrent(io, workerFn, .{&ctx2});

    std.log.info("master: {d} workers running, {d} item in pool", .{ N_WORKERS, N_ITEMS });

    // Cancel all: blocked workers get error.Canceled; the one that processed already exited.
    // group.cancel waits for all workers to finish before returning.
    group.cancel(io);
    std.log.info("master: all workers stopped via group.cancel", .{});

    // All workers done — safe to close and destroy pool.
    pool.close(ph);
    pool.destroy(ph, allocator);
    std.log.info("pool.close: on_close freed remaining items — no mailbox needed", .{});
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
