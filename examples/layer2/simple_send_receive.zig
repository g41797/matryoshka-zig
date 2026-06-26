pub fn run(allocator: std.mem.Allocator, io: std.Io) !void {
    const mbh: MailboxHandle = try mailbox.new(io, allocator);
    defer {
        var rem: std.DoublyLinkedList = mailbox.close(mbh);
        helpers.freeList(&rem, allocator);
        mailbox.destroy(mbh, allocator);
    }

    const ev: *types.Event = try allocator.create(types.Event);
    ev.* = .{ .code = 53 };
    types.EventPolyHelper.init(ev);
    var slot: Slot = &ev.poly;
    try mailbox.send(mbh, &slot);

    const sn: *types.Sensor = try allocator.create(types.Sensor);
    sn.* = .{ .value = 5.3 };
    types.SensorPolyHelper.init(sn);
    slot = &sn.poly;
    try mailbox.send(mbh, &slot);

    var out: Slot = null;

    try mailbox.receive(mbh, &out, 1_000_000_000);
    const ev_recv: *types.Event = types.EventPolyHelper.cast(out.?) orelse return error.WrongTag;
    try helpers.expect(error.SimpleSendReceiveFailed, ev_recv.code == 53, "wrong event code");
    std.log.info("received Event code={d}", .{ev_recv.code});
    allocator.destroy(ev_recv);

    out = null;
    try mailbox.receive(mbh, &out, 1_000_000_000);
    const sn_recv: *types.Sensor = types.SensorPolyHelper.cast(out.?) orelse return error.WrongTag;
    try helpers.expect(error.SimpleSendReceiveFailed, sn_recv.value == 5.3, "wrong sensor value");
    std.log.info("received Sensor value={d:.1}", .{sn_recv.value});
    allocator.destroy(sn_recv);
}

const std = @import("std");
const helpers = @import("helpers");
const matryoshka = @import("matryoshka");
const polynode = matryoshka.polynode;
const mailbox = matryoshka.mailbox;
const Slot = polynode.Slot;
const MailboxHandle = mailbox.MailboxHandle;
const types = helpers.types;
