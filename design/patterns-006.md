# Matryoshka Zig — Pattern Catalog (006)

Versioned doc. Replaces [patterns-005.md](patterns-005.md).
Reusable idioms confirmed in the examples and the API reference.
Companion: [rules-007.md](rules-007.md) — what is mandatory.
Companion: [matryoshka-model-003.md](matryoshka-model-003.md) — the thinking model.

How this doc differs from rules.
- Rules constrain. A rule says what you must or must not do.
- Patterns reuse. A pattern is a code shape that solves a recurring problem.
- A pattern is a suggestion grounded in working code, not a constraint.

How to use it.
- Find the topic. Read the "when to use" line.
- Copy the code shape. Adapt names to your domain.
- Open the referenced example for the full working version.

Each pattern lists: name, when to use, code shape, example reference.
Every example path is under `examples/` or `stories/`.

---

## Observable function shapes

Concrete templates for the "Observable by human" MUST rule. See [rules-007.md](rules-007.md).

### Coordinator / run

When to use.
- Any function that sequences discrete steps: `pub fn run`, a Master's `run`, any sequencing method.

Code shape.
```zig
fn run(self: *Master) !void {
    try self.seedResources();
    try self.eventLoop();
    self.gracefulShutdown();
    try helpers.expect(error.XFailed, self.count > 0, "expected items");
    std.log.info("done: {d} processed", .{self.count});
}
```

- Dominant structure: calls to named step functions.
- Simple glue (a guard, a `helpers.expect`, a `std.log.info`) stays inline.
- No inline logic blocks with distinct purpose — those are extracted to named steps.

Example: `examples/layer4/031-select_graceful_shutdown.zig`.

### Step function

When to use.
- Any function that implements one discrete phase of the coordinator.

Code shape.
```zig
fn seedResources(self: *Master) !void {
    for (0..N) |i| {
        var slot: Slot = null;
        defer types.EventPolyHelper.destroy(self.allocator, &slot);
        try types.EventPolyHelper.create(self.allocator, &slot);
        types.EventPolyHelper.cast(slot.?).?.code = @intCast(i + 1);
        try mailbox.send(self.mbh, &slot);
    }
}
```

- Each step implements one thing. Name = documentation.
- `var`/`const` declarations are fine.
- Loops are one unit at their scope level.

Example: `examples/layer4/031-select_graceful_shutdown.zig`.

### Init

When to use.
- Allocating a Master struct and acquiring its resources.

Code shape.
```zig
fn init(allocator: std.mem.Allocator, io: std.Io) !*Master {
    const self = try allocator.create(Master);
    errdefer allocator.destroy(self);
    self.allocator = allocator;
    self.io = io;
    self.mbh = try mailbox.new(io, allocator);
    errdefer {
        var rem = mailbox.close(self.mbh);
        helpers.freeList(&rem, allocator);
        mailbox.destroy(self.mbh, allocator);
    }
    self.ph = try pool.new(io, allocator, &self.pool_ctx, pool_hooks);
    return self;
}
```

- Allocate first, guard with `errdefer allocator.destroy`.
- Acquire each resource, guard with `errdefer` for that resource.
- Return `self` last.

Example: `examples/layer4/018-master_with_pool.zig`.

### Destroy

When to use.
- Releasing a Master struct and its resources.

Code shape.
```zig
fn destroy(self: *Master) void {
    var rem: std.DoublyLinkedList = mailbox.close(self.mbh);
    helpers.freeList(&rem, self.allocator);
    mailbox.destroy(self.mbh, self.allocator);
    pool.close(self.ph);
    pool.destroy(self.ph, self.allocator);
    self.allocator.destroy(self);
}
```

- Release resources in reverse acquisition order.
- Free the allocation last.

Example: `examples/layer4/018-master_with_pool.zig`.

### Coordinator with Select event loop (flat file)

When to use.
- A flat `pub fn run` (no Master struct) that owns an `Io.Select` event loop.
- `buf` and `sel` are declared at coordinator scope; passed as `*Sel` (transient) to step functions.
- Use when the file has 1-2 coordinator-scope params (explicit passing) or 3+ params (introduce a local Ctx struct).

