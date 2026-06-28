// SPDX-FileCopyrightText: Copyright (c) 2026 g41797
// SPDX-License-Identifier: MIT

// Ownership flow:
//
//  buf_pool (VideoBuffer×N_BUFFERS)
//  │ getWaitResult ──► Network Master (Io.Select)
//  │   on buffer: fill ──► attach to StreamContext ──► ready_queue
//  │                                                        │
//  ▼                                                        ▼
//  [ buf_pool ]◄── pool.put ◄── Worker (Io.Group) ◄── mailbox.receive
//  (pool fires ──► Network Master wakes)   │
//                                          └──► EncodedSegment ──► storage_mbh
//                                                                        │
//                                                                        ▼
//                                                              Storage Task
//                                                              (logs, frees)
//
//  Shutdown:
//  Network closes ready_queue ──► workers get error.Closed ──► group.await
//  close storage_mbh ──► storage task exits ──► pool.close ──► on_close frees

// --- Types ---

const N_CAMERAS: usize = 3;
const N_FRAMES_PER_CAMERA: usize = 2; // total frames = 6
const N_BUFFERS: usize = 2;           // fewer than workers — forces backpressure
const N_WORKERS: usize = 2;

const VideoBuffer = struct {
    poly: polynode.PolyNode = .{},
    camera_id: u32 = 0,
    frame_id: u32 = 0,
    data: [64]u8 = .{0} ** 64,
};
const VideoBufferPolyHelper = polynode.PolyHelper(VideoBuffer);

// StreamContext carries per-camera encoder state.
// Routed through ready_queue — worker gets exclusive ownership, no locks needed.
const StreamContext = struct {
    poly: polynode.PolyNode = .{},
    camera_id: u32 = 0,
    frame_id: u32 = 0,
    frames_processed: u32 = 0, // encoder state: accumulates across frames
    buffer_slot: Slot = null,  // VideoBuffer in transit (owned by StreamContext)
};
const StreamContextPolyHelper = polynode.PolyHelper(StreamContext);

const EncodedSegment = struct {
    poly: polynode.PolyNode = .{},
    camera_id: u32 = 0,
    segment_id: u32 = 0,
};
const EncodedSegmentPolyHelper = polynode.PolyHelper(EncodedSegment);

// --- Pool hooks for VideoBuffer pool (fixed-size: N_BUFFERS, no on-demand creation) ---

const VideoBufCtx = struct {
    alloc: std.mem.Allocator,

    pub fn poolHooks(self: *VideoBufCtx, tags: []const *const anyopaque) pool.PoolHooks {
        return .{
            .ctx = self,
            .tags = tags,
            .on_get = onGet,
            .on_put = onPut,
            .on_close = onClose,
        };
    }

    // No on-demand creation: pool size is fixed by seeding at startup.
    fn onGet(_: *anyopaque, _: *const anyopaque, _: usize, _: *Slot) void {}

    // Keep all returned buffers.
    fn onPut(_: *anyopaque, _: usize, _: *Slot) void {}

    fn onClose(ctx: *anyopaque, list: *std.DoublyLinkedList) void {
        const self: *VideoBufCtx = @ptrCast(@alignCast(ctx));
        while (list.popFirst()) |node| {
            const poly: *polynode.PolyNode = @fieldParentPtr("node", node);
            polynode.reset(poly);
            var s: Slot = poly;
            VideoBufferPolyHelper.destroy(self.alloc, &s);
        }
    }
};

// --- Storage task ---

const StorageCtx = struct {
    storage_mbh: MailboxHandle,
    alloc: std.mem.Allocator,
};

fn storageFn(ctx: *StorageCtx) error{Canceled}!void {
    while (true) {
        var slot: Slot = null;
        defer EncodedSegmentPolyHelper.destroy(ctx.alloc, &slot);
        mailbox.receive(ctx.storage_mbh, &slot, null) catch |err| switch (err) {
            error.Canceled => return error.Canceled,
            error.Closed, error.Timeout => return,
        };
        const seg: *EncodedSegment = EncodedSegmentPolyHelper.cast(slot.?).?;
        std.log.info("storage: camera={d} segment={d}", .{ seg.camera_id, seg.segment_id });
    }
}

