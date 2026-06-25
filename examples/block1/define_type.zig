pub const Message = struct {
    poly: polynode.PolyNode = .{},
    text: []const u8 = "",
    priority: u8 = 0,
};

pub const MessagePolyHelper = polynode.PolyHelper(Message);

pub fn run(allocator: std.mem.Allocator, io: std.Io) !void {
    _ = .{ allocator, io };

    var msg: Message = .{ .text = "hello", .priority = 1 };
    MessagePolyHelper.init(&msg);

    try helpers.expect(error.DefineTypeFailed, MessagePolyHelper.isIt(msg.poly.tag), "expected Message tag");
    try helpers.expect(error.DefineTypeFailed, !types.EventPolyHelper.isIt(msg.poly.tag), "unexpected Event tag");

    const poly: *polynode.PolyNode = &msg.poly;
    const recovered: *Message = MessagePolyHelper.cast(poly) orelse return error.CastFailed;
    try helpers.expect(error.DefineTypeFailed, std.mem.eql(u8, "hello", recovered.*.text), "wrong text");
    try helpers.expect(error.DefineTypeFailed, recovered.*.priority == 1, "wrong priority");
}

const std = @import("std");
const helpers = @import("helpers");
const polynode = @import("matryoshka").polynode;
const types = helpers.types;
