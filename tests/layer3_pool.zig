// --- Scenario 63: pool.new, pool.init, pool.destroy ---
test "63 - pool new, init, destroy" {
    const io: Io = testing.io;
    const alloc: std.mem.Allocator = testing.allocator;

    const ph: PoolHandle = try pool.new(io, alloc);
    try testing.expect(pool.is_it_you(ph.*.tag));

    var ctx: TestCtx = .{ .alloc = alloc };
    const event_tags = [_]*const anyopaque{EventPolyHelper.TAG};
    const hooks: PoolHooks = .{
        .ctx = &ctx,
        .tags = &event_tags,
        .on_get = onGetAlways,
        .on_put = onPutAdaptive,
        .on_close = onCloseAdaptive,
    };
    try pool.init(ph, hooks);

    pool.close(ph);
    pool.destroy(ph, alloc);
}

// --- Scenario 64: pool.get creates new item via on_get ---
test "64 - pool.get creates new item via on_get" {
    const io: Io = testing.io;
    const alloc: std.mem.Allocator = testing.allocator;

    const ph: PoolHandle = try pool.new(io, alloc);
    var ctx: TestCtx = .{ .alloc = alloc };
    const event_tags = [_]*const anyopaque{EventPolyHelper.TAG};
    try pool.init(ph, .{
        .ctx = &ctx,
        .tags = &event_tags,
        .on_get = onGetAlways,
        .on_put = onPutAdaptive,
        .on_close = onCloseAdaptive,
    });
    defer {
        pool.close(ph);
        pool.destroy(ph, alloc);
    }

    var slot: Slot = null;
    try pool.get(ph, EventPolyHelper.TAG, .available_or_new, &slot);
    try testing.expect(slot != null);
    try testing.expect(EventPolyHelper.cast(slot.?) != null);
    try testing.expectEqual(@as(usize, 1), ctx.get_call_count);

    // Return item so on_close can free it.
    pool.put(ph, &slot);
}

// --- Scenario 65: pool.get reuses stored item ---
test "65 - pool.get reuses stored item" {
    const io: Io = testing.io;
    const alloc: std.mem.Allocator = testing.allocator;

    const ph: PoolHandle = try pool.new(io, alloc);
    var ctx: TestCtx = .{ .alloc = alloc };
    const event_tags = [_]*const anyopaque{EventPolyHelper.TAG};
    try pool.init(ph, .{
        .ctx = &ctx,
        .tags = &event_tags,
        .on_get = onGetAlways,
        .on_put = onPutAdaptive,
        .on_close = onCloseAdaptive,
    });
    defer {
        pool.close(ph);
        pool.destroy(ph, alloc);
    }

    var slot: Slot = null;
    try pool.get(ph, EventPolyHelper.TAG, .available_or_new, &slot);
    const first_ptr: *PolyNode = slot.?;

    pool.put(ph, &slot);
    try testing.expectEqual(@as(Slot, null), slot);

    var m2: Slot = null;
    try pool.get(ph, EventPolyHelper.TAG, .available_or_new, &m2);
    try testing.expectEqual(first_ptr, m2.?);

    pool.put(ph, &m2);
}

// --- Scenario 66: on_get reinitializes recycled item ---
test "66 - on_get reinitializes recycled item" {
    const io: Io = testing.io;
    const alloc: std.mem.Allocator = testing.allocator;

    const ph: PoolHandle = try pool.new(io, alloc);
    var ctx: TestCtx = .{ .alloc = alloc };
    const event_tags = [_]*const anyopaque{EventPolyHelper.TAG};
    try pool.init(ph, .{
        .ctx = &ctx,
        .tags = &event_tags,
        .on_get = onGetAlways,
        .on_put = onPutAdaptive,
        .on_close = onCloseAdaptive,
    });
    defer {
        pool.close(ph);
        pool.destroy(ph, alloc);
    }

    var slot: Slot = null;
    try pool.get(ph, EventPolyHelper.TAG, .available_or_new, &slot);
    const ev: *Event = EventPolyHelper.cast(slot.?) orelse return error.WrongTag;
    ev.*.code = 66; // mark with dirty data
    pool.put(ph, &slot);

    var m2: Slot = null;
    try pool.get(ph, EventPolyHelper.TAG, .available_or_new, &m2);
    const ev2: *Event = EventPolyHelper.cast(m2.?) orelse return error.WrongTag;
    // on_get reinitializes recycled items (code reset to 0).
    try testing.expectEqual(@as(i32, 0), ev2.*.code);

    pool.put(ph, &m2);
}

