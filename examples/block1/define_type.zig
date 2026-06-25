pub const Message = struct {
    poly: polynode.PolyNode = .{},
    text: []const u8 = "",
    priority: u8 = 0,
};

pub const MessagePolyHelper = polynode.PolyHelper(Message);

pub fn run() !void {
    var msg: Message = .{ .text = "hello", .priority = 1 };
    MessagePolyHelper.init(&msg);

    try testing.expect(MessagePolyHelper.isIt(msg.poly.tag));
    try testing.expect(!types.EventPolyHelper.isIt(msg.poly.tag));

    const poly: *polynode.PolyNode = &msg.poly;
    const recovered: *Message = MessagePolyHelper.cast(poly) orelse return error.CastFailed;
    try testing.expectEqualStrings("hello", recovered.*.text);
    try testing.expectEqual(@as(u8, 1), recovered.*.priority);
}

const std = @import("std");
const testing = std.testing;
const polynode = @import("matryoshka").polynode;
const types = @import("helpers").types;
