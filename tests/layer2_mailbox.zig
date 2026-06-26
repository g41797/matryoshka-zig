// --- Scenario 26: mailbox.new and mailbox.destroy ---
test "26 - mailbox new and destroy" {
    const io: Io = testing.io;
    const alloc: std.mem.Allocator = testing.allocator;

    const mbh: MailboxHandle = try mailbox.new(io, alloc);
    try testing.expect(mailbox.is_it_you(mbh.*.tag));

    const remaining: std.DoublyLinkedList = mailbox.close(mbh);
    try testing.expect(remaining.first == null);
    mailbox.destroy(mbh, alloc);
}

// --- Scenario 27: Send and receive single item ---
test "27 - send and receive single item" {
    const io: Io = testing.io;
    const alloc: std.mem.Allocator = testing.allocator;

    const mbh: MailboxHandle = try mailbox.new(io, alloc);
    defer {
        var rem: std.DoublyLinkedList = mailbox.close(mbh);
        helpers.clearList(&rem);
        mailbox.destroy(mbh, alloc);
    }

    var ev: Event = .{ .code = 27 };
    EventPolyHelper.init(&ev);
    var slot: Slot = &ev.poly;

    try mailbox.send(mbh, &slot);
    try testing.expectEqual(@as(Slot, null), slot);

    var out: Slot = null;
    try mailbox.receive(mbh, &out, 1_000_000_000);
    try testing.expect(out != null);

    const poly: *PolyNode = out.?;
    const recovered: *Event = EventPolyHelper.cast(poly) orelse return error.WrongTag;
    try testing.expectEqual(@as(i32, 27), recovered.*.code);
}

// --- Scenario 28: FIFO ordering ---
test "28 - fifo ordering" {
    const io: Io = testing.io;
    const alloc: std.mem.Allocator = testing.allocator;

    const mbh: MailboxHandle = try mailbox.new(io, alloc);
    defer {
        var rem: std.DoublyLinkedList = mailbox.close(mbh);
        helpers.clearList(&rem);
        mailbox.destroy(mbh, alloc);
    }

    var ev1: Event = .{ .code = 1 };
    var ev2: Event = .{ .code = 2 };
    var ev3: Event = .{ .code = 3 };
    EventPolyHelper.init(&ev1);
    EventPolyHelper.init(&ev2);
    EventPolyHelper.init(&ev3);

    var s1: Slot = &ev1.poly;
    var s2: Slot = &ev2.poly;
    var s3: Slot = &ev3.poly;
    try mailbox.send(mbh, &s1);
    try mailbox.send(mbh, &s2);
    try mailbox.send(mbh, &s3);

    for ([_]i32{ 1, 2, 3 }) |expected| {
        var out: Slot = null;
        try mailbox.receive(mbh, &out, 1_000_000_000);
        const poly: *PolyNode = out.?;
        const ev: *Event = EventPolyHelper.cast(poly) orelse return error.WrongTag;
        try testing.expectEqual(expected, ev.*.code);
    }
}

// --- Scenario 29: Send to closed mailbox returns error.Closed ---
test "29 - send to closed mailbox" {
    const io: Io = testing.io;
    const alloc: std.mem.Allocator = testing.allocator;

    const mbh: MailboxHandle = try mailbox.new(io, alloc);
    var remaining: std.DoublyLinkedList = mailbox.close(mbh);
    helpers.clearList(&remaining);
    defer mailbox.destroy(mbh, alloc);

    var ev: Event = .{ .code = 29 };
    EventPolyHelper.init(&ev);
    var slot: Slot = &ev.poly;

    try testing.expectError(error.Closed, mailbox.send(mbh, &slot));
}

// --- Scenario 30: Receive from closed mailbox returns error.Closed ---
test "30 - receive from closed mailbox" {
    const io: Io = testing.io;
    const alloc: std.mem.Allocator = testing.allocator;

    const mbh: MailboxHandle = try mailbox.new(io, alloc);
    var remaining: std.DoublyLinkedList = mailbox.close(mbh);
    helpers.clearList(&remaining);
    defer mailbox.destroy(mbh, alloc);

    var out: Slot = null;
    try testing.expectError(error.Closed, mailbox.receive(mbh, &out, 1_000_000_000));
}

