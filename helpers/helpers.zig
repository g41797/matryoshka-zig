pub const types = @import("types.zig");

pub fn expect(comptime err: anyerror, ok: bool, comptime msg: []const u8) anyerror!void {
    if (!ok) {
        log.err("{s}", .{msg});
        return err;
    }
}

pub fn clearList(list: *std.DoublyLinkedList) void {
    while (list.popFirst()) |_| {}
}

const std = @import("std");
const log = std.log;
