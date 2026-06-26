// SPDX-FileCopyrightText: Copyright (c) 2026 g41797
// SPDX-License-Identifier: MIT

pub const PolyTag = struct { _: u8 = 0 };

pub const PolyNode = struct {
    node: std.DoublyLinkedList.Node = .{},
    tag: *const anyopaque = undefined,
};

pub const NodeHandle = *PolyNode;
pub const Slot = ?NodeHandle;

pub inline fn reset(n: *PolyNode) void {
    n.*.node.prev = null;
    n.*.node.next = null;
}

pub inline fn is_linked(n: *PolyNode) bool {
    return n.*.node.prev != null or n.*.node.next != null;
}

pub fn PolyHelper(comptime T: type) type {
    comptime validatePolyType(T);
    return struct {
        var _tag: PolyTag = .{};
        pub const TAG: *const anyopaque = &_tag;

        pub inline fn isIt(tag: *const anyopaque) bool {
            return tag == TAG;
        }

        pub inline fn cast(node: *PolyNode) ?*T {
            if (node.*.tag != TAG) return null;
            return @fieldParentPtr("poly", node);
        }

        pub fn init(self: *T) void {
            self.*.poly = .{ .node = .{}, .tag = TAG };
        }
    };
}

fn validatePolyType(comptime T: type) void {
    if (!@hasField(T, "poly"))
        @compileError(@typeName(T) ++ ": must have field 'poly: PolyNode'");
    if (@FieldType(T, "poly") != PolyNode)
        @compileError(@typeName(T) ++ ": field 'poly' must be PolyNode");
}

const std = @import("std");
const Node = std.DoublyLinkedList.Node;
