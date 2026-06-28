// SPDX-FileCopyrightText: Copyright (c) 2026 g41797
// SPDX-License-Identifier: MIT

// Ownership:
//
//  mailbox_a (2 items)    mailbox_b (3 items)
//  │
//  mailbox_a.close ──► list_a (std.DoublyLinkedList, 2 items)
//  mailbox_b.close ──► list_b (std.DoublyLinkedList, 3 items)
//  list_a.concatByMoving(&list_b) ──► combined (5 items)
//  walk combined: popFirst ──► freeItem (×5)
//  │
//  One stdlib walk handles items from multiple mailboxes — no special API.

const N_A: usize = 2;
const N_B: usize = 3;

pub fn run(allocator: std.mem.Allocator, io: std.Io) !void {
    const mbh_a: MailboxHandle = try mailbox.new(io, allocator);
    const mbh_b: MailboxHandle = try mailbox.new(io, allocator);

    // Fill mailbox_a.
    for (0..N_A) |i| {
        var slot: Slot = null;
        defer types.EventPolyHelper.destroy(allocator, &slot);
        try types.EventPolyHelper.create(allocator, &slot);
        types.EventPolyHelper.cast(slot.?).?.code = @intCast(i + 1);
        try mailbox.send(mbh_a, &slot);
    }

    // Fill mailbox_b with Sensor items.
    for (0..N_B) |i| {
        var slot: Slot = null;
        defer types.SensorPolyHelper.destroy(allocator, &slot);
        try types.SensorPolyHelper.create(allocator, &slot);
        types.SensorPolyHelper.cast(slot.?).?.value = @floatFromInt(i + 10);
        try mailbox.send(mbh_b, &slot);
    }

    std.log.info("before collect: {d} in mailbox_a, {d} in mailbox_b", .{ N_A, N_B });

    // Close both mailboxes, collect their returned lists.
    var list_a: std.DoublyLinkedList = mailbox.close(mbh_a);
    mailbox.destroy(mbh_a, allocator);

    var list_b: std.DoublyLinkedList = mailbox.close(mbh_b);
    mailbox.destroy(mbh_b, allocator);

    // Merge via concatByMoving — list_a absorbs list_b. list_b becomes empty.
    list_a.concatByMoving(&list_b);
    std.log.info("concatByMoving: combined list has {d} items", .{N_A + N_B});

    // Walk the combined list — one pass cleans up items from both mailboxes.
    var freed: usize = 0;
    while (list_a.popFirst()) |node| {
        const poly: *polynode.PolyNode = @fieldParentPtr("node", node);
        polynode.reset(poly);
        helpers.freeItem(poly, allocator);
        freed += 1;
    }

    try helpers.expect(error.MasterMultiMailboxFailed, freed == N_A + N_B, "freed count mismatch");
    std.log.info("done: {d} items from {d} mailboxes — stdlib concatByMoving + popFirst walk", .{ freed, 2 });
}

const helpers = @import("helpers");
const matryoshka = @import("matryoshka");
const std = @import("std");
const mailbox = matryoshka.mailbox;
const polynode = matryoshka.polynode;
const Slot = polynode.Slot;
const MailboxHandle = mailbox.MailboxHandle;
const types = helpers.types;
