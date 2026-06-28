// SPDX-FileCopyrightText: Copyright (c) 2026 g41797
// SPDX-License-Identifier: MIT

// Ownership:
//
//  master: pool.get (×3, new_only) ──► pool (3 items seeded)
//  │
//  worker1 ──pool.get (.available_only)──► slot ──► verify ──► pool.put
//  worker2 ──pool.get (.available_only)──► slot ──► verify ──► pool.put
//  worker3 ──pool.get (.available_only)──► slot ──► verify ──► pool.put
//  │
//  fut1.await + fut2.await + fut3.await
//  pool.close ──► on_close ──► freeList

const WorkerCtx = struct {
    ph: PoolHandle,
    alloc: std.mem.Allocator,
    got: bool = false,
};

fn workerFn(ctx: *WorkerCtx) anyerror!void {
    var slot: Slot = null;
    defer pool.put(ctx.ph, &slot);
    try pool.get(ctx.ph, types.EventPolyHelper.TAG, .available_only, &slot);
    const ev: *types.Event = types.EventPolyHelper.cast(slot.?).?;
    std.log.info("worker: got Event code={d}", .{ev.code});
    ctx.got = true;
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

    // Seed 3 Events into the pool.
    for (0..3) |i| {
        var slot: Slot = null;
        try pool.get(ph, types.EventPolyHelper.TAG, .new_only, &slot);
        types.EventPolyHelper.cast(slot.?).?.code = @intCast(i + 10);
        pool.put(ph, &slot);
    }

    var ctx1: WorkerCtx = .{ .ph = ph, .alloc = allocator };
    var ctx2: WorkerCtx = .{ .ph = ph, .alloc = allocator };
    var ctx3: WorkerCtx = .{ .ph = ph, .alloc = allocator };

    var fut1 = try io.concurrent(workerFn, .{&ctx1});
    var fut2 = try io.concurrent(workerFn, .{&ctx2});
    var fut3 = try io.concurrent(workerFn, .{&ctx3});

    try fut1.await(io);
    try fut2.await(io);
    try fut3.await(io);

    const all_got = ctx1.got and ctx2.got and ctx3.got;
    try helpers.expect(error.PoolFanOutFailed, all_got, "not all workers got an item");
    std.log.info("fan-out: 1 pool seeded with 3 items → 3 workers each got 1", .{});
}

const helpers = @import("helpers");
const matryoshka = @import("matryoshka");
const std = @import("std");
const pool = matryoshka.pool;
const polynode = matryoshka.polynode;
const Slot = polynode.Slot;
const PoolHandle = pool.PoolHandle;
const types = helpers.types;
