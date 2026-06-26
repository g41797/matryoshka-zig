// SPDX-FileCopyrightText: Copyright (c) 2026 g41797
// SPDX-License-Identifier: MIT

pub fn run(allocator: std.mem.Allocator, io: std.Io) !void {
    const mbh: MailboxHandle = try mailbox.new(io, allocator);
    defer {
        var rem: std.DoublyLinkedList = mailbox.close(mbh);
        helpers.freeList(&rem, allocator);
        mailbox.destroy(mbh, allocator);
    }

    // Send 3 regular Event items.
    for (0..3) |i| {
        const ev: *types.Event = try allocator.create(types.Event);
        errdefer allocator.destroy(ev);
        ev.* = .{ .code = @intCast(i + 1) };
        types.EventPolyHelper.init(ev);
        var slot: Slot = &ev.poly;
        try mailbox.send(mbh, &slot);
    }

    // Send 1 OOB item (ShutdownCommand) — goes to front of queue.
    const cmd: *types.ShutdownCommand = try allocator.create(types.ShutdownCommand);
    errdefer allocator.destroy(cmd);
    cmd.* = .{};
    types.ShutdownCommandPolyHelper.init(cmd);
    var oob_slot: Slot = &cmd.poly;
    try mailbox.send_oob(mbh, &oob_slot);

    std.log.info("sent 3 Events (regular) + 1 ShutdownCommand (OOB)", .{});

    // Receive 4 items: OOB comes first, then regular items in order.
    var shutdown_seen: bool = false;
    var event_count: usize = 0;

    for (0..4) |_| {
        var slot: Slot = null;
        try mailbox.receive(mbh, &slot, null);
        const poly: *PolyNode = slot.?;

        if (types.ShutdownCommandPolyHelper.cast(poly)) |sc| {
            try helpers.expect(error.OobOrderFailed, !shutdown_seen, "OOB ShutdownCommand must arrive before any Event");
            try helpers.expect(error.OobOrderFailed, event_count == 0, "OOB must be first item received");
            shutdown_seen = true;
            std.log.info("received OOB ShutdownCommand (first, as expected)", .{});
            allocator.destroy(sc);
        } else if (types.EventPolyHelper.cast(poly)) |ev| {
            try helpers.expect(error.OobOrderFailed, shutdown_seen, "Events must arrive after the OOB item");
            event_count += 1;
            std.log.info("received Event code={d} (event {d}/3)", .{ ev.code, event_count });
            allocator.destroy(ev);
        } else {
            return error.OobOrderFailed;
        }
    }

    try helpers.expect(error.OobOrderFailed, shutdown_seen, "OOB item not received");
    try helpers.expect(error.OobOrderFailed, event_count == 3, "expected 3 Events");

    std.log.info("OOB ordering verified: shutdown came first, then {d} events", .{event_count});
}

const std = @import("std");
const helpers = @import("helpers");
const matryoshka = @import("matryoshka");
const mailbox = matryoshka.mailbox;
const polynode = matryoshka.polynode;
const PolyNode = polynode.PolyNode;
const Slot = polynode.Slot;
const MailboxHandle = mailbox.MailboxHandle;
const types = helpers.types;
