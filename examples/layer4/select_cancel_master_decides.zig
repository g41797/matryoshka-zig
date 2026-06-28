// SPDX-FileCopyrightText: Copyright (c) 2026 g41797
// SPDX-License-Identifier: MIT

// Ownership:
//
//  mbh1 (empty)    mbh2 (empty)
//  │ receiveResult  │ receiveResult
//  └────────┬───────┘
//            ▼
//  Select(MasterEvent) ◄── sleepFn (timer fires first — both mailboxes empty)
//  │
//  .timer ──► sel.cancel() loop
//             .inbox1 .canceled ──► master decides: close mbh1 permanently
//             .inbox2 .canceled ──► master decides: keep mbh2, re-spawn later
//  │
//  Phase 2: new Select, mbh2 only
//  send 2 items to mbh2 ──► receive them via fresh Select

const TIMER_NS: i96 = 6_000_000; // 6 ms — fires first (both mailboxes are empty)

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
    const mbh2: MailboxHandle = try mailbox.new(io, allocator);
    var mbh1_closed: bool = false;
    defer {
        if (!mbh1_closed) {
            var rem: std.DoublyLinkedList = mailbox.close(mbh1);
            helpers.freeList(&rem, allocator);
        }
        mailbox.destroy(mbh1, allocator);
        var rem2: std.DoublyLinkedList = mailbox.close(mbh2);
        helpers.freeList(&rem2, allocator);
        mailbox.destroy(mbh2, allocator);
    }

    const sleep_t: std.Io.Timeout = .{
        .duration = .{ .raw = .{ .nanoseconds = TIMER_NS }, .clock = .real },
    };

    // Phase 1: both mailboxes empty — timer fires first.
    var buf: [8]MasterEvent = undefined;
    var sel: std.Io.Select(MasterEvent) = std.Io.Select(MasterEvent).init(io, &buf);
    defer sel.cancelDiscard();

    try sel.concurrent(.inbox1, mailbox.receiveResult, .{ mbh1, null });
    try sel.concurrent(.inbox2, mailbox.receiveResult, .{ mbh2, null });
    try sel.concurrent(.timer, sleepFn, .{ sleep_t, io });

    const first: MasterEvent = try sel.await();
    try helpers.expect(error.SelectCancelMasterDecidesFailed, first == .timer, "expected timer to fire first");
    std.log.info("timer: making per-source decisions", .{});

    var respawn_inbox2: bool = false;

    while (sel.cancel()) |event| {
        switch (event) {
            .inbox1 => |r| switch (r) {
                .canceled, .closed => {
                    // Master decides: close mbh1 permanently — not interested anymore.
                    std.log.info("inbox1: stopped — master closes mbh1", .{});
                    var rem: std.DoublyLinkedList = mailbox.close(mbh1);
                    helpers.freeList(&rem, allocator);
                    mbh1_closed = true;
                },
                .item => |handle| {
                    var slot: Slot = handle;
                    helpers.freeSlot(&slot, allocator);
                },
                .timeout => {},
            },
            .inbox2 => |r| switch (r) {
                .canceled => {
                    // Master decides: keep mbh2 active — will re-spawn in Phase 2.
                    std.log.info("inbox2: canceled — master will continue using mbh2", .{});
                    respawn_inbox2 = true;
                },
                .item => |handle| {
                    var slot: Slot = handle;
                    helpers.freeSlot(&slot, allocator);
                },
                .closed, .timeout => {},
            },
            .timer => {},
        }
    }

    try helpers.expect(error.SelectCancelMasterDecidesFailed, mbh1_closed, "mbh1 should be closed");
    try helpers.expect(error.SelectCancelMasterDecidesFailed, respawn_inbox2, "expected inbox2 to be canceled");

    // Phase 2: continue with mbh2 only (master decided to keep it).
    // Send 2 items to mbh2 and receive them via a fresh Select.
    for (0..2) |i| {
        var slot: Slot = null;
        defer types.EventPolyHelper.destroy(allocator, &slot);
        try types.EventPolyHelper.create(allocator, &slot);
        types.EventPolyHelper.cast(slot.?).?.code = @intCast(i + 10);
        try mailbox.send(mbh2, &slot);
    }

    var buf2: [4]MasterEvent = undefined;
    var sel2: std.Io.Select(MasterEvent) = std.Io.Select(MasterEvent).init(io, &buf2);
    defer sel2.cancelDiscard();

    try sel2.concurrent(.inbox2, mailbox.receiveResult, .{ mbh2, null });

    var items_after: usize = 0;

    while (items_after < 2) {
        const event: MasterEvent = try sel2.await();
        switch (event) {
            .inbox2 => |r| switch (r) {
                .item => |handle| {
                    var slot: Slot = handle;
                    defer helpers.freeSlot(&slot, allocator);
                    items_after += 1;
                    std.log.info("inbox2 phase2: item code={d}", .{types.EventPolyHelper.cast(slot.?).?.code});
                    if (items_after < 2) {
                        try sel2.concurrent(.inbox2, mailbox.receiveResult, .{ mbh2, null });
                    }
                },
                .closed, .canceled, .timeout => break,
            },
            else => break,
        }
    }

    try helpers.expect(error.SelectCancelMasterDecidesFailed, items_after == 2, "expected 2 items from mbh2 in phase 2");
    std.log.info("done: mbh1 closed; mbh2 continued with {d} items in phase 2", .{items_after});
}

const helpers = @import("helpers");
const matryoshka = @import("matryoshka");
const std = @import("std");
const mailbox = matryoshka.mailbox;
const polynode = matryoshka.polynode;
const Slot = polynode.Slot;
const MailboxHandle = mailbox.MailboxHandle;
const types = helpers.types;
