// SPDX-FileCopyrightText: Copyright (c) 2026 g41797
// SPDX-License-Identifier: MIT

// Ownership:
//
//  pool.get ──► slot ──► pool.put ──► pool
//  │
//  get_wait_future ──► Future(PoolResult)
//  fut.await ──► PoolResult .item ──► slot (master owns)
//  │
//  pool.put ──► pool ──pool.close──► on_close ──► freeList

fn seedPool(ph: PoolHandle) !void {
    var slot: Slot = null;
    try pool.get(ph, types.EventPolyHelper.TAG, .new_only, &slot);
    types.EventPolyHelper.cast(slot.?).?.code = 7;
    pool.put(ph, &slot);
}

fn receiveViaFuture(ph: PoolHandle, io: std.Io) !void {
    var fut: std.Io.Future(pool.PoolResult) = try pool.get_wait_future(ph, types.EventPolyHelper.TAG, null);
    const result: pool.PoolResult = fut.await(io);

    switch (result) {
        .item => |handle| {
            var slot: Slot = handle;
            defer pool.put(ph, &slot);
            const ev: *types.Event = types.EventPolyHelper.cast(slot.?).?;
            try helpers.expect(error.GetWaitFutureDirectFailed, ev.code == 7, "wrong code");
            std.log.info("get_wait_future direct: got Event code={d}", .{ev.code});
        },
        else => return error.GetWaitFutureDirectFailed,
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

    try seedPool(ph);
    try receiveViaFuture(ph, io);
}

const helpers = @import("helpers");
const matryoshka = @import("matryoshka");
const std = @import("std");
const pool = matryoshka.pool;
const polynode = matryoshka.polynode;
const Slot = polynode.Slot;
const PoolHandle = pool.PoolHandle;
const types = helpers.types;
