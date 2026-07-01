// SPDX-FileCopyrightText: Copyright (c) 2026 g41797
// SPDX-License-Identifier: MIT

// Ownership (circular):
//
//  Master job list: [{code=10},{code=20},{code=30}]
//  pool (1 empty container seeded)
//  │ getWaitResult drives pace
//  ▼
//  master: fill container from job list ──► mailbox.send ──► mbh
//                                                              │ worker
//                                                              │ process (code *= 2) ──► pool.put ──► pool
//  pool fires again ──► master dispatches next job (or breaks when all N sent + last returned)
//
//  Container circulates: pool → master fills → mailbox → worker → pool.
//  Work input: Master's pre-loaded job list. Pool provides the container and controls pacing.
//  Master counter tracks completed jobs.

const N: usize = 3;

// Master's own job list — separate from pool containers.
const jobs = [N]i32{ 10, 20, 30 };

const WorkerCtx = struct {
    mbh: MailboxHandle,
    ph: PoolHandle,
};

fn workerFn(ctx: *WorkerCtx) anyerror!void {
    while (true) {
        var slot: Slot = null;
        mailbox.receive(ctx.mbh, &slot, null) catch return;
        defer pool.put(ctx.ph, &slot); // return container to pool after processing
        const ev: *types.Event = types.EventPolyHelper.cast(slot.?).?;
        ev.code *= 2; // process: double the job value
        std.log.info("worker: processed job, result code={d}", .{ev.code});
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

    const mbh: MailboxHandle = try mailbox.new(io, allocator);
    defer mailbox.destroy(mbh, allocator); // close handled explicitly before worker await

    // Seed 1 empty container to start the circular flow.
    {
        var slot: Slot = null;
        try pool.get(ph, types.EventPolyHelper.TAG, .new_only, &slot);
        pool.put(ph, &slot);
    }

    var ctx: WorkerCtx = .{ .mbh = mbh, .ph = ph };
    var worker_fut = try io.concurrent(workerFn, .{&ctx});

    const MasterEvent = union(enum) {
        pool_ev: pool.PoolResult,
    };
    var buf: [4]MasterEvent = undefined;
    var sel: std.Io.Select(MasterEvent) = std.Io.Select(MasterEvent).init(io, &buf);
    try sel.concurrent(.pool_ev, pool.getWaitResult, .{ ph, types.EventPolyHelper.TAG, null });

    var job_idx: usize = 0; // index into Master's job list
    var completed: usize = 0; // completed jobs tracked by Master counter

    while (true) {
        const event: MasterEvent = try sel.await();
        switch (event) {
            .pool_ev => |r| switch (r) {
                .item => |handle| {
                    if (job_idx < N) {
                        // Container available — fill from Master's job list and dispatch.
                        var slot: Slot = handle;
                        const ev: *types.Event = types.EventPolyHelper.cast(slot.?).?;
                        ev.code = jobs[job_idx];
                        std.log.info("master: dispatching job {d} (code={d})", .{ job_idx, ev.code });
                        job_idx += 1;
                        try mailbox.send(mbh, &slot);
                        try sel.concurrent(.pool_ev, pool.getWaitResult, .{ ph, types.EventPolyHelper.TAG, null });
                    } else {
                        // All jobs sent; worker returned the last container.
                        const ev: *types.Event = types.EventPolyHelper.cast(handle).?;
                        completed = job_idx;
                        std.log.info("master: last result code={d}, all {d} jobs complete", .{ ev.code, completed });
                        var slot: Slot = handle;
                        pool.put(ph, &slot); // return final container to pool
                        break;
                    }
                },
                .closed, .canceled, .timeout, .not_created => break,
            },
        }
    }

    sel.cancelDiscard();

    // Close mailbox to signal worker to stop, then collect any undelivered items.
    var rem: std.DoublyLinkedList = mailbox.close(mbh);
    helpers.freeList(&rem, allocator);
    try worker_fut.await(io);

    try helpers.expect(error.JobPoolCircularFailed, completed == N, "did not complete all jobs");
    std.log.info("done: {d} jobs — Master list → pool container → mailbox → worker → pool (circular)", .{completed});
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