// --- Scenario 31: Receive timeout ---
test "31 - receive timeout" {
    const io: Io = testing.io;
    const alloc: std.mem.Allocator = testing.allocator;

    const mbh: MailboxHandle = try mailbox.new(io, alloc);
    defer {
        var rem: std.DoublyLinkedList = mailbox.close(mbh);
        helpers.clearList(&rem);
        mailbox.destroy(mbh, alloc);
    }

    var out: Slot = null;
    try testing.expectError(error.Timeout, mailbox.receive(mbh, &out, 1_000));
}

// --- Scenario 32: Receive wait forever (item sent from another thread) ---

const Ctx32 = struct {
    mbh: MailboxHandle,
    ev: Event,
};

fn sender32(ctx: *Ctx32) void {
    var slot: Slot = &ctx.*.ev.poly;
    mailbox.send(ctx.*.mbh, &slot) catch {};
}

test "32 - receive wait forever (null timeout), item from thread" {
    const io: Io = testing.io;
    const alloc: std.mem.Allocator = testing.allocator;

    const mbh: MailboxHandle = try mailbox.new(io, alloc);
    defer {
        var rem: std.DoublyLinkedList = mailbox.close(mbh);
        helpers.clearList(&rem);
        mailbox.destroy(mbh, alloc);
    }

    var ctx: Ctx32 = .{
        .mbh = mbh,
        .ev = .{ .code = 32 },
    };
    EventPolyHelper.init(&ctx.ev);

    const t: Thread = try Thread.spawn(.{}, sender32, .{&ctx});
    defer t.join();

    var out: Slot = null;
    try mailbox.receive(mbh, &out, null);
    try testing.expect(out != null);

    const poly: *PolyNode = out.?;
    const ev: *Event = EventPolyHelper.cast(poly) orelse return error.WrongTag;
    try testing.expectEqual(@as(i32, 32), ev.*.code);
}

// --- Scenario 33: Close returns remaining items ---
test "33 - close returns remaining items" {
    const io: Io = testing.io;
    const alloc: std.mem.Allocator = testing.allocator;

    const mbh: MailboxHandle = try mailbox.new(io, alloc);

    var ev1: Event = .{ .code = 1 };
    var ev2: Event = .{ .code = 2 };
    var ev3: Event = .{ .code = 3 };
    EventPolyHelper.init(&ev1);
    EventPolyHelper.init(&ev2);
    EventPolyHelper.init(&ev3);

    var s1: Slot = &ev1.poly;
    var s2: Slot = &ev2.poly;
    var s3: Slot = &ev3.poly;
    try mailbox.send(mbh, &s1);
    try mailbox.send(mbh, &s2);
    try mailbox.send(mbh, &s3);

    var remaining: std.DoublyLinkedList = mailbox.close(mbh);
    defer mailbox.destroy(mbh, alloc);

    var count: usize = 0;
    while (remaining.popFirst()) |_| {
        count += 1;
    }
    try testing.expectEqual(@as(usize, 3), count);
}

// --- Scenario 34: Close is idempotent ---
test "34 - close is idempotent" {
    const io: Io = testing.io;
    const alloc: std.mem.Allocator = testing.allocator;

    const mbh: MailboxHandle = try mailbox.new(io, alloc);

    var ev: Event = .{ .code = 34 };
    EventPolyHelper.init(&ev);
    var slot: Slot = &ev.poly;
    try mailbox.send(mbh, &slot);

    var first: std.DoublyLinkedList = mailbox.close(mbh);
    const second: std.DoublyLinkedList = mailbox.close(mbh);
    defer mailbox.destroy(mbh, alloc);

    var count_first: usize = 0;
    while (first.popFirst()) |_| count_first += 1;
    try testing.expectEqual(@as(usize, 1), count_first);

    try testing.expectEqual(@as(?*std.DoublyLinkedList.Node, null), second.first);
}

