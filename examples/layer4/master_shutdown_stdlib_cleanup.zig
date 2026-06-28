// SPDX-FileCopyrightText: Copyright (c) 2026 g41797
// SPDX-License-Identifier: MIT

// Ownership:
//
//  pool (2 items)    mailbox (2 items)
//  │
//  mailbox.close ──► std.DoublyLinkedList ──► popFirst ──► freeItem (×2)
//  pool.close   ──► on_close ──► freeList (×2)
//  │
//  Entire shutdown: standard Zig stdlib — no Matryoshka-specific cleanup API.

const N_ITEMS: usize = 2;

pub fn run(allocator: std.mem.Allocator, io: std.Io) !void {
    const ph: PoolHandle = try pool.new(io, allocator);
    var pool_ctx: helpers.AlwaysCreateCtx = .{ .alloc = allocator };
    const tags = [_]*const anyopaque{types.EventPolyHelper.TAG};
    try pool.init(ph, pool_ctx.poolHooks(&tags));

    const mbh: MailboxHandle = try mailbox.new(io, allocator);

    // Seed mailbox with N_ITEMS items.
    for (0..N_ITEMS) |i| {
        var slot: Slot = null;
        defer types.EventPolyHelper.destroy(allocator, &slot);
        try types.EventPolyHelper.create(allocator, &slot);
        types.EventPolyHelper.cast(slot.?).?.code = @intCast(i + 1);
        try mailbox.send(mbh, &slot);
    }

    // Seed pool with N_ITEMS items.
    for (0..N_ITEMS) |i| {
        var slot: Slot = null;
        try pool.get(ph, types.EventPolyHelper.TAG, .new_only, &slot);
        types.EventPolyHelper.cast(slot.?).?.code = @intCast(100 + i);
        pool.put(ph, &slot);
    }

    std.log.info("master: shutdown initiated — {d} in mailbox, {d} in pool", .{ N_ITEMS, N_ITEMS });

    // Close mailbox — walk returned std.DoublyLinkedList with popFirst().
    var mbx_list: std.DoublyLinkedList = mailbox.close(mbh);
    var mbx_freed: usize = 0;
    while (mbx_list.popFirst()) |node| {
        const poly: *polynode.PolyNode = @fieldParentPtr("node", node);
        polynode.reset(poly);
        helpers.freeItem(poly, allocator);
        mbx_freed += 1;
    }
    mailbox.destroy(mbh, allocator);
    std.log.info("mailbox.close: freed {d} items via stdlib popFirst", .{mbx_freed});

    // Close pool — on_close handles its list internally.
    pool.close(ph);
    pool.destroy(ph, allocator);
    std.log.info("pool.close: on_close freed {d} pool items", .{N_ITEMS});

    try helpers.expect(error.MasterShutdownFailed, mbx_freed == N_ITEMS, "mailbox freed count mismatch");
    std.log.info("done: master shutdown — stdlib walk, no Matryoshka-specific cleanup API", .{});
}

const helpers = @import("helpers");
const matryoshka = @import("matryoshka");
const std = @import("std");
const mailbox = matryoshka.mailbox;
const pool = matryoshka.pool;
const polynode = matryoshka.polynode;
const Slot = polynode.Slot;
const MailboxHandle = mailbox.MailboxHandle;
const PoolHandle = pool.PoolHandle;
const types = helpers.types;
