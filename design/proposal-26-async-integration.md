# Proposal 26: Mailbox and Pool as Event Sources for Io.Select

## Status: Accepted

**Date**: 2026-06-22

## Summary

Add event source helpers to `mbox` and `pool` modules so Mailbox and Pool become native participants in `Io.Select`. Since both already store `io: Io` internally, they can spawn concurrent tasks themselves.

Adds 4 functions + 2 types. No changes to existing synchronous API.

## Motivation

Current blocking APIs work well inside dedicated worker loops:

```zig
try mbox.receive(mbh, &item, null);
try pool.get_wait(ph, tag, &item, null);
```

But Zig 0.16 introduces `Io.Select` — a coordination model where a Master waits on multiple event sources simultaneously: mailbox traffic, timer, network, file operations, pool availability, shutdown signals.

Today, bridging Mailbox or Pool to Select requires per-application adapter functions. Every application writes the same code. Matryoshka can provide this.

Pool availability as an event is especially important: it enables the job-pool pattern (worker returns item → Master is notified → Master submits new work), which has no clean solution today.

## Design Decisions

### Decision 1: Variant 2 chosen — `receive_future` / `get_wait_future`

Two variants were proposed (from external AI review):

**Variant 1** (`mbox.concurrent(&select, .inbox, mbh, null)`) — rejected:
- Hard-wires one adapter per call — no flexibility
- Uses `anytype` for Select and tag parameters
- Makes Layer 2/3 reach up into Layer 4's Select union — inverts the layer dependency
- Reuses the name `concurrent` with different semantics from `io.concurrent`

**Variant 2** (`mbox.receive_future(mbh, null)` returning `Future`) — accepted:
- Returns a Future — caller decides how to use it (await, feed to Select, feed to Group)
- No `anytype` — fully concrete signatures
- Layer 2/3 remain self-contained — the caller (Layer 4) feeds the result to Select using stock Io API

### Decision 2: Cancel and Close are separate — cancel never triggers close

Cancel is an Io/scheduler operation (`error.Canceled` from Io runtime).
Close is a Master/application decision (`mbox.close` / `pool.close`).

An adapter must **never** close a mailbox or pool in response to cancel. That's the Master's responsibility.

This is consistent with:
- Rule 6: "Pool must NOT interpret CANCEL"
- 2-channel contract: "DATA ≠ Cancel. Do not conflate them."
- The same principle applies equally to Mailbox

This eliminates the `receiveOrClose` wrapper from the original proposal. There is **one adapter per operation**, not a policy choice.

### Decision 3: Result by value, not out-pointer

`mbox.receive` takes `m: *MayItem` — a pointer to the caller's variable. In the async case, a concurrent task writing through this pointer creates a cross-thread reference to stack memory: the worker runs on a different thread, the Master only learns the result when `select.await()` returns.

**The async result carries the item by value inside a tagged union.** No `*MayItem` parameter on the async path. The adapter creates a local `MayItem`, calls the blocking API, and packages the result into the union. The local never escapes the worker's stack.

This preserves Matryoshka's move semantics: the worker's local goes out of scope, the union field becomes the sole owner. When `select.await()` hands the Master the `.item`, the Master is sole owner with no aliasing.

### Decision 4: Symmetric result types

Both result types are symmetric — `.canceled` is `void` for both. No list payload, no policy variation. Cancel just reports.

```zig
// mbox.zig
pub const ReceiveResult = union(enum) {
    item: MayItem,
    closed: void,
    timeout: void,
    canceled: void,
};

// pool.zig
pub const PoolResult = union(enum) {
    item: MayItem,
    closed: void,
    timeout: void,
    canceled: void,
    not_created: void,
};
```

Tagged union (not error union) because:
- Select field types map cleanly to union arms
- The Master's `switch (event) { .inbox => |r| switch (r) {...} }` is exhaustive-checked
- Consistent with the ICE agent reference pattern

`PoolResult` omits `not_available` and `already_in_use`: `get_wait` blocks so `NotAvailable` doesn't arise on the wait path, and `AlreadyInUse` is a programming error (panic per Proposal 14).