Code shape (explicit params, 1-2 shared values).
```zig
const Sel = std.Io.Select(MasterEvent);

pub fn run(allocator: std.mem.Allocator, io: std.Io) !void {
    const ph: PoolHandle = try pool.new(io, allocator, &pool_ctx, pool_hooks);
    defer pool.destroy(ph, allocator);

    try seedPool(ph, allocator);

    var buf: [8]MasterEvent = undefined;
    var sel: Sel = Sel.init(io, &buf);
    try setupSelect(ph, io, &sel);
    try runEventLoop(ph, io, &sel);

    try helpers.expect(error.XFailed, ...);
    std.log.info("done", .{});
}

fn setupSelect(ph: PoolHandle, io: std.Io, sel: *Sel) !void {
    const sleep_t: std.Io.Timeout = .{ .ns = 100_000_000 };
    try sel.concurrent(.pool_ev, pool.getWaitResult, .{ ph, TAG, null });
    try sel.concurrent(.timer, sleepFn, .{ sleep_t, io });
}

fn runEventLoop(ph: PoolHandle, io: std.Io, sel: *Sel) !void {
    while (true) {
        const event: MasterEvent = try sel.await();
        switch (event) {
            .pool_ev => |r| switch (r) {
                .item => |handle| {
                    // process handle
                    pool.put(ph, &(var s: Slot = handle; &s));
                    try sel.concurrent(.pool_ev, pool.getWaitResult, .{ ph, TAG, null });
                },
                .closed, .canceled, .not_created => break,
                .timeout => {},
            },
            .timer => break,
        }
    }
    sel.cancelDiscard();
}
```

Code shape (3+ shared values — local Ctx struct, stack-allocated).
```zig
const Ctx = struct {
    mbh: MailboxHandle,
    alloc: std.mem.Allocator,
    io: std.Io,

    fn setupSelect(self: *Ctx, sel: *Sel) !void { ... }
    fn runEventLoop(self: *Ctx, sel: *Sel) !void { ... }
};

pub fn run(allocator: std.mem.Allocator, io: std.Io) !void {
    const mbh: MailboxHandle = try mailbox.new(io, allocator);
    defer { ... }

    var ctx: Ctx = .{ .mbh = mbh, .alloc = allocator, .io = io };

    var buf: [8]MasterEvent = undefined;
    var sel: Sel = Sel.init(io, &buf);
    try ctx.setupSelect(&sel);
    try ctx.runEventLoop(&sel);
}
```

- `setupSelect` owns timeout construction and initial `concurrent` registrations.
- `runEventLoop` owns the loop body, re-registrations, and final `cancelDiscard`.
- `buf` and `sel` are declared at coordinator scope; passed as `*Sel` to steps.
- Ctx is stack-allocated (`var ctx: Ctx = .{...}`). No heap allocation.
- Methods declared inside the Ctx struct body (`fn setupSelect(self: *Ctx, ...) !void`).

Examples: `examples/layer4/046-select_pool_event.zig`, `examples/layer4/028-select_mixed_sources.zig`.

### Coordinator with spawn + await (flat file)

When to use.
- A flat `pub fn run` that spawns concurrent workers (`io.concurrent`, `group.concurrent`, `Thread.spawn`) and awaits them.
- The spawn block and the await block together form one named step.

Code shape (single spawn+await step).
```zig
pub fn run(allocator: std.mem.Allocator, io: std.Io) !void {
    const mbh: MailboxHandle = try mailbox.new(io, allocator);
    defer { ... }

    try seedMailbox(mbh, allocator);
    try spawnAndAwaitWorkers(mbh, allocator, io);

    try helpers.expect(error.XFailed, ...);
    std.log.info("done", .{});
}

fn spawnAndAwaitWorkers(mbh: MailboxHandle, alloc: std.mem.Allocator, io: std.Io) !void {
    var ctx1: WorkerCtx = .{ .mbh = mbh, .alloc = alloc };
    var ctx2: WorkerCtx = .{ .mbh = mbh, .alloc = alloc };
    var fut1 = try io.concurrent(workerFn, .{&ctx1});
    var fut2 = try io.concurrent(workerFn, .{&ctx2});
    try fut1.await(io);
    try fut2.await(io);
}
```

