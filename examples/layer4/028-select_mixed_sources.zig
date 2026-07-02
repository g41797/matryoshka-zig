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

fn seedMailbox(mbh: MailboxHandle, alloc: std.mem.Allocator, count: usize) !void {
    for (0..count) |i| {
        var slot: Slot = null;
        defer types.EventPolyHelper.destroy(alloc, &slot);
        try types.EventPolyHelper.create(alloc, &slot);
        types.EventPolyHelper.cast(slot.?).?.code = @intCast(i + 1);
        try mailbox.send(mbh, &slot);
    }
}

fn seedPool(ph: PoolHandle, count: usize) !void {
    for (0..count) |i| {
        var slot: Slot = null;
        try pool.get(ph, types.SensorPolyHelper.TAG, .new_only, &slot);
        types.SensorPolyHelper.cast(slot.?).?.value = @floatFromInt(i + 10);
        pool.put(ph, &slot);
    }
}

const Ctx = struct {
    mbh: MailboxHandle,
    ph: PoolHandle,
    alloc: std.mem.Allocator,
    io: std.Io,
    inbox_count: usize = 0,
    pool_count: usize = 0,
    ticks: usize = 0,

    fn setupSelect(self: *Ctx, sel: *std.Io.Select(MasterEvent)) !void {
        const sleep_t: std.Io.Timeout = .{
            .duration = .{ .raw = .{ .nanoseconds = TIMER_NS }, .clock = .real },
        };
        try sel.concurrent(.inbox, mailbox.receiveResult, .{ self.mbh, null });
        try sel.concurrent(.pool_ev, pool.getWaitResult, .{ self.ph, types.SensorPolyHelper.TAG, null });
        try sel.concurrent(.timer, sleepFn, .{ sleep_t, self.io });
    }

    fn runEventLoop(self: *Ctx, sel: *std.Io.Select(MasterEvent)) !void {
        while (self.inbox_count < INBOX_TARGET or self.pool_count < POOL_TARGET) {
            const event: MasterEvent = try sel.await();
            switch (event) {
                .inbox => |r| switch (r) {
                    .item => |handle| {
                        var slot: Slot = handle;
                        defer helpers.freeSlot(&slot, self.alloc);
                        self.inbox_count += 1;
                        std.log.info("inbox: Event code={d} ({d}/{d})", .{
                            types.EventPolyHelper.cast(slot.?).?.code,
                            self.inbox_count,
                            INBOX_TARGET,
                        });
                        if (self.inbox_count < INBOX_TARGET) {
                            try sel.concurrent(.inbox, mailbox.receiveResult, .{ self.mbh, null });
                        }
                    },
                    .closed, .canceled, .timeout => break,
                },
                .pool_ev => |r| switch (r) {
                    .item => |handle| {
                        var slot: Slot = handle;
                        defer pool.put(self.ph, &slot);
                        self.pool_count += 1;
                        std.log.info("pool_ev: Sensor value={d} ({d}/{d})", .{
                            types.SensorPolyHelper.cast(slot.?).?.value,
                            self.pool_count,
                            POOL_TARGET,
                        });
                        if (self.pool_count < POOL_TARGET) {
                            try sel.concurrent(.pool_ev, pool.getWaitResult, .{ self.ph, types.SensorPolyHelper.TAG, null });
                        }
                    },
                    .closed, .canceled, .timeout, .not_created => break,
                },
                .timer => {
                    self.ticks += 1;
                    std.log.info("timer: tick {d}", .{self.ticks});
                    const sleep_t: std.Io.Timeout = .{
                        .duration = .{ .raw = .{ .nanoseconds = TIMER_NS }, .clock = .real },
                    };
                    try sel.concurrent(.timer, sleepFn, .{ sleep_t, self.io });
                },
            }
        }
        sel.cancelDiscard();
    }
};

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

    try seedMailbox(mbh, allocator, INBOX_TARGET);
    try seedPool(ph, POOL_TARGET);

    var buf: [8]MasterEvent = undefined;
    var sel: std.Io.Select(MasterEvent) = std.Io.Select(MasterEvent).init(io, &buf);
    var ctx: Ctx = .{ .mbh = mbh, .ph = ph, .alloc = allocator, .io = io };
    try ctx.setupSelect(&sel);
    try ctx.runEventLoop(&sel);

    try helpers.expect(error.SelectMixedSourcesFailed, ctx.inbox_count == INBOX_TARGET, "inbox count mismatch");
    try helpers.expect(error.SelectMixedSourcesFailed, ctx.pool_count == POOL_TARGET, "pool count mismatch");
    std.log.info("done: inbox={d}, pool={d}, ticks={d}", .{ ctx.inbox_count, ctx.pool_count, ctx.ticks });
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
