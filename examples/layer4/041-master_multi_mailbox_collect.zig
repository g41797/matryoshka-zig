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

const Ctx = struct {
    mbh_a: MailboxHandle,
    mbh_b: MailboxHandle,
    alloc: std.mem.Allocator,

    fn fillMailboxA(self: *Ctx) !void {
        for (0..N_A) |i| {
            var slot: Slot = null;
            defer types.EventPolyHelper.destroy(self.alloc, &slot);
            try types.EventPolyHelper.create(self.alloc, &slot);
            types.EventPolyHelper.cast(slot.?).?.code = @intCast(i + 1);
            try mailbox.send(self.mbh_a, &slot);
        }
    }

    fn fillMailboxB(self: *Ctx) !void {
        for (0..N_B) |i| {
            var slot: Slot = null;
            defer types.SensorPolyHelper.destroy(self.alloc, &slot);
            try types.SensorPolyHelper.create(self.alloc, &slot);
            types.SensorPolyHelper.cast(slot.?).?.value = @floatFromInt(i + 10);
            try mailbox.send(self.mbh_b, &slot);
        }
    }

    fn closeAndMerge(self: *Ctx) std.DoublyLinkedList {
        var list_a: std.DoublyLinkedList = mailbox.close(self.mbh_a);
        mailbox.destroy(self.mbh_a, self.alloc);
        var list_b: std.DoublyLinkedList = mailbox.close(self.mbh_b);
        mailbox.destroy(self.mbh_b, self.alloc);
        list_a.concatByMoving(&list_b);
        std.log.info("concatByMoving: combined list has {d} items", .{N_A + N_B});
        return list_a;
    }
};

fn collectAndFree(combined: *std.DoublyLinkedList, alloc: std.mem.Allocator) usize {
    var freed: usize = 0;
    while (combined.popFirst()) |node| {
        const poly: *polynode.PolyNode = @fieldParentPtr("node", node);
        polynode.reset(poly);
        helpers.freeItem(poly, alloc);
        freed += 1;
    }
    return freed;
}

pub fn run(allocator: std.mem.Allocator, io: std.Io) !void {
    const mbh_a: MailboxHandle = try mailbox.new(io, allocator);
    const mbh_b: MailboxHandle = try mailbox.new(io, allocator);

    var ctx: Ctx = .{ .mbh_a = mbh_a, .mbh_b = mbh_b, .alloc = allocator };
    try ctx.fillMailboxA();
    try ctx.fillMailboxB();
    std.log.info("before collect: {d} in mailbox_a, {d} in mailbox_b", .{ N_A, N_B });

    var combined: std.DoublyLinkedList = ctx.closeAndMerge();
    const freed = collectAndFree(&combined, allocator);

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
