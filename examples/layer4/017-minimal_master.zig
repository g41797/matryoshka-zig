// SPDX-FileCopyrightText: Copyright (c) 2026 g41797
// SPDX-License-Identifier: MIT

// Ownership:
//
//  master ──alloc.create──► slot ──mailbox.send──► mailbox
//                                                      │ worker (io.concurrent)
//                                                      │ mailbox.receive ──► freeSlot
//  mailbox.close ──► remaining list ──► freeList
//  fut.await ──► worker done

const WorkerCtx = struct {
    mbh: MailboxHandle,
    alloc: std.mem.Allocator,
};

fn workerFn(ctx: *WorkerCtx) anyerror!void {
    while (true) {
        var slot: Slot = null;
        defer helpers.freeSlot(&slot, ctx.alloc);
        mailbox.receive(ctx.mbh, &slot, null) catch return;
    }
}

fn sendItems(mbh: MailboxHandle, alloc: std.mem.Allocator) !void {
    for (0..3) |i| {
        var slot: Slot = null;
        defer types.EventPolyHelper.destroy(alloc, &slot);
        try types.EventPolyHelper.create(alloc, &slot);
        types.EventPolyHelper.cast(slot.?).?.code = @intCast(i + 1);
        try mailbox.send(mbh, &slot);
        std.log.info("master: sent Event code={d}", .{i + 1});
    }
}

fn awaitWorker(mbh: MailboxHandle, alloc: std.mem.Allocator, io: std.Io, fut: *Io.Future(anyerror!void)) !void {
    var remaining: std.DoublyLinkedList = mailbox.close(mbh);
    helpers.freeList(&remaining, alloc);
    try fut.await(io);
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
    try sendItems(mbh, allocator);
    try awaitWorker(mbh, allocator, io, &fut);
    std.log.info("master: worker done", .{});
}

const helpers = @import("helpers");
const matryoshka = @import("matryoshka");
const std = @import("std");
const mailbox = matryoshka.mailbox;
const polynode = matryoshka.polynode;
const PolyNode = polynode.PolyNode;
const Slot = polynode.Slot;
const MailboxHandle = mailbox.MailboxHandle;
const Io = std.Io;
const types = helpers.types;
