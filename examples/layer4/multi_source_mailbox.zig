// SPDX-FileCopyrightText: Copyright (c) 2026 g41797
// SPDX-License-Identifier: MIT

const TICK_NS: i96 = 20_000_000; // 20 ms
const N_EVENTS: usize = 3;
const N_TICKS: usize = 2;

const SenderCtx = struct {
    mbh: MailboxHandle,
    alloc: std.mem.Allocator,
    io: std.Io,
};

fn timerSenderFn(ctx: *SenderCtx) anyerror!void {
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

fn eventSenderFn(ctx: *SenderCtx) anyerror!void {
    for (0..N_EVENTS) |i| {
        const ev: *types.Event = try ctx.alloc.create(types.Event);
        ev.* = .{ .code = @intCast(i + 1) };
        types.EventPolyHelper.init(ev);
        var slot: Slot = &ev.poly;
        mailbox.send(ctx.mbh, &slot) catch {
            ctx.alloc.destroy(ev);
            return;
        };
    }
}

fn signalSenderFn(ctx: *SenderCtx) anyerror!void {
    const cmd: *types.ShutdownCommand = try ctx.alloc.create(types.ShutdownCommand);
    cmd.* = .{};
    types.ShutdownCommandPolyHelper.init(cmd);
    var slot: Slot = &cmd.poly;
    mailbox.send(ctx.mbh, &slot) catch {
        ctx.alloc.destroy(cmd);
    };
}

const WorkerCtx = struct {
    mbh: MailboxHandle,
    alloc: std.mem.Allocator,
    timer_count: usize = 0,
    event_count: usize = 0,
    signal_count: usize = 0,
};

fn workerFn(ctx: *WorkerCtx) anyerror!void {
    while (true) {
        var slot: Slot = null;
        mailbox.receive(ctx.mbh, &slot, null) catch return;
        const poly: *PolyNode = slot.?;

        if (types.TimerPolyHelper.cast(poly)) |tm| {
            ctx.timer_count += 1;
            std.log.info("worker: timer tick {d}", .{ctx.timer_count});
            ctx.alloc.destroy(tm);
        } else if (types.EventPolyHelper.cast(poly)) |ev| {
            ctx.event_count += 1;
            std.log.info("worker: Event code={d}", .{ev.code});
            ctx.alloc.destroy(ev);
        } else if (types.ShutdownCommandPolyHelper.cast(poly)) |sc| {
            ctx.signal_count += 1;
            std.log.info("worker: ShutdownCommand signal", .{});
            ctx.alloc.destroy(sc);
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

    var sender_ctx: SenderCtx = .{ .mbh = mbh, .alloc = allocator, .io = io };
    var worker_ctx: WorkerCtx = .{ .mbh = mbh, .alloc = allocator };

    var fut_timer = try io.concurrent(timerSenderFn, .{&sender_ctx});
    var fut_events = try io.concurrent(eventSenderFn, .{&sender_ctx});
    var fut_signal = try io.concurrent(signalSenderFn, .{&sender_ctx});
    var fut_worker = try io.concurrent(workerFn, .{&worker_ctx});

    // Wait for all senders to finish, then close mailbox to stop worker.
    fut_timer.await(io) catch {};
    fut_events.await(io) catch {};
    fut_signal.await(io) catch {};

    var remaining: std.DoublyLinkedList = mailbox.close(mbh);
    helpers.freeList(&remaining, allocator);

    fut_worker.await(io) catch {};

    std.log.info("done: {d} events, {d} timer ticks, {d} signals — fan-in to one mailbox", .{
        worker_ctx.event_count,
        worker_ctx.timer_count,
        worker_ctx.signal_count,
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
