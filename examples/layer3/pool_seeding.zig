// SPDX-FileCopyrightText: Copyright (c) 2026 g41797
// SPDX-License-Identifier: MIT

pub fn run(allocator: std.mem.Allocator, io: std.Io) !void {
    var ctx: helpers.AlwaysCreateCtx = .{ .alloc = allocator };
    const tags = [_]*const anyopaque{types.SensorPolyHelper.TAG};

    const ph = try pool.new(io, allocator);
    defer {
        pool.close(ph);
        pool.destroy(ph, allocator);
    }
    try pool.init(ph, ctx.poolHooks(&tags));

    const n: usize = 5;

    // Seed: new_only forces allocation for each item.
    var i: usize = 0;
    while (i < n) : (i += 1) {
        var m: Slot = null;
        try pool.get(ph, types.SensorPolyHelper.TAG, .new_only, &m);
        const sn = types.SensorPolyHelper.cast(m.?).?;
        sn.value = @as(f64, @floatFromInt(i)) * 0.1;
        pool.put(ph, &m);
    }
    std.log.info("seeded {d} Sensor items into pool", .{n});

    // Consume: available_only takes pre-existing items — no allocation.
    var consumed: usize = 0;
    while (true) {
        var m: Slot = null;
        pool.get(ph, types.SensorPolyHelper.TAG, .available_only, &m) catch break;
        const sn = types.SensorPolyHelper.cast(m.?).?;
        std.log.info("consumed Sensor value={d:.1}", .{sn.value});
        allocator.destroy(sn);
        consumed += 1;
    }
    try helpers.expect(error.PoolSeedingFailed, consumed == n, "wrong consumed count");
}

const std = @import("std");
const helpers = @import("helpers");
const matryoshka = @import("matryoshka");
const pool = matryoshka.pool;
const polynode = matryoshka.polynode;
const Slot = polynode.Slot;
const PoolHandle = pool.PoolHandle;
const types = helpers.types;