// --- Scenario 35: send_oob delivers to front of queue ---
test "35 - send_oob delivers to front" {
    const io: Io = testing.io;
    const alloc: std.mem.Allocator = testing.allocator;

    const mbh: MailboxHandle = try mailbox.new(io, alloc);
    defer {
        var rem: std.DoublyLinkedList = mailbox.close(mbh);
        helpers.clearList(&rem);
        mailbox.destroy(mbh, alloc);
    }

    var ev1: Event = .{ .code = 1 };
    var ev2: Event = .{ .code = 2 };
    var ev3: Event = .{ .code = 3 };
    var oob: Event = .{ .code = 99 };
    EventPolyHelper.init(&ev1);
    EventPolyHelper.init(&ev2);
    EventPolyHelper.init(&ev3);
    EventPolyHelper.init(&oob);

    var s1: Slot = &ev1.poly;
    var s2: Slot = &ev2.poly;
    var s3: Slot = &ev3.poly;
    var so: Slot = &oob.poly;
    try mailbox.send(mbh, &s1);
    try mailbox.send(mbh, &s2);
    try mailbox.send(mbh, &s3);
    try mailbox.send_oob(mbh, &so);

    var out: Slot = null;
    try mailbox.receive(mbh, &out, 1_000_000_000);
    const poly: *PolyNode = out.?;
    const first_ev: *Event = EventPolyHelper.cast(poly) orelse return error.WrongTag;
    try testing.expectEqual(@as(i32, 99), first_ev.*.code);
}

// --- Scenario 36: send_oob wakes blocked receiver ---

const Ctx36 = struct {
    mbh: MailboxHandle,
    ev: Event,
};

fn oob_sender36(ctx: *Ctx36) void {
    var slot: Slot = &ctx.*.ev.poly;
    mailbox.send_oob(ctx.*.mbh, &slot) catch {};
}

test "36 - send_oob wakes blocked receiver" {
    const io: Io = testing.io;
    const alloc: std.mem.Allocator = testing.allocator;

    const mbh: MailboxHandle = try mailbox.new(io, alloc);
    defer {
        var rem: std.DoublyLinkedList = mailbox.close(mbh);
        helpers.clearList(&rem);
        mailbox.destroy(mbh, alloc);
    }

    var ctx: Ctx36 = .{
        .mbh = mbh,
        .ev = .{ .code = 36 },
    };
    EventPolyHelper.init(&ctx.ev);

    const t: Thread = try Thread.spawn(.{}, oob_sender36, .{&ctx});
    defer t.join();

    var out: Slot = null;
    try mailbox.receive(mbh, &out, 5_000_000_000);
    try testing.expect(out != null);

    const poly: *PolyNode = out.?;
    const ev: *Event = EventPolyHelper.cast(poly) orelse return error.WrongTag;
    try testing.expectEqual(@as(i32, 36), ev.*.code);
}

// --- Scenario 37: Multiple send_oob items maintain FIFO among themselves ---
test "37 - multiple send_oob items are FIFO among OOBs" {
    const io: Io = testing.io;
    const alloc: std.mem.Allocator = testing.allocator;

    const mbh: MailboxHandle = try mailbox.new(io, alloc);
    defer {
        var rem: std.DoublyLinkedList = mailbox.close(mbh);
        helpers.clearList(&rem);
        mailbox.destroy(mbh, alloc);
    }

    var oob_a: Event = .{ .code = 10 };
    var oob_b: Event = .{ .code = 20 };
    var regular: Event = .{ .code = 99 };
    EventPolyHelper.init(&oob_a);
    EventPolyHelper.init(&oob_b);
    EventPolyHelper.init(&regular);

    var sr: Slot = &regular.poly;
    var sa: Slot = &oob_a.poly;
    var sb: Slot = &oob_b.poly;
    try mailbox.send(mbh, &sr);
    try mailbox.send_oob(mbh, &sa);
    try mailbox.send_oob(mbh, &sb);

    // Expected order: oob_a(10), oob_b(20), regular(99)
    const expected = [_]i32{ 10, 20, 99 };
    for (expected) |code| {
        var out: Slot = null;
        try mailbox.receive(mbh, &out, 1_000_000_000);
        const poly: *PolyNode = out.?;
        const ev: *Event = EventPolyHelper.cast(poly) orelse return error.WrongTag;
        try testing.expectEqual(code, ev.*.code);
    }
}