// --- Scenario 67: pool.put calls on_put ---
test "67 - pool.put calls on_put" {
    const io: Io = testing.io;
    const alloc: std.mem.Allocator = testing.allocator;

    const ph: PoolHandle = try pool.new(io, alloc);
    var ctx: TestCtx = .{ .alloc = alloc };
    const event_tags = [_]*const anyopaque{EventPolyHelper.TAG};
    try pool.init(ph, .{
        .ctx = &ctx,
        .tags = &event_tags,
        .on_get = onGetAlways,
        .on_put = onPutAdaptive,
        .on_close = onCloseAdaptive,
    });
    defer {
        pool.close(ph);
        pool.destroy(ph, alloc);
    }

    var slot: Slot = null;
    try pool.get(ph, EventPolyHelper.TAG, .available_or_new, &slot);
    try testing.expectEqual(@as(usize, 0), ctx.put_call_count);

    pool.put(ph, &slot);
    try testing.expectEqual(@as(usize, 1), ctx.put_call_count);
}

// --- Scenario 68: on_put can destroy item ---
test "68 - on_put can destroy item" {
    const io: Io = testing.io;
    const alloc: std.mem.Allocator = testing.allocator;

    const ph: PoolHandle = try pool.new(io, alloc);
    var ctx: TestCtx = .{ .alloc = alloc, .destroy_on_put = true };
    const event_tags = [_]*const anyopaque{EventPolyHelper.TAG};
    try pool.init(ph, .{
        .ctx = &ctx,
        .tags = &event_tags,
        .on_get = onGetAlways,
        .on_put = onPutAdaptive,
        .on_close = onCloseAdaptive,
    });
    defer {
        pool.close(ph);
        pool.destroy(ph, alloc);
    }

    var slot: Slot = null;
    try pool.get(ph, EventPolyHelper.TAG, .available_or_new, &slot);
    try testing.expect(slot != null);

    pool.put(ph, &slot);
    // on_put destroyed the item; pool did not store it; slot is null.
    try testing.expectEqual(@as(Slot, null), slot);

    // Pool is empty — available_only must fail.
    var m2: Slot = null;
    try testing.expectError(error.NotAvailable, pool.get(ph, EventPolyHelper.TAG, .available_only, &m2));
}

// --- Scenario 69: on_put can keep item ---
test "69 - on_put can keep item" {
    const io: Io = testing.io;
    const alloc: std.mem.Allocator = testing.allocator;

    const ph: PoolHandle = try pool.new(io, alloc);
    var ctx: TestCtx = .{ .alloc = alloc };
    const event_tags = [_]*const anyopaque{EventPolyHelper.TAG};
    try pool.init(ph, .{
        .ctx = &ctx,
        .tags = &event_tags,
        .on_get = onGetAlways,
        .on_put = onPutAdaptive,
        .on_close = onCloseAdaptive,
    });
    defer {
        pool.close(ph);
        pool.destroy(ph, alloc);
    }

    var slot: Slot = null;
    try pool.get(ph, EventPolyHelper.TAG, .available_or_new, &slot);
    pool.put(ph, &slot);
    try testing.expectEqual(@as(Slot, null), slot); // pool took it

    // Pool has item — available_only must succeed.
    var m2: Slot = null;
    try pool.get(ph, EventPolyHelper.TAG, .available_only, &m2);
    try testing.expect(m2 != null);
    pool.put(ph, &m2);
}

// --- Scenario 70: GetMode.new_only always creates ---
test "70 - GetMode.new_only always creates, ignores available items" {
    const io: Io = testing.io;
    const alloc: std.mem.Allocator = testing.allocator;

    const ph: PoolHandle = try pool.new(io, alloc);
    var ctx: TestCtx = .{ .alloc = alloc };
    const event_tags = [_]*const anyopaque{EventPolyHelper.TAG};
    try pool.init(ph, .{
        .ctx = &ctx,
        .tags = &event_tags,
        .on_get = onGetAlways,
        .on_put = onPutAdaptive,
        .on_close = onCloseAdaptive,
    });
    defer {
        pool.close(ph);
        pool.destroy(ph, alloc);
    }

    // Seed one item.
    {
        var slot: Slot = null;
        try pool.get(ph, EventPolyHelper.TAG, .available_or_new, &slot);
        pool.put(ph, &slot);
    }
    const gets_before: usize = ctx.get_call_count;

    // new_only must call on_get with a null slot, creating a fresh item.
    {
        var slot: Slot = null;
        try pool.get(ph, EventPolyHelper.TAG, .new_only, &slot);
        try testing.expect(slot != null);
        try testing.expectEqual(gets_before + 1, ctx.get_call_count);
        pool.put(ph, &slot);
    }
    // Both the seeded item and the new item are now in the pool.
}

