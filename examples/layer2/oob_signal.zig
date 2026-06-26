// SPDX-FileCopyrightText: Copyright (c) 2026 g41797
// SPDX-License-Identifier: MIT

pub fn run(allocator: std.mem.Allocator, io: std.Io) !void {
    const mbh: MailboxHandle = try mailbox.new(io, allocator);
    defer {
        var rem: std.DoublyLinkedList = mailbox.close(mbh);
        helpers.freeList(&rem, allocator);
        mailbox.destroy(mbh, allocator);
    }

    // Fill queue with 3 normal Events.
    const codes = [_]i32{ 1, 2, 3 };
    for (codes) |code| {
        const ev: *types.Event = try allocator.create(types.Event);
        ev.* = .{ .code = code };
        types.EventPolyHelper.init(ev);
        var slot: Slot = &ev.poly;
        try mailbox.send(mbh, &slot);
    }
    // Queue: [ev1, ev2, ev3]

    // OOB Sensor jumps to front.
    const sn: *types.Sensor = try allocator.create(types.Sensor);
    sn.* = .{ .value = -1.0 };
    types.SensorPolyHelper.init(sn);
    var oob_slot: Slot = &sn.poly;
    try mailbox.send_oob(mbh, &oob_slot);
    // Queue: [sn, ev1, ev2, ev3]

    // Receive all 4 — OOB Sensor arrives first.
    var received_oob: bool = false;
    var event_count: usize = 0;
    var i: usize = 0;
    while (i < 4) : (i += 1) {
        var out: Slot = null;
        try mailbox.receive(mbh, &out, 1_000_000_000);
        const poly: *PolyNode = out.?;
        if (types.SensorPolyHelper.cast(poly)) |oob_sn| {
            std.log.info("OOB signal value={d:.1}", .{oob_sn.value});
            try helpers.expect(error.OobSignalFailed, !received_oob, "duplicate OOB");
            try helpers.expect(error.OobSignalFailed, event_count == 0, "OOB did not arrive first");
            received_oob = true;
            allocator.destroy(oob_sn);
        } else if (types.EventPolyHelper.cast(poly)) |ev| {
            std.log.info("event code={d}", .{ev.code});
            event_count += 1;
            allocator.destroy(ev);
        }
    }

    try helpers.expect(error.OobSignalFailed, received_oob, "OOB not received");
    try helpers.expect(error.OobSignalFailed, event_count == 3, "wrong event count");
}

const std = @import("std");
const helpers = @import("helpers");
const matryoshka = @import("matryoshka");
const polynode = matryoshka.polynode;
const mailbox = matryoshka.mailbox;
const PolyNode = polynode.PolyNode;
const Slot = polynode.Slot;
const MailboxHandle = mailbox.MailboxHandle;
const types = helpers.types;
