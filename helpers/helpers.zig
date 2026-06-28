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

pub fn freeSlot(slot: *polynode.Slot, alloc: std.mem.Allocator) void {
    if (slot.*) |poly| {
        freeItem(poly, alloc);
        slot.* = null;
    }
}

pub fn freeList(list: *std.DoublyLinkedList, alloc: std.mem.Allocator) void {
    while (list.popFirst()) |node| {
        freeItem(@fieldParentPtr("node", node), alloc);
    }
}

pub fn createByTag(tag: *const anyopaque, alloc: std.mem.Allocator, slot: *polynode.Slot) void {
    if (types.EventPolyHelper.isIt(tag)) {
        types.EventPolyHelper.create(alloc, slot) catch return;
    } else if (types.SensorPolyHelper.isIt(tag)) {
        types.SensorPolyHelper.create(alloc, slot) catch return;
    }
}

pub fn destroyByTag(tag: *const anyopaque, alloc: std.mem.Allocator, slot: *polynode.Slot) void {
    if (types.EventPolyHelper.isIt(tag)) {
        types.EventPolyHelper.destroy(alloc, slot);
    } else if (types.SensorPolyHelper.isIt(tag)) {
        types.SensorPolyHelper.destroy(alloc, slot);
    } else if (types.TimerPolyHelper.isIt(tag)) {
        types.TimerPolyHelper.destroy(alloc, slot);
    } else if (types.ShutdownCommandPolyHelper.isIt(tag)) {
        types.ShutdownCommandPolyHelper.destroy(alloc, slot);
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

    fn onGet(ctx: *anyopaque, tag: *const anyopaque, _: usize, slot: *polynode.Slot) void {
        if (slot.* != null) return;
        const self: *AlwaysCreateCtx = @ptrCast(@alignCast(ctx));
        createByTag(tag, self.alloc, slot);
    }

    fn onPut(_: *anyopaque, _: usize, _: *polynode.Slot) void {}

    fn onClose(ctx: *anyopaque, list: *std.DoublyLinkedList) void {
        const self: *AlwaysCreateCtx = @ptrCast(@alignCast(ctx));
        freeList(list, self.alloc);
    }
};

pub const CappedPoolCtx = struct {
    alloc: std.mem.Allocator,
    cap:   usize,
    io:    Io,
    mutex: Io.Mutex = .init,
    count: usize = 0,

    pub fn poolHooks(self: *CappedPoolCtx, tags: []const *const anyopaque) pool_mod.PoolHooks {
        return .{
            .ctx = self,
            .tags = tags,
            .on_get = onGet,
            .on_put = onPut,
            .on_close = onClose,
        };
    }

    fn onGet(ctx: *anyopaque, tag: *const anyopaque, _: usize, slot: *polynode.Slot) void {
        const self: *CappedPoolCtx = @ptrCast(@alignCast(ctx));
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);

        if (slot.* != null) {
            // item came from pool — pool already decremented its count; mirror that here
            self.count -= 1;
            return;
        }
        // no item in pool — create a fresh one (not counted until put back)
        createByTag(tag, self.alloc, slot);
    }

    fn onPut(ctx: *anyopaque, _: usize, slot: *polynode.Slot) void {
        if (slot.* == null) return;
        const self: *CappedPoolCtx = @ptrCast(@alignCast(ctx));
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);

        if (self.count >= self.cap) {
            freeItem(slot.*.?, self.alloc);
            slot.* = null;
        } else {
            self.count += 1;
        }
    }

    fn onClose(ctx: *anyopaque, list: *std.DoublyLinkedList) void {
        const self: *CappedPoolCtx = @ptrCast(@alignCast(ctx));
        freeList(list, self.alloc);
        self.count = 0;
    }
};

const polynode = @import("matryoshka").polynode;
const pool_mod = @import("matryoshka").pool;
const std = @import("std");
const Io = std.Io;
const log = std.log;