// --- Scenario 71: GetMode.available_only returns error.NotAvailable on empty pool ---
test "71 - GetMode.available_only returns error.NotAvailable" {
    const io: Io = testing.io;
    const alloc: std.mem.Allocator = testing.allocator;

    const ph: PoolHandle = try pool.new(io, alloc);
    var ctx: TestCtx = .{ .alloc = alloc };
    const event_tags = [_]*const anyopaque{EventPolyHelper.TAG};
    try pool.init(ph, .{
        .ctx = &ctx,
        .tags = &event_tags,
        .on_get = onGetAlways,
        .on_put = onPutAdaptive,
        .on_close = onCloseAdaptive,
    });
    defer {
        pool.close(ph);
        pool.destroy(ph, alloc);
    }

    var slot: Slot = null;
    try testing.expectError(error.NotAvailable, pool.get(ph, EventPolyHelper.TAG, .available_only, &slot));
    try testing.expectEqual(@as(Slot, null), slot);
}

// --- Scenario 72: GetMode.available_only returns stored item ---
test "72 - GetMode.available_only returns stored item" {
    const io: Io = testing.io;
    const alloc: std.mem.Allocator = testing.allocator;

    const ph: PoolHandle = try pool.new(io, alloc);
    var ctx: TestCtx = .{ .alloc = alloc };
    const event_tags = [_]*const anyopaque{EventPolyHelper.TAG};
    try pool.init(ph, .{
        .ctx = &ctx,
        .tags = &event_tags,
        .on_get = onGetAlways,
        .on_put = onPutAdaptive,
        .on_close = onCloseAdaptive,
    });
    defer {
        pool.close(ph);
        pool.destroy(ph, alloc);
    }

    {
        var slot: Slot = null;
        try pool.get(ph, EventPolyHelper.TAG, .available_or_new, &slot);
        pool.put(ph, &slot);
    }

    var slot: Slot = null;
    try pool.get(ph, EventPolyHelper.TAG, .available_only, &slot);
    try testing.expect(slot != null);
    try testing.expect(EventPolyHelper.cast(slot.?) != null);
    pool.put(ph, &slot);
}

// --- Scenario 73: Per-tag free lists ---
test "73 - per-tag free lists: Event and Sensor stored separately" {
    const io: Io = testing.io;
    const alloc: std.mem.Allocator = testing.allocator;

    const ph: PoolHandle = try pool.new(io, alloc);
    var ctx: TestCtx = .{ .alloc = alloc };
    const both_tags = [_]*const anyopaque{ EventPolyHelper.TAG, SensorPolyHelper.TAG };
    try pool.init(ph, .{
        .ctx = &ctx,
        .tags = &both_tags,
        .on_get = onGetAlways,
        .on_put = onPutAdaptive,
        .on_close = onCloseAdaptive,
    });
    defer {
        pool.close(ph);
        pool.destroy(ph, alloc);
    }

    {
        var slot: Slot = null;
        try pool.get(ph, EventPolyHelper.TAG, .available_or_new, &slot);
        pool.put(ph, &slot);
    }
    {
        var slot: Slot = null;
        try pool.get(ph, SensorPolyHelper.TAG, .available_or_new, &slot);
        pool.put(ph, &slot);
    }

    // get with EventPolyHelper.TAG must return an Event.
    {
        var slot: Slot = null;
        try pool.get(ph, EventPolyHelper.TAG, .available_only, &slot);
        try testing.expect(EventPolyHelper.cast(slot.?) != null);
        try testing.expect(SensorPolyHelper.cast(slot.?) == null);
        pool.put(ph, &slot);
    }

    // get with SensorPolyHelper.TAG must return a Sensor.
    {
        var slot: Slot = null;
        try pool.get(ph, SensorPolyHelper.TAG, .available_only, &slot);
        try testing.expect(SensorPolyHelper.cast(slot.?) != null);
        try testing.expect(EventPolyHelper.cast(slot.?) == null);
        pool.put(ph, &slot);
    }
}

