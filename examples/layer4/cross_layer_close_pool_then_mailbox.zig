// SPDX-FileCopyrightText: Copyright (c) 2026 g41797
// SPDX-License-Identifier: MIT

// Ownership:
//
//  pool (2 items in free-list)    mailbox (1 item in queue)
//  │
//  pool.close ──► on_close ──► freeList (2 pool items freed)
//  mailbox.close ──► std.DoublyLinkedList (1 item)
//  walk list: popFirst ──► freeItem
//  │
//  All 3 items accounted for, no leaks.

const N_POOL: usize = 2;
const N_MAILBOX: usize = 1;

pub fn run(allocator: std.mem.Allocator, io: std.Io) !void {
    const ph: PoolHandle = try pool.new(io, allocator);
    var pool_ctx: helpers.AlwaysCreateCtx = .{ .alloc = allocator };
    const tags = [_]*const anyopaque{types.EventPolyHelper.TAG};
    try pool.init(ph, pool_ctx.poolHooks(&tags));

    const mbh: MailboxHandle = try mailbox.new(io, allocator);

    // Seed pool with N_POOL items in free-list.
    for (0..N_POOL) |i| {
        var slot: Slot = null;
        try pool.get(ph, types.EventPolyHelper.TAG, .new_only, &slot);
        types.EventPolyHelper.cast(slot.?).?.code = @intCast(i + 1);
        pool.put(ph, &slot);
    }

    // Put N_MAILBOX items in mailbox queue.
    for (0..N_MAILBOX) |i| {
        var slot: Slot = null;
        defer types.EventPolyHelper.destroy(allocator, &slot);
        try types.EventPolyHelper.create(allocator, &slot);
        types.EventPolyHelper.cast(slot.?).?.code = @intCast(100 + i);
        try mailbox.send(mbh, &slot);
    }

    std.log.info("before close: {d} in pool, {d} in mailbox", .{ N_POOL, N_MAILBOX });

    // Close pool first — on_close frees all pool items.
    pool.close(ph);
    pool.destroy(ph, allocator);
    std.log.info("pool.close: on_close freed {d} pool items", .{N_POOL});

    // Close mailbox — returns remaining items as std.DoublyLinkedList.
    var rem: std.DoublyLinkedList = mailbox.close(mbh);
    var freed: usize = 0;
    while (rem.popFirst()) |node| {
        const poly: *polynode.PolyNode = @fieldParentPtr("node", node);
        polynode.reset(poly);
        helpers.freeItem(poly, allocator);
        freed += 1;
    }
    mailbox.destroy(mbh, allocator);
    std.log.info("mailbox.close: walked list, freed {d} mailbox items", .{freed});

    try helpers.expect(error.CrossLayerCloseOrderFailed, freed == N_MAILBOX, "mailbox item count mismatch");
    std.log.info("done: close pool-then-mailbox — {d}+{d} items cleaned up, no leaks", .{ N_POOL, N_MAILBOX });
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
