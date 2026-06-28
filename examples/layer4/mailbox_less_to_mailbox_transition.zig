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

pub fn run(allocator: std.mem.Allocator, io: std.Io) !void {
    const ph: PoolHandle = try pool.new(io, allocator);
    var pool_ctx: helpers.AlwaysCreateCtx = .{ .alloc = allocator };
    const tags = [_]*const anyopaque{types.EventPolyHelper.TAG};
    try pool.init(ph, pool_ctx.poolHooks(&tags));
    defer {
        pool.close(ph);
        pool.destroy(ph, allocator);
    }

    // Mailbox for fan-in from multiple clients.
    const mbh: MailboxHandle = try mailbox.new(io, allocator);
    defer mailbox.destroy(mbh, allocator);

    // Seed pool.
    for (0..N_POOL_ITEMS) |i| {
        var slot: Slot = null;
        try pool.get(ph, types.EventPolyHelper.TAG, .new_only, &slot);
        types.EventPolyHelper.cast(slot.?).?.code = @intCast(100 + i);
        pool.put(ph, &slot);
    }

    const client_delay: std.Io.Timeout = .{
        .duration = .{ .raw = .{ .nanoseconds = NET_DELAY_NS }, .clock = .real },
    };

    // Spawn N_CLIENTS independent senders — each sends exactly one item.
    var ctxs: [N_CLIENTS]ClientCtx = undefined;
    var futs: [N_CLIENTS]Io.Future(anyerror!void) = undefined;
    for (0..N_CLIENTS) |i| {
        ctxs[i] = .{ .mbh = mbh, .alloc = allocator, .id = i + 1, .delay = client_delay };
        futs[i] = try io.concurrent(clientFn, .{ &ctxs[i], io });
    }

    var buf: [8]MasterEvent = undefined;
    var sel: std.Io.Select(MasterEvent) = std.Io.Select(MasterEvent).init(io, &buf);

    try sel.concurrent(.pool_ev, pool.getWaitResult, .{ ph, types.EventPolyHelper.TAG, null });
    try sel.concurrent(.inbox, mailbox.receiveResult, .{ mbh, null });

    var pool_done: usize = 0;
    var inbox_done: usize = 0;

    while (pool_done < N_POOL_ITEMS or inbox_done < N_CLIENTS) {
        const event: MasterEvent = try sel.await();
        switch (event) {
            .pool_ev => |r| switch (r) {
                .item => |handle| {
                    var slot: Slot = handle;
                    defer pool.put(ph, &slot);
                    const ev: *types.Event = types.EventPolyHelper.cast(slot.?).?;
                    ev.code += 1;
                    pool_done += 1;
                    std.log.info("pool_ev: processed code={d} ({d}/{d})", .{ ev.code, pool_done, N_POOL_ITEMS });
                    if (pool_done < N_POOL_ITEMS) {
                        try sel.concurrent(.pool_ev, pool.getWaitResult, .{ ph, types.EventPolyHelper.TAG, null });
                    }
                },
                .closed, .canceled, .timeout, .not_created => break,
            },
            .inbox => |r| switch (r) {
                .item => |handle| {
                    var slot: Slot = handle;
                    defer helpers.freeSlot(&slot, allocator);
                    const ev: *types.Event = types.EventPolyHelper.cast(slot.?).?;
                    inbox_done += 1;
                    std.log.info("inbox: client item code={d} ({d}/{d})", .{ ev.code, inbox_done, N_CLIENTS });
                    if (inbox_done < N_CLIENTS) {
                        try sel.concurrent(.inbox, mailbox.receiveResult, .{ mbh, null });
                    }
                },
                .closed, .canceled, .timeout => break,
            },
        }
    }

    sel.cancelDiscard();

    // Wait for all client tasks to finish.
    for (&futs) |*fut| {
        fut.await(io) catch {};
    }

    // Close mailbox after all clients done.
    var rem: std.DoublyLinkedList = mailbox.close(mbh);
    helpers.freeList(&rem, allocator);

    try helpers.expect(error.MailboxTransitionFailed, pool_done == N_POOL_ITEMS, "pool items mismatch");
    try helpers.expect(error.MailboxTransitionFailed, inbox_done == N_CLIENTS, "client items mismatch");
    std.log.info("done: {d} clients → mailbox fan-in; {d} pool items — mailbox needed for independent senders", .{ inbox_done, pool_done });
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
