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

const Ctx = struct {
    ph: PoolHandle,
    mbh: MailboxHandle,
    alloc: std.mem.Allocator,

    fn getAndSend(self: *Ctx) !*types.Event {
        var slot: Slot = null;
        defer types.EventPolyHelper.destroy(self.alloc, &slot);
        try pool.get(self.ph, types.EventPolyHelper.TAG, .new_only, &slot);
        const ev: *types.Event = types.EventPolyHelper.cast(slot.?).?;
        ev.code = 42;
        std.log.info("pool.get: code={d} ptr={*}", .{ ev.code, ev });
        try mailbox.send(self.mbh, &slot);
        return ev;
    }

    fn receiveAndVerify(self: *Ctx, sent_ptr: *types.Event) !void {
        var slot: Slot = null;
        try mailbox.receive(self.mbh, &slot, null);
        defer pool.put(self.ph, &slot);
        const ev: *types.Event = types.EventPolyHelper.cast(slot.?).?;
        try helpers.expect(error.CrossLayerRoundtripFailed, ev.code == 42, "wrong code after receive");
        try helpers.expect(error.CrossLayerRoundtripFailed, ev == sent_ptr, "not same pointer after receive");
        std.log.info("mailbox.receive: code={d} same_ptr={}", .{ ev.code, ev == sent_ptr });
    }

    fn verifyRecycle(self: *Ctx, sent_ptr: *types.Event) !void {
        var slot: Slot = null;
        defer pool.put(self.ph, &slot);
        try pool.get(self.ph, types.EventPolyHelper.TAG, .available_only, &slot);
        const ev: *types.Event = types.EventPolyHelper.cast(slot.?).?;
        try helpers.expect(error.CrossLayerRoundtripFailed, ev == sent_ptr, "not same pointer on second get");
        std.log.info("pool.get (recycled): same_ptr={} — pool→mailbox→pool roundtrip complete", .{ev == sent_ptr});
    }
};

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

    var ctx: Ctx = .{ .ph = ph, .mbh = mbh, .alloc = allocator };
    const sent_ptr = try ctx.getAndSend();
    try ctx.receiveAndVerify(sent_ptr);
    try ctx.verifyRecycle(sent_ptr);
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