Code shape (separate spawn and await steps).
```zig
fn spawnWorkers(mbh: MailboxHandle, alloc: std.mem.Allocator, io: std.Io, group: *std.Io.Group) !void {
    for (0..N_WORKERS) |i| {
        group.concurrent(io, workerFn, .{ &worker_ctxs[i] }) catch return error.SpawnFailed;
    }
}

fn awaitWorkers(mbh: MailboxHandle, alloc: std.mem.Allocator, io: std.Io, group: *std.Io.Group) !void {
    try group.await(io);
    // verify results
}
```

- ctx declarations, spawns, and awaits all live inside the named step — not inline in the coordinator.
- Coordinator sees one or two calls. Flow is visible without opening the step.
- If spawn and await are tightly coupled (no coordinator logic between them), merge into one step.
- If coordinator logic falls between spawn and await, use two steps.

Examples: `examples/layer4/017-minimal_master.zig`, `examples/layer4/054-pool_fan_out.zig`.

---

## Pool patterns

### Pool mode — .available_or_new

When to use.
- The common case: reuse a stored item if one is free, otherwise create a fresh one.

Code shape.
```zig
var slot: Slot = null;
defer pool.put(ph, &slot);
try pool.get(ph, EventPolyHelper.TAG, .available_or_new, &slot);
```

- `on_get` runs every call. If `slot.*` is non-null it was recycled — reinitialize. If null, create.

Example: `examples/layer4/018-master_with_pool.zig`.

### Pool mode — .new_only

When to use.
- Seeding. You want a fresh item every time, never a stored one.

Code shape.
```zig
var slot: Slot = null;
try pool.get(ph, EventPolyHelper.TAG, .new_only, &slot);
// fill the new item
pool.put(ph, &slot);
```

Example: `examples/layer3/pool_seeding.zig`.

### Pool mode — .available_only

When to use.
- Consume what is stored. Stop when the pool is empty.
- Empty pool returns `error.NotAvailable` — a normal end condition, not a failure.

Code shape.
```zig
var slot: Slot = null;
pool.get(ph, EventPolyHelper.TAG, .available_only, &slot) catch |err| switch (err) {
    error.NotAvailable => break,
    else => return err,
};
```

Example: `examples/layer3/pool_seeding.zig`.

### Seeding pattern

When to use.
- A fixed-size pool. Pool capacity is set once at startup, no on-demand creation.

Code shape.
```zig
for (0..N_BUFFERS) |_| {
    var slot: Slot = null;
    try VideoBufferPolyHelper.create(allocator, &slot);
    pool.put(ph, &slot);
}
```

- Pair with `on_get` that does nothing — the pool never grows past the seed count.
- The fixed count becomes the backpressure limit.

Example: `stories/video_transcoder/video_transcoder.zig`.

### Backpressure via getWaitResult in Select

When to use.
- A producer must slow down when no buffers are free.
- Pool availability becomes an event source in the same loop as data.

Code shape.
```zig
try sel.concurrent(.buf_ev, pool.getWaitResult, .{ buf_ph, VideoBufferPolyHelper.TAG, null });
// ...
const ev = try sel.await();
switch (ev) {
    .buf_ev => |r| switch (r) {
        .item => |handle| {
            // fill buffer, route it, then re-register for the next free buffer
            try sel.concurrent(.buf_ev, pool.getWaitResult, .{ buf_ph, VideoBufferPolyHelper.TAG, null });
        },
        .closed, .canceled, .timeout, .not_created => break,
    },
}
```

- The loop blocks until a worker returns a buffer.
- No sleep. No poll. The pool wakes the waiter.

Example: `stories/video_transcoder/video_transcoder.zig`.

### on_get and on_put hooks

When to use.
- `on_get`: decide how an item is created or reinitialized.
- `on_put`: decide whether a returned item is kept or destroyed (cap policy).

Code shape.
```zig
fn onGet(_: *anyopaque, _: *const anyopaque, _: usize, _: *Slot) void {}        // fixed-size: never create
fn onPut(_: *anyopaque, _: usize, _: *Slot) void {}                              // keep all
```

- `on_put`: set `slot.* = null` to destroy; leave non-null to keep.
- Hooks run outside the pool lock. Multiple threads may call them at once. Protect shared state with `Io.Mutex.lockUncancelable`.

