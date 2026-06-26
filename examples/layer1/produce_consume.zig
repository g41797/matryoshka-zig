// SPDX-FileCopyrightText: Copyright (c) 2026 g41797
// SPDX-License-Identifier: MIT

pub fn run(allocator: std.mem.Allocator, io: std.Io) !void {
    _ = io;
    var list: std.DoublyLinkedList = .{};

    defer freeRemaining(&list, allocator);

    var i: i32 = 0;
    while (i < 5) : (i += 1) {
        const ev: *types.Event = try allocator.create(types.Event);
        ev.* = .{ .code = i };
        types.EventPolyHelper.init(ev);
        list.append(&ev.*.poly.node);
    }

    var sum: i32 = 0;
    while (list.popFirst()) |node| {
        const poly: *polynode.PolyNode = @fieldParentPtr("node", node);
        const ev: *types.Event = types.EventPolyHelper.cast(poly) orelse return error.CastFailed;
        sum += ev.*.code;
        allocator.destroy(ev);
    }

    try helpers.expect(error.ProduceConsumeFailed, sum == 0 + 1 + 2 + 3 + 4, "wrong sum");
}

fn freeRemaining(list: *std.DoublyLinkedList, alloc: std.mem.Allocator) void {
    while (list.popFirst()) |node| {
        const poly: *polynode.PolyNode = @fieldParentPtr("node", node);
        if (types.EventPolyHelper.cast(poly)) |ev| {
            alloc.destroy(ev);
        }
    }
}

const std = @import("std");
const helpers = @import("helpers");
const polynode = @import("matryoshka").polynode;
const types = helpers.types;
