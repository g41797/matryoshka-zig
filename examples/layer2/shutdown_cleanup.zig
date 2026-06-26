// SPDX-FileCopyrightText: Copyright (c) 2026 g41797
// SPDX-License-Identifier: MIT

pub fn run(allocator: std.mem.Allocator, io: std.Io) !void {
    const mbh: MailboxHandle = try mailbox.new(io, allocator);
    defer mailbox.destroy(mbh, allocator);

    const n_events: usize = 5;
    const n_sensors: usize = 3;

    var i: usize = 0;
    while (i < n_events) : (i += 1) {
        const ev: *types.Event = try allocator.create(types.Event);
        ev.* = .{ .code = @intCast(i) };
        types.EventPolyHelper.init(ev);
        var slot: Slot = &ev.poly;
        try mailbox.send(mbh, &slot);
    }

    i = 0;
    while (i < n_sensors) : (i += 1) {
        const sn: *types.Sensor = try allocator.create(types.Sensor);
        sn.* = .{ .value = @as(f64, @floatFromInt(i)) * 1.1 };
        types.SensorPolyHelper.init(sn);
        var slot: Slot = &sn.poly;
        try mailbox.send(mbh, &slot);
    }

    // Close without receiving — all items come back in the returned list.
    var remaining: std.DoublyLinkedList = mailbox.close(mbh);
    var freed: usize = 0;
    while (remaining.popFirst()) |node| {
        helpers.freeItem(@fieldParentPtr("node", node), allocator);
        freed += 1;
    }

    std.log.info("shutdown cleanup: freed {d} items", .{freed});
    try helpers.expect(error.ShutdownCleanupFailed, freed == n_events + n_sensors, "wrong freed count");
}

const std = @import("std");
const helpers = @import("helpers");
const matryoshka = @import("matryoshka");
const polynode = matryoshka.polynode;
const mailbox = matryoshka.mailbox;
const Slot = polynode.Slot;
const MailboxHandle = mailbox.MailboxHandle;
const types = helpers.types;
