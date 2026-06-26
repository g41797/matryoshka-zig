// Terminator sentinel: Event with code == -1 signals stage exit.

const ProducerCtx = struct {
    outbox: MailboxHandle,
    alloc: std.mem.Allocator,
};

fn producerFn(ctx: *ProducerCtx) void {
    var i: i32 = 0;
    while (i < 5) : (i += 1) {
        const ev: *types.Event = ctx.alloc.create(types.Event) catch return;
        ev.* = .{ .code = i };
        types.EventPolyHelper.init(ev);
        var slot: Slot = &ev.poly;
        mailbox.send(ctx.outbox, &slot) catch {
            ctx.alloc.destroy(ev);
            return;
        };
    }
    // Send terminator.
    const term: *types.Event = ctx.alloc.create(types.Event) catch return;
    term.* = .{ .code = -1 };
    types.EventPolyHelper.init(term);
    var slot: Slot = &term.poly;
    mailbox.send(ctx.outbox, &slot) catch ctx.alloc.destroy(term);
}

const StageCtx = struct {
    inbox: MailboxHandle,
    outbox: MailboxHandle,
    alloc: std.mem.Allocator,
};

fn transformerFn(ctx: *StageCtx) void {
    while (true) {
        var out: Slot = null;
        mailbox.receive(ctx.inbox, &out, null) catch return;
        const ev: *types.Event = types.EventPolyHelper.cast(out.?) orelse {
            helpers.freeItem(out.?, ctx.alloc);
            continue;
        };
        if (ev.code == -1) {
            // Propagate terminator downstream.
            var slot: Slot = &ev.poly;
            mailbox.send(ctx.outbox, &slot) catch ctx.alloc.destroy(ev);
            return;
        }
        ev.code = ev.code * ev.code;
        var slot: Slot = &ev.poly;
        mailbox.send(ctx.outbox, &slot) catch ctx.alloc.destroy(ev);
    }
}

const ConsumerCtx = struct {
    mbh: MailboxHandle,
    alloc: std.mem.Allocator,
    sum: i32 = 0,
    count: usize = 0,
};

fn consumerFn(ctx: *ConsumerCtx) void {
    while (true) {
        var out: Slot = null;
        mailbox.receive(ctx.mbh, &out, null) catch return;
        const ev: *types.Event = types.EventPolyHelper.cast(out.?) orelse {
            helpers.freeItem(out.?, ctx.alloc);
            continue;
        };
        if (ev.code == -1) {
            ctx.alloc.destroy(ev);
            return;
        }
        std.log.info("pipeline: result={d}", .{ev.code});
        ctx.sum += ev.code;
        ctx.count += 1;
        ctx.alloc.destroy(ev);
    }
}

pub fn run(allocator: std.mem.Allocator, io: std.Io) !void {
    const stage1: MailboxHandle = try mailbox.new(io, allocator);
    const stage2: MailboxHandle = try mailbox.new(io, allocator);
    defer {
        var r1: std.DoublyLinkedList = mailbox.close(stage1);
        helpers.freeList(&r1, allocator);
        var r2: std.DoublyLinkedList = mailbox.close(stage2);
        helpers.freeList(&r2, allocator);
        mailbox.destroy(stage1, allocator);
        mailbox.destroy(stage2, allocator);
    }

    var prod_ctx: ProducerCtx = .{ .outbox = stage1, .alloc = allocator };
    var tran_ctx: StageCtx = .{ .inbox = stage1, .outbox = stage2, .alloc = allocator };
    var cons_ctx: ConsumerCtx = .{ .mbh = stage2, .alloc = allocator };

    const t_prod = try std.Thread.spawn(.{}, producerFn, .{&prod_ctx});
    const t_tran = try std.Thread.spawn(.{}, transformerFn, .{&tran_ctx});
    const t_cons = try std.Thread.spawn(.{}, consumerFn, .{&cons_ctx});

    t_prod.join();
    t_tran.join();
    t_cons.join();

    // 0²+1²+2²+3²+4² = 30.
    std.log.info("pipeline: count={d} sum={d}", .{ cons_ctx.count, cons_ctx.sum });
    try helpers.expect(error.PipelineFailed, cons_ctx.count == 5, "wrong item count");
    try helpers.expect(error.PipelineFailed, cons_ctx.sum == 30, "wrong sum");
}

const std = @import("std");
const helpers = @import("helpers");
const matryoshka = @import("matryoshka");
const polynode = matryoshka.polynode;
const mailbox = matryoshka.mailbox;
const Slot = polynode.Slot;
const MailboxHandle = mailbox.MailboxHandle;
const types = helpers.types;
