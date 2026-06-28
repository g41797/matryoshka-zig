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

pub fn run(allocator: std.mem.Allocator, io: std.Io) !void {
    const mbh: MailboxHandle = try mailbox.new(io, allocator);
    defer {
        var rem: std.DoublyLinkedList = mailbox.close(mbh);
        helpers.freeList(&rem, allocator);
        mailbox.destroy(mbh, allocator);
    }

    for (0..N_ITEMS) |i| {
        var slot: Slot = null;
        defer types.EventPolyHelper.destroy(allocator, &slot);
        try types.EventPolyHelper.create(allocator, &slot);
        types.EventPolyHelper.cast(slot.?).?.code = @intCast(i + 1);
        try mailbox.send(mbh, &slot);
    }

    const sleep_t: std.Io.Timeout = .{
        .duration = .{ .raw = .{ .nanoseconds = TIMER_NS }, .clock = .real },
    };

    var buf: [4]MasterEvent = undefined;
    var sel: std.Io.Select(MasterEvent) = std.Io.Select(MasterEvent).init(io, &buf);

    try sel.concurrent(.inbox, mailbox.receiveResult, .{mbh, null});
    try sel.concurrent(.timer, sleepFn, .{sleep_t, io});

    var received: usize = 0;
    var ticks: usize = 0;

    while (received < N_ITEMS) {
        const event: MasterEvent = try sel.await();
        switch (event) {
            .inbox => |r| switch (r) {
                .item => |handle| {
                    var slot: Slot = handle;
                    defer helpers.freeSlot(&slot, allocator);
                    const ev: *types.Event = types.EventPolyHelper.cast(slot.?).?;
                    received += 1;
                    std.log.info("inbox: Event code={d} ({d}/{d})", .{ ev.code, received, N_ITEMS });
                    if (received < N_ITEMS) {
                        try sel.concurrent(.inbox, mailbox.receiveResult, .{mbh, null});
                    }
                },
                .closed, .canceled, .timeout => break,
            },
            .timer => {
                ticks += 1;
                std.log.info("timer: tick {d}", .{ticks});
                try sel.concurrent(.timer, sleepFn, .{sleep_t, io});
            },
        }
    }

    sel.cancelDiscard();

    try helpers.expect(error.SelectMailboxEventFailed, received == N_ITEMS, "did not receive all items");
    std.log.info("done: {d} items, {d} timer ticks", .{ received, ticks });
}

const helpers = @import("helpers");
const matryoshka = @import("matryoshka");
const std = @import("std");
const mailbox = matryoshka.mailbox;
const polynode = matryoshka.polynode;
const Slot = polynode.Slot;
const MailboxHandle = mailbox.MailboxHandle;
const types = helpers.types;
