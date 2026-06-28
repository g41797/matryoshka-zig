// SPDX-FileCopyrightText: Copyright (c) 2026 g41797
// SPDX-License-Identifier: MIT

// Ownership:
//
//  mailbox (5 items)
//  │
//  mailbox.receive_batch ──► std.DoublyLinkedList
//  pool.put_all ──► pool free-list (5 items recycled)
//  │
//  std.DoublyLinkedList flows from mailbox to pool without conversion.
//  pool.close ──► on_close ──► freeList

const N_ITEMS: usize = 5;

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

    // Fill mailbox with N_ITEMS items.
    for (0..N_ITEMS) |i| {
        var slot: Slot = null;
        defer types.EventPolyHelper.destroy(allocator, &slot);
        try types.EventPolyHelper.create(allocator, &slot);
        types.EventPolyHelper.cast(slot.?).?.code = @intCast(i + 1);
        try mailbox.send(mbh, &slot);
    }
    std.log.info("mailbox: {d} items queued", .{N_ITEMS});

    // Batch receive: collect all at once, pass list directly to pool.put_all.
    var batch: std.DoublyLinkedList = try mailbox.receive_batch(mbh);
    pool.put_all(ph, &batch);
    std.log.info("receive_batch → put_all: stdlib list bridges mailbox to pool", .{});

    // Verify: items are back in pool — get one and put it back.
    {
        var slot: Slot = null;
        defer pool.put(ph, &slot);
        pool.get(ph, types.EventPolyHelper.TAG, .available_only, &slot) catch {
            return error.MasterBatchDrainFailed;
        };
        std.log.info("verified: pool has items after put_all", .{});
    }

    std.log.info("done: {d} items — mailbox.receive_batch → pool.put_all, no conversion needed", .{N_ITEMS});
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
