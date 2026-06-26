// SPDX-FileCopyrightText: Copyright (c) 2026 g41797
// SPDX-License-Identifier: MIT

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
        const tm: *types.Timer = try ctx.alloc.create(types.Timer);
        tm.* = .{};
        types.TimerPolyHelper.init(tm);
        var slot: Slot = &tm.poly;
        mailbox.send(ctx.mbh, &slot) catch {
            ctx.alloc.destroy(tm);
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
        try mailbox.receive(ctx.mbh, &slot, null);
        received += 1;
        const poly: *PolyNode = slot.?;

        if (types.TimerPolyHelper.cast(poly)) |tm| {
            ctx.timer_count += 1;
            std.log.info("worker: timer tick {d}", .{ctx.timer_count});
            ctx.alloc.destroy(tm);
        } else if (types.EventPolyHelper.cast(poly)) |ev| {
            ctx.event_count += 1;
            std.log.info("worker: Event code={d} (event {d})", .{ ev.code, ctx.event_count });
            ctx.alloc.destroy(ev);
        } else {
            helpers.freeItem(poly, ctx.alloc);
        }
    }
}

pub fn run(allocator: std.mem.Allocator, io: std.Io) !void {
    const mbh: MailboxHandle = try mailbox.new(io, allocator);
    defer {
        var rem: std.DoublyLinkedList = mailbox.close(mbh);
        helpers.freeList(&rem, allocator);
        mailbox.destroy(mbh, allocator);
    }

    // Send data Events before spawning the timer task.
    for (0..N_EVENTS) |i| {
        const ev: *types.Event = try allocator.create(types.Event);
        errdefer allocator.destroy(ev);
        ev.* = .{ .code = @intCast(i + 1) };
        types.EventPolyHelper.init(ev);
        var slot: Slot = &ev.poly;
        try mailbox.send(mbh, &slot);
    }

    var timer_ctx: TimerCtx = .{ .mbh = mbh, .alloc = allocator, .io = io };
    var worker_ctx: WorkerCtx = .{
        .mbh = mbh,
        .alloc = allocator,
        .expected = N_EVENTS + N_TICKS,
    };

    var fut_timer = try io.concurrent(timerFn, .{&timer_ctx});
    var fut_worker = try io.concurrent(workerFn, .{&worker_ctx});
    errdefer fut_worker.cancel(io) catch {};

    try fut_timer.await(io);
    try fut_worker.await(io);

    try helpers.expect(error.TimerViaMailboxFailed, worker_ctx.event_count == N_EVENTS, "expected 2 Events");
    try helpers.expect(error.TimerViaMailboxFailed, worker_ctx.timer_count == N_TICKS, "expected 2 timer ticks");

    std.log.info("done: {d} events, {d} timer ticks — tag dispatch via single mailbox", .{
        worker_ctx.event_count,
        worker_ctx.timer_count,
    });
}

const std = @import("std");
const helpers = @import("helpers");
const matryoshka = @import("matryoshka");
const mailbox = matryoshka.mailbox;
const polynode = matryoshka.polynode;
const PolyNode = polynode.PolyNode;
const Slot = polynode.Slot;
const MailboxHandle = mailbox.MailboxHandle;
const types = helpers.types;