// --- Scenario 38: send_oob to closed mailbox returns error.Closed ---
test "38 - send_oob to closed mailbox" {
    const io: Io = testing.io;
    const alloc: std.mem.Allocator = testing.allocator;

    const mbh: MailboxHandle = try mailbox.new(io, alloc);
    var remaining: std.DoublyLinkedList = mailbox.close(mbh);
    helpers.clearList(&remaining);
    defer mailbox.destroy(mbh, alloc);

    var ev: Event = .{ .code = 38 };
    EventPolyHelper.init(&ev);
    var slot: Slot = &ev.poly;

    try testing.expectError(error.Closed, mailbox.send_oob(mbh, &slot));
}

// --- Scenario 39: Data priority over closed ---
test "39 - data priority over closed" {
    const io: Io = testing.io;
    const alloc: std.mem.Allocator = testing.allocator;

    const mbh: MailboxHandle = try mailbox.new(io, alloc);

    var ev: Event = .{ .code = 39 };
    EventPolyHelper.init(&ev);
    var slot: Slot = &ev.poly;
    try mailbox.send(mbh, &slot);

    var remaining: std.DoublyLinkedList = mailbox.close(mbh);
    defer mailbox.destroy(mbh, alloc);

    var count: usize = 0;
    while (remaining.popFirst()) |node| {
        count += 1;
        const poly: *PolyNode = @fieldParentPtr("node", node);
        const recovered: *Event = EventPolyHelper.cast(poly) orelse return error.WrongTag;
        try testing.expectEqual(@as(i32, 39), recovered.*.code);
    }
    try testing.expectEqual(@as(usize, 1), count);
}

// --- Scenario 40: receive_batch gets all items ---
test "40 - receive_batch gets all items" {
    const io: Io = testing.io;
    const alloc: std.mem.Allocator = testing.allocator;

    const mbh: MailboxHandle = try mailbox.new(io, alloc);
    defer {
        var rem: std.DoublyLinkedList = mailbox.close(mbh);
        helpers.clearList(&rem);
        mailbox.destroy(mbh, alloc);
    }

    var events: [5]Event = undefined;
    for (&events, 0..) |*ev, i| {
        ev.* = .{ .code = @as(i32, @intCast(i)) };
        EventPolyHelper.init(ev);
        var slot: Slot = &ev.*.poly;
        try mailbox.send(mbh, &slot);
    }

    var batch: std.DoublyLinkedList = try mailbox.receive_batch(mbh);

    var count: usize = 0;
    while (batch.popFirst()) |_| count += 1;
    try testing.expectEqual(@as(usize, 5), count);

    var empty_check: Slot = null;
    const got: bool = try mailbox.try_receive(mbh, &empty_check);
    try testing.expect(!got);
}

// --- Scenario 41: receive_batch on empty returns empty list ---
test "41 - receive_batch on empty returns empty list" {
    const io: Io = testing.io;
    const alloc: std.mem.Allocator = testing.allocator;

    const mbh: MailboxHandle = try mailbox.new(io, alloc);
    defer {
        var rem: std.DoublyLinkedList = mailbox.close(mbh);
        helpers.clearList(&rem);
        mailbox.destroy(mbh, alloc);
    }

    const batch: std.DoublyLinkedList = try mailbox.receive_batch(mbh);
    try testing.expectEqual(@as(?*std.DoublyLinkedList.Node, null), batch.first);
}

// --- Scenario 42: Batch items walkable via popFirst ---
test "42 - batch items walkable via popFirst" {
    const io: Io = testing.io;
    const alloc: std.mem.Allocator = testing.allocator;

    const mbh: MailboxHandle = try mailbox.new(io, alloc);
    defer {
        var rem: std.DoublyLinkedList = mailbox.close(mbh);
        helpers.clearList(&rem);
        mailbox.destroy(mbh, alloc);
    }

    var ev1: Event = .{ .code = 1 };
    var ev2: Event = .{ .code = 2 };
    EventPolyHelper.init(&ev1);
    EventPolyHelper.init(&ev2);

    var s1: Slot = &ev1.poly;
    var s2: Slot = &ev2.poly;
    try mailbox.send(mbh, &s1);
    try mailbox.send(mbh, &s2);

    var batch: std.DoublyLinkedList = try mailbox.receive_batch(mbh);

    while (batch.popFirst()) |node| {
        const poly: *PolyNode = @fieldParentPtr("node", node);
        // DoublyLinkedList does not clear links — caller must reset
        polynode.reset(poly);
        try testing.expect(!polynode.is_linked(poly));
    }
}

