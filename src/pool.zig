// SPDX-FileCopyrightText: Copyright (c) 2026 g41797
// SPDX-License-Identifier: MIT

pub const PoolHandle = polynode.NodeHandle;

pub const GetMode = enum {
    available_or_new,
    new_only,
    available_only,
};

pub const GetError = error{ Closed, NotAvailable, NotCreated };

pub const PoolHooks = struct {
    ctx: *anyopaque,
    tags: []const *const anyopaque,
    on_get: *const fn (ctx: *anyopaque, tag: *const anyopaque, in_pool_count: usize, m: *polynode.Slot) void,
    on_put: *const fn (ctx: *anyopaque, in_pool_count: usize, m: *polynode.Slot) void,
    on_close: *const fn (ctx: *anyopaque, list: *std.DoublyLinkedList) void,
};

const _Pool = struct {
    poly: polynode.PolyNode,
    mutex: Io.Mutex,
    cond: Io.Condition,
    lists: std.AutoHashMapUnmanaged(*const anyopaque, std.DoublyLinkedList),
    counts: std.AutoHashMapUnmanaged(*const anyopaque, usize),
    hooks: ?PoolHooks,
    closed: std.atomic.Value(bool),
    io: Io,
    alloc: std.mem.Allocator,
};

pub const PoolPolyHelper = polynode.PolyHelper(_Pool);

pub inline fn is_it_you(tag: *const anyopaque) bool {
    return PoolPolyHelper.isIt(tag);
}

pub fn new(io: Io, alloc: std.mem.Allocator) !PoolHandle {
    const p: *_Pool = try alloc.create(_Pool);
    errdefer alloc.destroy(p);
    p.* = .{
        .poly = .{ .tag = PoolPolyHelper.TAG },
        .mutex = .init,
        .cond = .init,
        .lists = .empty,
        .counts = .empty,
        .hooks = null,
        .closed = std.atomic.Value(bool).init(false),
        .io = io,
        .alloc = alloc,
    };
    return &p.*.poly;
}

pub fn destroy(ph: PoolHandle, alloc: std.mem.Allocator) void {
    const p: *_Pool = PoolPolyHelper.cast(ph).?;
    if (!p.*.closed.load(.acquire)) {
        @panic("pool.destroy: pool must be closed first");
    }
    p.*.lists.deinit(alloc);
    p.*.counts.deinit(alloc);
    alloc.destroy(p);
}

pub fn init(ph: PoolHandle, hooks: PoolHooks) !void {
    const p: *_Pool = PoolPolyHelper.cast(ph).?;
    std.debug.assert(hooks.tags.len > 0);

    const io: Io = p.*.io;
    p.*.mutex.lockUncancelable(io);
    defer p.*.mutex.unlock(io);

    std.debug.assert(!p.*.closed.load(.monotonic));
    std.debug.assert(p.*.hooks == null);

    // Ensure capacity before any modification — OOM fails cleanly here.
    const n: u32 = @intCast(hooks.tags.len);
    try p.*.lists.ensureTotalCapacity(p.*.alloc, n);
    try p.*.counts.ensureTotalCapacity(p.*.alloc, n);

    for (hooks.tags) |tag| {
        p.*.lists.putAssumeCapacity(tag, .{});
        p.*.counts.putAssumeCapacity(tag, 0);
    }

    p.*.hooks = hooks;
}

pub fn get(ph: PoolHandle, tag: *const anyopaque, mode: GetMode, m: *polynode.Slot) GetError!void {
    const p: *_Pool = PoolPolyHelper.cast(ph).?;
    std.debug.assert(m.* == null);

    if (p.*.closed.load(.acquire)) return error.Closed;

    return switch (mode) {
        .available_or_new => _get_available_or_new(p, tag, m),
        .new_only => _get_new_only(p, tag, m),
        .available_only => _get_available_only(p, tag, m),
    };
}

