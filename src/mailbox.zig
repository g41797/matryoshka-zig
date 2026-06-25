// SPDX-FileCopyrightText: Copyright (c) 2026 g41797
// SPDX-License-Identifier: MIT

pub const MailboxHandle = polynode.NodeHandle;

const _Mailbox = struct {
    poly: polynode.PolyNode,
    mutex: Io.Mutex,
    cond: Io.Condition,
    list: std.DoublyLinkedList,
    len: usize,
    closed: std.atomic.Value(bool),
    oob_count: usize,
    oob_last: ?*std.DoublyLinkedList.Node,
    io: Io,
    alloc: std.mem.Allocator,
};

const _MailboxPolyHelper = polynode.PolyHelper(_Mailbox);

pub fn new(io: Io, alloc: std.mem.Allocator) !MailboxHandle {
    const mbx: *_Mailbox = try alloc.create(_Mailbox);
    errdefer alloc.destroy(mbx);
    mbx.* = .{
        .poly = .{ .tag = _MailboxPolyHelper.TAG },
        .mutex = .init,
        .cond = .init,
        .list = .{},
        .len = 0,
        .closed = std.atomic.Value(bool).init(false),
        .oob_count = 0,
        .oob_last = null,
        .io = io,
        .alloc = alloc,
    };
    return &mbx.*.poly;
}

pub inline fn is_it_you(tag: *const anyopaque) bool {
    return _MailboxPolyHelper.isIt(tag);
}

pub fn destroy(mbh: MailboxHandle, alloc: std.mem.Allocator) void {
    const mbx: *_Mailbox = _MailboxPolyHelper.cast(mbh).?;
    if (!mbx.*.closed.load(.acquire)) {
        @panic("mailbox.destroy: mailbox must be closed first");
    }
    alloc.destroy(mbx);
}

pub fn send(mbh: MailboxHandle, m: *polynode.Slot) error{Closed}!void {
    std.debug.assert(m.* != null);
    std.debug.assert(!polynode.is_linked(m.*.?));

    const mbx: *_Mailbox = _MailboxPolyHelper.cast(mbh).?;

    if (mbx.*.closed.load(.acquire)) return error.Closed;
    const io: Io = mbx.*.io;

    mbx.*.mutex.lockUncancelable(io);
    defer mbx.*.mutex.unlock(io);

    if (mbx.*.closed.load(.monotonic)) return error.Closed;

    const handle: polynode.NodeHandle = m.*.?;
    mbx.*.list.append(&handle.*.node);
    mbx.*.len += 1;
    m.* = null;

    mbx.*.cond.signal(io);
}

pub fn send_oob(mbh: MailboxHandle, m: *polynode.Slot) error{Closed}!void {
    std.debug.assert(m.* != null);
    std.debug.assert(!polynode.is_linked(m.*.?));

    const mbx: *_Mailbox = _MailboxPolyHelper.cast(mbh).?;

    if (mbx.*.closed.load(.acquire)) return error.Closed;
    const io: Io = mbx.*.io;

    mbx.*.mutex.lockUncancelable(io);
    defer mbx.*.mutex.unlock(io);

    if (mbx.*.closed.load(.monotonic)) return error.Closed;

    const handle: polynode.NodeHandle = m.*.?;

    if (mbx.*.oob_last) |last| {
        mbx.*.list.insertAfter(last, &handle.*.node);
    } else {
        mbx.*.list.prepend(&handle.*.node);
    }
    mbx.*.oob_last = &handle.*.node;
    mbx.*.oob_count += 1;
    mbx.*.len += 1;
    m.* = null;

    mbx.*.cond.signal(io);
}

