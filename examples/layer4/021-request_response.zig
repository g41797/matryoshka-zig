// SPDX-FileCopyrightText: Copyright (c) 2026 g41797
// SPDX-License-Identifier: MIT

// Ownership:
//
//  master A ──Event(request)──► b_inbox ──► master B
//  master A ◄──Sensor(response)── a_inbox ◄── master B
//  (fut_a + fut_b run concurrently; fut_a.await → fut_b.await)

const MasterACtx = struct {
    a_inbox: MailboxHandle,
    b_inbox: MailboxHandle,
    alloc: std.mem.Allocator,
};

fn masterAFn(ctx: *MasterACtx) anyerror!void {
    {
        var slot: Slot = null;
        defer helpers.freeSlot(&slot, ctx.alloc);
        try types.EventPolyHelper.create(ctx.alloc, &slot);
        types.EventPolyHelper.cast(slot.?).?.code = 42;
        try mailbox.send(ctx.b_inbox, &slot);
        std.log.info("master A: sent Event code=42 request to B", .{});
    }

    var slot: Slot = null;
    defer helpers.freeSlot(&slot, ctx.alloc);
    try mailbox.receive(ctx.a_inbox, &slot, null);

    if (types.SensorPolyHelper.cast(slot.?)) |sn| {
        std.log.info("master A: received Sensor response value={d}", .{sn.value});
        helpers.freeSlot(&slot, ctx.alloc);
    } else {
        helpers.freeSlot(&slot, ctx.alloc);
    }
}

const MasterBCtx = struct {
    a_inbox: MailboxHandle,
    b_inbox: MailboxHandle,
    alloc: std.mem.Allocator,
};

fn masterBFn(ctx: *MasterBCtx) anyerror!void {
    var slot: Slot = null;
    defer helpers.freeSlot(&slot, ctx.alloc);
    try mailbox.receive(ctx.b_inbox, &slot, null);

    var response_value: f64 = 0.0;
    if (types.EventPolyHelper.cast(slot.?)) |ev| {
        response_value = @floatFromInt(ev.code);
        std.log.info("master B: received Event code={d}, computing response", .{ev.code});
        helpers.freeSlot(&slot, ctx.alloc);
    } else {
        helpers.freeSlot(&slot, ctx.alloc);
    }

    try types.SensorPolyHelper.create(ctx.alloc, &slot);
    types.SensorPolyHelper.cast(slot.?).?.value = response_value;
    try mailbox.send(ctx.a_inbox, &slot);
    std.log.info("master B: sent Sensor response value={d}", .{response_value});
}

fn runMasters(a_inbox: MailboxHandle, b_inbox: MailboxHandle, alloc: std.mem.Allocator, io: std.Io) !void {
    var ctx_a: MasterACtx = .{ .a_inbox = a_inbox, .b_inbox = b_inbox, .alloc = alloc };
    var ctx_b: MasterBCtx = .{ .a_inbox = a_inbox, .b_inbox = b_inbox, .alloc = alloc };
    var fut_a = try io.concurrent(masterAFn, .{&ctx_a});
    var fut_b = try io.concurrent(masterBFn, .{&ctx_b});
    try fut_a.await(io);
    try fut_b.await(io);
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

    try runMasters(a_inbox, b_inbox, allocator, io);
    std.log.info("request-response done: both masters completed", .{});
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
