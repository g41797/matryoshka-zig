// SPDX-FileCopyrightText: Copyright (c) 2026 g41797
// SPDX-License-Identifier: MIT

// Ownership:
//
//  EventPolyHelper.create ──► slot ──► mailbox.send ──► mailbox
//  SensorPolyHelper.create ──► slot ──► mailbox.send ──► mailbox
//  │
//  mailbox.receive ──► slot (Event or Sensor)
//    dispatch on poly.tag:
//    == EventPolyHelper.TAG  ──► cast to *Event  ──► verify code==10 ──► freeSlot
//    == SensorPolyHelper.TAG ──► cast to *Sensor ──► verify value==3.14 ──► freeSlot
//  │
//  mailbox.close ──► freeList (empty: all received)

pub fn run(allocator: std.mem.Allocator, io: std.Io) !void {
    const mbh: MailboxHandle = try mailbox.new(io, allocator);
    defer {
        var rem: std.DoublyLinkedList = mailbox.close(mbh);
        helpers.freeList(&rem, allocator);
        mailbox.destroy(mbh, allocator);
    }

    // Send Event (code=10).
    {
        var slot: Slot = null;
        defer types.EventPolyHelper.destroy(allocator, &slot);
        try types.EventPolyHelper.create(allocator, &slot);
        types.EventPolyHelper.cast(slot.?).?.code = 10;
        std.log.info("send: Event code={d}", .{10});
        try mailbox.send(mbh, &slot);
    }

    // Send Sensor (value=3.14).
    {
        var slot: Slot = null;
        defer types.SensorPolyHelper.destroy(allocator, &slot);
        try types.SensorPolyHelper.create(allocator, &slot);
        types.SensorPolyHelper.cast(slot.?).?.value = 3.14;
        std.log.info("send: Sensor value={d}", .{3.14});
        try mailbox.send(mbh, &slot);
    }

    // Receive both items; dispatch on tag.
    var event_ok: bool = false;
    var sensor_ok: bool = false;

    for (0..2) |_| {
        var slot: Slot = null;
        try mailbox.receive(mbh, &slot, null);
        defer helpers.freeSlot(&slot, allocator);
        const poly: *polynode.PolyNode = slot.?;
        if (types.EventPolyHelper.cast(poly)) |ev| {
            try helpers.expect(error.CrossLayerMixedTypesFailed, ev.code == 10, "wrong Event code");
            std.log.info("received: Event code={d}", .{ev.code});
            event_ok = true;
        } else if (types.SensorPolyHelper.cast(poly)) |sn| {
            try helpers.expect(error.CrossLayerMixedTypesFailed, sn.value == 3.14, "wrong Sensor value");
            std.log.info("received: Sensor value={d}", .{sn.value});
            sensor_ok = true;
        } else {
            return error.CrossLayerMixedTypesFailed;
        }
    }

    try helpers.expect(error.CrossLayerMixedTypesFailed, event_ok, "Event not received");
    try helpers.expect(error.CrossLayerMixedTypesFailed, sensor_ok, "Sensor not received");
    std.log.info("done: Event + Sensor through shared mailbox, dispatched on tag", .{});
}

const helpers = @import("helpers");
const matryoshka = @import("matryoshka");
const std = @import("std");
const mailbox = matryoshka.mailbox;
const polynode = matryoshka.polynode;
const Slot = polynode.Slot;
const MailboxHandle = mailbox.MailboxHandle;
const types = helpers.types;
