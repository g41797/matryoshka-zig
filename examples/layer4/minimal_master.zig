// SPDX-FileCopyrightText: Copyright (c) 2026 g41797
// SPDX-License-Identifier: MIT

const WorkerCtx = struct {
    mbh: MailboxHandle,
    alloc: std.mem.Allocator,
};

fn workerFn(ctx: *WorkerCtx) anyerror!void {
    while (true) {
        var slot: Slot = null;
        mailbox.receive(ctx.mbh, &slot, null) catch return;
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

    var ctx: WorkerCtx = .{ .mbh = mbh, .alloc = allocator };
    var fut = try io.concurrent(workerFn, .{&ctx});

    for (0..3) |i| {
        const ev: *types.Event = try allocator.create(types.Event);
        errdefer allocator.destroy(ev);
        ev.* = .{ .code = @intCast(i + 1) };
        types.EventPolyHelper.init(ev);
        var slot: Slot = &ev.poly;
        try mailbox.send(mbh, &slot);
        std.log.info("master: sent Event code={d}", .{i + 1});
    }

    // close signals worker to stop; returned list holds any undelivered items.
    var remaining: std.DoublyLinkedList = mailbox.close(mbh);
    helpers.freeList(&remaining, allocator);

    try fut.await(io);
    std.log.info("master: worker done", .{});
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
