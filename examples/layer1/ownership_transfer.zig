// SPDX-FileCopyrightText: Copyright (c) 2026 g41797
// SPDX-License-Identifier: MIT

pub fn run(allocator: std.mem.Allocator, io: std.Io) !void {
    _ = io;

    var slot: Slot = null;
    defer types.EventPolyHelper.destroy(allocator, &slot);
    try types.EventPolyHelper.create(allocator, &slot);
    const ev: *types.Event = types.EventPolyHelper.cast(slot.?).?;
    ev.*.code = 42;
    try helpers.expect(error.OwnershipTransferFailed, slot != null, "slot should be non-null after create");

    // Transfer to list — clear slot to signal transfer.
    var list: std.DoublyLinkedList = .{};
    list.append(&slot.?.node);
    slot = null;
    try helpers.expect(error.OwnershipTransferFailed, slot == null, "slot should be null after transfer");

    // Recover from list — assign back to slot.
    const node: *std.DoublyLinkedList.Node = list.popFirst() orelse return error.EmptyList;
    slot = @fieldParentPtr("node", node);
    try helpers.expect(error.OwnershipTransferFailed, slot != null, "slot should be non-null after recovery");

    const recovered: *types.Event = types.EventPolyHelper.cast(slot.?).?;
    try helpers.expect(error.OwnershipTransferFailed, recovered.*.code == 42, "wrong event code");

    helpers.freeSlot(&slot, allocator);
    try helpers.expect(error.OwnershipTransferFailed, slot == null, "slot should be null after destroy");
    // defer runs as no-op
}

const helpers = @import("helpers");
const polynode = @import("matryoshka").polynode;
const std = @import("std");
const Slot = polynode.Slot;
const types = helpers.types;
