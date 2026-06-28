// SPDX-FileCopyrightText: Copyright (c) 2026 g41797
// SPDX-License-Identifier: MIT

// Ownership (mailbox-less):
//
//  pool (seeded)            mock network (sleepFn)
//  │ getWaitResult           │ networkReadFn
//  └──────────┬──────────────┘
//             ▼
//  Select(MasterEvent)
//  │
//  .pool_ev .item ──► process ──► pool.put ──► pool (re-spawn)
//  .network       ──► log receipt ──► re-spawn (until targets met)
//  │
//  sel.cancelDiscard ──► pool.close ──► on_close ──► freed
//
//  No mailbox. Pool + Select + external Io: two independent event sources.

const NET_DELAY_NS: i96 = 15_000_000; // 15 ms simulated network latency
const N_POOL_ITEMS: usize = 2;
const N_NET_ROUNDS: usize = 2;

const NetworkResult = struct { bytes: usize };

const MasterEvent = union(enum) {
    pool_ev: pool.PoolResult,
    network: NetworkResult,
};

fn networkReadFn(delay: std.Io.Timeout, io: std.Io) NetworkResult {
    std.Io.Timeout.sleep(delay, io) catch {};
    return .{ .bytes = 64 };
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

    // Seed pool with items.
    for (0..N_POOL_ITEMS) |i| {
        var slot: Slot = null;
        try pool.get(ph, types.EventPolyHelper.TAG, .new_only, &slot);
        types.EventPolyHelper.cast(slot.?).?.code = @intCast(i + 1);
        pool.put(ph, &slot);
    }

    const net_delay: std.Io.Timeout = .{
        .duration = .{ .raw = .{ .nanoseconds = NET_DELAY_NS }, .clock = .real },
    };

    var buf: [8]MasterEvent = undefined;
    var sel: std.Io.Select(MasterEvent) = std.Io.Select(MasterEvent).init(io, &buf);

    try sel.concurrent(.pool_ev, pool.getWaitResult, .{ ph, types.EventPolyHelper.TAG, null });
    try sel.concurrent(.network, networkReadFn, .{ net_delay, io });

    var pool_done: usize = 0;
    var net_done: usize = 0;

    while (pool_done < N_POOL_ITEMS or net_done < N_NET_ROUNDS) {
        const event: MasterEvent = try sel.await();
        switch (event) {
            .pool_ev => |r| switch (r) {
                .item => |handle| {
                    var slot: Slot = handle;
                    defer pool.put(ph, &slot);
                    const ev: *types.Event = types.EventPolyHelper.cast(slot.?).?;
                    ev.code += 10;
                    pool_done += 1;
                    std.log.info("pool_ev: processed code={d} ({d}/{d})", .{ ev.code, pool_done, N_POOL_ITEMS });
                    if (pool_done < N_POOL_ITEMS) {
                        try sel.concurrent(.pool_ev, pool.getWaitResult, .{ ph, types.EventPolyHelper.TAG, null });
                    }
                },
                .closed, .canceled, .timeout, .not_created => break,
            },
            .network => |r| {
                net_done += 1;
                std.log.info("network: {d} bytes received ({d}/{d})", .{ r.bytes, net_done, N_NET_ROUNDS });
                if (net_done < N_NET_ROUNDS) {
                    try sel.concurrent(.network, networkReadFn, .{ net_delay, io });
                }
            },
        }
    }

    sel.cancelDiscard();

    try helpers.expect(error.MailboxLessNetworkFailed, pool_done == N_POOL_ITEMS, "pool items not all processed");
    try helpers.expect(error.MailboxLessNetworkFailed, net_done == N_NET_ROUNDS, "network rounds not complete");
    std.log.info("done: pool={d} net={d} — Pool+Select+Network, no mailbox", .{ pool_done, net_done });
}

const helpers = @import("helpers");
const matryoshka = @import("matryoshka");
const std = @import("std");
const pool = matryoshka.pool;
const polynode = matryoshka.polynode;
const Slot = polynode.Slot;
const PoolHandle = pool.PoolHandle;
const types = helpers.types;
