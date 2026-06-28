// SPDX-FileCopyrightText: Copyright (c) 2026 g41797
// SPDX-License-Identifier: MIT

// Ownership:
//
//  pool.get ──► slot (code=7)
//  mailbox.send ──► mailbox owns item
//  mailbox.receive ──► slot (same item)
//  pool.put ──► pool free-list
//  pool.close ──► on_close ──► freed
//
//  Pattern: pool → mailbox → pool. One ownership circuit, single-threaded.

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
    defer {
        var rem: std.DoublyLinkedList = mailbox.close(mbh);
        helpers.freeList(&rem, allocator);
        mailbox.destroy(mbh, allocator);
    }

    // Get from pool, fill, send.
    {
        var slot: Slot = null;
        defer types.EventPolyHelper.destroy(allocator, &slot);
        try pool.get(ph, types.EventPolyHelper.TAG, .new_only, &slot);
        types.EventPolyHelper.cast(slot.?).?.code = 7;
        std.log.info("pool.get: code={d}", .{7});
        try mailbox.send(mbh, &slot);
    }

    // Receive from mailbox, verify, put back to pool.
    {
        var slot: Slot = null;
        try mailbox.receive(mbh, &slot, null);
        defer pool.put(ph, &slot);
        const ev: *types.Event = types.EventPolyHelper.cast(slot.?).?;
        try helpers.expect(error.CrossLayerFlowFailed, ev.code == 7, "wrong code after receive");
        std.log.info("mailbox.receive: code={d} — pool→mailbox→pool flow complete", .{ev.code});
    }
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
