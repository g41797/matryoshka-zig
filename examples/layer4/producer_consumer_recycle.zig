// SPDX-FileCopyrightText: Copyright (c) 2026 g41797
// SPDX-License-Identifier: MIT

// Ownership:
//
//  pool.get ──► slot ──► producer fills (code=1)
//  mailbox.send ──► mailbox
//  │
//  consumer: mailbox.receive ──► slot (same pointer)
//            verify code==1
//            pool.put ──► pool (item recycled)
//  │
//  pool.get ──► slot (same pointer, code still 1)
//  verify recycled ──► pool.put ──► pool
//  pool.close ──► on_close ──► freeList

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

    // Producer: get from pool, fill, send.
    var sent_ptr: ?*types.Event = null;
    {
        var slot: Slot = null;
        defer types.EventPolyHelper.destroy(allocator, &slot);
        try pool.get(ph, types.EventPolyHelper.TAG, .new_only, &slot);
        const ev: *types.Event = types.EventPolyHelper.cast(slot.?).?;
        ev.code = 1;
        sent_ptr = ev;
        std.log.info("producer: get from pool, fill code={d}", .{ev.code});
        try mailbox.send(mbh, &slot);
    }

    // Consumer: receive, verify, put back to pool.
    {
        var slot: Slot = null;
        try mailbox.receive(mbh, &slot, null);
        defer pool.put(ph, &slot);
        const ev: *types.Event = types.EventPolyHelper.cast(slot.?).?;
        try helpers.expect(error.ProducerConsumerFailed, ev.code == 1, "wrong code after receive");
        try helpers.expect(error.ProducerConsumerFailed, @as(*types.Event, ev) == sent_ptr.?, "not same pointer");
        std.log.info("consumer: received code={d}, same pointer={}", .{ ev.code, @as(*types.Event, ev) == sent_ptr.? });
    }

    // Producer again: get recycled item from pool.
    {
        var slot: Slot = null;
        defer pool.put(ph, &slot);
        try pool.get(ph, types.EventPolyHelper.TAG, .available_only, &slot);
        const ev: *types.Event = types.EventPolyHelper.cast(slot.?).?;
        try helpers.expect(error.ProducerConsumerFailed, ev.code == 1, "wrong code after recycle");
        std.log.info("recycled item: code={d} — pool → producer → mailbox → consumer → pool cycle complete", .{ev.code});
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
