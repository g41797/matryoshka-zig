// SPDX-FileCopyrightText: Copyright (c) 2026 g41797
// SPDX-License-Identifier: MIT

const WorkerCtx = struct {
    mbh: MailboxHandle,
    alloc: std.mem.Allocator,
};

fn workerFn(ctx: *WorkerCtx) error{Canceled}!void {
    while (true) {
        var slot: Slot = null;
        mailbox.receive(ctx.mbh, &slot, null) catch |err| switch (err) {
            error.Canceled => return error.Canceled,
            error.Closed, error.Timeout => return,
        };
        const poly: *PolyNode = slot.?;
        helpers.freeItem(poly, ctx.alloc);
    }
}

pub fn run(allocator: std.mem.Allocator, io: std.Io) !void {
    const mbh: MailboxHandle = try mailbox.new(io, allocator);
    defer {
        var rem: std.DoublyLinkedList = mailbox.close(mbh);
        helpers.freeList(&rem, allocator);
        mailbox.destroy(mbh, allocator);
    }

    var ctx1: WorkerCtx = .{ .mbh = mbh, .alloc = allocator };
    var ctx2: WorkerCtx = .{ .mbh = mbh, .alloc = allocator };
    var ctx3: WorkerCtx = .{ .mbh = mbh, .alloc = allocator };

    var group: Io.Group = .init;
    defer group.cancel(io);

    try group.concurrent(io, workerFn, .{&ctx1});
    try group.concurrent(io, workerFn, .{&ctx2});
    try group.concurrent(io, workerFn, .{&ctx3});

    for (0..3) |i| {
        const ev: *types.Event = try allocator.create(types.Event);
        errdefer allocator.destroy(ev);
        ev.* = .{ .code = @intCast(i + 1) };
        types.EventPolyHelper.init(ev);
        var slot: Slot = &ev.poly;
        try mailbox.send(mbh, &slot);
        std.log.info("master: sent Event code={d}", .{i + 1});
    }

    // Close signals all workers to stop: their next receive returns error.Closed.
    var remaining: std.DoublyLinkedList = mailbox.close(mbh);
    helpers.freeList(&remaining, allocator);

    try group.await(io);
    std.log.info("master: all workers done", .{});
}

const std = @import("std");
const helpers = @import("helpers");
const matryoshka = @import("matryoshka");
const mailbox = matryoshka.mailbox;
const polynode = matryoshka.polynode;
const PolyNode = polynode.PolyNode;
const Slot = polynode.Slot;
const MailboxHandle = mailbox.MailboxHandle;
const Io = std.Io;
const types = helpers.types;
