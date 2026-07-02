// SPDX-FileCopyrightText: Copyright (c) 2026 g41797
// SPDX-License-Identifier: MIT

// Ownership:
//
//  mailbox (empty)
//  │ receiveResult (blocking)
//  ▼
//  Select(MasterEvent) ◄── sleepFn (timer triggers first)
//  │
//  .timer ──► mailbox.close(mbh) ──► freeList(rem)
//             (running receiveResult unblocks with .closed)
//  │
//  sel.await() ──► .inbox .closed
//  sel.cancelDiscard()

const TIMER_NS: i96 = 10_000_000; // 10 ms

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
    mbh_closed: bool = false,
    got_closed: bool = false,

    fn setupSelect(self: *Ctx, sel: *std.Io.Select(MasterEvent)) !void {
        const sleep_t: std.Io.Timeout = .{
            .duration = .{ .raw = .{ .nanoseconds = TIMER_NS }, .clock = .real },
        };
        try sel.concurrent(.inbox, mailbox.receiveResult, .{ self.mbh, null });
        try sel.concurrent(.timer, sleepFn, .{ sleep_t, self.io });
    }

    fn runEventLoop(self: *Ctx, sel: *std.Io.Select(MasterEvent)) !void {
        loop: while (true) {
            const event: MasterEvent = try sel.await();
            switch (event) {
                .timer => {
                    std.log.info("timer: closing mailbox while receiveResult is running", .{});
                    var rem: std.DoublyLinkedList = mailbox.close(self.mbh);
                    helpers.freeList(&rem, self.alloc);
                    self.mbh_closed = true;
                },
                .inbox => |r| switch (r) {
                    .closed => {
                        std.log.info("inbox: .closed — mailbox.close propagated into Select", .{});
                        self.got_closed = true;
                        break :loop;
                    },
                    .item => |handle| {
                        var slot: Slot = handle;
                        helpers.freeSlot(&slot, self.alloc);
                    },
                    .canceled, .timeout => break :loop,
                },
            }
        }
        sel.cancelDiscard();
    }
};

pub fn run(allocator: std.mem.Allocator, io: std.Io) !void {
    const mbh: MailboxHandle = try mailbox.new(io, allocator);
    var ctx: Ctx = .{ .mbh = mbh, .alloc = allocator, .io = io };
    defer {
        if (!ctx.mbh_closed) {
            var rem: std.DoublyLinkedList = mailbox.close(ctx.mbh);
            helpers.freeList(&rem, ctx.alloc);
        }
        mailbox.destroy(ctx.mbh, ctx.alloc);
    }

    var buf: [4]MasterEvent = undefined;
    var sel: std.Io.Select(MasterEvent) = std.Io.Select(MasterEvent).init(io, &buf);
    try ctx.setupSelect(&sel);
    try ctx.runEventLoop(&sel);

    try helpers.expect(error.SelectMailboxCloseFailed, ctx.got_closed, "expected .closed from Select inbox");
    std.log.info("done: mailbox.close propagated .closed through Select", .{});
}

const helpers = @import("helpers");
const matryoshka = @import("matryoshka");
const std = @import("std");
const mailbox = matryoshka.mailbox;
const polynode = matryoshka.polynode;
const Slot = polynode.Slot;
const MailboxHandle = mailbox.MailboxHandle;
const types = helpers.types;
