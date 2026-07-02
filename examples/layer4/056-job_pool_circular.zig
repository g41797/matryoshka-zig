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
//  pool triggers again ──► master dispatches next job (or breaks when all N sent + last returned)
//
//  Container circulates: pool → master fills → mailbox → worker → pool.
//  Work input: Master's pre-loaded job list. Pool provides the container and controls pacing.
//  Master counter tracks completed jobs.

const N: usize = 3;

const jobs = [N]i32{ 10, 20, 30 };

const MasterEvent = union(enum) {
    pool_ev: pool.PoolResult,
};

const WorkerCtx = struct {
    mbh: MailboxHandle,
    ph: PoolHandle,
};

fn workerFn(ctx: *WorkerCtx) anyerror!void {
    while (true) {
        var slot: Slot = null;
        mailbox.receive(ctx.mbh, &slot, null) catch return;
        defer pool.put(ctx.ph, &slot);
        const ev: *types.Event = types.EventPolyHelper.cast(slot.?).?;
        ev.code *= 2;
        std.log.info("worker: processed job, result code={d}", .{ev.code});
    }
}

const Ctx = struct {
    mbh: MailboxHandle,
    alloc: std.mem.Allocator,
    io: std.Io,

    fn spawnWorkerAndSetupSelect(self: *Ctx, ph: PoolHandle, worker_ctx: *WorkerCtx, sel: *std.Io.Select(MasterEvent)) !Io.Future(anyerror!void) {
        const fut = try self.io.concurrent(workerFn, .{worker_ctx});
        try sel.concurrent(.pool_ev, pool.getWaitResult, .{ ph, types.EventPolyHelper.TAG, null });
        return fut;
    }

    fn runEventLoop(self: *Ctx, ph: PoolHandle, sel: *std.Io.Select(MasterEvent), job_idx: *usize, completed: *usize) !void {
        while (true) {
            const event: MasterEvent = try sel.await();
            switch (event) {
                .pool_ev => |r| switch (r) {
                    .item => |handle| {
                        if (job_idx.* < N) {
                            var slot: Slot = handle;
                            const ev: *types.Event = types.EventPolyHelper.cast(slot.?).?;
                            ev.code = jobs[job_idx.*];
                            std.log.info("master: dispatching job {d} (code={d})", .{ job_idx.*, ev.code });
                            job_idx.* += 1;
                            try mailbox.send(self.mbh, &slot);
                            try sel.concurrent(.pool_ev, pool.getWaitResult, .{ ph, types.EventPolyHelper.TAG, null });
                        } else {
                            const ev: *types.Event = types.EventPolyHelper.cast(handle).?;
                            completed.* = job_idx.*;
                            std.log.info("master: last result code={d}, all {d} jobs complete", .{ ev.code, completed.* });
                            var slot: Slot = handle;
                            pool.put(ph, &slot);
                            break;
                        }
                    },
                    .closed, .canceled, .timeout, .not_created => break,
                },
            }
        }
        sel.cancelDiscard();
    }

    fn closeMailboxAndAwait(self: *Ctx, worker_fut: *Io.Future(anyerror!void)) !void {
        var rem: std.DoublyLinkedList = mailbox.close(self.mbh);
        helpers.freeList(&rem, self.alloc);
        try worker_fut.await(self.io);
    }
};

fn seedContainer(ph: PoolHandle) !void {
    var slot: Slot = null;
    try pool.get(ph, types.EventPolyHelper.TAG, .new_only, &slot);
    pool.put(ph, &slot);
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
    defer mailbox.destroy(mbh, allocator);

    try seedContainer(ph);

    var ctx: Ctx = .{ .mbh = mbh, .alloc = allocator, .io = io };
    var worker_ctx: WorkerCtx = .{ .mbh = mbh, .ph = ph };
    var buf: [4]MasterEvent = undefined;
    var sel: std.Io.Select(MasterEvent) = std.Io.Select(MasterEvent).init(io, &buf);
    var worker_fut = try ctx.spawnWorkerAndSetupSelect(ph, &worker_ctx, &sel);

    var job_idx: usize = 0;
    var completed: usize = 0;
    try ctx.runEventLoop(ph, &sel, &job_idx, &completed);

    try ctx.closeMailboxAndAwait(&worker_fut);

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
const Io = std.Io;
const types = helpers.types;
