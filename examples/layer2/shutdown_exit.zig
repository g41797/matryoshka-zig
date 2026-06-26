pub const ShutdownCommand = struct {
    poly: polynode.PolyNode = .{},
};
pub const ShutdownCommandPolyHelper = polynode.PolyHelper(ShutdownCommand);

const WorkerCtx = struct {
    mbh: MailboxHandle,
    alloc: std.mem.Allocator,
    processed: usize = 0,
};

fn workerFn(ctx: *WorkerCtx) void {
    while (true) {
        var out: Slot = null;
        mailbox.receive(ctx.mbh, &out, null) catch return;
        const poly: *PolyNode = out.?;
        if (ShutdownCommandPolyHelper.cast(poly)) |cmd| {
            std.log.info("worker: ShutdownCommand received, exiting cleanly", .{});
            ctx.alloc.destroy(cmd);
            return;
        } else if (types.EventPolyHelper.cast(poly)) |ev| {
            std.log.debug("worker: Event code={d}", .{ev.code});
            ctx.processed += 1;
            ctx.alloc.destroy(ev);
        } else if (types.SensorPolyHelper.cast(poly)) |sn| {
            std.log.debug("worker: Sensor value={d:.1}", .{sn.value});
            ctx.processed += 1;
            ctx.alloc.destroy(sn);
        }
    }
}

pub fn run(allocator: std.mem.Allocator, io: std.Io) !void {
    const mbh: MailboxHandle = try mailbox.new(io, allocator);

    defer {
        var rem: std.DoublyLinkedList = mailbox.close(mbh);
        helpers.freeList(&rem, allocator);
        mailbox.destroy(mbh, allocator);
    }

    var ctx: WorkerCtx = .{ .mbh = mbh, .alloc = allocator };
    const t = try std.Thread.spawn(.{}, workerFn, .{&ctx});

    const codes = [_]i32{ 10, 20, 30 };
    for (codes) |code| {
        const ev: *types.Event = try allocator.create(types.Event);
        ev.* = .{ .code = code };
        types.EventPolyHelper.init(ev);
        var slot: Slot = &ev.poly;
        try mailbox.send(mbh, &slot);
    }

    // Send shutdown signal — mailbox stays open.
    const cmd: *ShutdownCommand = try allocator.create(ShutdownCommand);
    cmd.* = .{};
    ShutdownCommandPolyHelper.init(cmd);
    var cmd_slot: Slot = &cmd.poly;
    try mailbox.send(mbh, &cmd_slot);

    t.join();

    std.log.info("shutdown_exit: worker processed {d} items before ShutdownCommand", .{ctx.processed});
    try helpers.expect(error.ShutdownExitFailed, ctx.processed == 3, "wrong processed count");
}

const std = @import("std");

const helpers = @import("helpers");
const types = helpers.types;
const matryoshka = @import("matryoshka");
const polynode = matryoshka.polynode;
const mailbox = matryoshka.mailbox;
const PolyNode = polynode.PolyNode;
const Slot = polynode.Slot;
const MailboxHandle = mailbox.MailboxHandle;

