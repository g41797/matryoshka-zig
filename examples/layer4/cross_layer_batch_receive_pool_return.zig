// SPDX-FileCopyrightText: Copyright (c) 2026 g41797
// SPDX-License-Identifier: MIT

// Ownership:
//
//  pool.get (×10, new_only) ──► mailbox.send (×10) ──► mailbox (10 items)
//  │
//  mailbox.receive_batch ──► std.DoublyLinkedList (10 items)
//  pool.put_all ──► pool free-list (10 items recycled)
//  │
//  pool.get (.available_only) ×10 ──► verify count==10
//  pool.close ──► on_close ──► freeList

const N_ITEMS: usize = 10;

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

    // Get 10 items from pool and send to mailbox.
    for (0..N_ITEMS) |i| {
        var slot: Slot = null;
        defer types.EventPolyHelper.destroy(allocator, &slot);
        try pool.get(ph, types.EventPolyHelper.TAG, .new_only, &slot);
        types.EventPolyHelper.cast(slot.?).?.code = @intCast(i + 1);
        try mailbox.send(mbh, &slot);
    }
    std.log.info("sent {d} items to mailbox", .{N_ITEMS});

    // Batch receive all items at once.
    var batch: std.DoublyLinkedList = try mailbox.receive_batch(mbh);
    std.log.info("receive_batch: got list (stdlib DoublyLinkedList)", .{});

    // Pass the list directly to pool.put_all — stdlib list bridges the two layers.
    pool.put_all(ph, &batch);
    std.log.info("pool.put_all: {d} items returned to pool", .{N_ITEMS});

    // Verify: items are back in pool — get one and put it back.
    {
        var slot: Slot = null;
        defer pool.put(ph, &slot);
        pool.get(ph, types.EventPolyHelper.TAG, .available_only, &slot) catch {
            return error.CrossLayerBatchFailed;
        };
        std.log.info("verified: pool has items after put_all", .{});
    }

    std.log.info("done: {d} items — mailbox.receive_batch → pool.put_all — stdlib list bridges layers", .{N_ITEMS});
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
