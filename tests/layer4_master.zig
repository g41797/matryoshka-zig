// SPDX-FileCopyrightText: Copyright (c) 2026 g41797
// SPDX-License-Identifier: MIT

const WorkerCtx = struct {
    mbh: MailboxHandle,
    alloc: std.mem.Allocator,
};

fn workerFn(ctx: *WorkerCtx) error{Canceled}!void {
    var slot: Slot = null;
    mailbox.receive(ctx.mbh, &slot, null) catch |err| switch (err) {
        error.Canceled => return error.Canceled,
        error.Closed, error.Timeout => return,
    };
    const poly: *PolyNode = slot.?;
    if (EventPolyHelper.cast(poly)) |ev| {
        ctx.alloc.destroy(ev);
    } else {
        helpers.freeItem(poly, ctx.alloc);
    }
}

// --- Scenario 1: single worker spawn and join ---
test "1 - single worker spawn and join" {
    std.testing.log_level = .debug;
    var threaded: std.Io.Threaded = std.Io.Threaded.init(testing.allocator, .{});
    defer threaded.deinit();
    const io: Io = threaded.io();

    const mbh: MailboxHandle = try mailbox.new(io, testing.allocator);
    defer {
        var rem: std.DoublyLinkedList = mailbox.close(mbh);
        helpers.freeList(&rem, testing.allocator);
        mailbox.destroy(mbh, testing.allocator);
    }

    var ctx: WorkerCtx = .{ .mbh = mbh, .alloc = testing.allocator };
    var fut = try io.concurrent(workerFn, .{&ctx});

    const ev: *Event = try testing.allocator.create(Event);
    errdefer testing.allocator.destroy(ev);
    ev.* = .{ .code = 42 };
    EventPolyHelper.init(ev);
    var slot: Slot = &ev.poly;
    try mailbox.send(mbh, &slot);
    try testing.expect(slot == null);

    try fut.await(io);
}

// --- Scenario 2: worker group spawn and join ---
test "2 - worker group spawn and join" {
    std.testing.log_level = .debug;
    var threaded: std.Io.Threaded = std.Io.Threaded.init(testing.allocator, .{});
    defer threaded.deinit();
    const io: Io = threaded.io();

    const mbh: MailboxHandle = try mailbox.new(io, testing.allocator);
    defer {
        var rem: std.DoublyLinkedList = mailbox.close(mbh);
        helpers.freeList(&rem, testing.allocator);
        mailbox.destroy(mbh, testing.allocator);
    }

    var ctx1: WorkerCtx = .{ .mbh = mbh, .alloc = testing.allocator };
    var ctx2: WorkerCtx = .{ .mbh = mbh, .alloc = testing.allocator };
    var ctx3: WorkerCtx = .{ .mbh = mbh, .alloc = testing.allocator };

    var group: Io.Group = .init;
    defer group.cancel(io);

    try group.concurrent(io, workerFn, .{&ctx1});
    try group.concurrent(io, workerFn, .{&ctx2});
    try group.concurrent(io, workerFn, .{&ctx3});

    for (0..3) |i| {
        const ev: *Event = try testing.allocator.create(Event);
        errdefer testing.allocator.destroy(ev);
        ev.* = .{ .code = @intCast(i) };
        EventPolyHelper.init(ev);
        var slot: Slot = &ev.poly;
        try mailbox.send(mbh, &slot);
    }

    try group.await(io);
}

const std = @import("std");
const testing = std.testing;
const Io = std.Io;

const matryoshka = @import("matryoshka");
const polynode = matryoshka.polynode;
const mailbox = matryoshka.mailbox;
const PolyNode = polynode.PolyNode;
const Slot = polynode.Slot;
const MailboxHandle = mailbox.MailboxHandle;

const helpers = @import("helpers");
const types = helpers.types;
const Event = types.Event;
const EventPolyHelper = types.EventPolyHelper;