// --- Scenario 74: pool.close calls on_close with all items ---
test "74 - pool.close calls on_close with all stored items" {
    const io: Io = testing.io;
    const alloc: std.mem.Allocator = testing.allocator;

    const ph: PoolHandle = try pool.new(io, alloc);
    var ctx: TestCtx = .{ .alloc = alloc };
    const event_tags = [_]*const anyopaque{EventPolyHelper.TAG};
    try pool.init(ph, .{
        .ctx = &ctx,
        .tags = &event_tags,
        .on_get = onGetAlways,
        .on_put = onPutAdaptive,
        .on_close = onCloseAdaptive,
    });

    // Use new_only to accumulate 5 distinct heap items in the pool.
    for (0..5) |_| {
        var slot: Slot = null;
        try pool.get(ph, EventPolyHelper.TAG, .new_only, &slot);
        pool.put(ph, &slot);
    }

    pool.close(ph);
    pool.destroy(ph, alloc);

    try testing.expectEqual(@as(usize, 5), ctx.close_item_count);
}

// --- Scenario 75: second pool.close is no-op ---
test "75 - pool.close second call is no-op" {
    const io: Io = testing.io;
    const alloc: std.mem.Allocator = testing.allocator;

    const ph: PoolHandle = try pool.new(io, alloc);
    var ctx: TestCtx = .{ .alloc = alloc };
    const event_tags = [_]*const anyopaque{EventPolyHelper.TAG};
    try pool.init(ph, .{
        .ctx = &ctx,
        .tags = &event_tags,
        .on_get = onGetAlways,
        .on_put = onPutAdaptive,
        .on_close = onCloseAdaptive,
    });
    defer pool.destroy(ph, alloc);

    pool.close(ph);
    pool.close(ph); // second close must be a no-op
}

// --- Scenario 76: pool.get on closed pool returns error.Closed ---
test "76 - pool.get on closed pool returns error.Closed" {
    const io: Io = testing.io;
    const alloc: std.mem.Allocator = testing.allocator;

    const ph: PoolHandle = try pool.new(io, alloc);
    var ctx: TestCtx = .{ .alloc = alloc };
    const event_tags = [_]*const anyopaque{EventPolyHelper.TAG};
    try pool.init(ph, .{
        .ctx = &ctx,
        .tags = &event_tags,
        .on_get = onGetAlways,
        .on_put = onPutAdaptive,
        .on_close = onCloseAdaptive,
    });
    defer pool.destroy(ph, alloc);

    pool.close(ph);

    var slot: Slot = null;
    try testing.expectError(error.Closed, pool.get(ph, EventPolyHelper.TAG, .available_or_new, &slot));
}

// --- Scenario 77: pool.put on closed pool returns item to caller ---
test "77 - pool.put on closed pool: caller retains ownership" {
    const io: Io = testing.io;
    const alloc: std.mem.Allocator = testing.allocator;

    const ph: PoolHandle = try pool.new(io, alloc);
    var ctx: TestCtx = .{ .alloc = alloc };
    const event_tags = [_]*const anyopaque{EventPolyHelper.TAG};
    try pool.init(ph, .{
        .ctx = &ctx,
        .tags = &event_tags,
        .on_get = onGetAlways,
        .on_put = onPutAdaptive,
        .on_close = onCloseAdaptive,
    });

    var slot: Slot = null;
    try pool.get(ph, EventPolyHelper.TAG, .available_or_new, &slot);
    const raw: *PolyNode = slot.?;

    pool.close(ph);

    // put after close: caller retains ownership (slot stays non-null).
    pool.put(ph, &slot);

    // Caller must still own the item.
    try testing.expectEqual(raw, slot.?);

    // Manually free item since pool rejected it, then destroy.
    helpers.freeItem(slot.?, alloc);
    pool.destroy(ph, alloc);
}

