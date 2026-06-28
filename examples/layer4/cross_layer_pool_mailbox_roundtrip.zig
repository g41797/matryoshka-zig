// SPDX-FileCopyrightText: Copyright (c) 2026 g41797
// SPDX-License-Identifier: MIT

// Ownership:
//
//  pool.get ──► slot (code=42, ptr=P)
//  mailbox.send ──► mailbox owns P
//  mailbox.receive ──► slot (same ptr P, code still 42)
//  verify code==42, ptr==P
//  pool.put ──► pool free-list (P recycled)
//  pool.get (.available_only) ──► slot (same ptr P)
//  verify ptr==P ──► pool.put ──► pool
//  pool.close ──► on_close ──► freed

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

    var sent_ptr: ?*types.Event = null;

    // Get from pool, fill, send to mailbox.
    {
        var slot: Slot = null;
        defer types.EventPolyHelper.destroy(allocator, &slot);
        try pool.get(ph, types.EventPolyHelper.TAG, .new_only, &slot);
        const ev: *types.Event = types.EventPolyHelper.cast(slot.?).?;
        ev.code = 42;
        sent_ptr = ev;
        std.log.info("pool.get: code={d} ptr={*}", .{ ev.code, ev });
        try mailbox.send(mbh, &slot);
    }

    // Receive from mailbox, verify data and pointer, put back to pool.
    {
        var slot: Slot = null;
        try mailbox.receive(mbh, &slot, null);
        defer pool.put(ph, &slot);
        const ev: *types.Event = types.EventPolyHelper.cast(slot.?).?;
        try helpers.expect(error.CrossLayerRoundtripFailed, ev.code == 42, "wrong code after receive");
        try helpers.expect(error.CrossLayerRoundtripFailed, ev == sent_ptr.?, "not same pointer after receive");
        std.log.info("mailbox.receive: code={d} same_ptr={}", .{ ev.code, ev == sent_ptr.? });
    }

    // Get recycled item from pool — must be the same pointer.
    {
        var slot: Slot = null;
        defer pool.put(ph, &slot);
        try pool.get(ph, types.EventPolyHelper.TAG, .available_only, &slot);
        const ev: *types.Event = types.EventPolyHelper.cast(slot.?).?;
        try helpers.expect(error.CrossLayerRoundtripFailed, ev == sent_ptr.?, "not same pointer on second get");
        std.log.info("pool.get (recycled): same_ptr={} — pool→mailbox→pool roundtrip complete", .{ev == sent_ptr.?});
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