// --- Encoding worker ---

const WorkerCtx = struct {
    ready_queue: MailboxHandle,
    buf_ph: PoolHandle,
    storage_mbh: MailboxHandle,
    alloc: std.mem.Allocator,
    id: usize,
};

fn workerFn(ctx: *WorkerCtx) error{Canceled}!void {
    while (true) {
        var slot: Slot = null;
        defer StreamContextPolyHelper.destroy(ctx.alloc, &slot);
        mailbox.receive(ctx.ready_queue, &slot, null) catch |err| switch (err) {
            error.Canceled => return error.Canceled,
            error.Closed, error.Timeout => return,
        };
        const sc: *StreamContext = StreamContextPolyHelper.cast(slot.?).?;
        sc.frames_processed += 1;
        std.log.info("worker {d}: encoding camera={d} frame={d} (total={d})", .{
            ctx.id, sc.camera_id, sc.frame_id, sc.frames_processed,
        });

        // Return buffer to pool — wakes Network Master if it is waiting.
        pool.put(ctx.buf_ph, &sc.buffer_slot);
        // If pool closed during shutdown, buffer is retained; free it.
        if (sc.buffer_slot != null) {
            VideoBufferPolyHelper.destroy(ctx.alloc, &sc.buffer_slot);
        }

        // Send encoded segment to storage.
        var seg_slot: Slot = null;
        defer EncodedSegmentPolyHelper.destroy(ctx.alloc, &seg_slot);
        EncodedSegmentPolyHelper.create(ctx.alloc, &seg_slot) catch continue;
        const seg: *EncodedSegment = EncodedSegmentPolyHelper.cast(seg_slot.?).?;
        seg.camera_id = sc.camera_id;
        seg.segment_id = sc.frames_processed;
        mailbox.send(ctx.storage_mbh, &seg_slot) catch {};
    }
}

// --- Network Master and main entry point ---

const NetworkEvent = union(enum) {
    buf_ev: pool.PoolResult,
};

