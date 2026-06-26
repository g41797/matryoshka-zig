// SPDX-FileCopyrightText: Copyright (c) 2026 g41797
// SPDX-License-Identifier: MIT

const WorkerCtx = struct {
    mbh: MailboxHandle,
    alloc: std.mem.Allocator,
    first_count: usize = 0,
    batch_count: usize = 0,
};

fn batchWorkerFn(ctx: *WorkerCtx) void {
    while (true) {
        var out: Slot = null;
        mailbox.receive(ctx.mbh, &out, null) catch return;
        const poly: *PolyNode = out.?;

        if (types.ShutdownCommandPolyHelper.cast(poly)) |cmd| {
            ctx.alloc.destroy(cmd);
            return;
        }

        helpers.freeItem(poly, ctx.alloc);
        ctx.first_count += 1;

        // Drain whatever accumulated while blocked.
        var batch: std.DoublyLinkedList = mailbox.receive_batch(ctx.mbh) catch return;
        while (batch.popFirst()) |node| {
            const bpoly: *PolyNode = @fieldParentPtr("node", node);
            if (types.ShutdownCommandPolyHelper.cast(bpoly)) |cmd| {
                ctx.alloc.destroy(cmd);
                return;
            }
            helpers.freeItem(bpoly, ctx.alloc);
            ctx.batch_count += 1;
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

    var ctx: WorkerCtx = .{ .mbh = mbh, .alloc = allocator };
    const t = try std.Thread.spawn(.{}, batchWorkerFn, .{&ctx});

    const n: usize = 10;
    var i: usize = 0;
    while (i < n) : (i += 1) {
        const ev: *types.Event = try allocator.create(types.Event);
        ev.* = .{ .code = @intCast(i) };
        types.EventPolyHelper.init(ev);
        var slot: Slot = &ev.poly;
        try mailbox.send(mbh, &slot);
    }

    // Signal worker to stop — all n items are already queued before this.
    const cmd: *types.ShutdownCommand = try allocator.create(types.ShutdownCommand);
    cmd.* = .{};
    types.ShutdownCommandPolyHelper.init(cmd);
    var cmd_slot: Slot = &cmd.poly;
    try mailbox.send(mbh, &cmd_slot);

    t.join();

    const total = ctx.first_count + ctx.batch_count;
    std.log.info("batch: first={d} batch={d} total={d}", .{ ctx.first_count, ctx.batch_count, total });
    try helpers.expect(error.BatchProcessingFailed, total == n, "wrong total");
    try helpers.expect(error.BatchProcessingFailed, ctx.first_count > 0, "no items received as first");
}

const std = @import("std");

const helpers = @import("helpers");
const types = helpers.types;
const matryoshka = @import("matryoshka");
const polynode = matryoshka.polynode;
const mailbox = matryoshka.mailbox;
const PolyNode = polynode.PolyNode;
const Slot = polynode.Slot;
const MailboxHandle = mailbox.MailboxHandle;
