// SPDX-FileCopyrightText: Copyright (c) 2026 g41797
// SPDX-License-Identifier: MIT

// Ownership:
//
//  mailbox (pre-loaded: Event×2)   pool (seeded: Event×1)
//     │ receiveResult                  │ getWaitResult
//     └────────────┬───────────────────┘
//                  ▼
//         Select(MasterEvent) ◄── sleepFn (timer)
//                  │ sel.await()
//                  ▼
//  .inbox .item ──► freeSlot
//  .pool_ev .item ──► pool.put
//  .timer         ──► log tick, re-spawn
//  done when inbox×2 + pool×1 received ──► sel.cancelDiscard()

const TIMER_NS: i96 = 20_000_000; // 20 ms

const MasterEvent = union(enum) {
    inbox: mailbox.ReceiveResult,
    pool_ev: pool.PoolResult,
    timer: void,
};

fn sleepFn(sleep_t: std.Io.Timeout, io: std.Io) void {
    std.Io.Timeout.sleep(sleep_t, io) catch {};
}

pub fn run(allocator: std.mem.Allocator, io: std.Io) !void {
    const mbh: MailboxHandle = try mailbox.new(io, allocator);
    defer {
        var rem: std.DoublyLinkedList = mailbox.close(mbh);
        helpers.freeList(&rem, allocator);
        mailbox.destroy(mbh, allocator);
    }

    const ph: PoolHandle = try pool.new(io, allocator);
    var pool_ctx: helpers.AlwaysCreateCtx = .{ .alloc = allocator };
    const tags = [_]*const anyopaque{types.EventPolyHelper.TAG};
    try pool.init(ph, pool_ctx.poolHooks(&tags));
    defer {
        pool.close(ph);
        pool.destroy(ph, allocator);
    }

    // Pre-load mailbox with 2 Events.
    for (0..2) |i| {
        var slot: Slot = null;
        defer types.EventPolyHelper.destroy(allocator, &slot);
        try types.EventPolyHelper.create(allocator, &slot);
        types.EventPolyHelper.cast(slot.?).?.code = @intCast(i + 1);
        try mailbox.send(mbh, &slot);
    }

    // Seed pool with 1 Event.
    {
        var slot: Slot = null;
        try pool.get(ph, types.EventPolyHelper.TAG, .new_only, &slot);
        types.EventPolyHelper.cast(slot.?).?.code = 10;
        pool.put(ph, &slot);
    }

    const sleep_t: std.Io.Timeout = .{
        .duration = .{ .raw = .{ .nanoseconds = TIMER_NS }, .clock = .real },
    };

    var buf: [8]MasterEvent = undefined;
    var sel: std.Io.Select(MasterEvent) = std.Io.Select(MasterEvent).init(io, &buf);

    try sel.concurrent(.inbox, mailbox.receiveResult, .{ mbh, null });
    try sel.concurrent(.pool_ev, pool.getWaitResult, .{ ph, types.EventPolyHelper.TAG, null });
    try sel.concurrent(.timer, sleepFn, .{ sleep_t, io });

    var inbox_count: usize = 0;
    var pool_count: usize = 0;
    var ticks: usize = 0;

    const want_inbox: usize = 2;
    const want_pool: usize = 1;

    while (inbox_count < want_inbox or pool_count < want_pool) {
        const event: MasterEvent = try sel.await();
        switch (event) {
            .inbox => |r| switch (r) {
                .item => |handle| {
                    var slot: Slot = handle;
                    defer helpers.freeSlot(&slot, allocator);
                    const ev: *types.Event = types.EventPolyHelper.cast(slot.?).?;
                    inbox_count += 1;
                    std.log.info("inbox: Event code={d} ({d}/{d})", .{ ev.code, inbox_count, want_inbox });
                    if (inbox_count < want_inbox) {
                        try sel.concurrent(.inbox, mailbox.receiveResult, .{ mbh, null });
                    }
                },
                .closed, .canceled, .timeout => break,
            },
            .pool_ev => |r| switch (r) {
                .item => |handle| {
                    var slot: Slot = handle;
                    defer pool.put(ph, &slot);
                    const ev: *types.Event = types.EventPolyHelper.cast(slot.?).?;
                    pool_count += 1;
                    std.log.info("pool_ev: Event code={d} ({d}/{d})", .{ ev.code, pool_count, want_pool });
                },
                .closed, .canceled, .timeout, .not_created => break,
            },
            .timer => {
                ticks += 1;
                std.log.info("timer: tick {d}", .{ticks});
                try sel.concurrent(.timer, sleepFn, .{ sleep_t, io });
            },
        }
    }

    sel.cancelDiscard();

    try helpers.expect(error.SelectMailboxPoolTimerFailed, inbox_count == want_inbox, "mailbox items mismatch");
    try helpers.expect(error.SelectMailboxPoolTimerFailed, pool_count == want_pool, "pool items mismatch");
    std.log.info("done: inbox={d}, pool={d}, ticks={d}", .{ inbox_count, pool_count, ticks });
}

const helpers = @import("helpers");
const matryoshka = @import("matryoshka");
const std = @import("std");
const mailbox = matryoshka.mailbox;
const pool = matryoshka.pool;
const polynode = matryoshka.polynode;
const Slot = polynode.Slot;
const MailboxHandle = mailbox.MailboxHandle;
const PoolHandle = pool.PoolHandle;
const types = helpers.types;