// --- Scenario 43: Send transfers ownership ---
test "43 - send transfers ownership (slot is null)" {
    const io: Io = testing.io;
    const alloc: std.mem.Allocator = testing.allocator;

    const mbh: MailboxHandle = try mailbox.new(io, alloc);
    defer {
        var rem: std.DoublyLinkedList = mailbox.close(mbh);
        helpers.clearList(&rem);
        mailbox.destroy(mbh, alloc);
    }

    var ev: Event = .{ .code = 43 };
    EventPolyHelper.init(&ev);
    var slot: Slot = &ev.poly;

    try testing.expect(slot != null);
    try mailbox.send(mbh, &slot);
    try testing.expectEqual(@as(Slot, null), slot);
}

// --- Scenario 44: Receive transfers ownership ---
test "44 - receive transfers ownership (slot is non-null)" {
    const io: Io = testing.io;
    const alloc: std.mem.Allocator = testing.allocator;

    const mbh: MailboxHandle = try mailbox.new(io, alloc);
    defer {
        var rem: std.DoublyLinkedList = mailbox.close(mbh);
        helpers.clearList(&rem);
        mailbox.destroy(mbh, alloc);
    }

    var ev: Event = .{ .code = 44 };
    EventPolyHelper.init(&ev);
    var slot: Slot = &ev.poly;
    try mailbox.send(mbh, &slot);

    var out: Slot = null;
    try mailbox.receive(mbh, &out, 1_000_000_000);
    try testing.expect(out != null);
}

// --- Scenario 45: try_receive on empty returns false ---
test "45 - try_receive on empty returns false" {
    const io: Io = testing.io;
    const alloc: std.mem.Allocator = testing.allocator;

    const mbh: MailboxHandle = try mailbox.new(io, alloc);
    defer {
        var rem: std.DoublyLinkedList = mailbox.close(mbh);
        helpers.clearList(&rem);
        mailbox.destroy(mbh, alloc);
    }

    var out: Slot = null;
    const got: bool = try mailbox.try_receive(mbh, &out);
    try testing.expect(!got);
    try testing.expectEqual(@as(Slot, null), out);
}

// --- Scenario 46: try_receive gets item ---
test "46 - try_receive gets item" {
    const io: Io = testing.io;
    const alloc: std.mem.Allocator = testing.allocator;

    const mbh: MailboxHandle = try mailbox.new(io, alloc);
    defer {
        var rem: std.DoublyLinkedList = mailbox.close(mbh);
        helpers.clearList(&rem);
        mailbox.destroy(mbh, alloc);
    }

    var ev: Event = .{ .code = 46 };
    EventPolyHelper.init(&ev);
    var slot: Slot = &ev.poly;
    try mailbox.send(mbh, &slot);

    var out: Slot = null;
    const got: bool = try mailbox.try_receive(mbh, &out);
    try testing.expect(got);
    try testing.expect(out != null);
}

// --- Scenario 47: IN_FLIGHT → HELD (mailbox.send) ---
test "47 - send: IN_FLIGHT to HELD, slot is null" {
    const io: Io = testing.io;
    const alloc: std.mem.Allocator = testing.allocator;

    const mbh: MailboxHandle = try mailbox.new(io, alloc);
    defer {
        var rem: std.DoublyLinkedList = mailbox.close(mbh);
        helpers.clearList(&rem);
        mailbox.destroy(mbh, alloc);
    }

    var ev1: Event = .{ .code = 47 };
    var ev2: Event = .{ .code = 48 };
    EventPolyHelper.init(&ev1);
    EventPolyHelper.init(&ev2);
    var slot1: Slot = &ev1.poly;
    var slot2: Slot = &ev2.poly;

    try testing.expect(slot1 != null);
    try testing.expect(!polynode.is_linked(&ev1.poly));

    try mailbox.send(mbh, &slot1);
    try mailbox.send(mbh, &slot2);

    try testing.expectEqual(@as(Slot, null), slot1);
    try testing.expect(polynode.is_linked(&ev1.poly));
}

