// SPDX-FileCopyrightText: Copyright (c) 2026 g41797
// SPDX-License-Identifier: MIT

// Master A sends an Event request to Master B's inbox.
// Master B processes it, sends a Sensor response to Master A's inbox.
// Ownership transfers: A→B (request), B→A (response). No shared mutable state.

const MasterACtx = struct {
    a_inbox: MailboxHandle,
    b_inbox: MailboxHandle,
    alloc: std.mem.Allocator,
};

fn masterAFn(ctx: *MasterACtx) anyerror!void {
    const ev: *types.Event = try ctx.alloc.create(types.Event);
    ev.* = .{ .code = 42 };
    types.EventPolyHelper.init(ev);
    var req_slot: Slot = &ev.poly;
    try mailbox.send(ctx.b_inbox, &req_slot);
    std.log.info("master A: sent Event code=42 request to B", .{});

    var resp_slot: Slot = null;
    try mailbox.receive(ctx.a_inbox, &resp_slot, null);
    const poly: *PolyNode = resp_slot.?;

    if (types.SensorPolyHelper.cast(poly)) |sn| {
        std.log.info("master A: received Sensor response value={d}", .{sn.value});
        ctx.alloc.destroy(sn);
    } else {
        helpers.freeItem(poly, ctx.alloc);
    }
}

const MasterBCtx = struct {
    a_inbox: MailboxHandle,
    b_inbox: MailboxHandle,
    alloc: std.mem.Allocator,
};

fn masterBFn(ctx: *MasterBCtx) anyerror!void {
    var req_slot: Slot = null;
    try mailbox.receive(ctx.b_inbox, &req_slot, null);
    const poly: *PolyNode = req_slot.?;

    var response_value: f64 = 0.0;
    if (types.EventPolyHelper.cast(poly)) |ev| {
        response_value = @floatFromInt(ev.code);
        std.log.info("master B: received Event code={d}, computing response", .{ev.code});
        ctx.alloc.destroy(ev);
    } else {
        helpers.freeItem(poly, ctx.alloc);
    }

    const sn: *types.Sensor = try ctx.alloc.create(types.Sensor);
    sn.* = .{ .value = response_value };
    types.SensorPolyHelper.init(sn);
    var resp_slot: Slot = &sn.poly;
    try mailbox.send(ctx.a_inbox, &resp_slot);
    std.log.info("master B: sent Sensor response value={d}", .{response_value});
}

pub fn run(allocator: std.mem.Allocator, io: std.Io) !void {
    const a_inbox: MailboxHandle = try mailbox.new(io, allocator);
    defer {
        var rem: std.DoublyLinkedList = mailbox.close(a_inbox);
        helpers.freeList(&rem, allocator);
        mailbox.destroy(a_inbox, allocator);
    }

    const b_inbox: MailboxHandle = try mailbox.new(io, allocator);
    defer {
        var rem: std.DoublyLinkedList = mailbox.close(b_inbox);
        helpers.freeList(&rem, allocator);
        mailbox.destroy(b_inbox, allocator);
    }

    var ctx_a: MasterACtx = .{ .a_inbox = a_inbox, .b_inbox = b_inbox, .alloc = allocator };
    var ctx_b: MasterBCtx = .{ .a_inbox = a_inbox, .b_inbox = b_inbox, .alloc = allocator };

    var fut_a = try io.concurrent(masterAFn, .{&ctx_a});
    var fut_b = try io.concurrent(masterBFn, .{&ctx_b});

    try fut_a.await(io);
    try fut_b.await(io);

    std.log.info("request-response done: both masters completed", .{});
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
