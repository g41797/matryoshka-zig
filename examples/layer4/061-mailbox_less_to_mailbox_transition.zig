// SPDX-FileCopyrightText: Copyright (c) 2026 g41797
// SPDX-License-Identifier: MIT

// Ownership (transition: mailbox-less → mailbox needed):
//
//  pool (seeded)       mock clients (io.concurrent ×N_CLIENTS → mailbox.send)
//  │ getWaitResult      │ receiveResult
//  └────────┬───────────┘
//           ▼
//  Select(MasterEvent)
//  │
//  .pool_ev .item ──► process ──► pool.put ──► pool (re-spawn)
//  .inbox .item   ──► freeSlot               (re-spawn receiveResult)
//  │
//  clients finish → mailbox.close → inbox returns .closed
//  sel.cancelDiscard ──► pool.close ──► on_close ──► freed
//
//  Transition: when senders are multiple and independent, fan-in via mailbox
//  becomes necessary. Mailbox is the third event source in Select.

const NET_DELAY_NS: i96 = 10_000_000; // 10 ms per client
const N_CLIENTS: usize = 3;
const N_POOL_ITEMS: usize = 2;

const MasterEvent = union(enum) {
    pool_ev: pool.PoolResult,
    inbox: mailbox.ReceiveResult,
};

const ClientCtx = struct {
    mbh: MailboxHandle,
    alloc: std.mem.Allocator,
    id: usize,
    delay: std.Io.Timeout,
};

fn clientFn(ctx: *ClientCtx, io: std.Io) anyerror!void {
    std.Io.Timeout.sleep(ctx.delay, io) catch {};
    var slot: Slot = null;
    defer types.EventPolyHelper.destroy(ctx.alloc, &slot);
    try types.EventPolyHelper.create(ctx.alloc, &slot);
    types.EventPolyHelper.cast(slot.?).?.code = @intCast(ctx.id);
    std.log.info("client {d}: sending to mailbox", .{ctx.id});
    mailbox.send(ctx.mbh, &slot) catch {};
}

const Ctx = struct {
    mbh: MailboxHandle,
    alloc: std.mem.Allocator,
    io: std.Io,
    pool_done: usize = 0,
    inbox_done: usize = 0,

    fn spawnClients(self: *Ctx, ctxs: *[N_CLIENTS]ClientCtx, futs: *[N_CLIENTS]Io.Future(anyerror!void)) !void {
        const client_delay: std.Io.Timeout = .{
            .duration = .{ .raw = .{ .nanoseconds = NET_DELAY_NS }, .clock = .real },
        };
        for (0..N_CLIENTS) |i| {
            ctxs[i] = .{ .mbh = self.mbh, .alloc = self.alloc, .id = i + 1, .delay = client_delay };
            futs[i] = try self.io.concurrent(clientFn, .{ &ctxs[i], self.io });
        }
    }

    fn awaitClients(self: *Ctx, futs: *[N_CLIENTS]Io.Future(anyerror!void)) void {
        for (futs) |*fut| {
            fut.await(self.io) catch {};
        }
    }

    fn closeMailboxAfterClients(self: *Ctx) void {
        var rem: std.DoublyLinkedList = mailbox.close(self.mbh);
        helpers.freeList(&rem, self.alloc);
    }

    fn setupSelect(self: *Ctx, ph: PoolHandle, sel: *std.Io.Select(MasterEvent)) !void {
        try sel.concurrent(.pool_ev, pool.getWaitResult, .{ ph, types.EventPolyHelper.TAG, null });
        try sel.concurrent(.inbox, mailbox.receiveResult, .{ self.mbh, null });
    }

    fn runEventLoop(self: *Ctx, ph: PoolHandle, sel: *std.Io.Select(MasterEvent)) !void {
        while (self.pool_done < N_POOL_ITEMS or self.inbox_done < N_CLIENTS) {
            const event: MasterEvent = try sel.await();
            switch (event) {
                .pool_ev => |r| switch (r) {
                    .item => |handle| {
                        var slot: Slot = handle;
                        defer pool.put(ph, &slot);
                        const ev: *types.Event = types.EventPolyHelper.cast(slot.?).?;
                        ev.code += 1;
                        self.pool_done += 1;
                        std.log.info("pool_ev: processed code={d} ({d}/{d})", .{ ev.code, self.pool_done, N_POOL_ITEMS });
                        if (self.pool_done < N_POOL_ITEMS) {
                            try sel.concurrent(.pool_ev, pool.getWaitResult, .{ ph, types.EventPolyHelper.TAG, null });
                        }
                    },
                    .closed, .canceled, .timeout, .not_created => break,
                },
                .inbox => |r| switch (r) {
                    .item => |handle| {
                        var slot: Slot = handle;
                        defer helpers.freeSlot(&slot, self.alloc);
                        const ev: *types.Event = types.EventPolyHelper.cast(slot.?).?;
                        self.inbox_done += 1;
                        std.log.info("inbox: client item code={d} ({d}/{d})", .{ ev.code, self.inbox_done, N_CLIENTS });
                        if (self.inbox_done < N_CLIENTS) {
                            try sel.concurrent(.inbox, mailbox.receiveResult, .{ self.mbh, null });
                        }
                    },
                    .closed, .canceled, .timeout => break,
                },
            }
        }
        sel.cancelDiscard();
    }
};

fn seedPool(ph: PoolHandle) !void {
    for (0..N_POOL_ITEMS) |i| {
        var slot: Slot = null;
        try pool.get(ph, types.EventPolyHelper.TAG, .new_only, &slot);
        types.EventPolyHelper.cast(slot.?).?.code = @intCast(100 + i);
        pool.put(ph, &slot);
    }
}

pub fn run(allocator: std.mem.Allocator, io: std.Io) !void {
    const ph: PoolHandle = try pool.new(io, allocator);
    var pool_ctx: helpers.AlwaysCreateCtx = .{ .alloc = allocator };
    const tags = [_]*const anyopaque{types.EventPolyHelper.TAG};
    try pool.init(ph, pool_ctx.poolHooks(&tags));
    defer {
        pool.close(ph);
        pool.destroy(ph, allocator);
    }

    const mbh: MailboxHandle = try mailbox.new(io, allocator);
    defer mailbox.destroy(mbh, allocator);

    try seedPool(ph);

    var ctxs: [N_CLIENTS]ClientCtx = undefined;
    var futs: [N_CLIENTS]Io.Future(anyerror!void) = undefined;
    var ctx: Ctx = .{ .mbh = mbh, .alloc = allocator, .io = io };
    try ctx.spawnClients(&ctxs, &futs);

    var buf: [8]MasterEvent = undefined;
    var sel: std.Io.Select(MasterEvent) = std.Io.Select(MasterEvent).init(io, &buf);
    try ctx.setupSelect(ph, &sel);
    try ctx.runEventLoop(ph, &sel);

    ctx.awaitClients(&futs);
    ctx.closeMailboxAfterClients();

    try helpers.expect(error.MailboxTransitionFailed, ctx.pool_done == N_POOL_ITEMS, "pool items mismatch");
    try helpers.expect(error.MailboxTransitionFailed, ctx.inbox_done == N_CLIENTS, "client items mismatch");
    std.log.info("done: {d} clients → mailbox fan-in; {d} pool items — mailbox needed for independent senders", .{ ctx.inbox_done, ctx.pool_done });
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
const Io = std.Io;
const types = helpers.types;