Example: `examples/layer3/capped_pool.zig` (cap policy), `helpers/helpers.zig` `CappedPoolCtx` (thread-safe reference).

### on_close hook

When to use.
- Free all stored items when the pool shuts down.

Code shape.
```zig
fn onClose(ctx: *anyopaque, list: *std.DoublyLinkedList) void {
    const self: *VideoBufCtx = @ptrCast(@alignCast(ctx));
    while (list.popFirst()) |node| {
        const poly: *polynode.PolyNode = @fieldParentPtr("node", node);
        polynode.reset(poly);
        var s: Slot = poly;
        VideoBufferPolyHelper.destroy(self.alloc, &s);
    }
}
```

- Always call `polynode.reset(poly)` after `popFirst` before destroy.

Example: `examples/layer3/pool_teardown.zig`, `stories/video_transcoder/video_transcoder.zig`.

---

## Io.Select patterns

### Event loop — register, await, re-register

When to use.
- Wait on several sources at once: mailbox, pool, timer, external push.

Code shape.
```zig
var buf: [8]MasterEvent = undefined;
var sel: std.Io.Select(MasterEvent) = std.Io.Select(MasterEvent).init(io, &buf);

try sel.concurrent(.inbox, mailbox.receiveResult, .{ mbh, null });
try sel.concurrent(.pool_ev, pool.getWaitResult, .{ ph, TAG, null });
try sel.concurrent(.timer, sleepFn, .{ sleep_t, io });

while (true) {
    const event: MasterEvent = try sel.await();
    switch (event) {
        .inbox => |r| switch (r) {
            .item => |handle| {
                // process, then re-register the source
                try sel.concurrent(.inbox, mailbox.receiveResult, .{ mbh, null });
            },
            .closed, .canceled, .timeout => break,
        },
        // ...
    }
}
```

- Re-register the source after each item. A source delivers one result per `concurrent` call.

Example: `examples/layer4/031-select_graceful_shutdown.zig`, `examples/layer4/028-select_mixed_sources.zig`.

### Direct push — putOneUncancelable

When to use.
- A result is already available, or an external thread or callback must inject one without spawning.

Code shape.
```zig
select.queue.putOneUncancelable(select.io, .{ .field = value }) catch {};
```

Example: `examples/layer4/043-select_direct_push.zig`.

### Graceful cancel walk — recover in-flight items

When to use.
- Shutting down a Select loop. Spawned sources may still hold items. None must leak.

Code shape.
```zig
while (sel.cancel()) |event| {
    switch (event) {
        .inbox => |r| switch (r) {
            .item => |handle| {
                var slot: Slot = handle;
                helpers.freeSlot(&slot, allocator);   // recover the item
            },
            .canceled, .closed, .timeout => {},
        },
        .pool_ev => |r| switch (r) {
            .item => |handle| {
                var slot: Slot = handle;
                pool.put(ph, &slot);                   // recycle it
            },
            .canceled, .closed, .timeout, .not_created => {},
        },
        .timer => {},
    }
}
```

Example: `examples/layer4/031-select_graceful_shutdown.zig`.

### cancelDiscard — timer-only or no-item sources

When to use.
- The remaining spawned sources carry no owned item (e.g. a timer). Discard them.

Code shape.
```zig
sel.cancelDiscard();
```

Example: `stories/video_transcoder/video_transcoder.zig`.

---

## Io.Group patterns

### Worker set — concurrent then await

When to use.
- Run several workers. Wait for all to finish.

Code shape.
```zig
var group: Io.Group = .init;
try group.concurrent(io, workerFn, .{&ctx0});
try group.concurrent(io, workerFn, .{&ctx1});
try group.await(io);
```

- Worker return type must coerce to `Cancelable!void`.

Example: `stories/video_transcoder/video_transcoder.zig`.

### Shutdown signal — close the source mailbox

When to use.
- Stop a Group of workers that block on `mailbox.receive`.

Code shape.
```zig
// workers exit when receive returns error.Closed
var rem: std.DoublyLinkedList = mailbox.close(ready_queue);
// walk rem, recover any unreceived items
try group.await(io);
```

- Close is the end-of-stream signal. Workers return on `error.Closed`.

Example: `stories/video_transcoder/video_transcoder.zig`.

