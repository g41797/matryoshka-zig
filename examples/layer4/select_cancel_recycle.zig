// SPDX-FileCopyrightText: Copyright (c) 2026 g41797
// SPDX-License-Identifier: MIT

// Ownership:
//
//  pool (seeded: Event×3)
//  │ getWaitResult
//  ▼
//  Select(MasterEvent) ◄── sleepFn (timer)
//  │
//  .pool_ev .item ──► process ──pool.put──► pool   (1 item processed)
//  .timer ──► sel.cancel() loop
//             .pool_ev .item ──► pool.put (recycle, not freed!)
//             .pool_ev .canceled ──► (no item, skip)
//  │
//  pool.close ──► on_close ──► freeList (all recycled items freed cleanly)

const TIMER_NS: i96 = 15_000_000; // 15 ms

const MasterEvent = union(enum) {
    pool_ev: pool.PoolResult,
    timer: void,
};

fn sleepFn(sleep_t: std.Io.Timeout, io: std.Io) void {
    std.Io.Timeout.sleep(sleep_t, io) catch {};
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

    // Seed pool with 3 items.
    for (0..3) |i| {
        var slot: Slot = null;
        try pool.get(ph, types.EventPolyHelper.TAG, .new_only, &slot);
        types.EventPolyHelper.cast(slot.?).?.code = @intCast(i + 1);
        pool.put(ph, &slot);
    }

    const sleep_t: std.Io.Timeout = .{
        .duration = .{ .raw = .{ .nanoseconds = TIMER_NS }, .clock = .real },
    };

    var buf: [8]MasterEvent = undefined;
    var sel: std.Io.Select(MasterEvent) = std.Io.Select(MasterEvent).init(io, &buf);

    try sel.concurrent(.pool_ev, pool.getWaitResult, .{ ph, types.EventPolyHelper.TAG, null });
    try sel.concurrent(.timer, sleepFn, .{ sleep_t, io });

    var processed: usize = 0;
    var recycled: usize = 0;

    // Event loop: process 1 item, then let timer trigger cancel.
    loop: while (true) {
        const event: MasterEvent = try sel.await();
        switch (event) {
            .pool_ev => |r| switch (r) {
                .item => |handle| {
                    var slot: Slot = handle;
                    defer pool.put(ph, &slot); // put back = recycle
                    const ev: *types.Event = types.EventPolyHelper.cast(slot.?).?;
                    processed += 1;
                    std.log.info("pool_ev: processed code={d} → put back to pool", .{ev.code});
                    // Re-spawn pool watcher for next item.
                    try sel.concurrent(.pool_ev, pool.getWaitResult, .{ ph, types.EventPolyHelper.TAG, null });
                },
                .closed, .canceled, .timeout, .not_created => break :loop,
            },
            .timer => {
                std.log.info("timer: canceling remaining pool watchers", .{});
                break :loop;
            },
        }
    }

    // Walk remaining items from outstanding pool.getWaitResult and recycle them.
    while (sel.cancel()) |event| {
        switch (event) {
            .pool_ev => |r| switch (r) {
                .item => |handle| {
                    var slot: Slot = handle;
                    pool.put(ph, &slot); // recycle — do NOT free
                    recycled += 1;
                    std.log.info("cancel walk: recycled pool item (not freed)", .{});
                },
                .canceled, .closed, .timeout, .not_created => {},
            },
            .timer => {},
        }
    }

    std.log.info("done: processed={d}, recycled via cancel={d}", .{ processed, recycled });
    // pool.close (deferred above) will cleanly free any items still in pool via on_close.
}

const helpers = @import("helpers");
const matryoshka = @import("matryoshka");
const std = @import("std");
const pool = matryoshka.pool;
const polynode = matryoshka.polynode;
const Slot = polynode.Slot;
const PoolHandle = pool.PoolHandle;
const types = helpers.types;