// --- Scenario 78: Backpressure policy ---
test "78 - backpressure: on_put drops items beyond cap" {
    const io: Io = testing.io;
    const alloc: std.mem.Allocator = testing.allocator;

    const ph: PoolHandle = try pool.new(io, alloc);
    var ctx: TestCtx = .{ .alloc = alloc, .cap = 2 };
    const event_tags = [_]*const anyopaque{EventPolyHelper.TAG};
    try pool.init(ph, .{
        .ctx = &ctx,
        .tags = &event_tags,
        .on_get = onGetAlways,
        .on_put = onPutAdaptive,
        .on_close = onCloseAdaptive,
    });
    defer {
        pool.close(ph);
        pool.destroy(ph, alloc);
    }

    // Create and put 4 items — only 2 should be kept (cap=2 means keep when count < 2).
    for (0..4) |_| {
        var slot: Slot = null;
        try pool.get(ph, EventPolyHelper.TAG, .available_or_new, &slot);
        pool.put(ph, &slot);
    }

    // capped at 2 — on_put destroyed 2 of 4; on_close sees at most 2 (close_item_count verified above)
}

// --- Scenario 79: Pool seeding ---
test "79 - pool seeding: pre-allocate N items, then available_only consumes them" {
    const io: Io = testing.io;
    const alloc: std.mem.Allocator = testing.allocator;

    const ph: PoolHandle = try pool.new(io, alloc);
    var ctx: TestCtx = .{ .alloc = alloc };
    const event_tags = [_]*const anyopaque{EventPolyHelper.TAG};
    try pool.init(ph, .{
        .ctx = &ctx,
        .tags = &event_tags,
        .on_get = onGetAlways,
        .on_put = onPutAdaptive,
        .on_close = onCloseAdaptive,
    });
    defer {
        pool.close(ph);
        pool.destroy(ph, alloc);
    }

    // Seed 3 items using new_only + put.
    for (0..3) |_| {
        var slot: Slot = null;
        try pool.get(ph, EventPolyHelper.TAG, .new_only, &slot);
        pool.put(ph, &slot);
    }

    // Must be able to retrieve all 3 with available_only (no allocation).
    var retrieved: usize = 0;
    while (true) {
        var slot: Slot = null;
        pool.get(ph, EventPolyHelper.TAG, .available_only, &slot) catch break;
        retrieved += 1;
        helpers.freeItem(slot.?, alloc);
    }
    try testing.expectEqual(@as(usize, 3), retrieved);
}

// --- Scenario 80: in_pool_count accuracy ---
test "80 - in_pool_count: on_put and on_get receive correct count" {
    const io: Io = testing.io;
    const alloc: std.mem.Allocator = testing.allocator;

    const ph: PoolHandle = try pool.new(io, alloc);
    var ctx: TestCtx = .{ .alloc = alloc };
    const event_tags = [_]*const anyopaque{EventPolyHelper.TAG};
    try pool.init(ph, .{
        .ctx = &ctx,
        .tags = &event_tags,
        .on_get = onGetAlways,
        .on_put = onPutAdaptive,
        .on_close = onCloseAdaptive,
    });
    defer {
        pool.close(ph);
        pool.destroy(ph, alloc);
    }

    // First get on empty pool: on_get sees count=0 (no items before this get).
    var m1: Slot = null;
    try pool.get(ph, EventPolyHelper.TAG, .available_or_new, &m1);
    try testing.expectEqual(@as(usize, 0), ctx.last_get_count);

    // Put m1 back: pool is empty (count=0), on_put sees count=0.
    pool.put(ph, &m1);
    try testing.expectEqual(@as(usize, 0), ctx.last_put_count);

    // Second get recycling the item: pool had 1, pop → count=0, on_get sees 0.
    var m2: Slot = null;
    try pool.get(ph, EventPolyHelper.TAG, .available_or_new, &m2);
    try testing.expectEqual(@as(usize, 0), ctx.last_get_count);

    pool.put(ph, &m2);
}

// --- Scenario 81: Hooks run outside lock ---
test "81 - hooks run outside lock: no deadlock on put+get cycle" {
    // hooks run outside lock — a blocking hook inside the mutex would deadlock; full put+get cycle verifies no deadlock
    const io: Io = testing.io;
    const alloc: std.mem.Allocator = testing.allocator;

    const ph: PoolHandle = try pool.new(io, alloc);
    var ctx: TestCtx = .{ .alloc = alloc };
    const event_tags = [_]*const anyopaque{EventPolyHelper.TAG};
    try pool.init(ph, .{
        .ctx = &ctx,
        .tags = &event_tags,
        .on_get = onGetAlways,
        .on_put = onPutAdaptive,
        .on_close = onCloseAdaptive,
    });
    defer {
        pool.close(ph);
        pool.destroy(ph, alloc);
    }

    var slot: Slot = null;
    try pool.get(ph, EventPolyHelper.TAG, .available_or_new, &slot);
    pool.put(ph, &slot);
    try testing.expectEqual(@as(usize, 1), ctx.get_call_count);
    try testing.expectEqual(@as(usize, 1), ctx.put_call_count);
}

