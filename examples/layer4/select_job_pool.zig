// SPDX-FileCopyrightText: Copyright (c) 2026 g41797
// SPDX-License-Identifier: MIT

// Ownership:
//
//  Master job queue: [{code=10},{code=20},{code=30}] (pre-loaded before loop)
//  pool (N empty containers seeded)
//  │ getWaitResult — fires when a container is returned by a worker (or initially available)
//  ▼
//  Select(MasterEvent)
//  │
//  .pool_ev .item ──► pop job from Master queue ──► fill container ──► mailbox.send ──► mbh[worker_i]
//                 ──► re-spawn getWaitResult (until queue exhausted)
//                 ──► break (queue empty — no more jobs to dispatch)
//  │
//  worker[i]: mailbox.receive ──► process (code *= 2) ──► pool.put ──► pool (triggers next pool_ev)
//  │
//  master: mailbox.close (×N) ──► workers exit ──► futs.await
//  pool.close ──► on_close ──► freeList (returns all remaining containers)
//
//  Pool availability gates job submission. Work input: Master's pre-loaded queue.
//  Pool provides empty containers. One container per in-flight job.
//  Master dispatches jobs until queue exhausted, then shuts down workers.

const N: usize = 3;

// Master's pre-loaded job queue — separate from pool containers.
const jobs = [N]i32{ 10, 20, 30 };

const WorkerCtx = struct {
    mbh: MailboxHandle,
    ph: PoolHandle,
    id: usize,
};

fn workerFn(ctx: *WorkerCtx) anyerror!void {
    while (true) {
        var slot: Slot = null;
        mailbox.receive(ctx.mbh, &slot, null) catch return;
        defer pool.put(ctx.ph, &slot); // return container to pool — triggers next pool_ev
        const ev: *types.Event = types.EventPolyHelper.cast(slot.?).?;
        ev.code *= 2; // process: double the job value
        std.log.info("worker {d}: processed job, result code={d}", .{ ctx.id, ev.code });
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

    // Seed N empty containers — one per in-flight job.
    for (0..N) |_| {
        var slot: Slot = null;
        try pool.get(ph, types.EventPolyHelper.TAG, .new_only, &slot);
        pool.put(ph, &slot);
    }

    // One mailbox and one worker per job slot.
    var mbhs: [N]MailboxHandle = undefined;
    var ctxs: [N]WorkerCtx = undefined;
    var futs: [N]std.Io.Future(anyerror!void) = undefined;
    for (0..N) |i| {
        mbhs[i] = try mailbox.new(io, allocator);
        ctxs[i] = .{ .mbh = mbhs[i], .ph = ph, .id = i };
        futs[i] = try io.concurrent(workerFn, .{&ctxs[i]});
    }
    defer {
        for (0..N) |i| mailbox.destroy(mbhs[i], allocator);
    }

    const MasterEvent = union(enum) {
        pool_ev: pool.PoolResult,
    };
    var buf: [N + 1]MasterEvent = undefined;
    var sel: std.Io.Select(MasterEvent) = std.Io.Select(MasterEvent).init(io, &buf);
    try sel.concurrent(.pool_ev, pool.getWaitResult, .{ ph, types.EventPolyHelper.TAG, null });

    var job_idx: usize = 0; // index into Master's pre-loaded queue
    var worker_i: usize = 0; // round-robin worker index

    // Dispatch jobs until queue is exhausted. Pool availability gates submission.
    while (job_idx < N) {
        const event: MasterEvent = try sel.await();
        switch (event) {
            .pool_ev => |r| switch (r) {
                .item => |handle| {
                    var slot: Slot = handle;
                    const ev: *types.Event = types.EventPolyHelper.cast(slot.?).?;
                    ev.code = jobs[job_idx];
                    std.log.info("master: dispatching job {d} (code={d}) to worker {d}", .{ job_idx, ev.code, worker_i });
                    try mailbox.send(mbhs[worker_i], &slot);
                    job_idx += 1;
                    worker_i = (worker_i + 1) % N;
                    if (job_idx < N) {
                        try sel.concurrent(.pool_ev, pool.getWaitResult, .{ ph, types.EventPolyHelper.TAG, null });
                    }
                },
                .closed, .canceled, .timeout, .not_created => break,
            },
        }
    }

    sel.cancelDiscard();

    // All jobs dispatched. Close worker mailboxes to signal shutdown.
    for (0..N) |i| {
        var rem: std.DoublyLinkedList = mailbox.close(mbhs[i]);
        helpers.freeList(&rem, allocator);
    }
    for (0..N) |i| try futs[i].await(io);

    try helpers.expect(error.SelectJobPoolFailed, job_idx == N, "not all jobs dispatched");
    std.log.info("done: {d} jobs dispatched — Master queue → pool containers → worker mailboxes (pool gated)", .{job_idx});
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
