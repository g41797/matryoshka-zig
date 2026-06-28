// SPDX-FileCopyrightText: Copyright (c) 2026 g41797
// SPDX-License-Identifier: MIT

// Ownership:
//
//  mbh1 (empty)    mbh2 (empty)
//  │ receiveResult  │ receiveResult
//  └────────┬───────┘
//           ▼
//  Select(MasterEvent) ◄── sleepFn (short timer fires first)
//  │
//  .timer ──► send item to mbh1, send item to mbh2
//             re-spawn timer (longer)
//  .inbox1 .item ──► freeSlot, re-spawn inbox1
//  .inbox2 .item ──► freeSlot
//  sel.cancelDiscard()

const SHORT_NS: i96 = 5_000_000; // 5 ms — fires before mailboxes have items
const LONG_NS: i96 = 50_000_000; // 50 ms — runs while mailboxes are being emptied

const MasterEvent = union(enum) {
    inbox1: mailbox.ReceiveResult,
    inbox2: mailbox.ReceiveResult,
    timer: void,
};

fn sleepFn(sleep_t: std.Io.Timeout, io: std.Io) void {
    std.Io.Timeout.sleep(sleep_t, io) catch {};
}

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

    const short_t: std.Io.Timeout = .{
        .duration = .{ .raw = .{ .nanoseconds = SHORT_NS }, .clock = .real },
    };
    const long_t: std.Io.Timeout = .{
        .duration = .{ .raw = .{ .nanoseconds = LONG_NS }, .clock = .real },
    };

    var buf: [8]MasterEvent = undefined;
    var sel: std.Io.Select(MasterEvent) = std.Io.Select(MasterEvent).init(io, &buf);

    // Both mailboxes are empty — timer fires first.
    try sel.concurrent(.inbox1, mailbox.receiveResult, .{ mbh1, null });
    try sel.concurrent(.inbox2, mailbox.receiveResult, .{ mbh2, null });
    try sel.concurrent(.timer, sleepFn, .{ short_t, io });

    var got1: bool = false;
    var got2: bool = false;

    loop: while (true) {
        const event: MasterEvent = try sel.await();
        switch (event) {
            .timer => {
                std.log.info("timer: fired — seeding both mailboxes and re-spawning longer timer", .{});
                // Now send items to both mailboxes so inbox sources can complete.
                var s1: Slot = null;
                defer types.EventPolyHelper.destroy(allocator, &s1);
                try types.EventPolyHelper.create(allocator, &s1);
                types.EventPolyHelper.cast(s1.?).?.code = 1;
                try mailbox.send(mbh1, &s1);

                var s2: Slot = null;
                defer types.EventPolyHelper.destroy(allocator, &s2);
                try types.EventPolyHelper.create(allocator, &s2);
                types.EventPolyHelper.cast(s2.?).?.code = 2;
                try mailbox.send(mbh2, &s2);

                try sel.concurrent(.timer, sleepFn, .{ long_t, io });
            },
            .inbox1 => |r| switch (r) {
                .item => |handle| {
                    var slot: Slot = handle;
                    defer helpers.freeSlot(&slot, allocator);
                    std.log.info("inbox1: Event code={d}", .{types.EventPolyHelper.cast(slot.?).?.code});
                    got1 = true;
                    if (!got2) {
                        try sel.concurrent(.inbox1, mailbox.receiveResult, .{ mbh1, null });
                    }
                },
                .closed, .canceled, .timeout => break :loop,
            },
            .inbox2 => |r| switch (r) {
                .item => |handle| {
                    var slot: Slot = handle;
                    defer helpers.freeSlot(&slot, allocator);
                    std.log.info("inbox2: Event code={d}", .{types.EventPolyHelper.cast(slot.?).?.code});
                    got2 = true;
                },
                .closed, .canceled, .timeout => break :loop,
            },
        }
        if (got1 and got2) break :loop;
    }

    sel.cancelDiscard();

    try helpers.expect(error.SelectTwoMailboxesFailed, got1 and got2, "did not receive from both mailboxes");
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
