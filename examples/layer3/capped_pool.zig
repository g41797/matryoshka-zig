// SPDX-FileCopyrightText: Copyright (c) 2026 g41797
// SPDX-License-Identifier: MIT

pub fn run(allocator: std.mem.Allocator, io: std.Io) !void {
    const cap: usize = 2;
    var ctx: helpers.CappedPoolCtx = .{ .alloc = allocator, .cap = cap };
    const tags = [_]*const anyopaque{types.EventPolyHelper.TAG};

    const ph = try pool.new(io, allocator);
    defer {
        pool.close(ph);
        pool.destroy(ph, allocator);
    }
    try pool.init(ph, ctx.poolHooks(&tags));

    // Seed 3 items. on_put destroys the 3rd (pool already at cap).
    var i: usize = 0;
    while (i < 3) : (i += 1) {
        var m: Slot = null;
        try pool.get(ph, types.EventPolyHelper.TAG, .new_only, &m);
        pool.put(ph, &m);
    }
    std.log.info("seeded 3 Events into capped pool (cap={d})", .{cap});

    // Consume all available items — exactly cap survive.
    var consumed: usize = 0;
    while (true) {
        var m: Slot = null;
        pool.get(ph, types.EventPolyHelper.TAG, .available_only, &m) catch break;
        allocator.destroy(types.EventPolyHelper.cast(m.?).?);
        consumed += 1;
    }
    std.log.info("consumed {d} items (expected {d})", .{ consumed, cap });
    try helpers.expect(error.CappedPoolFailed, consumed == cap, "capped pool held wrong count");
}

const std = @import("std");
const helpers = @import("helpers");
const matryoshka = @import("matryoshka");
const pool = matryoshka.pool;
const polynode = matryoshka.polynode;
const Slot = polynode.Slot;
const PoolHandle = pool.PoolHandle;
const types = helpers.types;