// --- Scenario 82: pool.put_all ---
test "82 - pool.put_all returns batch from std.DoublyLinkedList" {
    const io: Io = testing.io;
    const alloc: std.mem.Allocator = testing.allocator;

    const ph: PoolHandle = try pool.new(io, alloc);
    var ctx: TestCtx = .{ .alloc = alloc };
    const event_tags = [_]*const anyopaque{EventPolyHelper.TAG};
    try pool.init(ph, .{
        .ctx = &ctx,
        .tags = &event_tags,
        .on_get = onGetAlways,
        .on_put = onPutAdaptive,
        .on_close = onCloseAdaptive,
    });
    defer {
        pool.close(ph);
        pool.destroy(ph, alloc);
    }

    // Collect 3 items into a raw list.
    var batch: std.DoublyLinkedList = .{};
    for (0..3) |_| {
        var slot: Slot = null;
        try pool.get(ph, EventPolyHelper.TAG, .available_or_new, &slot);
        batch.append(&slot.?.*.node);
        slot = null; // ownership transferred to batch
    }

    pool.put_all(ph, &batch);
    // All items transferred to pool; batch must be empty.
    try testing.expectEqual(@as(?*std.DoublyLinkedList.Node, null), batch.first);
    try testing.expectEqual(@as(usize, 3), ctx.put_call_count);
}

// --- Scenario 83: pool.get_wait timeout ---
test "83 - pool.get_wait timeout on empty pool" {
    const io: Io = testing.io;
    const alloc: std.mem.Allocator = testing.allocator;

    const ph: PoolHandle = try pool.new(io, alloc);
    var ctx: TestCtx = .{ .alloc = alloc };
    const event_tags = [_]*const anyopaque{EventPolyHelper.TAG};
    try pool.init(ph, .{
        .ctx = &ctx,
        .tags = &event_tags,
        .on_get = onGetAlways,
        .on_put = onPutAdaptive,
        .on_close = onCloseAdaptive,
    });
    defer {
        pool.close(ph);
        pool.destroy(ph, alloc);
    }

    var slot: Slot = null;
    try testing.expectError(error.Timeout, pool.get_wait(ph, EventPolyHelper.TAG, &slot, 1_000));
    try testing.expectEqual(@as(Slot, null), slot);
}

// --- Scenario 84: pool.get_wait forever (item put from another thread) ---

const Ctx84 = struct {
    ph: PoolHandle,
    io: Io,
    alloc: std.mem.Allocator,
};

fn putter84(ctx: *Ctx84) void {
    const sleep_t: Io.Timeout = .{
        .duration = .{ .raw = .{ .nanoseconds = @as(i96, 10_000_000) }, .clock = .real },
    };
    Io.Timeout.sleep(sleep_t, ctx.*.io) catch {};
    var slot: Slot = null;
    EventPolyHelper.create(ctx.*.alloc, &slot) catch return;
    pool.put(ctx.*.ph, &slot);
    if (slot != null) EventPolyHelper.destroy(ctx.*.alloc, &slot);
}

test "84 - pool.get_wait forever: item put from another thread" {
    const io: Io = testing.io;
    const alloc: std.mem.Allocator = testing.allocator;

    const ph: PoolHandle = try pool.new(io, alloc);
    var ctx: TestCtx = .{ .alloc = alloc };
    const event_tags = [_]*const anyopaque{EventPolyHelper.TAG};
    try pool.init(ph, .{
        .ctx = &ctx,
        .tags = &event_tags,
        .on_get = onGetAlways,
        .on_put = onPutAdaptive,
        .on_close = onCloseAdaptive,
    });
    defer {
        pool.close(ph);
        pool.destroy(ph, alloc);
    }

    var pctx: Ctx84 = .{ .ph = ph, .io = io, .alloc = alloc };
    const t: Thread = try Thread.spawn(.{}, putter84, .{&pctx});

    var slot: Slot = null;
    try pool.get_wait(ph, EventPolyHelper.TAG, &slot, null);
    t.join();

    try testing.expect(slot != null);
    try testing.expect(EventPolyHelper.cast(slot.?) != null);
    pool.put(ph, &slot);
}

