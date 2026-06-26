const SenderCtx = struct {
    mbh: MailboxHandle,
    alloc: std.mem.Allocator,
    sent: usize = 0,
};

fn eventSenderFn(ctx: *SenderCtx) void {
    var i: i32 = 0;
    while (i < 5) : (i += 1) {
        const ev: *types.Event = ctx.alloc.create(types.Event) catch return;
        ev.* = .{ .code = i };
        types.EventPolyHelper.init(ev);
        var slot: Slot = &ev.poly;
        mailbox.send(ctx.mbh, &slot) catch {
            ctx.alloc.destroy(ev);
            return;
        };
        ctx.sent += 1;
    }
}

fn sensorSenderFn(ctx: *SenderCtx) void {
    var i: usize = 0;
    while (i < 5) : (i += 1) {
        const sn: *types.Sensor = ctx.alloc.create(types.Sensor) catch return;
        sn.* = .{ .value = @as(f64, @floatFromInt(i)) * 0.1 };
        types.SensorPolyHelper.init(sn);
        var slot: Slot = &sn.poly;
        mailbox.send(ctx.mbh, &slot) catch {
            ctx.alloc.destroy(sn);
            return;
        };
        ctx.sent += 1;
    }
}

fn altSenderFn(ctx: *SenderCtx) void {
    var i: i32 = 0;
    while (i < 4) : (i += 1) {
        if (@rem(i, 2) == 0) {
            const ev: *types.Event = ctx.alloc.create(types.Event) catch return;
            ev.* = .{ .code = 100 + i };
            types.EventPolyHelper.init(ev);
            var slot: Slot = &ev.poly;
            mailbox.send(ctx.mbh, &slot) catch {
                ctx.alloc.destroy(ev);
                return;
            };
        } else {
            const sn: *types.Sensor = ctx.alloc.create(types.Sensor) catch return;
            sn.* = .{ .value = @as(f64, @floatFromInt(i)) };
            types.SensorPolyHelper.init(sn);
            var slot: Slot = &sn.poly;
            mailbox.send(ctx.mbh, &slot) catch {
                ctx.alloc.destroy(sn);
                return;
            };
        }
        ctx.sent += 1;
    }
}

pub fn run(allocator: std.mem.Allocator, io: std.Io) !void {
    const mbh: MailboxHandle = try mailbox.new(io, allocator);
    defer mailbox.destroy(mbh, allocator);

    var ctx_ev: SenderCtx = .{ .mbh = mbh, .alloc = allocator };
    var ctx_sn: SenderCtx = .{ .mbh = mbh, .alloc = allocator };
    var ctx_alt: SenderCtx = .{ .mbh = mbh, .alloc = allocator };

    const t1 = try std.Thread.spawn(.{}, eventSenderFn, .{&ctx_ev});
    const t2 = try std.Thread.spawn(.{}, sensorSenderFn, .{&ctx_sn});
    const t3 = try std.Thread.spawn(.{}, altSenderFn, .{&ctx_alt});

    t1.join();
    t2.join();
    t3.join();

    // All senders done. Batch-receive everything at once.
    const total_sent: usize = ctx_ev.sent + ctx_sn.sent + ctx_alt.sent;
    var batch: std.DoublyLinkedList = try mailbox.receive_batch(mbh);
    var events_received: usize = 0;
    var sensors_received: usize = 0;

    while (batch.popFirst()) |node| {
        const poly: *PolyNode = @fieldParentPtr("node", node);
        if (types.EventPolyHelper.cast(poly)) |ev| {
            events_received += 1;
            allocator.destroy(ev);
        } else if (types.SensorPolyHelper.cast(poly)) |sn| {
            sensors_received += 1;
            allocator.destroy(sn);
        }
    }

    var rem: std.DoublyLinkedList = mailbox.close(mbh);
    helpers.freeList(&rem, allocator);

    std.log.info("fan-in: sent={d} events={d} sensors={d}", .{ total_sent, events_received, sensors_received });
    try helpers.expect(error.FanInFailed, events_received + sensors_received == total_sent, "wrong total");
}

const std = @import("std");
const helpers = @import("helpers");
const matryoshka = @import("matryoshka");
const polynode = matryoshka.polynode;
const mailbox = matryoshka.mailbox;
const PolyNode = polynode.PolyNode;
const Slot = polynode.Slot;
const MailboxHandle = mailbox.MailboxHandle;
const types = helpers.types;