### Shutdown signal — group.cancel

When to use.
- Stop a Group of workers that block on `pool.get_wait`, with no mailbox to close.

Code shape.
```zig
group.cancel(io);   // injects error.Canceled into all blocked workers, then waits
```

- Blocked workers return `error.Canceled`. A worker that already finished is unaffected.

Example: `examples/layer4/059-mailbox_less_pool_group_workers.zig`.

---

## Graceful shutdown sequence

When to use.
- Tearing down a Master that owns workers, mailboxes, and a pool.

Mandatory order.
1. Stop the producer loop (the Select Master). Stop registering new work.
2. Close the mailbox that feeds the workers. This signals end-of-stream.
3. Walk the mailbox close list. Recover or recycle every item it returns.
4. `group.await(io)` — wait for all workers to finish their current item.
5. Destroy the worker mailbox.
6. Close any downstream mailbox (e.g. storage). Its task exits on `error.Closed`.
7. Await the downstream task. Destroy its mailbox.
8. `pool.close` — `on_close` frees all stored items.
9. `pool.destroy`.

Why this order.
- Close upstream before awaiting workers, or workers block forever.
- Await workers before closing the pool, or a worker returns an item to a closed pool.
- A pool returns the item to the caller when closed — the worker must free it as a fallback.

Code shape (worker fallback for closed pool).
```zig
pool.put(ctx.buf_ph, &sc.buffer_slot);
if (sc.buffer_slot != null) {
    VideoBufferPolyHelper.destroy(ctx.alloc, &sc.buffer_slot);
}
```

Example: `stories/video_transcoder/video_transcoder.zig`, `examples/layer4/037-cross_layer_close_mailbox_then_pool.zig`.

---

## Polymorphic dispatch

When to use.
- One mailbox or one list carries more than one item type. The receiver recovers the concrete type.

Code shape.
```zig
if (EventPolyHelper.cast(handle)) |ev| {
    // handle Event
} else if (ShutdownCommandPolyHelper.cast(handle)) |_| {
    // handle ShutdownCommand
} else {
    // unknown — free and move on
}
```

- `cast` returns null on a tag mismatch. Chain casts for each known type.
- Tag identifies class, not instance. Use a `kind`/`role` field or pointer comparison for instance identity.

Example: `examples/layer4/031-select_graceful_shutdown.zig`, `examples/layer4/033-cross_layer_mixed_types_mailbox.zig`.

---

## Error handling on receive

When to use.
- A worker blocks on `mailbox.receive` or `pool.get_wait` and must react to each outcome.

Code shape.
```zig
mailbox.receive(ctx.mbh, &slot, null) catch |err| switch (err) {
    error.Canceled => return error.Canceled,   // report up — Master decides
    error.Closed, error.Timeout => return,      // end-of-stream — exit cleanly
};
```

The distinction.
- `error.Canceled` — external stop signal. Propagate it. Do not close anything.
- `error.Closed` — the Master closed the source. End of stream. Exit.
- `error.Timeout` — the wait window passed. Treat per domain.
- Never remap `error.Canceled` to `error.Closed`. They mean different things.

Example: `stories/video_transcoder/video_transcoder.zig`, `examples/layer4/059-mailbox_less_pool_group_workers.zig`.

---

## Master composition

When to use.
- A story or service has more than one coordination boundary.

The shape.
- Each Master owns its resources and coordinates their lifecycle.
- A Master is a state struct plus a loop function — not inlined into `run`.
- `run` is thin: initialize resources, start Masters, await shutdown in order.

Two Masters in the pilot story.
- Network Master — an `Io.Select` loop. Owns the buffer pool as a backpressure source. Fills buffers, routes `StreamContext` to the ready queue.
- Worker set — an `Io.Group`. Each worker receives a `StreamContext`, encodes, returns the buffer to the pool, sends an `EncodedSegment` to storage.
- Storage task — a single-mailbox loop. Receives `EncodedSegment`, logs, frees.

Code shape (thin run).
```zig
pub fn run(allocator: std.mem.Allocator, io: std.Io) !void {
    // 1. initialize shared resources: pool, mailboxes
    // 2. start Masters: storage task, worker group, network loop
    // 3. await shutdown in mandatory order
}
```