### Decision 5: No `anytype`

The only comptime-generic boundary is `select.concurrent(.tag, mbox.receive_select, .{...})` — stock Io API the application already uses. The Matryoshka functions themselves are fully concrete.

Rule 7 ("Do NOT use `anytype` for polymorphism where tag dispatch covers the use case") does not technically apply here because Select is genuinely comptime-generic. However, Variant 2 avoids `anytype` entirely, making the point moot.

## API Addition

### Terminology

- **"event source"** replaces "leg" — each Select event source is a concurrent task
- **"adapter"** replaces "wrapper" — it's a format conversion, not a policy

### mbox module

```zig
pub const ReceiveResult = union(enum) {
    item: MayItem,
    closed: void,
    timeout: void,
    canceled: void,
};
```

```zig
pub fn receive_select(mbh: MailboxHandle, timeout_ns: ?u64) ReceiveResult
```
Adapter from error-union API to `ReceiveResult` for use as a Select event source. Creates a local `MayItem`, calls `mbox.receive`, maps the result to the union. Suitable for `select.concurrent(.tag, mbox.receive_select, .{mbh, timeout})`.

```zig
pub fn receive_future(mbh: MailboxHandle, timeout_ns: ?u64) ConcurrentError!Io.Future(ReceiveResult)
```
Spawns `receive_select` as a concurrent task using the mailbox's stored `io`. Returns a Future that can be awaited directly, fed to Select, or fed to Group. Returns `error.ConcurrencyUnavailable` on single-threaded backends.

### pool module

```zig
pub const PoolResult = union(enum) {
    item: MayItem,
    closed: void,
    timeout: void,
    canceled: void,
    not_created: void,
};
```

```zig
pub fn get_wait_select(ph: PoolHandle, tag: *const anyopaque, timeout_ns: ?u64) PoolResult
```
Adapter from error-union API to `PoolResult` for use as a Select event source. Creates a local `MayItem`, calls `pool.get_wait`, maps the result to the union. Suitable for `select.concurrent(.tag, pool.get_wait_select, .{ph, node_tag, timeout})`.

```zig
pub fn get_wait_future(ph: PoolHandle, tag: *const anyopaque, timeout_ns: ?u64) ConcurrentError!Io.Future(PoolResult)
```
Spawns `get_wait_select` as a concurrent task using the pool's stored `io`. Returns a Future. Returns `error.ConcurrencyUnavailable` on single-threaded backends.

### Cancel contract (additions)

| Function | Cancelable | Cancel-protected | Notes |
|----------|-----------|-----------------|-------|
| `mbox.receive_select` | yes | no | adapter — inherits from `mbox.receive` |
| `mbox.receive_future` | yes | no | spawns `receive_select` concurrently |
| `pool.get_wait_select` | yes | no | adapter — inherits from `pool.get_wait` |
| `pool.get_wait_future` | yes | no | spawns `get_wait_select` concurrently |

## Usage Patterns

### Select with multiple event sources

```zig
const Event = union(enum) {
    inbox: mbox.ReceiveResult,
    timer: void,
    pool: pool.PoolResult,
};

var select = Io.Select(Event).init(io);

try select.concurrent(.inbox, mbox.receive_select, .{ inbox, null });
try select.concurrent(.pool, pool.get_wait_select, .{ job_pool, JOB_TAG, null });
try select.concurrent(.timer, sleepWorker, .{ io, std.time.ns_per_s });

while (select.await()) |ev| switch (ev) {
    .inbox => |r| switch (r) {
        .item => |m| {
            processMessage(m);
            try select.concurrent(.inbox, mbox.receive_select, .{ inbox, null });
        },
        .closed => break,
        .canceled => break,
        .timeout => {},
    },
    .pool => |r| switch (r) {
        .item => |job| {
            submit(job);
            try select.concurrent(.pool, pool.get_wait_select, .{ job_pool, JOB_TAG, null });
        },
        .closed => break,
        .canceled => break,
        else => {},
    },
    .timer => {
        runMaintenance();
        try select.concurrent(.timer, sleepWorker, .{ io, std.time.ns_per_s });
    },
};
```