pub fn get_wait(ph: PoolHandle, tag: *const anyopaque, m: *polynode.Slot, timeout_ns: ?u64) (GetError || Io.Cancelable || error{Timeout})!void {
    const p: *_Pool = PoolPolyHelper.cast(ph).?;
    std.debug.assert(m.* == null);

    if (p.*.closed.load(.acquire)) return error.Closed;
    const io: Io = p.*.io;

    const timeout_val: Io.Timeout = if (timeout_ns) |ns|
        Io.Timeout{ .duration = .{ .raw = .{ .nanoseconds = @as(i96, @intCast(ns)) }, .clock = .real } }
    else
        .none;
    const deadline: Io.Timeout = timeout_val.toDeadline(io);

    p.*.mutex.lock(io) catch |err| return err;
    defer p.*.mutex.unlock(io);

    std.debug.assert(p.*.hooks != null);
    std.debug.assert(p.*.lists.contains(tag));

    while (true) {
        if (p.*.closed.load(.monotonic)) return error.Closed;

        if (p.*.lists.getPtr(tag)) |list| {
            if (list.popFirst()) |node| {
                p.*.counts.getPtr(tag).?.* -= 1;
                const poly: *polynode.PolyNode = @fieldParentPtr("node", node);
                polynode.reset(poly);
                m.* = poly;
                return;
            }
        }

        cond_timeout.condition_waitTimeout(&p.*.cond, io, &p.*.mutex, deadline) catch |err| switch (err) {
            error.Timeout => return error.Timeout,
            error.Canceled => return err,
        };
    }
}

pub fn put(ph: PoolHandle, m: *polynode.Slot) void {
    const p: *_Pool = PoolPolyHelper.cast(ph).?;
    std.debug.assert(m.* != null);
    std.debug.assert(!polynode.is_linked(m.*.?));

    const io: Io = p.*.io;
    p.*.mutex.lockUncancelable(io);

    if (p.*.closed.load(.monotonic)) {
        p.*.mutex.unlock(io);
        return; // caller retains ownership
    }

    std.debug.assert(p.*.hooks != null);

    const handle: polynode.NodeHandle = m.*.?;
    const tag: *const anyopaque = handle.*.tag;
    std.debug.assert(p.*.lists.contains(tag));

    const hooks: PoolHooks = p.*.hooks.?;
    const count: usize = p.*.counts.get(tag) orelse 0;

    p.*.mutex.unlock(io);
    hooks.on_put(hooks.ctx, count, m);
    p.*.mutex.lockUncancelable(io);

    if (!p.*.closed.load(.monotonic) and m.* != null) {
        const kept: polynode.NodeHandle = m.*.?;
        std.debug.assert(!polynode.is_linked(kept));
        const kept_tag: *const anyopaque = kept.*.tag;
        if (p.*.lists.getPtr(kept_tag)) |list| {
            list.prepend(&kept.*.node);
            p.*.counts.getPtr(kept_tag).?.* += 1;
            m.* = null;
            p.*.cond.signal(io);
        }
    }

    p.*.mutex.unlock(io);
}

pub fn put_all(ph: PoolHandle, list: *std.DoublyLinkedList) void {
    if (list.first == null) return;

    const p: *_Pool = PoolPolyHelper.cast(ph).?;
    const io: Io = p.*.io;

    // Validate all tags under one lock — no partial transfer on bad input.
    p.*.mutex.lockUncancelable(io);
    var node: ?*std.DoublyLinkedList.Node = list.first;
    while (node) |n| : (node = n.next) {
        const poly: *polynode.PolyNode = @fieldParentPtr("node", n);
        std.debug.assert(p.*.lists.contains(poly.*.tag));
    }
    p.*.mutex.unlock(io);

    // Put each item individually.
    while (list.popFirst()) |n| {
        const poly: *polynode.PolyNode = @fieldParentPtr("node", n);
        polynode.reset(poly);
        var slot: polynode.Slot = poly;
        put(ph, &slot);
        if (slot != null) {
            // Pool closed — item returned to caller — restore and stop.
            list.prepend(&slot.?.*.node);
            break;
        }
    }
}