- The coordination logic of each Master lives in its own function.
- `run` shows the startup order and the shutdown order — nothing else.

Example: `stories/video_transcoder/video_transcoder.zig`.


# Matryoshka Zig — Pattern Catalog (002)

Additional reusable patterns extracted from the API reference.
They are grouped from the simplest ownership idioms to higher-level Io integration.

---

# Ownership patterns

## Empty Slot initialization

When to use.
- Every ownership acquisition.

Code shape.

```zig
var slot: Slot = null;
```

Why.
- Every acquisition API requires an empty slot.
- Passing a non-null slot is a programming error.

---

## Slot overwrite prevention

When to use.
- Before every receive/get/create operation.

Pattern.

```zig
std.debug.assert(slot.* == null);
```

Why.
- A slot always owns exactly one object.
- Overwriting a non-null slot loses ownership.

---

## Transfer clears ownership

When to use.
- Every ownership transfer.

Code shape.

```zig
try mailbox.send(mbh, &slot);

// slot == null
```

or

```zig
pool.put(ph, &slot);

// slot == null if accepted by pool
```

Why.
- Sender no longer owns the object.
- Cleanup code becomes naturally safe.

---

## Null-safe cleanup

When to use.
- Every deferred cleanup.

Code shape.

```zig
defer pool.put(ph, &slot);
```

or

```zig
defer EventPolyHelper.destroy(allocator, &slot);
```

Why.
- Cleanup helpers ignore null slots.
- Cleanup may safely execute after transfer.

---

## Acquire-after-defer

When to use.
- Resource acquisition.

Code shape.

```zig
var slot: Slot = null;

defer pool.put(ph, &slot);

try pool.get(ph, TAG, .available_or_new, &slot);
```

Why.
- Failure path.
- Success path.
- Ownership transfer.
- All become correct automatically.

---

## Fallback destroy after pool.put

When to use.
- Pool may already be closed.

Code shape.

```zig
defer EventPolyHelper.destroy(allocator, &slot);
defer pool.put(ph, &slot);
```

Why.
- Pool receives the item if open.
- Destroy executes only if ownership remained with caller.

---

# PolyNode patterns

## PolyHelper everywhere

When to use.
- Every PolyNode type.

Code shape.

```zig
pub const EventPolyHelper =
    polynode.PolyHelper(Event);
```

Why.
- Eliminates manual tag management.
- Eliminates unsafe casts.
- Eliminates initialization boilerplate.

---

## Safe polymorphic cast

When to use.
- Recovering a concrete type.

Code shape.

```zig
if (EventPolyHelper.cast(handle)) |ev| {
    ...
}
```

Why.
- Tag check and cast are combined.
- Wrong types return null.

---

## Tag identifies the class

When to use.
- Runtime dispatch.

Pattern.

```
tag
    ↓
type
```

Not

```
tag
    ↓
instance
```

Use.
- Pointer comparison for infrastructure handles.
- User fields (`kind`, `role`) for application roles.

---

## Wrapper type for infrastructure handles

When to use.
- Mailbox or Pool must participate in polymorphic dispatch.

Code shape.

```zig
const WorkerInbox = struct {
    poly: PolyNode,
    handle: mailbox.MailboxHandle,
};
```

Why.
- Wrapper has its own PolyHelper tag.
- Enables normal type dispatch.

---

## Mailbox-as-message

When to use.
- Returning ownership of communication endpoints.

Pattern.

```
Worker
    │
returns MailboxHandle
    │
Master receives mailbox
```

Typical use.
- Worker completion notification.
- Dynamic topology construction.
- Channel migration.

---

## Pool-as-message

When to use.
- Sharing lifecycle managers.

Pattern.

```
PoolHandle
    ↓
mailbox.send()
```

Why.
- PoolHandle is itself a PolyNode.

---

# Mailbox patterns

## Try-receive polling

When to use.
- Non-blocking work loop.

Code shape.

```zig
if (try mailbox.try_receive(mbh, &slot)) {
    ...
}
```

---

## Batch receive

When to use.
- Drain an entire mailbox.

Code shape.

```zig
var list = try mailbox.receive_batch(mbh);

while (list.popFirst()) |node| {
    ...
}
```

Why.
- Reduces synchronization overhead.
- Natural bulk processing.

