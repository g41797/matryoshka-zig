// SPDX-FileCopyrightText: Copyright (c) 2026 g41797
// SPDX-License-Identifier: MIT

// Ownership:
//
//  master ──Event×3 + ShutdownCommand──► worker_mbh ──► worker thread
//                                                           │ process
//                                                           │ send worker_mbh ──► master_inbox
//                                                           ▼ exit
//  master ◄──worker_mbh (as NodeHandle)── master_inbox
//  master: close + destroy worker_mbh (tag+pointer verified first)

const WorkerCtx = struct {
    master_inbox: MailboxHandle,
    worker_mbh: MailboxHandle,
    alloc: std.mem.Allocator,
    processed: usize = 0,
};

fn cleanupReturnedMailbox(slot: *Slot, alloc: std.mem.Allocator) void {
    const returned: MailboxHandle = slot.*.?;
    _ = mailbox.close(returned);
    mailbox.destroy(returned, alloc);
    slot.* = null;
}

fn workerFn(ctx: *WorkerCtx) void {
    while (true) {
        var slot: Slot = null;
        defer helpers.freeSlot(&slot, ctx.alloc);
        mailbox.receive(ctx.worker_mbh, &slot, null) catch return;
        const poly: *PolyNode = slot.?;

        if (types.ShutdownCommandPolyHelper.cast(poly) != null) {
            helpers.freeSlot(&slot, ctx.alloc);
            slot = ctx.worker_mbh;
            mailbox.send(ctx.master_inbox, &slot) catch {};
            slot = null;
            return;
        }

        if (types.EventPolyHelper.cast(poly)) |ev| {
            ctx.processed += 1;
            std.log.info("worker processed Event code={d}", .{ev.code});
            helpers.freeSlot(&slot, ctx.alloc);
        }
    }
}

fn sendJobsAndShutdown(worker_mbh: MailboxHandle, alloc: std.mem.Allocator) !void {
    var i: usize = 0;
    while (i < 3) : (i += 1) {
        var slot: Slot = null;
        defer types.EventPolyHelper.destroy(alloc, &slot);
        try types.EventPolyHelper.create(alloc, &slot);
        types.EventPolyHelper.cast(slot.?).?.code = @as(i32, @intCast(i + 1));
        try mailbox.send(worker_mbh, &slot);
    }

    var slot: Slot = null;
    defer types.ShutdownCommandPolyHelper.destroy(alloc, &slot);
    try types.ShutdownCommandPolyHelper.create(alloc, &slot);
    try mailbox.send(worker_mbh, &slot);

    std.log.info("master: sent 3 Events + ShutdownCommand to worker", .{});
}

fn spawnWorker(master_inbox: MailboxHandle, worker_mbh: MailboxHandle, ctx: *WorkerCtx, alloc: std.mem.Allocator) !std.Thread {
    ctx.* = .{ .master_inbox = master_inbox, .worker_mbh = worker_mbh, .alloc = alloc };
    return std.Thread.spawn(.{}, workerFn, .{ctx});
}

fn receiveAndVerify(master_inbox: MailboxHandle, worker_mbh: MailboxHandle, alloc: std.mem.Allocator) !void {
    var slot: Slot = null;
    defer if (slot) |mh| {
        _ = mailbox.close(mh);
        mailbox.destroy(mh, alloc);
    };
    try mailbox.receive(master_inbox, &slot, null);
    try helpers.expect(error.WorkerFinishFailed, mailbox.is_it_you(slot.?.*.tag), "expected a MailboxHandle");
    try helpers.expect(error.WorkerFinishFailed, slot.? == worker_mbh, "wrong mailbox returned");
    cleanupReturnedMailbox(&slot, alloc);
}

pub fn run(allocator: std.mem.Allocator, io: std.Io) !void {
    const master_inbox: MailboxHandle = try mailbox.new(io, allocator);
    defer {
        _ = mailbox.close(master_inbox);
        mailbox.destroy(master_inbox, allocator);
    }

    const worker_mbh: MailboxHandle = try mailbox.new(io, allocator);

    try sendJobsAndShutdown(worker_mbh, allocator);

    var worker_ctx: WorkerCtx = undefined;
    const t = try spawnWorker(master_inbox, worker_mbh, &worker_ctx, allocator);

    try receiveAndVerify(master_inbox, worker_mbh, allocator);
    std.log.info("master: received worker_mbh back — worker finished (processed={d})", .{worker_ctx.processed});

    t.join();
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
