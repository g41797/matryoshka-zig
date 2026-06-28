// SPDX-FileCopyrightText: Copyright (c) 2026 g41797
// SPDX-License-Identifier: MIT

// Ownership:
//
//  mailbox (single-threaded io)
//  │
//  receive_future ──► error.ConcurrencyUnavailable
//  (no concurrent task can be spawned on single-threaded backend)
//  │
//  mailbox.receive (synchronous) still works

pub fn run(allocator: std.mem.Allocator, io: std.Io) !void {
    const mbh: MailboxHandle = try mailbox.new(io, allocator);
    defer {
        var rem: std.DoublyLinkedList = mailbox.close(mbh);
        helpers.freeList(&rem, allocator);
        mailbox.destroy(mbh, allocator);
    }

    // receive_future fails on single-threaded backend.
    if (mailbox.receive_future(mbh, null)) |_| {
        return error.FutureSingleThreadedFailed;
    } else |_| {}
    std.log.info("receive_future: ConcurrencyUnavailable on single-threaded backend as expected", .{});

    // Synchronous receive still works: send then receive.
    var slot: Slot = null;
    defer types.EventPolyHelper.destroy(allocator, &slot);
    try types.EventPolyHelper.create(allocator, &slot);
    types.EventPolyHelper.cast(slot.?).?.code = 1;
    try mailbox.send(mbh, &slot);

    var received: Slot = null;
    defer helpers.freeSlot(&received, allocator);
    try mailbox.receive(mbh, &received, null);
    std.log.info("synchronous receive still works: code={d}", .{types.EventPolyHelper.cast(received.?).?.code});
}

const helpers = @import("helpers");
const matryoshka = @import("matryoshka");
const std = @import("std");
const mailbox = matryoshka.mailbox;
const polynode = matryoshka.polynode;
const Slot = polynode.Slot;
const MailboxHandle = mailbox.MailboxHandle;
const types = helpers.types;