---

## Out-of-band priority

When to use.
- Shutdown.
- Urgent control messages.

Code shape.

```zig
try mailbox.send_oob(mbh, &slot);
```

Why.
- OOB messages always precede normal traffic.
- FIFO inside the OOB region.

---

## Mailbox close recovery

When to use.
- Shutdown.

Code shape.

```zig
var list = mailbox.close(mbh);

while (list.popFirst()) |node| {
    ...
}
```

Why.
- Recover every queued object.
- Nothing leaks.

---

# Pool patterns

## Pool as lifecycle policy

When to use.
- Object reuse.

Pattern.

```
on_get
    ↓
create or reinitialize

on_put
    ↓
keep or destroy
```

Why.
- Allocation policy stays outside business logic.

---

## Hook decision pattern

When to use.
- Pool hooks.

Pattern.

```
slot == null
    ↓
create

slot != null
    ↓
reuse
```

---

## Hook outside lock

When to use.
- Shared hook state.

Pattern.

```zig
lockUncancelable()

...modify shared state...

unlock()
```

Why.
- Hooks execute concurrently.
- Pool does not serialize hook execution.

---

## Multi-tag pool

When to use.
- Pool stores multiple object types.

Pattern.

```
Pool
 ├── Event
 ├── Buffer
 └── Command
```

Why.
- One lifecycle manager.
- Separate free lists per tag.

---

# Future patterns

## Direct Future

When to use.
- Only one asynchronous operation.

Code shape.

```zig
const future =
    try mailbox.receive_future(mbh, null);

const result =
    try future.await(io);
```

---

## Future cancellation

When to use.
- Abort one asynchronous operation.

Code shape.

```zig
try future.cancel(io);
```

Why.
- Ownership stays in mailbox/pool.
- Only the wait is canceled.

---

# Io.Select patterns

## Mailbox as event source

When to use.
- Event-driven Master.

Code shape.

```zig
try select.concurrent(
    .mailbox,
    mailbox.receiveResult,
    .{ mbh, null },
);
```

---

## Pool as event source

When to use.
- Wait for reusable objects.

Code shape.

```zig
try select.concurrent(
    .pool,
    pool.getWaitResult,
    .{ ph, TAG, null },
);
```

---

## Mixed event sources

When to use.
- One loop coordinates everything.

Pattern.

```
Mailbox
Pool
Timer
Socket
External callback
        │
        ▼
    Io.Select
```

---

## One-shot event registration

When to use.
- Every Select source.

Pattern.

```
register
    ↓
await
    ↓
process
    ↓
register again
```

Why.
- Each registration produces exactly one completion.

---

# Io.Group patterns

## Fire-and-forget worker launch

When to use.
- Spawn worker without immediate wait.

Code shape.

```zig
try group.concurrent(
    io,
    workerFn,
    .{ &ctx },
);
```

Later.

```zig
try group.await(io);
```

---

## Reusable Group

When to use.
- Multiple execution rounds.

Pattern.

```
spawn
await

spawn
await
```

Why.
- Group may be reused after completion.

---

# Cancellation patterns

## Cancellation boundary

When to use.
- Designing APIs.

Rule.

Only waiting operations are cancelable.

Examples.

- mailbox.receive
- pool.get_wait
- receiveResult
- getWaitResult

Everything else completes normally.

---

## Cancellation preserves ownership

When to use.
- Recovering after cancellation.

Pattern.

```
Canceled
    ↓
slot unchanged
    ↓
resource still owned by mailbox/pool
```

---

## Close versus Cancel

Pattern.

```
Close
    ↓
end of stream

Cancel
    ↓
stop waiting
```

Never substitute one for the other.

---

# Integration patterns

## Mailbox + Pool

Pattern.

```
Pool
   │
 get
   │
 work
   │
send
   │
Mailbox
```

Purpose.
- Separate lifecycle from transport.

---

## Full Layer-4 architecture

Pattern.

```
          Io.Select
               │
      ┌────────┴────────┐
      │                 │
  Mailbox          Pool events
      │                 │
      └────────┬────────┘
               │
            Master
               │
         Io.Group workers
```

Purpose.
- Event-driven coordination.
- Worker parallelism.
- Ownership-safe transport.
- Automatic backpressure.
