// SPDX-FileCopyrightText: Copyright (c) 2026 g41797
// SPDX-License-Identifier: MIT

// Ownership:
//
//  mailbox (empty)
//  │
//  receive_future(50ms) ──► Future(ReceiveResult)
//  fut.await ──► ReceiveResult .timeout
//  │
//  EventPolyHelper.create ──► slot ──mailbox.send──► mailbox
//  receive_future(null) ──► fut.await ──► ReceiveResult .item ──► freeSlot

const TIMEOUT_NS: u64 = 50_000_000; // 50 ms

pub fn run(allocator: std.mem.Allocator, io: std.Io) !void {
    const mbh: MailboxHandle = try mailbox.new(io, allocator);
    defer {
        var rem: std.DoublyLinkedList = mailbox.close(mbh);
        helpers.freeList(&rem, allocator);
        mailbox.destroy(mbh, allocator);
    }

    // Attempt receive on empty mailbox — expect .timeout.
    var fut_t: std.Io.Future(mailbox.ReceiveResult) = try mailbox.receive_future(mbh, TIMEOUT_NS);
    const r_timeout: mailbox.ReceiveResult = fut_t.await(io);
    try helpers.expect(error.ReceiveFutureTimeoutFailed, r_timeout == .timeout, "expected .timeout");
    std.log.info("receive_future timeout: got .timeout as expected", .{});

    // Now send an item and receive it with no timeout.
    var slot: Slot = null;
    defer types.EventPolyHelper.destroy(allocator, &slot);
    try types.EventPolyHelper.create(allocator, &slot);
    types.EventPolyHelper.cast(slot.?).?.code = 5;
    try mailbox.send(mbh, &slot);

    var fut_item: std.Io.Future(mailbox.ReceiveResult) = try mailbox.receive_future(mbh, null);
    const r_item: mailbox.ReceiveResult = fut_item.await(io);
    switch (r_item) {
        .item => |handle| {
            var received: Slot = handle;
            defer helpers.freeSlot(&received, allocator);
            std.log.info("receive_future after timeout: got Event code={d}", .{types.EventPolyHelper.cast(received.?).?.code});
        },
        else => return error.ReceiveFutureTimeoutFailed,
    }
}

const helpers = @import("helpers");
const matryoshka = @import("matryoshka");
const std = @import("std");
const mailbox = matryoshka.mailbox;
const polynode = matryoshka.polynode;
const Slot = polynode.Slot;
const MailboxHandle = mailbox.MailboxHandle;
const types = helpers.types;
