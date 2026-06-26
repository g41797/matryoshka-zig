const WorkerCtx = struct {
    req_mbh: MailboxHandle,
    resp_mbh: MailboxHandle,
    alloc: std.mem.Allocator,
};

fn workerFn(ctx: *WorkerCtx) void {
    while (true) {
        var out: Slot = null;
        mailbox.receive(ctx.req_mbh, &out, null) catch return;
        const ev: *types.Event = types.EventPolyHelper.cast(out.?) orelse {
            helpers.freeItem(out.?, ctx.alloc);
            continue;
        };
        std.log.debug("worker: request code={d}", .{ev.code});
        ev.code += 1000;
        var slot: Slot = &ev.poly;
        mailbox.send(ctx.resp_mbh, &slot) catch {
            ctx.alloc.destroy(ev);
        };
    }
}

pub fn run(allocator: std.mem.Allocator, io: std.Io) !void {
    const req_mbh: MailboxHandle = try mailbox.new(io, allocator);
    defer mailbox.destroy(req_mbh, allocator);

    const resp_mbh: MailboxHandle = try mailbox.new(io, allocator);
    defer mailbox.destroy(resp_mbh, allocator);

    var ctx: WorkerCtx = .{ .req_mbh = req_mbh, .resp_mbh = resp_mbh, .alloc = allocator };
    const t = try std.Thread.spawn(.{}, workerFn, .{&ctx});

    const req: *types.Event = try allocator.create(types.Event);
    req.* = .{ .code = 42 };
    types.EventPolyHelper.init(req);
    var slot: Slot = &req.poly;
    try mailbox.send(req_mbh, &slot);

    var out: Slot = null;
    try mailbox.receive(resp_mbh, &out, 5_000_000_000);
    const resp: *types.Event = types.EventPolyHelper.cast(out.?) orelse return error.WrongTag;
    std.log.info("request_response: response code={d}", .{resp.code});
    try helpers.expect(error.RequestResponseFailed, resp.code == 1042, "wrong response code");
    allocator.destroy(resp);

    var rem_req: std.DoublyLinkedList = mailbox.close(req_mbh);
    helpers.freeList(&rem_req, allocator);
    t.join();

    var rem_resp: std.DoublyLinkedList = mailbox.close(resp_mbh);
    helpers.freeList(&rem_resp, allocator);
}

const std = @import("std");
const helpers = @import("helpers");
const matryoshka = @import("matryoshka");
const polynode = matryoshka.polynode;
const mailbox = matryoshka.mailbox;
const Slot = polynode.Slot;
const MailboxHandle = mailbox.MailboxHandle;
const types = helpers.types;
