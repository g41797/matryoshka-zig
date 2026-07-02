// SPDX-FileCopyrightText: Copyright (c) 2026 g41797
// SPDX-License-Identifier: MIT

// Ownership:
//
//  master ──Event×3──► mailbox ──► worker A (Io.Group)
//                             ├──► worker B  (compete; each freeSlot)
//                             └──► worker C
//  mailbox.close ──► remaining freeList ──► group.await

const WorkerCtx = struct {
    mbh: MailboxHandle,
    alloc: std.mem.Allocator,
};

fn workerFn(ctx: *WorkerCtx) error{Canceled}!void {
    while (true) {
        var slot: Slot = null;
        defer helpers.freeSlot(&slot, ctx.alloc);
        mailbox.receive(ctx.mbh, &slot, null) catch |err| switch (err) {
            error.Canceled => return error.Canceled,
            error.Closed, error.Timeout => return,
        };
    }
}

fn spawnWorkers(mbh: MailboxHandle, alloc: std.mem.Allocator, io: std.Io, group: *Io.Group, ctxs: *[3]WorkerCtx) !void {
    for (ctxs) |*ctx| {
        ctx.* = .{ .mbh = mbh, .alloc = alloc };
        try group.concurrent(io, workerFn, .{ctx});
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

fn awaitAll(mbh: MailboxHandle, alloc: std.mem.Allocator, io: std.Io, group: *Io.Group) !void {
    var remaining: std.DoublyLinkedList = mailbox.close(mbh);
    helpers.freeList(&remaining, alloc);
    try group.await(io);
}

pub fn run(allocator: std.mem.Allocator, io: std.Io) !void {
    const mbh: MailboxHandle = try mailbox.new(io, allocator);
    defer {
        var rem: std.DoublyLinkedList = mailbox.close(mbh);
        helpers.freeList(&rem, allocator);
        mailbox.destroy(mbh, allocator);
    }

    var worker_ctxs: [3]WorkerCtx = undefined;
    var group: Io.Group = .init;
    defer group.cancel(io);
    try spawnWorkers(mbh, allocator, io, &group, &worker_ctxs);
    try sendItems(mbh, allocator);
    try awaitAll(mbh, allocator, io, &group);
    std.log.info("master: all workers done", .{});
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