pub fn receive(mbh: MailboxHandle, m: *polynode.Slot, timeout_ns: ?u64) (error{ Closed, Timeout } || Io.Cancelable)!void {
    std.debug.assert(m.* == null);

    const mbx: *_Mailbox = _MailboxPolyHelper.cast(mbh).?;

    if (mbx.*.closed.load(.acquire)) return error.Closed;
    const io: Io = mbx.*.io;

    const timeout_val: Io.Timeout = if (timeout_ns) |ns|
        Io.Timeout{ .duration = .{ .raw = .{ .nanoseconds = @as(i96, @intCast(ns)) }, .clock = .real } }
    else
        .none;

    const deadline: Io.Timeout = timeout_val.toDeadline(io);

    mbx.*.mutex.lock(io) catch |err| return err;
    defer mbx.*.mutex.unlock(io);

    if (mbx.*.closed.load(.monotonic)) return error.Closed;

    while (mbx.*.len == 0) {
        if (mbx.*.closed.load(.monotonic)) return error.Closed;
        cond_timeout.condition_waitTimeout(&mbx.*.cond, io, &mbx.*.mutex, deadline) catch |err| switch (err) {
            error.Timeout => return error.Timeout,
            error.Canceled => return err,
        };
    }

    const node: *std.DoublyLinkedList.Node = mbx.*.list.popFirst().?;
    mbx.*.len -= 1;
    if (mbx.*.oob_count > 0) {
        mbx.*.oob_count -= 1;
        if (mbx.*.oob_count == 0) mbx.*.oob_last = null;
    }

    const poly: *polynode.PolyNode = @fieldParentPtr("node", node);
    m.* = poly;
}

pub fn try_receive(mbh: MailboxHandle, m: *polynode.Slot) error{Closed}!bool {
    std.debug.assert(m.* == null);

    const mbx: *_Mailbox = _MailboxPolyHelper.cast(mbh).?;

    if (mbx.*.closed.load(.acquire)) return error.Closed;
    const io: Io = mbx.*.io;

    mbx.*.mutex.lockUncancelable(io);
    defer mbx.*.mutex.unlock(io);

    if (mbx.*.closed.load(.monotonic)) return error.Closed;

    if (mbx.*.len == 0) return false;

    const node: *std.DoublyLinkedList.Node = mbx.*.list.popFirst().?;
    mbx.*.len -= 1;
    if (mbx.*.oob_count > 0) {
        mbx.*.oob_count -= 1;
        if (mbx.*.oob_count == 0) mbx.*.oob_last = null;
    }

    const poly: *polynode.PolyNode = @fieldParentPtr("node", node);
    m.* = poly;
    return true;
}

pub fn receive_batch(mbh: MailboxHandle) error{Closed}!std.DoublyLinkedList {
    const mbx: *_Mailbox = _MailboxPolyHelper.cast(mbh).?;

    if (mbx.*.closed.load(.acquire)) return error.Closed;
    const io: Io = mbx.*.io;

    mbx.*.mutex.lockUncancelable(io);
    defer mbx.*.mutex.unlock(io);

    if (mbx.*.closed.load(.monotonic)) return error.Closed;

    const result: std.DoublyLinkedList = mbx.*.list;
    mbx.*.list = .{};
    mbx.*.len = 0;
    mbx.*.oob_count = 0;
    mbx.*.oob_last = null;
    return result;
}

pub fn close(mbh: MailboxHandle) std.DoublyLinkedList {
    const mbx: *_Mailbox = _MailboxPolyHelper.cast(mbh).?;

    if (mbx.*.closed.cmpxchgStrong(false, true, .acq_rel, .acquire) != null) {
        return .{};
    }

    const io: Io = mbx.*.io;
    mbx.*.mutex.lockUncancelable(io);
    defer mbx.*.mutex.unlock(io);

    const result: std.DoublyLinkedList = mbx.*.list;
    mbx.*.list = .{};
    mbx.*.len = 0;
    mbx.*.oob_count = 0;
    mbx.*.oob_last = null;

    mbx.*.cond.broadcast(io);

    return result;
}

const polynode = @import("polynode.zig");
const cond_timeout = @import("internal/cond_timeout.zig");
const std = @import("std");
const Io = std.Io;
