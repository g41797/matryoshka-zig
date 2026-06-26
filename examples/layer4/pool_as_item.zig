// SPDX-FileCopyrightText: Copyright (c) 2026 g41797
// SPDX-License-Identifier: MIT

const CarrierCtx = struct {
    alloc: std.mem.Allocator,
    closed_count: usize = 0,
};

fn onGet(_: *anyopaque, _: *const anyopaque, _: usize, _: *Slot) void {}

fn onPut(_: *anyopaque, _: usize, _: *Slot) void {}

fn onClose(ctx_opaque: *anyopaque, list: *std.DoublyLinkedList) void {
    const ctx: *CarrierCtx = @ptrCast(@alignCast(ctx_opaque));
    while (list.popFirst()) |node| {
        const poly: *PolyNode = @fieldParentPtr("node", node);
        const ph: PoolHandle = poly;
        pool.close(ph);
        pool.destroy(ph, ctx.alloc);
        ctx.closed_count += 1;
    }
    std.log.info("on_close: closed and destroyed {d} inner pool(s)", .{ctx.closed_count});
}

pub fn run(allocator: std.mem.Allocator, io: std.Io) !void {
    // Carrier pool — holds inner PoolHandles as items.
    const carrier: PoolHandle = try pool.new(io, allocator);
    var carrier_ctx: CarrierCtx = .{ .alloc = allocator };
    const carrier_tags = [_]*const anyopaque{PoolPolyHelper.TAG};
    try pool.init(carrier, .{
        .ctx = &carrier_ctx,
        .tags = &carrier_tags,
        .on_get = onGet,
        .on_put = onPut,
        .on_close = onClose,
    });

    // Create 2 inner pools and store them in the carrier.
    const n: usize = 2;
    var j: usize = 0;
    while (j < n) : (j += 1) {
        const inner: PoolHandle = try pool.new(io, allocator);
        var slot: Slot = inner;
        pool.put(carrier, &slot);
        try helpers.expect(error.PoolAsItemFailed, slot == null, "carrier did not accept inner pool");
        std.log.info("stored inner pool {d} in carrier", .{j + 1});
    }

    // Close carrier — on_close receives both inner pools and frees them.
    // Tag dispatch is not needed here: all items are PoolHandles by construction.
    pool.close(carrier);

    try helpers.expect(error.PoolAsItemFailed, carrier_ctx.closed_count == n, "wrong number of inner pools cleaned up");

    std.log.info("carrier closed: {d} inner pool(s) cleaned up", .{carrier_ctx.closed_count});

    pool.destroy(carrier, allocator);
}

const std = @import("std");
const helpers = @import("helpers");
const matryoshka = @import("matryoshka");
const pool = matryoshka.pool;
const polynode = matryoshka.polynode;
const PolyNode = polynode.PolyNode;
const Slot = polynode.Slot;
const PoolHandle = pool.PoolHandle;
const PoolPolyHelper = pool.PoolPolyHelper;
