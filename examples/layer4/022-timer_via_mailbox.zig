// SPDX-FileCopyrightText: Copyright (c) 2026 g41797
// SPDX-License-Identifier: MIT

// Ownership:
//
//  main ──Event×2──►
//  timerFn ──Timer×2──► mailbox ──► workerFn (tag dispatch; fixed count)
//  (workerFn exits after receiving N_EVENTS + N_TICKS items)
//  fut_timer.await → fut_worker.await

const TICK_NS: i96 = 50_000_000; // 50 ms
const N_EVENTS: usize = 2;
const N_TICKS: usize = 2;

const TimerCtx = struct {
    mbh: MailboxHandle,
    alloc: std.mem.Allocator,
    io: std.Io,
};

fn timerFn(ctx: *TimerCtx) anyerror!void {
    const sleep_t: std.Io.Timeout = .{
        .duration = .{ .raw = .{ .nanoseconds = TICK_NS }, .clock = .real },
    };
    for (0..N_TICKS) |_| {
        try std.Io.Timeout.sleep(sleep_t, ctx.io);
        var slot: Slot = null;
        try types.TimerPolyHelper.create(ctx.alloc, &slot);
        mailbox.send(ctx.mbh, &slot) catch {
            helpers.freeSlot(&slot, ctx.alloc);
            return;
        };
    }
}

const WorkerCtx = struct {
    mbh: MailboxHandle,
    alloc: std.mem.Allocator,
    expected: usize,
    timer_count: usize = 0,
    event_count: usize = 0,
};

fn workerFn(ctx: *WorkerCtx) anyerror!void {
    var received: usize = 0;
    while (received < ctx.expected) {
        var slot: Slot = null;
        defer helpers.freeSlot(&slot, ctx.alloc);
        try mailbox.receive(ctx.mbh, &slot, null);
        received += 1;

        if (types.TimerPolyHelper.cast(slot.?)) |_| {
            ctx.timer_count += 1;
            std.log.info("worker: timer tick {d}", .{ctx.timer_count});
        } else if (types.EventPolyHelper.cast(slot.?)) |ev| {
            ctx.event_count += 1;
            std.log.info("worker: Event code={d} (event {d})", .{ ev.code, ctx.event_count });
        }
    }
}

fn sendEvents(mbh: MailboxHandle, alloc: std.mem.Allocator, count: usize) !void {
    for (0..count) |i| {
        var slot: Slot = null;
        defer types.EventPolyHelper.destroy(alloc, &slot);
        try types.EventPolyHelper.create(alloc, &slot);
        types.EventPolyHelper.cast(slot.?).?.code = @intCast(i + 1);
        try mailbox.send(mbh, &slot);
    }
}

fn spawnAndAwait(mbh: MailboxHandle, alloc: std.mem.Allocator, io: std.Io, worker_ctx: *WorkerCtx) !void {
    var timer_ctx: TimerCtx = .{ .mbh = mbh, .alloc = alloc, .io = io };
    var fut_timer = try io.concurrent(timerFn, .{&timer_ctx});
    var fut_worker = try io.concurrent(workerFn, .{worker_ctx});
    errdefer fut_worker.cancel(io) catch {};
    try fut_timer.await(io);
    try fut_worker.await(io);
}

pub fn run(allocator: std.mem.Allocator, io: std.Io) !void {
    const mbh: MailboxHandle = try mailbox.new(io, allocator);
    defer {
        var rem: std.DoublyLinkedList = mailbox.close(mbh);
        helpers.freeList(&rem, allocator);
        mailbox.destroy(mbh, allocator);
    }

    try sendEvents(mbh, allocator, N_EVENTS);

    var worker_ctx: WorkerCtx = .{
        .mbh = mbh,
        .alloc = allocator,
        .expected = N_EVENTS + N_TICKS,
    };
    try spawnAndAwait(mbh, allocator, io, &worker_ctx);

    try helpers.expect(error.TimerViaMailboxFailed, worker_ctx.event_count == N_EVENTS, "expected 2 Events");
    try helpers.expect(error.TimerViaMailboxFailed, worker_ctx.timer_count == N_TICKS, "expected 2 timer ticks");

    std.log.info("done: {d} events, {d} timer ticks — tag dispatch via single mailbox", .{
        worker_ctx.event_count,
        worker_ctx.timer_count,
    });
}

const helpers = @import("helpers");
const matryoshka = @import("matryoshka");
const std = @import("std");
const mailbox = matryoshka.mailbox;
const polynode = matryoshka.polynode;
const PolyNode = polynode.PolyNode;
const Slot = polynode.Slot;
const MailboxHandle = mailbox.MailboxHandle;
const types = helpers.types;