// --- Scenario 48: HELD → IN_FLIGHT (mailbox.receive) ---
test "48 - receive: HELD to IN_FLIGHT, slot is non-null" {
    const io: Io = testing.io;
    const alloc: std.mem.Allocator = testing.allocator;

    const mbh: MailboxHandle = try mailbox.new(io, alloc);
    defer {
        var rem: std.DoublyLinkedList = mailbox.close(mbh);
        helpers.clearList(&rem);
        mailbox.destroy(mbh, alloc);
    }

    var ev: Event = .{ .code = 48 };
    EventPolyHelper.init(&ev);
    var slot: Slot = &ev.poly;
    try mailbox.send(mbh, &slot);

    var out: Slot = null;
    try mailbox.receive(mbh, &out, 1_000_000_000);

    try testing.expect(out != null);
    const poly: *PolyNode = out.?;
    try testing.expect(!polynode.is_linked(poly));
}

// --- Scenario 49: Send linked item assertion ---
// mailbox.send asserts !polynode.is_linked(m.*.?) in Debug/ReleaseSafe.
// No panic-catching available in std.testing (Open Item 11).
// This test verifies the is_linked detection used by the assert.
test "49 - send linked item: is_linked detection (assert documented)" {
    var ev1: Event = .{ .code = 49 };
    var ev2: Event = .{ .code = 50 };
    EventPolyHelper.init(&ev1);
    EventPolyHelper.init(&ev2);

    var list: std.DoublyLinkedList = .{};
    list.append(&ev1.poly.node);
    list.append(&ev2.poly.node);

    // mailbox.send would assert(!is_linked) here (Open Item 11)
    try testing.expect(polynode.is_linked(&ev1.poly));

    _ = list.popFirst();
    // DoublyLinkedList does not clear links — caller must reset
    polynode.reset(&ev1.poly);
    try testing.expect(!polynode.is_linked(&ev1.poly));
    _ = list.popFirst();
}

// --- Scenario 50: Fan-in (3+1) — 3 sender threads, main receives ---

const Ctx50Sender = struct {
    mbh: MailboxHandle,
    alloc: std.mem.Allocator,
};

fn sender50_event(ctx: *Ctx50Sender) void {
    const ev: *Event = ctx.*.alloc.create(Event) catch return;
    ev.* = .{};
    EventPolyHelper.init(ev);
    var slot: Slot = &ev.*.poly;
    mailbox.send(ctx.*.mbh, &slot) catch ctx.*.alloc.destroy(ev);
}

fn sender50_sensor(ctx: *Ctx50Sender) void {
    const sn: *Sensor = ctx.*.alloc.create(Sensor) catch return;
    sn.* = .{};
    SensorPolyHelper.init(sn);
    var slot: Slot = &sn.*.poly;
    mailbox.send(ctx.*.mbh, &slot) catch ctx.*.alloc.destroy(sn);
}

test "50 - fan-in (3+1): 3 sender threads, main receives all" {
    const io: Io = testing.io;
    const alloc: std.mem.Allocator = testing.allocator;

    const mbh: MailboxHandle = try mailbox.new(io, alloc);

    var ctx_a: Ctx50Sender = .{ .mbh = mbh, .alloc = alloc };
    var ctx_b: Ctx50Sender = .{ .mbh = mbh, .alloc = alloc };
    var ctx_c: Ctx50Sender = .{ .mbh = mbh, .alloc = alloc };

    const ta: Thread = try Thread.spawn(.{}, sender50_event, .{&ctx_a});
    const tb: Thread = try Thread.spawn(.{}, sender50_sensor, .{&ctx_b});
    const tc: Thread = try Thread.spawn(.{}, sender50_event, .{&ctx_c});

    var received: usize = 0;
    while (received < 3) {
        var out: Slot = null;
        mailbox.receive(mbh, &out, 5_000_000_000) catch break;
        if (out) |poly| {
            freeItem(poly, alloc);
            received += 1;
        }
    }

    ta.join();
    tb.join();
    tc.join();

    var rem: std.DoublyLinkedList = mailbox.close(mbh);
    while (rem.popFirst()) |node| {
        freeItem(@fieldParentPtr("node", node), alloc);
    }
    mailbox.destroy(mbh, alloc);

    try testing.expectEqual(@as(usize, 3), received);
}

