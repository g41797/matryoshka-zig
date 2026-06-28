// SPDX-FileCopyrightText: Copyright (c) 2026 g41797
// SPDX-License-Identifier: MIT

// Ownership (circular):
//
//  pool ──getWaitResult──► master
//        │ slot dispatched
//        ▼
//      worker ──mailbox.send──► mbh
//                               │ receiveResult
//                               ▼
//                             master ──pool.put──► pool (cycle repeats)
//
//  pool.getWaitResult drives pace: master blocks until a slot is available.
//  N_ROUNDS complete cycles with 1 slot in circulation.

const N_ROUNDS: usize = 3;

const MasterEvent = union(enum) {
    pool_ev: pool.PoolResult,
    inbox: mailbox.ReceiveResult,
};

const WorkerCtx = struct {
    mbh: MailboxHandle,
    slot: Slot,
};

fn workerFn(ctx: *WorkerCtx) anyerror!void {
    const ev: *types.Event = types.EventPolyHelper.cast(ctx.slot.?).?;
    ev.code += 1;
    std.log.info("worker: processed slot (code now {d})", .{ev.code});
    try mailbox.send(ctx.mbh, &ctx.slot);
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
    defer {
        var rem: std.DoublyLinkedList = mailbox.close(mbh);
        helpers.freeList(&rem, allocator);
        mailbox.destroy(mbh, allocator);
    }

    // Seed pool with 1 slot to start the circular flow.
    {
        var slot: Slot = null;
        try pool.get(ph, types.EventPolyHelper.TAG, .new_only, &slot);
        types.EventPolyHelper.cast(slot.?).?.code = 0;
        pool.put(ph, &slot);
    }

    var buf: [4]MasterEvent = undefined;
    var sel: std.Io.Select(MasterEvent) = std.Io.Select(MasterEvent).init(io, &buf);

    // ctx lives for the full duration of run() so the concurrent fn's pointer stays valid.
    var ctx: WorkerCtx = .{ .mbh = mbh, .slot = null };
    var worker_fut: std.Io.Future(anyerror!void) = undefined;
    var worker_active: bool = false;

    // Start by watching pool (getWaitResult drives the pace).
    try sel.concurrent(.pool_ev, pool.getWaitResult, .{ ph, types.EventPolyHelper.TAG, null });

    var round: usize = 0;

    while (round < N_ROUNDS) {
        const event: MasterEvent = try sel.await();
        switch (event) {
            .pool_ev => |r| switch (r) {
                .item => |handle| {
                    std.log.info("master: got pool slot (round {d}) — dispatching to worker", .{round});
                    ctx = .{ .mbh = mbh, .slot = handle };
                    worker_fut = try io.concurrent(workerFn, .{&ctx});
                    worker_active = true;
                    try sel.concurrent(.inbox, mailbox.receiveResult, .{ mbh, null });
                },
                .closed, .canceled, .timeout, .not_created => break,
            },
            .inbox => |r| switch (r) {
                .item => |handle| {
                    // Worker completed before mailbox delivered — await to collect result.
                    if (worker_active) {
                        try worker_fut.await(io);
                        worker_active = false;
                    }
                    const ev: *types.Event = types.EventPolyHelper.cast(handle).?;
                    std.log.info("master: received from worker (code={d}) — put back to pool", .{ev.code});
                    var slot: Slot = handle;
                    pool.put(ph, &slot); // recycle — slot circulates back
                    round += 1;
                    if (round < N_ROUNDS) {
                        // Pool now has 1 item — re-spawn pool watcher.
                        try sel.concurrent(.pool_ev, pool.getWaitResult, .{ ph, types.EventPolyHelper.TAG, null });
                    }
                },
                .closed, .canceled, .timeout => break,
            },
        }
    }

    sel.cancelDiscard();

    try helpers.expect(error.JobPoolCircularFailed, round == N_ROUNDS, "did not complete all rounds");
    std.log.info("done: {d} circular rounds (pool → worker → mailbox → pool)", .{round});
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
