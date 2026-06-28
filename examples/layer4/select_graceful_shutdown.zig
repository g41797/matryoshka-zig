// SPDX-FileCopyrightText: Copyright (c) 2026 g41797
// SPDX-License-Identifier: MIT

// Ownership:
//
//  mbh (Event items + ShutdownCommand)    pool (Event items)
//  │ receiveResult                         │ getWaitResult
//  └──────────────────────┬───────────────┘
//                         ▼
//                 Select(MasterEvent) ◄── sleepFn (timer)
//                         │ event loop
//                         ▼
//  .inbox .item (Event)   ──► process, re-spawn inbox
//  .inbox .item (Shutdown)──► initiate graceful shutdown:
//                              sel.cancel() loop
//                              .inbox  .item ──► freeSlot   (no item lost)
//                              .pool_ev .item──► pool.put    (no item lost)
//  sel.cancelDiscard() ──► pool.close ──► mailbox.close

const TIMER_NS: i96 = 30_000_000; // 30 ms
const N_EVENTS: usize = 2;

const MasterEvent = union(enum) {
    inbox: mailbox.ReceiveResult,
    pool_ev: pool.PoolResult,
    timer: void,
};

fn sleepFn(sleep_t: std.Io.Timeout, io: std.Io) void {
    std.Io.Timeout.sleep(sleep_t, io) catch {};
}

pub fn run(allocator: std.mem.Allocator, io: std.Io) !void {
    const mbh: MailboxHandle = try mailbox.new(io, allocator);
    defer {
        var rem: std.DoublyLinkedList = mailbox.close(mbh);
        helpers.freeList(&rem, allocator);
        mailbox.destroy(mbh, allocator);
    }

    const ph: PoolHandle = try pool.new(io, allocator);
    var pool_ctx: helpers.AlwaysCreateCtx = .{ .alloc = allocator };
    const tags = [_]*const anyopaque{types.EventPolyHelper.TAG};
    try pool.init(ph, pool_ctx.poolHooks(&tags));
    defer {
        pool.close(ph);
        pool.destroy(ph, allocator);
    }

    // Pre-load mailbox: N_EVENTS Event items followed by a ShutdownCommand.
    for (0..N_EVENTS) |i| {
        var slot: Slot = null;
        defer types.EventPolyHelper.destroy(allocator, &slot);
        try types.EventPolyHelper.create(allocator, &slot);
        types.EventPolyHelper.cast(slot.?).?.code = @intCast(i + 1);
        try mailbox.send(mbh, &slot);
    }
    {
        var slot: Slot = null;
        defer types.ShutdownCommandPolyHelper.destroy(allocator, &slot);
        try types.ShutdownCommandPolyHelper.create(allocator, &slot);
        try mailbox.send(mbh, &slot);
    }

    // Seed pool with 1 item (will be recycled during cancel walk).
    {
        var slot: Slot = null;
        try pool.get(ph, types.EventPolyHelper.TAG, .new_only, &slot);
        types.EventPolyHelper.cast(slot.?).?.code = 99;
        pool.put(ph, &slot);
    }

    const sleep_t: std.Io.Timeout = .{
        .duration = .{ .raw = .{ .nanoseconds = TIMER_NS }, .clock = .real },
    };

    var buf: [8]MasterEvent = undefined;
    var sel: std.Io.Select(MasterEvent) = std.Io.Select(MasterEvent).init(io, &buf);

    try sel.concurrent(.inbox, mailbox.receiveResult, .{ mbh, null });
    try sel.concurrent(.pool_ev, pool.getWaitResult, .{ ph, types.EventPolyHelper.TAG, null });
    try sel.concurrent(.timer, sleepFn, .{ sleep_t, io });

    var events_processed: usize = 0;
    var shutdown_seen: bool = false;

    outer: while (true) {
        const event: MasterEvent = try sel.await();
        switch (event) {
            .inbox => |r| switch (r) {
                .item => |handle| {
                    if (types.EventPolyHelper.cast(handle)) |ev| {
                        var slot: Slot = handle;
                        defer helpers.freeSlot(&slot, allocator);
                        events_processed += 1;
                        std.log.info("inbox: Event code={d}", .{ev.code});
                        try sel.concurrent(.inbox, mailbox.receiveResult, .{ mbh, null });
                    } else if (types.ShutdownCommandPolyHelper.cast(handle)) |_| {
                        var slot: Slot = handle;
                        helpers.freeSlot(&slot, allocator);
                        std.log.info("inbox: ShutdownCommand — initiating graceful shutdown", .{});
                        shutdown_seen = true;
                        break :outer;
                    } else {
                        var slot: Slot = handle;
                        helpers.freeSlot(&slot, allocator);
                    }
                },
                .closed, .canceled, .timeout => break :outer,
            },
            .pool_ev => |r| switch (r) {
                .item => |handle| {
                    var slot: Slot = handle;
                    defer pool.put(ph, &slot);
                    std.log.info("pool_ev: item received", .{});
                    try sel.concurrent(.pool_ev, pool.getWaitResult, .{ ph, types.EventPolyHelper.TAG, null });
                },
                .closed, .canceled, .timeout, .not_created => {},
            },
            .timer => {
                std.log.info("timer: tick", .{});
                try sel.concurrent(.timer, sleepFn, .{ sleep_t, io });
            },
        }
    }

    // Graceful shutdown: walk any remaining in-flight results, no item lost.
    var freed_inbox: usize = 0;
    var recycled_pool: usize = 0;

    while (sel.cancel()) |event| {
        switch (event) {
            .inbox => |r| switch (r) {
                .item => |handle| {
                    var slot: Slot = handle;
                    helpers.freeSlot(&slot, allocator);
                    freed_inbox += 1;
                    std.log.info("graceful cancel: freed inbox item", .{});
                },
                .canceled, .closed, .timeout => {},
            },
            .pool_ev => |r| switch (r) {
                .item => |handle| {
                    var slot: Slot = handle;
                    pool.put(ph, &slot); // recycle
                    recycled_pool += 1;
                    std.log.info("graceful cancel: recycled pool item", .{});
                },
                .canceled, .closed, .timeout, .not_created => {},
            },
            .timer => {},
        }
    }

    try helpers.expect(error.SelectGracefulShutdownFailed, shutdown_seen, "shutdown command not received");
    try helpers.expect(error.SelectGracefulShutdownFailed, events_processed == N_EVENTS, "events not all processed");
    std.log.info("done: events={d}, freed_inbox={d}, recycled_pool={d}", .{ events_processed, freed_inbox, recycled_pool });
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
