// SPDX-FileCopyrightText: Copyright (c) 2026 g41797
// SPDX-License-Identifier: MIT

// Ownership (mailbox-less):
//
//  pool (3 items seeded)
//  │ getWaitResult         timer (sleepFn)
//  └──────┬────────────────────────┘
//         ▼
//  Select(MasterEvent)
//  │
//  .pool_ev .item ──► fill (code++) ──► pool.put ──► pool (re-spawn getWaitResult)
//  .timer        ──► maintenance log ──► re-spawn timer (until N_ITEMS processed)
//  │
//  sel.cancelDiscard ──► pool.close ──► on_close ──► freed
//
//  No mailbox. Pool + Select drives job scheduling.

const TIMER_NS: i96 = 20_000_000; // 20 ms
const N_ITEMS: usize = 3;

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

    // Seed pool with N_ITEMS items.
    for (0..N_ITEMS) |i| {
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
    var ticks: usize = 0;

    while (processed < N_ITEMS) {
        const event: MasterEvent = try sel.await();
        switch (event) {
            .pool_ev => |r| switch (r) {
                .item => |handle| {
                    var slot: Slot = handle;
                    defer pool.put(ph, &slot);
                    const ev: *types.Event = types.EventPolyHelper.cast(slot.?).?;
                    ev.code += 100;
                    processed += 1;
                    std.log.info("pool_ev: scheduled item code={d} ({d}/{d})", .{ ev.code, processed, N_ITEMS });
                    if (processed < N_ITEMS) {
                        try sel.concurrent(.pool_ev, pool.getWaitResult, .{ ph, types.EventPolyHelper.TAG, null });
                    }
                },
                .closed, .canceled, .timeout, .not_created => break,
            },
            .timer => {
                ticks += 1;
                std.log.info("timer tick {d}: maintenance", .{ticks});
                try sel.concurrent(.timer, sleepFn, .{ sleep_t, io });
            },
        }
    }

    sel.cancelDiscard();

    try helpers.expect(error.MailboxLessSchedulerFailed, processed == N_ITEMS, "not all items scheduled");
    std.log.info("done: {d} jobs scheduled, {d} timer ticks — Pool+Select, no mailbox", .{ processed, ticks });
}

const helpers = @import("helpers");
const matryoshka = @import("matryoshka");
const std = @import("std");
const pool = matryoshka.pool;
const polynode = matryoshka.polynode;
const Slot = polynode.Slot;
const PoolHandle = pool.PoolHandle;
const types = helpers.types;
