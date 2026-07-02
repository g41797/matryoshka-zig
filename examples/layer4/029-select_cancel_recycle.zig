// SPDX-FileCopyrightText: Copyright (c) 2026 g41797
// SPDX-License-Identifier: MIT

// Ownership:
//
//  pool (seeded: Event×3)
//  │ getWaitResult
//  ▼
//  Select(MasterEvent) ◄── sleepFn (timer)
//  │
//  .pool_ev .item ──► process ──pool.put──► pool   (1 item processed)
//  .timer ──► sel.cancel() loop
//             .pool_ev .item ──► pool.put (recycle, not freed!)
//             .pool_ev .canceled ──► (no item, skip)
//  │
//  pool.close ──► on_close ──► freeList (all recycled items freed cleanly)

const TIMER_NS: i96 = 15_000_000; // 15 ms

const MasterEvent = union(enum) {
    pool_ev: pool.PoolResult,
    timer: void,
};

fn sleepFn(sleep_t: std.Io.Timeout, io: std.Io) void {
    std.Io.Timeout.sleep(sleep_t, io) catch {};
}

fn seedPool(ph: PoolHandle) !void {
    for (0..3) |i| {
        var slot: Slot = null;
        try pool.get(ph, types.EventPolyHelper.TAG, .new_only, &slot);
        types.EventPolyHelper.cast(slot.?).?.code = @intCast(i + 1);
        pool.put(ph, &slot);
    }
}

fn setupSelect(ph: PoolHandle, io: std.Io, sel: *std.Io.Select(MasterEvent)) !void {
    const sleep_t: std.Io.Timeout = .{
        .duration = .{ .raw = .{ .nanoseconds = TIMER_NS }, .clock = .real },
    };
    try sel.concurrent(.pool_ev, pool.getWaitResult, .{ ph, types.EventPolyHelper.TAG, null });
    try sel.concurrent(.timer, sleepFn, .{ sleep_t, io });
}

fn eventLoop(ph: PoolHandle, sel: *std.Io.Select(MasterEvent), processed: *usize) !void {
    loop: while (true) {
        const event: MasterEvent = try sel.await();
        switch (event) {
            .pool_ev => |r| switch (r) {
                .item => |handle| {
                    var slot: Slot = handle;
                    defer pool.put(ph, &slot);
                    const ev: *types.Event = types.EventPolyHelper.cast(slot.?).?;
                    processed.* += 1;
                    std.log.info("pool_ev: processed code={d} → put back to pool", .{ev.code});
                    try sel.concurrent(.pool_ev, pool.getWaitResult, .{ ph, types.EventPolyHelper.TAG, null });
                },
                .closed, .canceled, .timeout, .not_created => break :loop,
            },
            .timer => {
                std.log.info("timer: canceling remaining pool watchers", .{});
                break :loop;
            },
        }
    }
}

fn cancelAndRecycle(ph: PoolHandle, sel: *std.Io.Select(MasterEvent), recycled: *usize) void {
    while (sel.cancel()) |event| {
        switch (event) {
            .pool_ev => |r| switch (r) {
                .item => |handle| {
                    var slot: Slot = handle;
                    pool.put(ph, &slot);
                    recycled.* += 1;
                    std.log.info("cancel walk: recycled pool item (not freed)", .{});
                },
                .canceled, .closed, .timeout, .not_created => {},
            },
            .timer => {},
        }
    }
}

pub fn run(allocator: std.mem.Allocator, io: std.Io) !void {
    const ph: PoolHandle = try pool.new(io, allocator);
    var pool_ctx: helpers.AlwaysCreateCtx = .{ .alloc = allocator };
    const tags = [_]*const anyopaque{types.EventPolyHelper.TAG};
    try pool.init(ph, pool_ctx.poolHooks(&tags));
    defer {
        pool.close(ph);
        pool.destroy(ph, allocator);
    }

    try seedPool(ph);

    var buf: [8]MasterEvent = undefined;
    var sel: std.Io.Select(MasterEvent) = std.Io.Select(MasterEvent).init(io, &buf);
    try setupSelect(ph, io, &sel);

    var processed: usize = 0;
    var recycled: usize = 0;
    try eventLoop(ph, &sel, &processed);
    cancelAndRecycle(ph, &sel, &recycled);

    std.log.info("done: processed={d}, recycled via cancel={d}", .{ processed, recycled });
}

const helpers = @import("helpers");
const matryoshka = @import("matryoshka");
const std = @import("std");
const pool = matryoshka.pool;
const polynode = matryoshka.polynode;
const Slot = polynode.Slot;
const PoolHandle = pool.PoolHandle;
const types = helpers.types;
