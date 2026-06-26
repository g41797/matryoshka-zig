// SPDX-FileCopyrightText: Copyright (c) 2026 g41797
// SPDX-License-Identifier: MIT

// Pipeline: producer → transformer → consumer
//
// Producer sends 3 Events then a ShutdownCommand sentinel.
// Transformer receives Events → converts to Sensors → forwards to consumer.
// Transformer receives ShutdownCommand → forwards to consumer → returns.
// Consumer counts Sensors, exits on ShutdownCommand.
// Ownership transfers cleanly at each stage via mailbox send.

const ProducerCtx = struct {
    out_mbh: MailboxHandle,
    alloc: std.mem.Allocator,
};

fn producerFn(ctx: *ProducerCtx) anyerror!void {
    for (0..3) |i| {
        const ev: *types.Event = try ctx.alloc.create(types.Event);
        ev.* = .{ .code = @intCast(i + 1) };
        types.EventPolyHelper.init(ev);
        var slot: Slot = &ev.poly;
        try mailbox.send(ctx.out_mbh, &slot);
        std.log.info("producer: sent Event code={d}", .{i + 1});
    }
    const cmd: *types.ShutdownCommand = try ctx.alloc.create(types.ShutdownCommand);
    cmd.* = .{};
    types.ShutdownCommandPolyHelper.init(cmd);
    var sentinel: Slot = &cmd.poly;
    try mailbox.send(ctx.out_mbh, &sentinel);
    std.log.info("producer: sent ShutdownCommand sentinel", .{});
}

const TransformerCtx = struct {
    in_mbh: MailboxHandle,
    out_mbh: MailboxHandle,
    alloc: std.mem.Allocator,
};

fn transformerFn(ctx: *TransformerCtx) anyerror!void {
    while (true) {
        var slot: Slot = null;
        mailbox.receive(ctx.in_mbh, &slot, null) catch return;
        const poly: *PolyNode = slot.?;

        if (types.EventPolyHelper.cast(poly)) |ev| {
            const value: f64 = @floatFromInt(ev.code);
            ctx.alloc.destroy(ev);
            const sn: *types.Sensor = ctx.alloc.create(types.Sensor) catch continue;
            sn.* = .{ .value = value };
            types.SensorPolyHelper.init(sn);
            var out_slot: Slot = &sn.poly;
            mailbox.send(ctx.out_mbh, &out_slot) catch {
                ctx.alloc.destroy(sn);
            };
            std.log.info("transformer: Event→Sensor value={d}", .{value});
        } else if (types.ShutdownCommandPolyHelper.cast(poly)) |_| {
            // Forward sentinel to consumer, then stop.
            var fwd: Slot = poly;
            mailbox.send(ctx.out_mbh, &fwd) catch {
                helpers.freeItem(poly, ctx.alloc);
            };
            std.log.info("transformer: forwarded ShutdownCommand, done", .{});
            return;
        } else {
            helpers.freeItem(poly, ctx.alloc);
        }
    }
}

const ConsumerCtx = struct {
    in_mbh: MailboxHandle,
    alloc: std.mem.Allocator,
    count: usize = 0,
};

fn consumerFn(ctx: *ConsumerCtx) anyerror!void {
    while (true) {
        var slot: Slot = null;
        mailbox.receive(ctx.in_mbh, &slot, null) catch return;
        const poly: *PolyNode = slot.?;

        if (types.SensorPolyHelper.cast(poly)) |sn| {
            ctx.count += 1;
            std.log.info("consumer: Sensor value={d} (total={d})", .{ sn.value, ctx.count });
            ctx.alloc.destroy(sn);
        } else if (types.ShutdownCommandPolyHelper.cast(poly)) |sc| {
            std.log.info("consumer: ShutdownCommand received, done", .{});
            ctx.alloc.destroy(sc);
            return;
        } else {
            helpers.freeItem(poly, ctx.alloc);
        }
    }
}

pub fn run(allocator: std.mem.Allocator, io: std.Io) !void {
    const transformer_mbh: MailboxHandle = try mailbox.new(io, allocator);
    defer {
        var rem: std.DoublyLinkedList = mailbox.close(transformer_mbh);
        helpers.freeList(&rem, allocator);
        mailbox.destroy(transformer_mbh, allocator);
    }

    const consumer_mbh: MailboxHandle = try mailbox.new(io, allocator);
    defer {
        var rem: std.DoublyLinkedList = mailbox.close(consumer_mbh);
        helpers.freeList(&rem, allocator);
        mailbox.destroy(consumer_mbh, allocator);
    }

    var prod_ctx: ProducerCtx = .{ .out_mbh = transformer_mbh, .alloc = allocator };
    var trans_ctx: TransformerCtx = .{
        .in_mbh = transformer_mbh,
        .out_mbh = consumer_mbh,
        .alloc = allocator,
    };
    var cons_ctx: ConsumerCtx = .{ .in_mbh = consumer_mbh, .alloc = allocator };

    var fut_prod = try io.concurrent(producerFn, .{&prod_ctx});
    var fut_trans = try io.concurrent(transformerFn, .{&trans_ctx});
    var fut_cons = try io.concurrent(consumerFn, .{&cons_ctx});

    try fut_prod.await(io);
    try fut_trans.await(io);
    try fut_cons.await(io);

    try helpers.expect(error.PipelineFailed, cons_ctx.count == 3, "expected consumer to receive 3 Sensors");

    std.log.info("pipeline done: consumer received {d} items", .{cons_ctx.count});
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
