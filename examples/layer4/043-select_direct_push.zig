// SPDX-FileCopyrightText: Copyright (c) 2026 g41797
// SPDX-License-Identifier: MIT

// Ownership:
//
//  wild thread ──sel.queue.putOneUncancelable──► Select queue
//               (bypasses concurrent fn mechanism)
//  │
//  sel.await() ──► .direct u32 value
//  │
//  sel.cancelDiscard() ──► cancels blocking .inbox source

const MasterEvent = union(enum) {
    inbox: mailbox.ReceiveResult,
    direct: u32,
};

fn pusherFn(sel_ptr: *std.Io.Select(MasterEvent)) void {
    sel_ptr.queue.putOneUncancelable(sel_ptr.io, .{ .direct = 99 }) catch {};
}

fn setupSourcesAndPusher(mbh: MailboxHandle, io: std.Io, sel: *std.Io.Select(MasterEvent)) !std.Io.Future(void) {
    try sel.concurrent(.inbox, mailbox.receiveResult, .{ mbh, null });
    return io.concurrent(pusherFn, .{sel});
}

fn awaitDirectPushAndShutdown(sel: *std.Io.Select(MasterEvent), pusher_fut: *std.Io.Future(void), io: std.Io) !void {
    const event: MasterEvent = try sel.await();
    switch (event) {
        .direct => |v| {
            try helpers.expect(error.SelectDirectPushFailed, v == 99, "wrong direct push value");
            std.log.info("direct push: received {d}", .{v});
        },
        .inbox => return error.SelectDirectPushFailed,
    }
    pusher_fut.await(io);
    sel.cancelDiscard();
}

pub fn run(allocator: std.mem.Allocator, io: std.Io) !void {
    const mbh: MailboxHandle = try mailbox.new(io, allocator);
    defer {
        var rem: std.DoublyLinkedList = mailbox.close(mbh);
        helpers.freeList(&rem, allocator);
        mailbox.destroy(mbh, allocator);
    }

    var buf: [4]MasterEvent = undefined;
    var sel: std.Io.Select(MasterEvent) = std.Io.Select(MasterEvent).init(io, &buf);
    var pusher_fut = try setupSourcesAndPusher(mbh, io, &sel);
    try awaitDirectPushAndShutdown(&sel, &pusher_fut, io);
    std.log.info("done: direct push bypassed concurrent fn path", .{});
}

const helpers = @import("helpers");
const matryoshka = @import("matryoshka");
const std = @import("std");
const mailbox = matryoshka.mailbox;
const polynode = matryoshka.polynode;
const Slot = polynode.Slot;
const MailboxHandle = mailbox.MailboxHandle;
const types = helpers.types;