// --- Scenario 51: Fan-out (1+2) — main sends, 2 receiver threads ---

const Ctx51Receiver = struct {
    mbh: MailboxHandle,
    alloc: std.mem.Allocator,
    items_received: usize = 0,
};

fn receiver51(ctx: *Ctx51Receiver) void {
    var out: Slot = null;
    mailbox.receive(ctx.*.mbh, &out, null) catch return;
    if (out) |poly| {
        freeItem(poly, ctx.*.alloc);
        ctx.*.items_received += 1;
    }
}

test "51 - fan-out (1+2): main sends, 2 receiver threads" {
    const io: Io = testing.io;
    const alloc: std.mem.Allocator = testing.allocator;

    const mbh: MailboxHandle = try mailbox.new(io, alloc);

    const ev: *Event = try alloc.create(Event);
    ev.* = .{};
    EventPolyHelper.init(ev);
    var slot_ev: Slot = &ev.*.poly;
    try mailbox.send(mbh, &slot_ev);

    const sn: *Sensor = try alloc.create(Sensor);
    sn.* = .{};
    SensorPolyHelper.init(sn);
    var slot_sn: Slot = &sn.*.poly;
    try mailbox.send(mbh, &slot_sn);

    var ctx_a: Ctx51Receiver = .{ .mbh = mbh, .alloc = alloc };
    var ctx_b: Ctx51Receiver = .{ .mbh = mbh, .alloc = alloc };

    const ta: Thread = try Thread.spawn(.{}, receiver51, .{&ctx_a});
    const tb: Thread = try Thread.spawn(.{}, receiver51, .{&ctx_b});

    var rem: std.DoublyLinkedList = mailbox.close(mbh);

    ta.join();
    tb.join();

    var remaining_count: usize = 0;
    while (rem.popFirst()) |node| {
        freeItem(@fieldParentPtr("node", node), alloc);
        remaining_count += 1;
    }
    mailbox.destroy(mbh, alloc);

    const total: usize = ctx_a.items_received + ctx_b.items_received + remaining_count;
    try testing.expectEqual(@as(usize, 2), total);
}

// --- Scenario 52: Combined (3+2+main) — fan-in + fan-out, close after 100ms ---

const Ctx52Sender = struct {
    mbh: MailboxHandle,
    alloc: std.mem.Allocator,
    items_sent: usize = 0,
};

const Ctx52AltSender = struct {
    mbh: MailboxHandle,
    alloc: std.mem.Allocator,
    items_sent: usize = 0,
    send_event: bool = true,
};

const Ctx52Receiver = struct {
    mbh: MailboxHandle,
    alloc: std.mem.Allocator,
    items_received: usize = 0,
};

fn sender52_event(ctx: *Ctx52Sender) void {
    while (true) {
        const item: *Event = ctx.*.alloc.create(Event) catch break;
        item.* = .{};
        EventPolyHelper.init(item);
        var slot: Slot = &item.*.poly;
        mailbox.send(ctx.*.mbh, &slot) catch {
            ctx.*.alloc.destroy(item);
            break;
        };
        ctx.*.items_sent += 1;
    }
}

fn sender52_sensor(ctx: *Ctx52Sender) void {
    while (true) {
        const item: *Sensor = ctx.*.alloc.create(Sensor) catch break;
        item.* = .{};
        SensorPolyHelper.init(item);
        var slot: Slot = &item.*.poly;
        mailbox.send(ctx.*.mbh, &slot) catch {
            ctx.*.alloc.destroy(item);
            break;
        };
        ctx.*.items_sent += 1;
    }
}

