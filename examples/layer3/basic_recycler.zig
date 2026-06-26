// SPDX-FileCopyrightText: Copyright (c) 2026 g41797
// SPDX-License-Identifier: MIT

pub fn run(allocator: std.mem.Allocator, io: std.Io) !void {
    var ctx: helpers.AlwaysCreateCtx = .{ .alloc = allocator };
    const tags = [_]*const anyopaque{types.EventPolyHelper.TAG};

    const ph = try pool.new(io, allocator);
    defer {
        pool.close(ph);
        pool.destroy(ph, allocator);
    }
    try pool.init(ph, ctx.poolHooks(&tags));

    var m: Slot = null;

    // First get: pool is empty, on_get creates a fresh Event.
    try pool.get(ph, types.EventPolyHelper.TAG, .available_or_new, &m);
    const ev = types.EventPolyHelper.cast(m.?) orelse return error.WrongTag;
    ev.code = 89;
    std.log.info("got fresh Event, set code={d}", .{ev.code});

    pool.put(ph, &m);
    std.log.info("returned Event to pool", .{});

    // Second get: on_get is called with m.* already set (recycled item).
    try pool.get(ph, types.EventPolyHelper.TAG, .available_or_new, &m);
    const ev2 = types.EventPolyHelper.cast(m.?) orelse return error.WrongTag;
    std.log.info("recycled Event code={d}", .{ev2.code});
    try helpers.expect(error.BasicRecyclerFailed, ev2.code == 89, "recycled item lost its data");

    // We hold the only item; free it before the defer closes the pool.
    allocator.destroy(ev2);
    m = null;
}

const std = @import("std");
const helpers = @import("helpers");
const matryoshka = @import("matryoshka");
const pool = matryoshka.pool;
const polynode = matryoshka.polynode;
const Slot = polynode.Slot;
const PoolHandle = pool.PoolHandle;
const types = helpers.types;
