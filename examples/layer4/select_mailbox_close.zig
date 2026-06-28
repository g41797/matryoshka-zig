// SPDX-FileCopyrightText: Copyright (c) 2026 g41797
// SPDX-License-Identifier: MIT

// Ownership:
//
//  mailbox (empty)
//  │ receiveResult (blocking)
//  ▼
//  Select(MasterEvent) ◄── sleepFn (timer, fires first)
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

pub fn run(allocator: std.mem.Allocator, io: std.Io) !void {
    const mbh: MailboxHandle = try mailbox.new(io, allocator);
    // Note: mailbox is closed inside the loop when timer fires — do not double-close.
    var mbh_closed: bool = false;
    defer {
        if (!mbh_closed) {
            var rem: std.DoublyLinkedList = mailbox.close(mbh);
            helpers.freeList(&rem, allocator);
        }
        mailbox.destroy(mbh, allocator);
    }

    const sleep_t: std.Io.Timeout = .{
        .duration = .{ .raw = .{ .nanoseconds = TIMER_NS }, .clock = .real },
    };

    var buf: [4]MasterEvent = undefined;
    var sel: std.Io.Select(MasterEvent) = std.Io.Select(MasterEvent).init(io, &buf);

    try sel.concurrent(.inbox, mailbox.receiveResult, .{ mbh, null });
    try sel.concurrent(.timer, sleepFn, .{ sleep_t, io });

    var got_closed: bool = false;

    loop: while (true) {
        const event: MasterEvent = try sel.await();
        switch (event) {
            .timer => {
                std.log.info("timer: closing mailbox while receiveResult is running", .{});
                var rem: std.DoublyLinkedList = mailbox.close(mbh);
                helpers.freeList(&rem, allocator);
                mbh_closed = true;
                // receiveResult will unblock with .closed; await it next.
            },
            .inbox => |r| switch (r) {
                .closed => {
                    std.log.info("inbox: .closed — mailbox.close propagated into Select", .{});
                    got_closed = true;
                    break :loop;
                },
                .item => |handle| {
                    var slot: Slot = handle;
                    helpers.freeSlot(&slot, allocator);
                },
                .canceled, .timeout => break :loop,
            },
        }
    }

    sel.cancelDiscard();

    try helpers.expect(error.SelectMailboxCloseFailed, got_closed, "expected .closed from Select inbox");
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
