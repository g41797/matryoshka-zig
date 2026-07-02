// SPDX-FileCopyrightText: Copyright (c) 2026 g41797
// SPDX-License-Identifier: MIT

// Ownership:
//
//  mailbox (pre-loaded: Event×3)
//     │ receiveResult
//     ▼
//  Select(MasterEvent) ◄── sleepFn (timer, re-spawned each tick)
//     │ sel.await()
//     ▼
//  .inbox .item ──► freeSlot (re-spawn receiveResult)
//  .timer        ──► re-spawn sleepFn
//  .inbox .closed ──► exit loop
//  │
//  sel.cancelDiscard()

const TIMER_NS: i96 = 20_000_000; // 20 ms
const N_ITEMS: usize = 3;

const MasterEvent = union(enum) {
    inbox: mailbox.ReceiveResult,
    timer: void,
};

fn sleepFn(sleep_t: std.Io.Timeout, io: std.Io) void {
    std.Io.Timeout.sleep(sleep_t, io) catch {};
}

const Ctx = struct {
    mbh: MailboxHandle,
    alloc: std.mem.Allocator,
    io: std.Io,
    received: usize = 0,
    ticks: usize = 0,

    fn seedMailbox(self: *Ctx) !void {
        for (0..N_ITEMS) |i| {
            var slot: Slot = null;
            defer types.EventPolyHelper.destroy(self.alloc, &slot);
            try types.EventPolyHelper.create(self.alloc, &slot);
            types.EventPolyHelper.cast(slot.?).?.code = @intCast(i + 1);
            try mailbox.send(self.mbh, &slot);
        }
    }

    fn setupSelect(self: *Ctx, sel: *std.Io.Select(MasterEvent)) !void {
        const sleep_t: std.Io.Timeout = .{
            .duration = .{ .raw = .{ .nanoseconds = TIMER_NS }, .clock = .real },
        };
        try sel.concurrent(.inbox, mailbox.receiveResult, .{ self.mbh, null });
        try sel.concurrent(.timer, sleepFn, .{ sleep_t, self.io });
    }

    fn runEventLoop(self: *Ctx, sel: *std.Io.Select(MasterEvent)) !void {
        while (self.received < N_ITEMS) {
            const event: MasterEvent = try sel.await();
            switch (event) {
                .inbox => |r| switch (r) {
                    .item => |handle| {
                        var slot: Slot = handle;
                        defer helpers.freeSlot(&slot, self.alloc);
                        const ev: *types.Event = types.EventPolyHelper.cast(slot.?).?;
                        self.received += 1;
                        std.log.info("inbox: Event code={d} ({d}/{d})", .{ ev.code, self.received, N_ITEMS });
                        if (self.received < N_ITEMS) {
                            try sel.concurrent(.inbox, mailbox.receiveResult, .{ self.mbh, null });
                        }
                    },
                    .closed, .canceled, .timeout => break,
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

    var ctx: Ctx = .{ .mbh = mbh, .alloc = allocator, .io = io };
    try ctx.seedMailbox();

    var buf: [4]MasterEvent = undefined;
    var sel: std.Io.Select(MasterEvent) = std.Io.Select(MasterEvent).init(io, &buf);
    try ctx.setupSelect(&sel);
    try ctx.runEventLoop(&sel);

    try helpers.expect(error.SelectMailboxEventFailed, ctx.received == N_ITEMS, "did not receive all items");
    std.log.info("done: {d} items, {d} timer ticks", .{ ctx.received, ctx.ticks });
}

const helpers = @import("helpers");
const matryoshka = @import("matryoshka");
const std = @import("std");
const mailbox = matryoshka.mailbox;
const polynode = matryoshka.polynode;
const Slot = polynode.Slot;
const MailboxHandle = mailbox.MailboxHandle;
const types = helpers.types;
