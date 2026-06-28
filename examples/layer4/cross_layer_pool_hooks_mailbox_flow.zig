// SPDX-FileCopyrightText: Copyright (c) 2026 g41797
// SPDX-License-Identifier: MIT

// Ownership:
//
//  pool.get (new_only) ──► on_get creates ──► slot (code=1)
//  mailbox.send ──► mailbox owns item
//  mailbox.receive ──► slot (same item)
//  pool.put ──► on_put: count<cap → keep ──► pool free-list
//  │
//  pool.get (new_only) ──► on_get creates fresh ──► slot (code=2)
//  mailbox.send ──► mailbox owns item
//  mailbox.receive ──► slot (same item)
//  pool.put ──► on_put: count>=cap → destroy ──► freed
//  │
//  pool.get (.available_only) ──► recycled (code=1) ──► verify
//  pool.close ──► on_close ──► freeList

pub fn run(allocator: std.mem.Allocator, io: std.Io) !void {
    const ph: PoolHandle = try pool.new(io, allocator);
    // CappedPoolCtx: cap=1 — first put keeps, second put destroys.
    var pool_ctx: helpers.CappedPoolCtx = .{ .alloc = allocator, .cap = 1, .io = io };
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

    // Round 1: get, send, receive, put — on_put keeps (count 0 < cap 1).
    {
        var slot: Slot = null;
        defer types.EventPolyHelper.destroy(allocator, &slot);
        try pool.get(ph, types.EventPolyHelper.TAG, .new_only, &slot);
        types.EventPolyHelper.cast(slot.?).?.code = 1;
        std.log.info("on_get: created Event code=1", .{});
        try mailbox.send(mbh, &slot);
    }
    {
        var slot: Slot = null;
        try mailbox.receive(mbh, &slot, null);
        defer pool.put(ph, &slot);
        std.log.info("on_put: count<cap → keeping Event code={d}", .{types.EventPolyHelper.cast(slot.?).?.code});
    }

    // Round 2: get fresh, send, receive, put — on_put destroys (count 1 >= cap 1).
    {
        var slot: Slot = null;
        defer types.EventPolyHelper.destroy(allocator, &slot);
        try pool.get(ph, types.EventPolyHelper.TAG, .new_only, &slot);
        types.EventPolyHelper.cast(slot.?).?.code = 2;
        std.log.info("on_get: created fresh Event code=2", .{});
        try mailbox.send(mbh, &slot);
    }
    {
        var slot: Slot = null;
        try mailbox.receive(mbh, &slot, null);
        defer helpers.freeSlot(&slot, allocator);
        std.log.info("on_put: count>=cap → destroying Event code={d}", .{types.EventPolyHelper.cast(slot.?).?.code});
        pool.put(ph, &slot);
        // on_put set slot.* = null — item was freed; freeSlot sees null → no-op.
    }

    // Verify only the recycled item (code=1) remains in pool.
    {
        var slot: Slot = null;
        defer pool.put(ph, &slot);
        try pool.get(ph, types.EventPolyHelper.TAG, .available_only, &slot);
        const ev: *types.Event = types.EventPolyHelper.cast(slot.?).?;
        try helpers.expect(error.CrossLayerHooksFailed, ev.code == 1, "expected recycled item code=1");
        std.log.info("recycled item: code={d} — hooks decided keep/destroy correctly", .{ev.code});
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