pub fn close(ph: PoolHandle) void {
    const p: *_Pool = PoolPolyHelper.cast(ph).?;

    // CAS: only one caller does the work; others return immediately.
    if (p.*.closed.cmpxchgStrong(false, true, .acq_rel, .acquire) != null) return;

    const io: Io = p.*.io;
    p.*.mutex.lockUncancelable(io);

    var collected: std.DoublyLinkedList = .{};
    var it = p.*.lists.valueIterator();
    while (it.next()) |list| {
        _concat(&collected, list);
    }
    p.*.lists.clearRetainingCapacity();
    p.*.counts.clearRetainingCapacity();

    p.*.cond.broadcast(io);
    p.*.mutex.unlock(io);

    if (p.*.hooks) |hooks| {
        hooks.on_close(hooks.ctx, &collected);
    }
}

// O(1) splice: move all nodes from src to end of dst, clear src.
fn _concat(dst: *std.DoublyLinkedList, src: *std.DoublyLinkedList) void {
    if (src.first == null) return;
    if (dst.last) |last| {
        last.next = src.first;
        src.first.?.prev = last;
    } else {
        dst.first = src.first;
    }
    dst.last = src.last;
    src.* = .{};
}

fn _get_available_or_new(p: *_Pool, tag: *const anyopaque, m: *polynode.Slot) GetError!void {
    const io: Io = p.*.io;
    p.*.mutex.lockUncancelable(io);

    if (p.*.closed.load(.monotonic)) {
        p.*.mutex.unlock(io);
        return error.Closed;
    }
    std.debug.assert(p.*.hooks != null);
    std.debug.assert(p.*.lists.contains(tag));

    if (p.*.lists.getPtr(tag)) |list| {
        if (list.popFirst()) |node| {
            p.*.counts.getPtr(tag).?.* -= 1;
            const poly: *polynode.PolyNode = @fieldParentPtr("node", node);
            polynode.reset(poly);
            m.* = poly;
        }
    }

    const hooks: PoolHooks = p.*.hooks.?;
    const count: usize = p.*.counts.get(tag) orelse 0;
    p.*.mutex.unlock(io);

    hooks.on_get(hooks.ctx, tag, count, m);
    if (m.*) |h| std.debug.assert(h.*.tag == tag);

    return if (m.* != null) {} else error.NotCreated;
}

fn _get_new_only(p: *_Pool, tag: *const anyopaque, m: *polynode.Slot) GetError!void {
    const io: Io = p.*.io;
    p.*.mutex.lockUncancelable(io);

    if (p.*.closed.load(.monotonic)) {
        p.*.mutex.unlock(io);
        return error.Closed;
    }
    std.debug.assert(p.*.hooks != null);
    std.debug.assert(p.*.lists.contains(tag));

    const hooks: PoolHooks = p.*.hooks.?;
    const count: usize = p.*.counts.get(tag) orelse 0;
    p.*.mutex.unlock(io);

    hooks.on_get(hooks.ctx, tag, count, m);
    if (m.*) |h| std.debug.assert(h.*.tag == tag);

    return if (m.* != null) {} else error.NotCreated;
}

fn _get_available_only(p: *_Pool, tag: *const anyopaque, m: *polynode.Slot) GetError!void {
    const io: Io = p.*.io;
    p.*.mutex.lockUncancelable(io);
    defer p.*.mutex.unlock(io);

    if (p.*.closed.load(.monotonic)) return error.Closed;
    std.debug.assert(p.*.hooks != null);
    std.debug.assert(p.*.lists.contains(tag));

    if (p.*.lists.getPtr(tag)) |list| {
        if (list.popFirst()) |node| {
            p.*.counts.getPtr(tag).?.* -= 1;
            const poly: *polynode.PolyNode = @fieldParentPtr("node", node);
            polynode.reset(poly);
            m.* = poly;
            return;
        }
    }

    return error.NotAvailable;
}

const polynode = @import("polynode.zig");
const cond_timeout = @import("internal/cond_timeout.zig");
const std = @import("std");
const Io = std.Io;
