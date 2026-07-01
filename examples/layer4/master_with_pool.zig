// SPDX-FileCopyrightText: Copyright (c) 2026 g41797
// SPDX-License-Identifier: MIT

// Ownership:
//
//  master ──pool.get──► slot ──mailbox.send──► mailbox
//                                                 │ worker (io.concurrent)
//                                                 │ mailbox.receive ──► slot
//                                                 │ pool.put (defer) ──► pool (recycled)
//  fut.cancel ──► worker exits at next mailbox.receive
//  master.destroy ──► pool.close ──► mailbox.close ──► free remaining

const WorkerCtx = struct {
    mbh: MailboxHandle,
    ph: PoolHandle,
};

fn workerFn(ctx: *WorkerCtx) anyerror!void {
    while (true) {
        var slot: Slot = null;
        defer pool.put(ctx.ph, &slot);
        mailbox.receive(ctx.mbh, &slot, null) catch return;
    }
}

const MasterWithPool = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    pool_ctx: helpers.AlwaysCreateCtx,
    tags: [1]*const anyopaque,
    ph: PoolHandle,
    mbh: MailboxHandle,
    worker_ctx: WorkerCtx,

    fn init(allocator: std.mem.Allocator, io: std.Io) !*MasterWithPool {
        const self = try allocator.create(MasterWithPool);
        errdefer allocator.destroy(self);
        self.allocator = allocator;
        self.io = io;
        self.pool_ctx = .{ .alloc = allocator };
        self.tags = .{types.EventPolyHelper.TAG};
        self.ph = try pool.new(io, allocator);
        errdefer {
            pool.close(self.ph);
            pool.destroy(self.ph, allocator);
        }
        try pool.init(self.ph, self.pool_ctx.poolHooks(&self.tags));
        self.mbh = try mailbox.new(io, allocator);
        self.worker_ctx = .{ .mbh = self.mbh, .ph = self.ph };
        return self;
    }

    fn destroy(self: *MasterWithPool) void {
        pool.close(self.ph);
        pool.destroy(self.ph, self.allocator);
        var rem: std.DoublyLinkedList = mailbox.close(self.mbh);
        helpers.freeList(&rem, self.allocator);
        mailbox.destroy(self.mbh, self.allocator);
        self.allocator.destroy(self);
    }

    fn run(self: *MasterWithPool) !void {
        try self.sendItems();
        var fut = try self.io.concurrent(workerFn, .{&self.worker_ctx});
        fut.cancel(self.io) catch {};
        std.log.info("master: worker stopped", .{});
    }

    fn sendItems(self: *MasterWithPool) !void {
        for (0..3) |i| {
            var slot: Slot = null;
            defer pool.put(self.ph, &slot);
            try pool.get(self.ph, types.EventPolyHelper.TAG, .available_or_new, &slot);
            const ev = types.EventPolyHelper.cast(slot.?).?;
            ev.code = @intCast(i + 1);
            std.log.info("master: sending Event code={d}", .{ev.code});
            try mailbox.send(self.mbh, &slot);
        }
    }
};

pub fn run(allocator: std.mem.Allocator, io: std.Io) !void {
    const master = try MasterWithPool.init(allocator, io);
    defer master.destroy();
    try master.run();
}

const helpers = @import("helpers");
const matryoshka = @import("matryoshka");
const std = @import("std");
const mailbox = matryoshka.mailbox;
const pool = matryoshka.pool;
const polynode = matryoshka.polynode;
const Slot = polynode.Slot;
const MailboxHandle = mailbox.MailboxHandle;
const PoolHandle = pool.PoolHandle;
const types = helpers.types;