### Future awaited directly

```zig
const fut = try mbox.receive_future(inbox, null);
const result = fut.await(io);
switch (result) {
    .item => |m| processMessage(m),
    .closed => {},
    .canceled => {},
    .timeout => {},
}
```

### Job pool pattern (pool as event source)

Worker finishes a job, returns it to the pool:

```zig
pool.put(job_pool, &item);
```

Master is notified when a job buffer becomes available:

```zig
try select.concurrent(.pool, pool.get_wait_select, .{ job_pool, JOB_TAG, null });

// in the event loop:
.pool => |r| switch (r) {
    .item => |job| {
        fillJob(job);
        submitWork(job);
        // re-register for next availability
        try select.concurrent(.pool, pool.get_wait_select, .{ job_pool, JOB_TAG, null });
    },
    .closed => break,
    .canceled => break,
    else => {},
},
```

Note: the `.item` arm hands ownership to the Master. The `get_wait` that produced it has already removed the item from the pool. Re-spawn the event source only after deciding the item's fate.

### When to use Select vs fan-in mailbox

**Inside Matryoshka** — when items carry ownership, use fan-in: many senders send tagged PolyNodes to one mailbox, Master dispatches on tag. One queue, one ownership model, one shutdown model.

**Bridging to external Io** — use Select event sources: mailbox traffic alongside timers, sockets, files, or pool availability. Select is the composition point between Matryoshka and the rest of the Io world.

## Implementation Notes

### Internal pattern

```zig
pub fn receive_select(mbh: MailboxHandle, timeout_ns: ?u64) ReceiveResult {
    var item: MayItem = null;
    mbox.receive(mbh, &item, timeout_ns) catch |err| switch (err) {
        error.Canceled => return .{ .canceled = {} },
        error.Closed   => return .{ .closed = {} },
        error.Timeout  => return .{ .timeout = {} },
    };
    return .{ .item = item };
}

pub fn receive_future(mbh: MailboxHandle, timeout_ns: ?u64) ConcurrentError!Io.Future(ReceiveResult) {
    const self: *_Mbox = @fieldParentPtr("poly", mbh);
    return self.io.concurrent(receive_select, .{ mbh, timeout_ns });
}
```

Pool adapter is symmetric — `get_wait_select` calls `pool.get_wait`, maps errors to `PoolResult` arms.

### Thread cost

Each Select event source may consume a worker thread on the Threaded backend. This is a property of `Io.Select` and `io.concurrent`, not of Matryoshka. Developer decides when the cost is acceptable. Future backends (Evented, Uring) may behave differently.

### Single-threaded backends

`receive_future` / `get_wait_future` return `error.ConcurrencyUnavailable` on `global_single_threaded`. This is by design — async event sources need real concurrency. The synchronous API (`mbox.receive`, `pool.get_wait`) remains available for single-threaded use.

### Evented backend

Design is backend-independent: result-by-value ownership eliminates cross-thread pointer hazards regardless of backend. Only Threaded is tested in Zig 0.16.

## Relationship to Proposals 1-25

| Proposal | Relationship |
|----------|-------------|
| 3 (Timeout as `?u64`) | Adapters pass through `timeout_ns: ?u64` unchanged |
| 4 (Module-function style) | `mbox.receive_select`, `pool.get_wait_future` follow the convention |
| 6 (Handle param type) | Adapters take `MailboxHandle` / `PoolHandle` — same as core API |
| 7/18 (No dispose) | Result types use `MayItem`, not wrapped types — caller disposes |
| 13 (Handles are PolyNode items) | `receive_future` recovers `_Mbox` via `@fieldParentPtr("poly", mbh)` — handle is still a PolyNode |
| 17 (Diamond dependencies) | `ReceiveResult` lives in mbox, `PoolResult` in pool — independent siblings |
| 25 (Wrapper cancel policy) | **Superseded for cancel-close mixing.** Cancel never triggers close. Adapters are format converters, not policy. Proposal 25's insight about per-event-source flexibility is preserved: the caller can write custom adapters with any behavior they want and feed them to `select.concurrent` |
