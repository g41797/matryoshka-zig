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
        helpers.freeItem(out.?, ctx.alloc);
        ctx.first_count += 1;

        // Drain whatever accumulated while blocked.
        var batch: std.DoublyLinkedList = mailbox.receive_batch(ctx.mbh) catch return;
        while (batch.popFirst()) |node| {
            helpers.freeItem(@fieldParentPtr("node", node), ctx.alloc);
            ctx.batch_count += 1;
        }
    }
}

pub fn run(allocator: std.mem.Allocator, io: std.Io) !void {
    const mbh: MailboxHandle = try mailbox.new(io, allocator);
    defer mailbox.destroy(mbh, allocator);

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

    var rem: std.DoublyLinkedList = mailbox.close(mbh);
    var remaining: usize = 0;
    while (rem.popFirst()) |node| {
        helpers.freeItem(@fieldParentPtr("node", node), allocator);
        remaining += 1;
    }
    t.join();

    std.log.info("batch: first={d} batch={d} remaining={d} total={d}", .{
        ctx.first_count, ctx.batch_count, remaining, ctx.first_count + ctx.batch_count + remaining,
    });
    try helpers.expect(error.BatchProcessingFailed, ctx.first_count + ctx.batch_count + remaining == n, "wrong total");
    try helpers.expect(error.BatchProcessingFailed, ctx.first_count > 0, "no items received as first");
}


const std = @import("std");

const helpers = @import("helpers");
const types = helpers.types;
const matryoshka = @import("matryoshka");
const polynode = matryoshka.polynode;
const mailbox = matryoshka.mailbox;
const Slot = polynode.Slot;
const MailboxHandle = mailbox.MailboxHandle;