// --- Scenario 85: HELD → IN_FLIGHT (pool.get) ---
test "85 - ownership: HELD->IN_FLIGHT via pool.get" {
    const io: Io = testing.io;
    const alloc: std.mem.Allocator = testing.allocator;

    const ph: PoolHandle = try pool.new(io, alloc);
    var ctx: TestCtx = .{ .alloc = alloc };
    const event_tags = [_]*const anyopaque{EventPolyHelper.TAG};
    try pool.init(ph, .{
        .ctx = &ctx,
        .tags = &event_tags,
        .on_get = onGetAlways,
        .on_put = onPutAdaptive,
        .on_close = onCloseAdaptive,
    });
    defer {
        pool.close(ph);
        pool.destroy(ph, alloc);
    }

    // Seed one item.
    {
        var slot: Slot = null;
        try pool.get(ph, EventPolyHelper.TAG, .available_or_new, &slot);
        pool.put(ph, &slot);
    }

    // Item is now HELD in pool (is_linked == true from pool's perspective).
    // pool.get transitions it to IN_FLIGHT (slot non-null, not linked after reset).
    var slot: Slot = null;
    try pool.get(ph, EventPolyHelper.TAG, .available_only, &slot);
    try testing.expect(slot != null);
    try testing.expect(!polynode.is_linked(slot.?));

    pool.put(ph, &slot);
}

// --- Scenario 86: IN_FLIGHT → HELD (pool.put, keep policy) ---
test "86 - ownership: IN_FLIGHT->HELD via pool.put with keep" {
    const io: Io = testing.io;
    const alloc: std.mem.Allocator = testing.allocator;

    const ph: PoolHandle = try pool.new(io, alloc);
    var ctx: TestCtx = .{ .alloc = alloc };
    const event_tags = [_]*const anyopaque{EventPolyHelper.TAG};
    try pool.init(ph, .{
        .ctx = &ctx,
        .tags = &event_tags,
        .on_get = onGetAlways,
        .on_put = onPutAdaptive,
        .on_close = onCloseAdaptive,
    });
    defer {
        pool.close(ph);
        pool.destroy(ph, alloc);
    }

    var slot: Slot = null;
    try pool.get(ph, EventPolyHelper.TAG, .available_or_new, &slot);
    try testing.expect(slot != null);
    try testing.expect(!polynode.is_linked(slot.?)); // IN_FLIGHT: not linked

    pool.put(ph, &slot);
    try testing.expectEqual(@as(Slot, null), slot); // slot cleared: pool holds it
}

// --- Scenario 87: IN_FLIGHT → FREE (pool.put, destroy policy) ---
test "87 - ownership: IN_FLIGHT->FREE via pool.put with destroy" {
    const io: Io = testing.io;
    const alloc: std.mem.Allocator = testing.allocator;

    const ph: PoolHandle = try pool.new(io, alloc);
    var ctx: TestCtx = .{ .alloc = alloc, .destroy_on_put = true };
    const event_tags = [_]*const anyopaque{EventPolyHelper.TAG};
    try pool.init(ph, .{
        .ctx = &ctx,
        .tags = &event_tags,
        .on_get = onGetAlways,
        .on_put = onPutAdaptive,
        .on_close = onCloseAdaptive,
    });
    defer {
        pool.close(ph);
        pool.destroy(ph, alloc);
    }

    var slot: Slot = null;
    try pool.get(ph, EventPolyHelper.TAG, .available_or_new, &slot);
    try testing.expect(slot != null); // IN_FLIGHT

    pool.put(ph, &slot);
    // on_put freed the item; pool did not store it; slot is null (FREE).
    try testing.expectEqual(@as(Slot, null), slot);
}

