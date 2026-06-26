// SPDX-FileCopyrightText: Copyright (c) 2026 g41797
// SPDX-License-Identifier: MIT

pub fn run(allocator: std.mem.Allocator, io: std.Io) !void {
    _ = io;

    const ev: *types.Event = try allocator.create(types.Event);
    errdefer allocator.destroy(ev);
    ev.* = .{ .code = 42 };
    types.EventPolyHelper.init(ev);

    var slot: polynode.Slot = &ev.*.poly;
    try helpers.expect(error.OwnershipTransferFailed, slot != null, "slot should be non-null after init");

    var list: std.DoublyLinkedList = .{};
    list.append(&ev.*.poly.node);
    slot = null;
    try helpers.expect(error.OwnershipTransferFailed, slot == null, "slot should be null after transfer");

    const node: *std.DoublyLinkedList.Node = list.popFirst() orelse return error.EmptyList;
    const poly: *polynode.PolyNode = @fieldParentPtr("node", node);
    slot = poly;
    try helpers.expect(error.OwnershipTransferFailed, slot != null, "slot should be non-null after recovery");

    const recovered: *types.Event = types.EventPolyHelper.cast(poly) orelse return error.CastFailed;
    try helpers.expect(error.OwnershipTransferFailed, recovered.*.code == 42, "wrong event code");

    allocator.destroy(recovered);
    slot = null;
    try helpers.expect(error.OwnershipTransferFailed, slot == null, "slot should be null after destroy");
}

const std = @import("std");
const helpers = @import("helpers");
const polynode = @import("matryoshka").polynode;
const types = helpers.types;
