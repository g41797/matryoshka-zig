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
//  .timer ──► sel.cancel() loop
//             .inbox1 .canceled ──► log
//             .inbox2 .canceled ──► log
//  │
//  mailbox.close(mbh1) ──► freeList
//  mailbox.close(mbh2) ──► freeList

const TIMER_NS: i96 = 8_000_000; // 8 ms

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
    defer {
        var rem1: std.DoublyLinkedList = mailbox.close(mbh1);
        helpers.freeList(&rem1, allocator);
        mailbox.destroy(mbh1, allocator);
        var rem2: std.DoublyLinkedList = mailbox.close(mbh2);
        helpers.freeList(&rem2, allocator);
        mailbox.destroy(mbh2, allocator);
    }

    const sleep_t: std.Io.Timeout = .{
        .duration = .{ .raw = .{ .nanoseconds = TIMER_NS }, .clock = .real },
    };

    var buf: [8]MasterEvent = undefined;
    var sel: std.Io.Select(MasterEvent) = std.Io.Select(MasterEvent).init(io, &buf);

    try sel.concurrent(.inbox1, mailbox.receiveResult, .{ mbh1, null });
    try sel.concurrent(.inbox2, mailbox.receiveResult, .{ mbh2, null });
    try sel.concurrent(.timer, sleepFn, .{ sleep_t, io });

    const first: MasterEvent = try sel.await();
    switch (first) {
        .timer => std.log.info("timer: canceling both inbox sources", .{}),
        else => return error.SelectCancelCloseFailed,
    }

    var canceled1: bool = false;
    var canceled2: bool = false;

    while (sel.cancel()) |event| {
        switch (event) {
            .inbox1 => |r| switch (r) {
                .canceled => {
                    std.log.info("inbox1: .canceled", .{});
                    canceled1 = true;
                },
                .item => |handle| {
                    var slot: Slot = handle;
                    helpers.freeSlot(&slot, allocator);
                },
                .closed, .timeout => {},
            },
            .inbox2 => |r| switch (r) {
                .canceled => {
                    std.log.info("inbox2: .canceled", .{});
                    canceled2 = true;
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

    try helpers.expect(error.SelectCancelCloseFailed, canceled1 and canceled2, "expected both inboxes canceled");
    std.log.info("done: timer fired, sel.cancel() stopped both inbox sources", .{});
}

const helpers = @import("helpers");
const matryoshka = @import("matryoshka");
const std = @import("std");
const mailbox = matryoshka.mailbox;
const polynode = matryoshka.polynode;
const Slot = polynode.Slot;
const MailboxHandle = mailbox.MailboxHandle;
const types = helpers.types;