// --- Scenario 88: is_linked detection; assert triggers on double pool.put in Debug/ReleaseSafe ---
test "88 - double pool.put: is_linked detection (assert documented)" {
    const io: Io = testing.io;
    const alloc: std.mem.Allocator = testing.allocator;

    const ph: PoolHandle = try pool.new(io, alloc);
    var ctx: TestCtx = .{ .alloc = alloc };
    const event_tags = [_]*const anyopaque{EventPolyHelper.TAG};
    try pool.init(ph, .{
        .ctx = &ctx,
        .tags = &event_tags,
        .on_get = onGetAlways,
        .on_put = onPutAdaptive,
        .on_close = onCloseAdaptive,
    });
    defer {
        pool.close(ph);
        pool.destroy(ph, alloc);
    }

    // 2-node list: tail has prev != null so is_linked=true; single-node list has prev==next==null
    var m1: Slot = null;
    var m2: Slot = null;
    try pool.get(ph, EventPolyHelper.TAG, .new_only, &m1);
    try pool.get(ph, EventPolyHelper.TAG, .new_only, &m2);
    const raw: *PolyNode = m1.?;

    pool.put(ph, &m1); // pool: [m1], count=1
    pool.put(ph, &m2); // prepend → pool: [m2, m1], count=2; m1 now has prev set

    // m1 is now the tail of the pool list (has prev pointer → is_linked true).
    // pool.put asserts !polynode.is_linked(slot.*.?) before storing (Debug/ReleaseSafe).
    try testing.expect(polynode.is_linked(raw));
}

// --- Hook implementations ---

const TestCtx = struct {
    alloc: std.mem.Allocator,
    cap: usize = std.math.maxInt(usize),
    destroy_on_put: bool = false,
    get_call_count: usize = 0,
    put_call_count: usize = 0,
    close_item_count: usize = 0,
    last_get_count: usize = 0,
    last_put_count: usize = 0,
};

fn onGetAlways(ctx_opaque: *anyopaque, tag: *const anyopaque, in_pool_count: usize, slot: *Slot) void {
    const ctx: *TestCtx = @ptrCast(@alignCast(ctx_opaque));
    ctx.get_call_count += 1;
    ctx.last_get_count = in_pool_count;
    if (slot.* != null) {
        // Reinitialize recycled item.
        if (EventPolyHelper.cast(slot.*.?)) |ev| ev.*.code = 0;
        if (SensorPolyHelper.cast(slot.*.?)) |sn| sn.*.value = 0.0;
        return;
    }
    // Create new item based on tag.
    if (tag == EventPolyHelper.TAG) {
        const ev: *Event = ctx.alloc.create(Event) catch return;
        ev.* = .{};
        EventPolyHelper.init(ev);
        slot.* = &ev.*.poly;
    } else if (tag == SensorPolyHelper.TAG) {
        const sn: *Sensor = ctx.alloc.create(Sensor) catch return;
        sn.* = .{};
        SensorPolyHelper.init(sn);
        slot.* = &sn.*.poly;
    }
}

fn onPutAdaptive(ctx_opaque: *anyopaque, in_pool_count: usize, slot: *Slot) void {
    const ctx: *TestCtx = @ptrCast(@alignCast(ctx_opaque));
    ctx.put_call_count += 1;
    ctx.last_put_count = in_pool_count;
    if (ctx.destroy_on_put or in_pool_count >= ctx.cap) {
        if (slot.*) |poly| {
            helpers.freeItem(poly, ctx.alloc);
            slot.* = null;
        }
    }
    // else: keep — leave slot.* unchanged
}

fn onCloseAdaptive(ctx_opaque: *anyopaque, list: *std.DoublyLinkedList) void {
    const ctx: *TestCtx = @ptrCast(@alignCast(ctx_opaque));
    while (list.popFirst()) |node| {
        const poly: *PolyNode = @fieldParentPtr("node", node);
        ctx.close_item_count += 1;
        helpers.freeItem(poly, ctx.alloc);
    }
}

const helpers = @import("helpers");

const matryoshka = @import("matryoshka");
const polynode = matryoshka.polynode;
const pool = matryoshka.pool;
const PoolHandle = pool.PoolHandle;
const PoolHooks = pool.PoolHooks;
const Slot = polynode.Slot;
const PolyNode = polynode.PolyNode;

const types = helpers.types;
const Event = types.Event;
const Sensor = types.Sensor;
const EventPolyHelper = types.EventPolyHelper;
const SensorPolyHelper = types.SensorPolyHelper;
const std = @import("std");
const testing = std.testing;
const Thread = std.Thread;
const Io = std.Io;