pub fn run(allocator: std.mem.Allocator, io: std.Io) !void {
    // Buffer pool: fixed N_BUFFERS — acts as backpressure signal.
    const buf_ph: PoolHandle = try pool.new(io, allocator);
    var buf_ctx: VideoBufCtx = .{ .alloc = allocator };
    const buf_tags = [_]*const anyopaque{VideoBufferPolyHelper.TAG};
    try pool.init(buf_ph, buf_ctx.poolHooks(&buf_tags));
    defer {
        pool.close(buf_ph);
        pool.destroy(buf_ph, allocator);
    }

    // Seed pool with exactly N_BUFFERS buffers.
    for (0..N_BUFFERS) |_| {
        var slot: Slot = null;
        try VideoBufferPolyHelper.create(allocator, &slot);
        pool.put(buf_ph, &slot);
    }

    // Ready queue: StreamContext objects route camera state to workers.
    const ready_queue: MailboxHandle = try mailbox.new(io, allocator);
    // (closed and destroyed explicitly during shutdown below)

    // Storage mailbox: encoded segments flow from workers to storage task.
    // Closed explicitly before storage_fut.await — cannot use defer (would deadlock).
    const storage_mbh: MailboxHandle = try mailbox.new(io, allocator);

    // Start storage task.
    var storage_ctx: StorageCtx = .{ .storage_mbh = storage_mbh, .alloc = allocator };
    var storage_fut = try io.concurrent(storageFn, .{&storage_ctx});

    // Start encoding workers.
    var wctx0: WorkerCtx = .{ .ready_queue = ready_queue, .buf_ph = buf_ph, .storage_mbh = storage_mbh, .alloc = allocator, .id = 0 };
    var wctx1: WorkerCtx = .{ .ready_queue = ready_queue, .buf_ph = buf_ph, .storage_mbh = storage_mbh, .alloc = allocator, .id = 1 };
    var group: Io.Group = .init;
    try group.concurrent(io, workerFn, .{&wctx0});
    try group.concurrent(io, workerFn, .{&wctx1});

    // Network Master: Io.Select waits for VideoBuffer availability (backpressure).
    var sel_buf: [4]NetworkEvent = undefined;
    var sel: std.Io.Select(NetworkEvent) = std.Io.Select(NetworkEvent).init(io, &sel_buf);

    const total: usize = N_CAMERAS * N_FRAMES_PER_CAMERA;
    var sent: usize = 0;
    var camera_frames: [N_CAMERAS]u32 = .{0} ** N_CAMERAS;
    var camera_idx: usize = 0;

    try sel.concurrent(.buf_ev, pool.getWaitResult, .{ buf_ph, VideoBufferPolyHelper.TAG, null });

    while (sent < total) {
        const ev: NetworkEvent = try sel.await();
        switch (ev) {
            .buf_ev => |r| switch (r) {
                .item => |handle| {
                    var buf_slot: Slot = handle;

                    // Fill buffer with camera and frame identifiers.
                    const vb: *VideoBuffer = VideoBufferPolyHelper.cast(buf_slot.?).?;
                    vb.camera_id = @intCast(camera_idx);
                    vb.frame_id = camera_frames[camera_idx];
                    camera_frames[camera_idx] += 1;
                    std.log.info("network: camera={d} frame={d} buffer filled", .{ vb.camera_id, vb.frame_id });

                    // Create StreamContext; attach buffer.
                    var ctx_slot: Slot = null;
                    defer StreamContextPolyHelper.destroy(allocator, &ctx_slot);
                    try StreamContextPolyHelper.create(allocator, &ctx_slot);
                    const sc: *StreamContext = StreamContextPolyHelper.cast(ctx_slot.?).?;
                    sc.camera_id = vb.camera_id;
                    sc.frame_id = vb.frame_id;
                    sc.buffer_slot = buf_slot;
                    buf_slot = null; // ownership transferred to StreamContext

                    // Send StreamContext to ready queue. Worker gets exclusive ownership.
                    errdefer pool.put(buf_ph, &sc.buffer_slot);
                    try mailbox.send(ready_queue, &ctx_slot);

                    sent += 1;
                    camera_idx = (camera_idx + 1) % N_CAMERAS;

                    if (sent < total) {
                        try sel.concurrent(.buf_ev, pool.getWaitResult, .{ buf_ph, VideoBufferPolyHelper.TAG, null });
                    }
                },
                .closed, .canceled, .timeout, .not_created => break,
            },
        }
    }

    sel.cancelDiscard();
    std.log.info("network: all {d} frames sent", .{total});

    // Close ready queue; walk and free any StreamContexts not yet received by workers.
    var rem: std.DoublyLinkedList = mailbox.close(ready_queue);
    while (rem.popFirst()) |node| {
        const poly: *polynode.PolyNode = @fieldParentPtr("node", node);
        polynode.reset(poly);
        const sc: *StreamContext = StreamContextPolyHelper.cast(poly).?;
        pool.put(buf_ph, &sc.buffer_slot);
        if (sc.buffer_slot != null) {
            VideoBufferPolyHelper.destroy(allocator, &sc.buffer_slot);
        }
        var sc_slot: Slot = poly;
        StreamContextPolyHelper.destroy(allocator, &sc_slot);
    }

    // Wait for all workers to finish current frames.
    try group.await(io);
    mailbox.destroy(ready_queue, allocator);
    std.log.info("workers: all done", .{});

    // Close storage mailbox — signals storage task to exit via error.Closed.
    {
        var srem: std.DoublyLinkedList = mailbox.close(storage_mbh);
        while (srem.popFirst()) |node| {
            const poly: *polynode.PolyNode = @fieldParentPtr("node", node);
            polynode.reset(poly);
            var s: Slot = poly;
            EncodedSegmentPolyHelper.destroy(allocator, &s);
        }
    }
    storage_fut.await(io) catch {};
    mailbox.destroy(storage_mbh, allocator);
    std.log.info("storage: done", .{});

    try helpers.expect(
        error.VideoTranscoderFailed,
        sent == total,
        "not all frames were sent",
    );
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
