// SPDX-FileCopyrightText: Copyright (c) 2026 g41797
// SPDX-License-Identifier: MIT

// Ownership:
//
//  worker1 ──EventPolyHelper.create──► slot ──pool.put──► pool
//  worker2 ──EventPolyHelper.create──► slot ──pool.put──► pool
//  worker3 ──EventPolyHelper.create──► slot ──pool.put──► pool
//  │
//  master: fut1.await + fut2.await + fut3.await (all done)
//  │
//  pool.get (×3) ──► slot ──► verify ──► freeSlot
//  │
//  pool.close ──► on_close ──► freeList (remaining items)

const WorkerCtx = struct {
    ph: PoolHandle,
    alloc: std.mem.Allocator,
    code: i32,
};

fn workerFn(ctx: *WorkerCtx) anyerror!void {
    var slot: Slot = null;
    try types.EventPolyHelper.create(ctx.alloc, &slot);
    types.EventPolyHelper.cast(slot.?).?.code = ctx.code;
    pool.put(ctx.ph, &slot);
    std.log.info("worker: put Event code={d}", .{ctx.code});
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

    var ctx1: WorkerCtx = .{ .ph = ph, .alloc = allocator, .code = 1 };
    var ctx2: WorkerCtx = .{ .ph = ph, .alloc = allocator, .code = 2 };
    var ctx3: WorkerCtx = .{ .ph = ph, .alloc = allocator, .code = 3 };

    var fut1 = try io.concurrent(workerFn, .{&ctx1});
    var fut2 = try io.concurrent(workerFn, .{&ctx2});
    var fut3 = try io.concurrent(workerFn, .{&ctx3});

    try fut1.await(io);
    try fut2.await(io);
    try fut3.await(io);

    // All 3 workers finished — get all 3 items from pool.
    var total: usize = 0;
    while (true) {
        var slot: Slot = null;
        pool.get(ph, types.EventPolyHelper.TAG, .available_only, &slot) catch break;
        defer helpers.freeSlot(&slot, allocator);
        const ev: *types.Event = types.EventPolyHelper.cast(slot.?).?;
        std.log.info("master: got Event code={d}", .{ev.code});
        total += 1;
    }

    try helpers.expect(error.PoolFanInFailed, total == 3, "expected 3 items from 3 workers");
    std.log.info("fan-in: {d} items — 3 workers → one pool → master", .{total});
}

const helpers = @import("helpers");
const matryoshka = @import("matryoshka");
const std = @import("std");
const pool = matryoshka.pool;
const polynode = matryoshka.polynode;
const Slot = polynode.Slot;
const PoolHandle = pool.PoolHandle;
const types = helpers.types;
