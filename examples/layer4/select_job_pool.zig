// SPDX-FileCopyrightText: Copyright (c) 2026 g41797
// SPDX-License-Identifier: MIT

// Ownership:
//
//  pool (seeded: Event×3)
//  │
//  worker1 ──pool.get──► process ──pool.put──► pool
//  worker2 ──pool.get──► process ──pool.put──► pool
//  worker3 ──pool.get──► process ──pool.put──► pool
//  │
//  master: Select(MasterEvent) ──getWaitResult──► .pool_ev .item
//          re-spawn getWaitResult after each item
//          stop after N_ITEMS returned
//  │
//  sel.cancelDiscard() ──► pool.close ──► on_close ──► freeList

const N_ITEMS: usize = 3;

const MasterEvent = union(enum) {
    pool_ev: pool.PoolResult,
};

const WorkerCtx = struct {
    ph: PoolHandle,
    alloc: std.mem.Allocator,
};

fn workerFn(ctx: *WorkerCtx) anyerror!void {
    var slot: Slot = null;
    try pool.get(ctx.ph, types.EventPolyHelper.TAG, .available_only, &slot);
    const ev: *types.Event = types.EventPolyHelper.cast(slot.?).?;
    std.log.info("worker: processing Event code={d}", .{ev.code});
    // Simulate work, then return to pool.
    pool.put(ctx.ph, &slot);
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

    // Seed pool with N_ITEMS.
    for (0..N_ITEMS) |i| {
        var slot: Slot = null;
        try pool.get(ph, types.EventPolyHelper.TAG, .new_only, &slot);
        types.EventPolyHelper.cast(slot.?).?.code = @intCast(i + 100);
        pool.put(ph, &slot);
    }

    // Launch workers that each take one item, process, put back.
    var ctx1: WorkerCtx = .{ .ph = ph, .alloc = allocator };
    var ctx2: WorkerCtx = .{ .ph = ph, .alloc = allocator };
    var ctx3: WorkerCtx = .{ .ph = ph, .alloc = allocator };
    var w1 = try io.concurrent(workerFn, .{&ctx1});
    var w2 = try io.concurrent(workerFn, .{&ctx2});
    var w3 = try io.concurrent(workerFn, .{&ctx3});

    // Master uses Select to watch the pool for returned items.
    var buf: [4]MasterEvent = undefined;
    var sel: std.Io.Select(MasterEvent) = std.Io.Select(MasterEvent).init(io, &buf);

    try sel.concurrent(.pool_ev, pool.getWaitResult, .{ ph, types.EventPolyHelper.TAG, null });

    var returned: usize = 0;

    while (returned < N_ITEMS) {
        const event: MasterEvent = try sel.await();
        switch (event) {
            .pool_ev => |r| switch (r) {
                .item => |handle| {
                    var slot: Slot = handle;
                    defer pool.put(ph, &slot);
                    const ev: *types.Event = types.EventPolyHelper.cast(slot.?).?;
                    returned += 1;
                    std.log.info("master: pool item returned code={d} ({d}/{d})", .{ ev.code, returned, N_ITEMS });
                    if (returned < N_ITEMS) {
                        try sel.concurrent(.pool_ev, pool.getWaitResult, .{ ph, types.EventPolyHelper.TAG, null });
                    }
                },
                .closed, .canceled, .timeout, .not_created => break,
            },
        }
    }

    sel.cancelDiscard();

    try w1.await(io);
    try w2.await(io);
    try w3.await(io);

    try helpers.expect(error.SelectJobPoolFailed, returned == N_ITEMS, "not all jobs returned");
    std.log.info("done: {d} jobs processed by workers, master tracked all returns", .{returned});
}

const helpers = @import("helpers");
const matryoshka = @import("matryoshka");
const std = @import("std");
const pool = matryoshka.pool;
const polynode = matryoshka.polynode;
const Slot = polynode.Slot;
const PoolHandle = pool.PoolHandle;
const types = helpers.types;
