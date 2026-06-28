// SPDX-FileCopyrightText: Copyright (c) 2026 g41797
// SPDX-License-Identifier: MIT

// Ownership:
//
//  pool (1 item in free-list)    mailbox (1 item in queue)
//  │
//  mailbox.close ──► std.DoublyLinkedList (1 item)
//  walk list: popFirst ──► cast ──► pool.put (pool still open)
//  │                                        └──► pool free-list (now 2 items)
//  pool.close ──► on_close ──► freeList (both items freed)
//  │
//  Verify: pool received the item from mailbox close list.

pub fn run(allocator: std.mem.Allocator, io: std.Io) !void {
    const ph: PoolHandle = try pool.new(io, allocator);
    var pool_ctx: helpers.AlwaysCreateCtx = .{ .alloc = allocator };
    const tags = [_]*const anyopaque{types.EventPolyHelper.TAG};
    try pool.init(ph, pool_ctx.poolHooks(&tags));
    defer {
        pool.close(ph);
        pool.destroy(ph, allocator);
    }

    const mbh: MailboxHandle = try mailbox.new(io, allocator);

    // Seed pool with 1 item.
    {
        var slot: Slot = null;
        try pool.get(ph, types.EventPolyHelper.TAG, .new_only, &slot);
        types.EventPolyHelper.cast(slot.?).?.code = 1;
        pool.put(ph, &slot);
    }

    // Put 1 item in mailbox.
    {
        var slot: Slot = null;
        defer types.EventPolyHelper.destroy(allocator, &slot);
        try types.EventPolyHelper.create(allocator, &slot);
        types.EventPolyHelper.cast(slot.?).?.code = 2;
        try mailbox.send(mbh, &slot);
    }

    std.log.info("before close: 1 item in pool, 1 item in mailbox", .{});

    // Close mailbox first — returns remaining items.
    var rem: std.DoublyLinkedList = mailbox.close(mbh);
    mailbox.destroy(mbh, allocator);

    // Walk the close list and return each item to the pool (pool still open).
    var returned: usize = 0;
    while (rem.popFirst()) |node| {
        const poly: *polynode.PolyNode = @fieldParentPtr("node", node);
        polynode.reset(poly);
        var slot: Slot = poly;
        pool.put(ph, &slot);
        returned += 1;
        std.log.info("mailbox close list: returned item to pool (code={d})", .{types.EventPolyHelper.cast(poly).?.code});
    }

    try helpers.expect(error.CrossLayerCloseOrderFailed, returned == 1, "expected 1 item from mailbox close");
    std.log.info("pool now has 2 items — pool.close will free all via on_close", .{});
    // Deferred pool.close calls on_close with both items.
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
