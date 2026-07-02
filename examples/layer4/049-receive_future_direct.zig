// SPDX-FileCopyrightText: Copyright (c) 2026 g41797
// SPDX-License-Identifier: MIT

// Ownership:
//
//  master ──EventPolyHelper.create──► slot
//          ──mailbox.send──► mailbox
//          │
//  receive_future ──► Future(ReceiveResult)
//  fut.await ──► ReceiveResult .item ──► slot (master owns)
//          │
//  freeSlot

fn sendItem(mbh: MailboxHandle, alloc: std.mem.Allocator) !void {
    var slot: Slot = null;
    defer types.EventPolyHelper.destroy(alloc, &slot);
    try types.EventPolyHelper.create(alloc, &slot);
    types.EventPolyHelper.cast(slot.?).?.code = 42;
    try mailbox.send(mbh, &slot);
}

fn receiveAndVerify(mbh: MailboxHandle, alloc: std.mem.Allocator, io: std.Io) !void {
    var fut: std.Io.Future(mailbox.ReceiveResult) = try mailbox.receive_future(mbh, null);
    const result: mailbox.ReceiveResult = fut.await(io);

    switch (result) {
        .item => |handle| {
            var received: Slot = handle;
            defer helpers.freeSlot(&received, alloc);
            const ev: *types.Event = types.EventPolyHelper.cast(received.?).?;
            try helpers.expect(error.ReceiveFutureDirectFailed, ev.code == 42, "wrong code");
            std.log.info("receive_future direct: got Event code={d}", .{ev.code});
        },
        else => return error.ReceiveFutureDirectFailed,
    }
}

pub fn run(allocator: std.mem.Allocator, io: std.Io) !void {
    const mbh: MailboxHandle = try mailbox.new(io, allocator);
    defer {
        var rem: std.DoublyLinkedList = mailbox.close(mbh);
        helpers.freeList(&rem, allocator);
        mailbox.destroy(mbh, allocator);
    }

    try sendItem(mbh, allocator);
    try receiveAndVerify(mbh, allocator, io);
}

const helpers = @import("helpers");
const matryoshka = @import("matryoshka");
const std = @import("std");
const mailbox = matryoshka.mailbox;
const polynode = matryoshka.polynode;
const Slot = polynode.Slot;
const MailboxHandle = mailbox.MailboxHandle;
const types = helpers.types;
