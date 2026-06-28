// SPDX-FileCopyrightText: Copyright (c) 2026 g41797
// SPDX-License-Identifier: MIT

const thread_count = 4;
const iterations = 8;

const WorkerCtx = struct {
    ph:    PoolHandle,
    alloc: std.mem.Allocator,
};

fn workerFn(ctx: *WorkerCtx) void {
    var i: usize = 0;
    while (i < iterations) : (i += 1) {
        var slot: Slot = null;
        defer pool.put(ctx.ph, &slot);
        pool.get(ctx.ph, types.EventPolyHelper.TAG, .available_or_new, &slot) catch return;
        std.log.debug("worker: got item", .{});
    }
}

pub fn run(allocator: std.mem.Allocator, io: std.Io) !void {
    const cap: usize = 2;
    var pool_ctx: helpers.CappedPoolCtx = .{ .alloc = allocator, .cap = cap, .io = io };
    const tags = [_]*const anyopaque{types.EventPolyHelper.TAG};

    const ph = try pool.new(io, allocator);
    defer {
        pool.close(ph);
        pool.destroy(ph, allocator);
    }
    try pool.init(ph, pool_ctx.poolHooks(&tags));

    var workers: [thread_count]WorkerCtx = undefined;
    var threads: [thread_count]std.Thread = undefined;

    for (&workers, &threads) |*wctx, *t| {
        wctx.* = .{ .ph = ph, .alloc = allocator };
        t.* = try std.Thread.spawn(.{}, workerFn, .{wctx});
    }

    for (&threads) |t| t.join();

    // consume remaining items to count them
    var in_pool: usize = 0;
    while (true) {
        var slot: Slot = null;
        defer types.EventPolyHelper.destroy(allocator, &slot);
        pool.get(ph, types.EventPolyHelper.TAG, .available_only, &slot) catch break;
        in_pool += 1;
    }

    std.log.info("capped pool (cap={d}): {d} items remain after {d} threads x {d} iterations", .{
        cap, in_pool, thread_count, iterations,
    });
    try helpers.expect(error.CappedPoolFailed, in_pool <= cap, "pool exceeded cap");
}

const helpers = @import("helpers");
const matryoshka = @import("matryoshka");
const std = @import("std");
const pool = matryoshka.pool;
const polynode = matryoshka.polynode;
const Slot = polynode.Slot;
const PoolHandle = pool.PoolHandle;
const types = helpers.types;
