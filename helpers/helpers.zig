pub const types = @import("types.zig");

pub fn expect(comptime err: anyerror, ok: bool, comptime msg: []const u8) anyerror!void {
    if (!ok) {
        log.err("{s}", .{msg});
        return err;
    }
}

pub fn clearList(list: *std.DoublyLinkedList) void {
    while (list.popFirst()) |_| {}
}

pub fn freeItem(poly: *polynode.PolyNode, alloc: std.mem.Allocator) void {
    if (types.EventPolyHelper.cast(poly)) |ev| {
        alloc.destroy(ev);
    } else if (types.SensorPolyHelper.cast(poly)) |sn| {
        alloc.destroy(sn);
    } else if (types.TimerPolyHelper.cast(poly)) |tm| {
        alloc.destroy(tm);
    } else if (types.ShutdownCommandPolyHelper.cast(poly)) |sc| {
        alloc.destroy(sc);
    }
}

pub fn freeList(list: *std.DoublyLinkedList, alloc: std.mem.Allocator) void {
    while (list.popFirst()) |node| {
        freeItem(@fieldParentPtr("node", node), alloc);
    }
}

pub fn createByTag(tag: *const anyopaque, alloc: std.mem.Allocator, m: *polynode.Slot) void {
    if (types.EventPolyHelper.isIt(tag)) {
        const ev = alloc.create(types.Event) catch return;
        ev.* = .{};
        types.EventPolyHelper.init(ev);
        m.* = &ev.poly;
    } else if (types.SensorPolyHelper.isIt(tag)) {
        const sn = alloc.create(types.Sensor) catch return;
        sn.* = .{};
        types.SensorPolyHelper.init(sn);
        m.* = &sn.poly;
    }
}

pub const AlwaysCreateCtx = struct {
    alloc: std.mem.Allocator,

    pub fn poolHooks(self: *AlwaysCreateCtx, tags: []const *const anyopaque) pool_mod.PoolHooks {
        return .{
            .ctx = self,
            .tags = tags,
            .on_get = onGet,
            .on_put = onPut,
            .on_close = onClose,
        };
    }

    fn onGet(ctx: *anyopaque, tag: *const anyopaque, _: usize, m: *polynode.Slot) void {
        if (m.* != null) return;
        const self: *AlwaysCreateCtx = @ptrCast(@alignCast(ctx));
        createByTag(tag, self.alloc, m);
    }

    fn onPut(_: *anyopaque, _: usize, _: *polynode.Slot) void {}

    fn onClose(ctx: *anyopaque, list: *std.DoublyLinkedList) void {
        const self: *AlwaysCreateCtx = @ptrCast(@alignCast(ctx));
        freeList(list, self.alloc);
    }
};

pub const CappedPoolCtx = struct {
    alloc: std.mem.Allocator,
    cap: usize,

    pub fn poolHooks(self: *CappedPoolCtx, tags: []const *const anyopaque) pool_mod.PoolHooks {
        return .{
            .ctx = self,
            .tags = tags,
            .on_get = onGet,
            .on_put = onPut,
            .on_close = onClose,
        };
    }

    fn onGet(ctx: *anyopaque, tag: *const anyopaque, _: usize, m: *polynode.Slot) void {
        if (m.* != null) return;
        const self: *CappedPoolCtx = @ptrCast(@alignCast(ctx));
        createByTag(tag, self.alloc, m);
    }

    fn onPut(ctx: *anyopaque, in_pool_count: usize, m: *polynode.Slot) void {
        if (m.* == null) return;
        const self: *CappedPoolCtx = @ptrCast(@alignCast(ctx));
        if (in_pool_count >= self.cap) {
            freeItem(m.*.?, self.alloc);
            m.* = null;
        }
    }

    fn onClose(ctx: *anyopaque, list: *std.DoublyLinkedList) void {
        const self: *CappedPoolCtx = @ptrCast(@alignCast(ctx));
        freeList(list, self.alloc);
    }
};

const std = @import("std");
const log = std.log;
const polynode = @import("matryoshka").polynode;
const pool_mod = @import("matryoshka").pool;
