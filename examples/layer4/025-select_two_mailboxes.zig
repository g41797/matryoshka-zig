// SPDX-FileCopyrightText: Copyright (c) 2026 g41797
// SPDX-License-Identifier: MIT

// Ownership:
//
//  mbh1 (empty)    mbh2 (empty)
//  │ receiveResult  │ receiveResult
//  └────────┬───────┘
//           ▼
//  Select(MasterEvent) ◄── sleepFn (short timer triggers first)
//  │
//  .timer ──► send item to mbh1, send item to mbh2
//             re-spawn timer (longer)
//  .inbox1 .item ──► freeSlot, re-spawn inbox1
//  .inbox2 .item ──► freeSlot
//  sel.cancelDiscard()

const SHORT_NS: i96 = 5_000_000; // 5 ms — triggers before mailboxes have items
const LONG_NS: i96 = 50_000_000; // 50 ms — runs while mailboxes are being emptied

const MasterEvent = union(enum) {
    inbox1: mailbox.ReceiveResult,
    inbox2: mailbox.ReceiveResult,
    timer: void,
};

fn sleepFn(sleep_t: std.Io.Timeout, io: std.Io) void {
    std.Io.Timeout.sleep(sleep_t, io) catch {};
}

const Ctx = struct {
    mbh1: MailboxHandle,
    mbh2: MailboxHandle,
    alloc: std.mem.Allocator,
    io: std.Io,
    got1: bool = false,
    got2: bool = false,

    fn seedMailboxes(self: *Ctx, sel: *std.Io.Select(MasterEvent)) !void {
        var s1: Slot = null;
        defer types.EventPolyHelper.destroy(self.alloc, &s1);
        try types.EventPolyHelper.create(self.alloc, &s1);
        types.EventPolyHelper.cast(s1.?).?.code = 1;
        try mailbox.send(self.mbh1, &s1);

        var s2: Slot = null;
        defer types.EventPolyHelper.destroy(self.alloc, &s2);
        try types.EventPolyHelper.create(self.alloc, &s2);
        types.EventPolyHelper.cast(s2.?).?.code = 2;
        try mailbox.send(self.mbh2, &s2);

        const long_t: std.Io.Timeout = .{
            .duration = .{ .raw = .{ .nanoseconds = LONG_NS }, .clock = .real },
        };
        try sel.concurrent(.timer, sleepFn, .{ long_t, self.io });
    }

    fn setupSelect(self: *Ctx, sel: *std.Io.Select(MasterEvent)) !void {
        const short_t: std.Io.Timeout = .{
            .duration = .{ .raw = .{ .nanoseconds = SHORT_NS }, .clock = .real },
        };
        try sel.concurrent(.inbox1, mailbox.receiveResult, .{ self.mbh1, null });
        try sel.concurrent(.inbox2, mailbox.receiveResult, .{ self.mbh2, null });
        try sel.concurrent(.timer, sleepFn, .{ short_t, self.io });
    }

    fn runEventLoop(self: *Ctx, sel: *std.Io.Select(MasterEvent)) !void {
        loop: while (true) {
            const event: MasterEvent = try sel.await();
            switch (event) {
                .timer => {
                    std.log.info("timer: fired — seeding both mailboxes and re-spawning longer timer", .{});
                    try self.seedMailboxes(sel);
                },
                .inbox1 => |r| switch (r) {
                    .item => |handle| {
                        var slot: Slot = handle;
                        defer helpers.freeSlot(&slot, self.alloc);
                        std.log.info("inbox1: Event code={d}", .{types.EventPolyHelper.cast(slot.?).?.code});
                        self.got1 = true;
                        if (!self.got2) {
                            try sel.concurrent(.inbox1, mailbox.receiveResult, .{ self.mbh1, null });
                        }
                    },
                    .closed, .canceled, .timeout => break :loop,
                },
                .inbox2 => |r| switch (r) {
                    .item => |handle| {
                        var slot: Slot = handle;
                        defer helpers.freeSlot(&slot, self.alloc);
                        std.log.info("inbox2: Event code={d}", .{types.EventPolyHelper.cast(slot.?).?.code});
                        self.got2 = true;
                    },
                    .closed, .canceled, .timeout => break :loop,
                },
            }
            if (self.got1 and self.got2) break :loop;
        }
        sel.cancelDiscard();
    }
};

pub fn run(allocator: std.mem.Allocator, io: std.Io) !void {
    const mbh1: MailboxHandle = try mailbox.new(io, allocator);
    defer {
        var rem: std.DoublyLinkedList = mailbox.close(mbh1);
        helpers.freeList(&rem, allocator);
        mailbox.destroy(mbh1, allocator);
    }

    const mbh2: MailboxHandle = try mailbox.new(io, allocator);
    defer {
        var rem: std.DoublyLinkedList = mailbox.close(mbh2);
        helpers.freeList(&rem, allocator);
        mailbox.destroy(mbh2, allocator);
    }

    var buf: [8]MasterEvent = undefined;
    var sel: std.Io.Select(MasterEvent) = std.Io.Select(MasterEvent).init(io, &buf);
    var ctx: Ctx = .{ .mbh1 = mbh1, .mbh2 = mbh2, .alloc = allocator, .io = io };
    try ctx.setupSelect(&sel);
    try ctx.runEventLoop(&sel);

    try helpers.expect(error.SelectTwoMailboxesFailed, ctx.got1 and ctx.got2, "did not receive from both mailboxes");
    std.log.info("done: timer fired first; then received from both mailboxes", .{});
}

const helpers = @import("helpers");
const matryoshka = @import("matryoshka");
const std = @import("std");
const mailbox = matryoshka.mailbox;
const polynode = matryoshka.polynode;
const Slot = polynode.Slot;
const MailboxHandle = mailbox.MailboxHandle;
const types = helpers.types;
