// SPDX-FileCopyrightText: Copyright (c) 2026 g41797
// SPDX-License-Identifier: MIT

// Ownership:
//
//  mailbox (Event items)    pool (Sensor items)    timer
//  │ receiveResult           │ getWaitResult         │ sleepFn
//  └──────────────────┬──────┘                        │
//                     ▼                               │
//             Select(MasterEvent) ◄───────────────────┘
//                     │ sel.await() loop
//                     ▼
//  .inbox .item  ──► freeSlot             (count inbox)
//  .pool_ev .item──► pool.put             (count pool)
//  .timer        ──► re-spawn timer       (count ticks)
//  exit when inbox_target + pool_target reached ──► sel.cancelDiscard()

const TIMER_NS: i96 = 25_000_000; // 25 ms
const INBOX_TARGET: usize = 2;
const POOL_TARGET: usize = 2;

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
    const tags = [_]*const anyopaque{types.SensorPolyHelper.TAG};
    try pool.init(ph, pool_ctx.poolHooks(&tags));
    defer {
        pool.close(ph);
        pool.destroy(ph, allocator);
    }

    // Pre-load mailbox with Event items.
    for (0..INBOX_TARGET) |i| {
        var slot: Slot = null;
        defer types.EventPolyHelper.destroy(allocator, &slot);
        try types.EventPolyHelper.create(allocator, &slot);
        types.EventPolyHelper.cast(slot.?).?.code = @intCast(i + 1);
        try mailbox.send(mbh, &slot);
    }

    // Seed pool with Sensor items.
    for (0..POOL_TARGET) |i| {
        var slot: Slot = null;
        try pool.get(ph, types.SensorPolyHelper.TAG, .new_only, &slot);
        types.SensorPolyHelper.cast(slot.?).?.value = @floatFromInt(i + 10);
        pool.put(ph, &slot);
    }

    const sleep_t: std.Io.Timeout = .{
        .duration = .{ .raw = .{ .nanoseconds = TIMER_NS }, .clock = .real },
    };

    var buf: [8]MasterEvent = undefined;
    var sel: std.Io.Select(MasterEvent) = std.Io.Select(MasterEvent).init(io, &buf);

    try sel.concurrent(.inbox, mailbox.receiveResult, .{ mbh, null });
    try sel.concurrent(.pool_ev, pool.getWaitResult, .{ ph, types.SensorPolyHelper.TAG, null });
    try sel.concurrent(.timer, sleepFn, .{ sleep_t, io });

    var inbox_count: usize = 0;
    var pool_count: usize = 0;
    var ticks: usize = 0;

    while (inbox_count < INBOX_TARGET or pool_count < POOL_TARGET) {
        const event: MasterEvent = try sel.await();
        switch (event) {
            .inbox => |r| switch (r) {
                .item => |handle| {
                    var slot: Slot = handle;
                    defer helpers.freeSlot(&slot, allocator);
                    inbox_count += 1;
                    std.log.info("inbox: Event code={d} ({d}/{d})", .{
                        types.EventPolyHelper.cast(slot.?).?.code,
                        inbox_count,
                        INBOX_TARGET,
                    });
                    if (inbox_count < INBOX_TARGET) {
                        try sel.concurrent(.inbox, mailbox.receiveResult, .{ mbh, null });
                    }
                },
                .closed, .canceled, .timeout => break,
            },
            .pool_ev => |r| switch (r) {
                .item => |handle| {
                    var slot: Slot = handle;
                    defer pool.put(ph, &slot);
                    pool_count += 1;
                    std.log.info("pool_ev: Sensor value={d} ({d}/{d})", .{
                        types.SensorPolyHelper.cast(slot.?).?.value,
                        pool_count,
                        POOL_TARGET,
                    });
                    if (pool_count < POOL_TARGET) {
                        try sel.concurrent(.pool_ev, pool.getWaitResult, .{ ph, types.SensorPolyHelper.TAG, null });
                    }
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

    try helpers.expect(error.SelectMixedSourcesFailed, inbox_count == INBOX_TARGET, "inbox count mismatch");
    try helpers.expect(error.SelectMixedSourcesFailed, pool_count == POOL_TARGET, "pool count mismatch");
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
