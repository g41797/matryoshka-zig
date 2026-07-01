// SPDX-FileCopyrightText: Copyright (c) 2026 g41797
// SPDX-License-Identifier: MIT

// Ownership:
//
//  Master job list: [{code=1},{code=2},{code=3}]
//  pool (3 empty containers seeded)
//  │
//  master: pool.get ──► fill from job list ──► mailbox.send ──► mbh[0..2]
//                                                                    │ worker[i] (io.concurrent)
//                                                                    │ mailbox.receive ──► process ──► pool.put ──► pool
//  master: fut[i].await ──► all workers done
//  master: pool.get ×3 ──► verify results
//  pool.close ──► on_close ──► freeList
//
//  Ownership: Master list → pool containers → worker mailboxes → workers → pool → master.
//  Pool items are empty containers: Master fills from job list, worker writes result back.

const N: usize = 3;

// Job descriptors — Master's own list, separate from pool containers.
const jobs = [N]i32{ 10, 20, 30 };

const WorkerCtx = struct {
    mbh: MailboxHandle,
    ph: PoolHandle,
};

fn workerFn(ctx: *WorkerCtx) anyerror!void {
    var slot: Slot = null;
    mailbox.receive(ctx.mbh, &slot, null) catch return;
    defer pool.put(ctx.ph, &slot); // return container to pool after processing
    const ev: *types.Event = types.EventPolyHelper.cast(slot.?).?;
    ev.code *= 2; // process: double the job value
    std.log.info("worker: processed job, result code={d}", .{ev.code});
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

    // Seed N empty containers — pool items carry no work data on acquisition.
    for (0..N) |_| {
        var slot: Slot = null;
        try pool.get(ph, types.EventPolyHelper.TAG, .new_only, &slot);
        pool.put(ph, &slot);
    }

    // One mailbox per worker.
    var mbhs: [N]MailboxHandle = undefined;
    for (0..N) |i| {
        mbhs[i] = try mailbox.new(io, allocator);
    }
    defer {
        for (0..N) |i| {
            var rem: std.DoublyLinkedList = mailbox.close(mbhs[i]);
            helpers.freeList(&rem, allocator);
            mailbox.destroy(mbhs[i], allocator);
        }
    }

    var ctxs: [N]WorkerCtx = undefined;
    var futs: [N]std.Io.Future(anyerror!void) = undefined;
    for (0..N) |i| {
        ctxs[i] = .{ .mbh = mbhs[i], .ph = ph };
        futs[i] = try io.concurrent(workerFn, .{&ctxs[i]});
    }

    // Master gets each empty container, fills with job descriptor, sends to worker mailbox.
    for (0..N) |i| {
        var slot: Slot = null;
        try pool.get(ph, types.EventPolyHelper.TAG, .available_only, &slot);
        const ev: *types.Event = types.EventPolyHelper.cast(slot.?).?;
        ev.code = jobs[i]; // fill empty container from Master's job list
        std.log.info("master: filled container with job code={d}, sending to worker {d}", .{ ev.code, i });
        try mailbox.send(mbhs[i], &slot);
    }

    for (0..N) |i| try futs[i].await(io);

    // Collect results from pool. Free each item directly — do NOT put back (would re-trigger loop).
    var total: usize = 0;
    var result_sum: i32 = 0;
    while (true) {
        var slot: Slot = null;
        pool.get(ph, types.EventPolyHelper.TAG, .available_only, &slot) catch break;
        defer helpers.freeSlot(&slot, allocator);
        const ev: *types.Event = types.EventPolyHelper.cast(slot.?).?;
        result_sum += ev.code;
        total += 1;
        std.log.info("master: result code={d}", .{ev.code});
    }

    try helpers.expect(error.PoolFanInFailed, total == N, "expected N results in pool");
    // jobs doubled: 10*2 + 20*2 + 30*2 = 120
    try helpers.expect(error.PoolFanInFailed, result_sum == 120, "wrong result sum");
    std.log.info("fan-in: {d} results — Master list → pool → worker mailboxes → pool → master", .{total});
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
