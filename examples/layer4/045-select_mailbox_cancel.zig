// SPDX-FileCopyrightText: Copyright (c) 2026 g41797
// SPDX-License-Identifier: MIT

// Ownership:
//
//  mailbox (empty)
//  │ receiveResult (blocking)
//  ▼
//  Select(MasterEvent) ◄── sleepFn (timer)
//  │
//  .timer ──► sel.cancel() loop ──► .inbox .canceled
//             (group.cancel signals receiveResult to stop)
//  │
//  mailbox.close ──► freeList ──► mailbox.destroy

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
    got_canceled: bool = false,

    fn setupSelect(self: *Ctx, sel: *std.Io.Select(MasterEvent)) !void {
        const sleep_t: std.Io.Timeout = .{
            .duration = .{ .raw = .{ .nanoseconds = TIMER_NS }, .clock = .real },
        };
        try sel.concurrent(.inbox, mailbox.receiveResult, .{ self.mbh, null });
        try sel.concurrent(.timer, sleepFn, .{ sleep_t, self.io });
    }

    fn awaitTimerFirst(sel: *std.Io.Select(MasterEvent)) !void {
        const first: MasterEvent = try sel.await();
        switch (first) {
            .timer => std.log.info("timer: canceling Select", .{}),
            else => return error.SelectMailboxCancelFailed,
        }
    }

    fn clearCanceled(self: *Ctx, sel: *std.Io.Select(MasterEvent)) void {
        while (sel.cancel()) |event| {
            switch (event) {
                .inbox => |r| switch (r) {
                    .canceled => {
                        std.log.info("inbox: .canceled — select.cancel propagated through mailbox", .{});
                        self.got_canceled = true;
                    },
                    .item => |handle| {
                        var slot: Slot = handle;
                        helpers.freeSlot(&slot, self.alloc);
                    },
                    .closed, .timeout => {},
                },
                .timer => {},
            }
        }
    }
};

pub fn run(allocator: std.mem.Allocator, io: std.Io) !void {
    const mbh: MailboxHandle = try mailbox.new(io, allocator);
    defer {
        var rem: std.DoublyLinkedList = mailbox.close(mbh);
        helpers.freeList(&rem, allocator);
        mailbox.destroy(mbh, allocator);
    }

    var buf: [4]MasterEvent = undefined;
    var sel: std.Io.Select(MasterEvent) = std.Io.Select(MasterEvent).init(io, &buf);
    var ctx: Ctx = .{ .mbh = mbh, .alloc = allocator, .io = io };
    try ctx.setupSelect(&sel);
    try Ctx.awaitTimerFirst(&sel);
    ctx.clearCanceled(&sel);

    try helpers.expect(error.SelectMailboxCancelFailed, ctx.got_canceled, "expected .canceled from inbox");
    std.log.info("done: sel.cancel() propagated .canceled through mailbox.receiveResult", .{});
}

const helpers = @import("helpers");
const matryoshka = @import("matryoshka");
const std = @import("std");
const mailbox = matryoshka.mailbox;
const polynode = matryoshka.polynode;
const Slot = polynode.Slot;
const MailboxHandle = mailbox.MailboxHandle;
const types = helpers.types;
