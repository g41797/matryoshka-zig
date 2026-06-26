// SPDX-FileCopyrightText: Copyright (c) 2026 g41797
// SPDX-License-Identifier: MIT

pub fn run(allocator: std.mem.Allocator, io: std.Io) !void {
    var ctx: helpers.AlwaysCreateCtx = .{ .alloc = allocator };
    const tags = [_]*const anyopaque{types.EventPolyHelper.TAG};

    const ph = try pool.new(io, allocator);
    defer pool.destroy(ph, allocator);
    try pool.init(ph, ctx.poolHooks(&tags));

    const n: usize = 4;
    var i: usize = 0;
    while (i < n) : (i += 1) {
        var m: Slot = null;
        try pool.get(ph, types.EventPolyHelper.TAG, .new_only, &m);
        pool.put(ph, &m);
    }
    std.log.info("pool holds {d} Events before teardown", .{n});

    // Close: on_close receives all pooled items and frees them via AlwaysCreateCtx.
    pool.close(ph);
    std.log.info("pool closed: on_close freed all {d} items", .{n});
}

const std = @import("std");
const helpers = @import("helpers");
const matryoshka = @import("matryoshka");
const pool = matryoshka.pool;
const polynode = matryoshka.polynode;
const Slot = polynode.Slot;
const PoolHandle = pool.PoolHandle;
const types = helpers.types;