fn sender52_alt(ctx: *Ctx52AltSender) void {
    while (true) {
        if (ctx.*.send_event) {
            const item: *Event = ctx.*.alloc.create(Event) catch break;
            item.* = .{};
            EventPolyHelper.init(item);
            var slot: Slot = &item.*.poly;
            mailbox.send(ctx.*.mbh, &slot) catch {
                ctx.*.alloc.destroy(item);
                break;
            };
        } else {
            const item: *Sensor = ctx.*.alloc.create(Sensor) catch break;
            item.* = .{};
            SensorPolyHelper.init(item);
            var slot: Slot = &item.*.poly;
            mailbox.send(ctx.*.mbh, &slot) catch {
                ctx.*.alloc.destroy(item);
                break;
            };
        }
        ctx.*.items_sent += 1;
        ctx.*.send_event = !ctx.*.send_event;
    }
}

fn receiver52(ctx: *Ctx52Receiver) void {
    while (true) {
        var out: Slot = null;
        mailbox.receive(ctx.*.mbh, &out, null) catch break;
        if (out) |poly| {
            freeItem(poly, ctx.*.alloc);
            ctx.*.items_received += 1;
        }
    }
}

test "52 - combined (3+2+main): fan-in + fan-out, close after 100ms" {
    const io: Io = testing.io;
    const alloc: std.mem.Allocator = testing.allocator;

    const mbh: MailboxHandle = try mailbox.new(io, alloc);

    var ctx_se: Ctx52Sender = .{ .mbh = mbh, .alloc = alloc };
    var ctx_ss: Ctx52Sender = .{ .mbh = mbh, .alloc = alloc };
    var ctx_sa: Ctx52AltSender = .{ .mbh = mbh, .alloc = alloc };
    var ctx_ra: Ctx52Receiver = .{ .mbh = mbh, .alloc = alloc };
    var ctx_rb: Ctx52Receiver = .{ .mbh = mbh, .alloc = alloc };

    const t_se: Thread = try Thread.spawn(.{}, sender52_event, .{&ctx_se});
    const t_ss: Thread = try Thread.spawn(.{}, sender52_sensor, .{&ctx_ss});
    const t_sa: Thread = try Thread.spawn(.{}, sender52_alt, .{&ctx_sa});
    const t_ra: Thread = try Thread.spawn(.{}, receiver52, .{&ctx_ra});
    const t_rb: Thread = try Thread.spawn(.{}, receiver52, .{&ctx_rb});

    const sleep_t: Io.Timeout = .{
        .duration = .{
            .raw = .{ .nanoseconds = @as(i96, 100_000_000) },
            .clock = .real,
        },
    };
    Io.Timeout.sleep(sleep_t, io) catch {};

    var rem: std.DoublyLinkedList = mailbox.close(mbh);

    t_se.join();
    t_ss.join();
    t_sa.join();
    t_ra.join();
    t_rb.join();

    var remaining_count: usize = 0;
    while (rem.popFirst()) |node| {
        freeItem(@fieldParentPtr("node", node), alloc);
        remaining_count += 1;
    }
    mailbox.destroy(mbh, alloc);

    const total_sent: usize = ctx_se.items_sent + ctx_ss.items_sent + ctx_sa.items_sent;
    const total_received: usize = ctx_ra.items_received + ctx_rb.items_received;
    try testing.expectEqual(total_sent, total_received + remaining_count);
}


const std = @import("std");
const testing = std.testing;
const Thread = std.Thread;
const Io = std.Io;

const helpers = @import("helpers");

const matryoshka = @import("matryoshka");
const polynode = matryoshka.polynode;
const mailbox = matryoshka.mailbox;
const PolyNode = polynode.PolyNode;
const Slot = polynode.Slot;
const MailboxHandle = mailbox.MailboxHandle;

const types = helpers.types;
const Event = types.Event;
const Sensor = types.Sensor;
const EventPolyHelper = types.EventPolyHelper;
const SensorPolyHelper = types.SensorPolyHelper;
const freeItem = helpers.freeItem;
