// SPDX-FileCopyrightText: Copyright (c) 2026 g41797
// SPDX-License-Identifier: MIT

// Ownership:
//
//  pool (seeded: Event×3, all empty — code=0)
//  │ getWaitResult — blocks until item available
//  ▼
//  Select(MasterEvent) ◄── sleepFn (timer)
//  │
//  .pool_ev .item ──► fill ev.code from Master counter ──► put back
//                 ──► re-spawn getWaitResult (while cycle < target)
//                 ──► break (when cycle == target, timer still in-flight)
//  .timer         ──► log Master counter ──► re-spawn timer
//  │
//  sel.cancelDiscard() ──► timer cancelled (no items in-flight at this point)
//  pool.close ──► on_close ──► freed
//
//  Work input: Master's own cycle counter. Pool item is an empty container.
//  Stop condition: cycle reaches target. getWaitResult not re-spawned at target,
//  so cancelDiscard only cancels the timer — no items in-transit, no leak.

const N_ITEMS: usize = 3;
const TARGET: usize = N_ITEMS * 2; // process each container twice
const TIMER_NS: i96 = 30_000_000; // 30 ms

const MasterEvent = union(enum) {
    pool_ev: pool.PoolResult,
    timer: void,
};

fn sleepFn(sleep_t: std.Io.Timeout, io: std.Io) void {
    std.Io.Timeout.sleep(sleep_t, io) catch {};
}

fn seedPool(ph: PoolHandle) !void {
    for (0..N_ITEMS) |_| {
        var slot: Slot = null;
        try pool.get(ph, types.EventPolyHelper.TAG, .new_only, &slot);
        pool.put(ph, &slot);
    }
}

fn setupSelect(ph: PoolHandle, io: std.Io, sel: *std.Io.Select(MasterEvent)) !void {
    const sleep_t: std.Io.Timeout = .{
        .duration = .{ .raw = .{ .nanoseconds = TIMER_NS }, .clock = .real },
    };
    try sel.concurrent(.pool_ev, pool.getWaitResult, .{ ph, types.EventPolyHelper.TAG, null });
    try sel.concurrent(.timer, sleepFn, .{ sleep_t, io });
}

fn runEventLoop(ph: PoolHandle, io: std.Io, sel: *std.Io.Select(MasterEvent)) !usize {
    var cycle: usize = 0;
    while (true) {
        const event: MasterEvent = try sel.await();
        switch (event) {
            .pool_ev => |r| switch (r) {
                .item => |handle| {
                    var slot: Slot = handle;
                    defer pool.put(ph, &slot);
                    const ev: *types.Event = types.EventPolyHelper.cast(slot.?).?;
                    ev.code = @intCast(cycle);
                    cycle += 1;
                    std.log.info("pool_ev: filled container with cycle={d}", .{ev.code});
                    if (cycle < TARGET) {
                        try sel.concurrent(.pool_ev, pool.getWaitResult, .{ ph, types.EventPolyHelper.TAG, null });
                    } else {
                        break;
                    }
                },
                .closed, .canceled, .timeout, .not_created => break,
            },
            .timer => {
                std.log.info("timer: maintenance — cycles completed so far: {d}", .{cycle});
                const sleep_t: std.Io.Timeout = .{
                    .duration = .{ .raw = .{ .nanoseconds = TIMER_NS }, .clock = .real },
                };
                try sel.concurrent(.timer, sleepFn, .{ sleep_t, io });
            },
        }
    }
    sel.cancelDiscard();
    return cycle;
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

    var buf: [4]MasterEvent = undefined;
    var sel: std.Io.Select(MasterEvent) = std.Io.Select(MasterEvent).init(io, &buf);
    try setupSelect(ph, io, &sel);
    const cycle = try runEventLoop(ph, io, &sel);

    try helpers.expect(error.SelectPoolEventFailed, cycle == TARGET, "wrong cycle count");
    std.log.info("done: {d} cycles driven by Master counter — pool items were empty containers", .{cycle});
}

const helpers = @import("helpers");
const matryoshka = @import("matryoshka");
const std = @import("std");
const pool = matryoshka.pool;
const polynode = matryoshka.polynode;
const Slot = polynode.Slot;
const PoolHandle = pool.PoolHandle;
const types = helpers.types;
