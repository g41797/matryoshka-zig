# Matryoshka in Zig 0.16 — Implementation Guide

**Scope**: Feasibility, design decisions, and risks for porting Matryoshka (Odin) to Zig 0.16.0
**Sources**: Odin source files, `kitchen/docs`, `examples/block1-4`, Zig 0.16 stdlib
**Date**: 2026-06-22

Reading path:

```text
0  Header + reading path
1  What you are building
2  Zig 0.16 — hard constraints        ← read first; the rest assumes it
3  Block 1 — PolyNode + MayItem
4  Block 2 — Mailbox (_Mbox)
5  Block 3 — Pool (_Pool)
6  Block 4 — Infrastructure as Items
7+ Cancellation, shutdown, idioms     (Part 2)
```

For architecture and rationale → `matryoshka-architecture-foundation-4.md`.

For exact API signatures → `matryoshka-api-reference.md`.

---

# 1. What You Are Building

Matryoshka is an ownership-transfer and lifecycle system.

It is not an I/O framework.

`std.Io` carries the wait operations. It controls how suspension happens, not what it means.

- Mailbox transfers ownership. It is not a stream.
- Pool manages lifecycle. It is not an Io primitive.

The system is four blocks:

- **Block 1 — PolyNode + MayItem.** The ownership atom. A node plus an optional pointer.
- **Block 2 — Mailbox.** Moves ownership between contexts. FIFO with an OOB front.
- **Block 3 — Pool.** Recycles items by tag. Hooks decide fate.
- **Block 4 — Infrastructure as Items.** Mailboxes and pools are themselves PolyNodes.

Build order:

```text
Block 1
   ↓
Block 2  ∥  Block 3      (independent; build in parallel)
   ↓
Block 4
   ↓
Master    (composes the rest)
```

Verdict: this port is viable. Every concept maps.

---

# 2. Zig 0.16 — What It Provides and Removes

Read this section first. It is a set of hard constraints, not advice.

## 2.1 std.Io is the concurrency interface

`std.Io` in 0.16 is not narrow "bytes from files" I/O.

It is the complete concurrency and scheduling interface: file system, networking, processes, time, mutexes, futexes, events, conditions.

`Io.Mutex` and `Io.Condition` are real types. They are not wrappers around `std.Thread.Mutex/Condition`. They are backed by `io.futexWait` through the vtable:

```zig
// Io.Mutex.lock — takes io, returns Cancelable
pub fn lock(m: *Mutex, io: Io) Cancelable!void {
    ...
    try io.futexWait(State, &m.state.raw, .contended);
}

// Io.Condition.wait — takes io, returns Cancelable
pub fn wait(cond: *Condition, io: Io, mutex: *Mutex) Cancelable!void {
    ...
    try io.futexWait(u32, &cond.epoch.raw, epoch);
}
```

Consequences:

- Every wait is a cancellation point returning `Cancelable!void`.
- `_Mbox` and `_Pool` must use `Io.Mutex` and `Io.Condition`.
- All `std.Thread.*` synchronization primitives were removed in 0.16.0.

## 2.2 Removed primitives — hard constraint

These do not exist in `std.Thread` anymore. Confirmed: `grep "pub" Thread.zig` returns zero matches for any of them.

| Removed | Replacement |
|---------|------------|
| `Thread.Mutex` | `Io.Mutex` |
| `Thread.Condition` | `Io.Condition` |
| `Thread.Futex` | `Io.Futex` |
| `Thread.ResetEvent` | `Io.Event` |
| `Thread.WaitGroup` | `Io.Group` |
| `Thread.Semaphore` | `Io.Semaphore` |
| `Thread.RwLock` | `Io.RwLock` |
| `Thread.Pool` | `Io.Group` + `io.concurrent()` |
| `Thread.Mutex.Recursive` | (no replacement — design smell) |

`std.Thread.spawn` and `std.Thread.join` still exist. Only the sync primitives and thread pool are gone.

This is not a recommendation. "Must not use" now means "does not exist."

`std.Thread.Mutex/Condition` would not go through the IO vtable and could not return `error.Canceled`. They must never appear in `_Mbox` or `_Pool`.

## 2.3 Two backends

```text
Io.Threaded   OS threads + futex.        Production-ready.   ← target this
Io.Evented    fibers (green threads).    Work in progress.   Not production-ready.
```

`_Mbox` and `_Pool` are correct for both backends — all blocking goes through the IO vtable.

The `Io.Evented` backend itself is incomplete in 0.16.0. Target `Io.Threaded` for production.

For tests, use the single-threaded backend (confirmed `Threaded.zig` line 1704):

```zig
const io = std.Io.Threaded.global_single_threaded.io();
```

## 2.4 Task spawning

Two IO-native spawning APIs (confirmed `Io.zig` lines 2326, 2365):

```zig
// io.async — may run eagerly (single-threaded: runs to completion inline)
pub fn async(io: Io, function: anytype, args: ...) Future(ReturnType)

// io.concurrent — requires actual concurrency (else ConcurrentError)
pub fn concurrent(io: Io, function: anytype, args: ...) ConcurrentError!Future(ReturnType)
```

`Future(T)` has two methods (`Io.zig` lines 1191, 1199):

```zig
pub fn cancel(f: *Future(T), io: Io) T  // request cancelation, then await
pub fn await(f: *Future(T), io: Io)  T  // await completion without cancelation
```

`Future.cancel(io)` injects `error.Canceled` at the worker's next cancellation point — the next `Io` call returning `Cancelable!void`.

`Io.Group` manages a set of concurrent tasks (confirmed `Io.zig` line 1218):

```zig
pub const Group = struct {
    pub fn async(g: *Group, io: Io, function: anytype, args: ...) void
    pub fn concurrent(g: *Group, io: Io, function: anytype, args: ...) ConcurrentError!void
    pub fn await(g: *Group, io: Io) Cancelable!void     // wait for all
    pub fn cancel(g: *Group, io: Io) void               // cancel all, then await
};
```

`Io.Group` is the idiomatic replacement for `Thread.Pool` + `Thread.WaitGroup`. For a Master managing multiple workers, prefer `Io.Group`.

## 2.5 Container migration

0.16.0 moves all growable containers to the unmanaged variant — the allocator is passed per operation, not stored in the struct.

| Old name | Status | Use instead |
|----------|--------|-------------|
| `ArrayHashMap` | removed | — |
| `AutoArrayHashMap` | removed | — |
| `StringArrayHashMap` | removed | — |
| `ArrayListUnmanaged` | deprecated alias | `ArrayList` (now IS unmanaged) |
| `array_list.Managed` | deprecated | `ArrayList` |
| `AutoHashMap` | still exists (managed) | prefer `AutoHashMapUnmanaged` |
| `AutoHashMapUnmanaged` | current | use this |
| `ArrayList` | current — IS unmanaged | use this |

`_Pool` uses `std.AutoHashMapUnmanaged`. Init with `.empty`. All mutating ops take the allocator explicitly:

```zig
var m: std.AutoHashMapUnmanaged(K, V) = .empty;
try m.put(alloc, key, value);   // allocator is the first arg
m.deinit(alloc);                // allocator required
```

`getPtr(key)` and `get(key)` are read-only — no allocator needed.

## 2.6 Known gaps

**No `Io.Condition.waitTimeout`** (open issue codeberg/zig#31278).

Use `condition_waitTimeout` from the reference implementation. It calls `io.futexWaitTimeout` directly. Both `mbox_receive` and `pool_get_wait` depend on it.

**Tests use `global_single_threaded`** — see 2.3.

**`heap.ThreadSafeAllocator` removed** as an anti-pattern. Allocators are expected to be thread-safe on their own. `heap.ArenaAllocator` is thread-safe and lock-free by default.

`_Mbox` and `_Pool` store `alloc` at init. Callers must pass a thread-safe allocator if `create`/`destroy` run from multiple threads. Matryoshka does not wrap allocators.

---

# 3. Block 1 — PolyNode + MayItem

Zig types first. Odin reference is one line.

> Odin uses `using` at offset 0. Zig uses `@fieldParentPtr`. See Appendix for full mapping.

## Types

```zig
pub const PolyTag = struct { _: u8 = 0 };
pub const PolyNode = struct {
    node: std.DoublyLinkedList.Node,  // embedded linked list node
    tag:  *const anyopaque,
};
pub const MayItem = ?*PolyNode;
```

Tags are unique addresses. Each `const foo_tag = PolyTag{}` has a distinct address:

```zig
var foo_tag: PolyTag = .{};
pub const FOO_TAG: *const anyopaque = &foo_tag;
```

## DoublyLinkedList.Node

```zig
pub const Node = struct {
    prev: ?*Node = null,
    next: ?*Node = null,
};
```

`prev`/`next` point to other `*DoublyLinkedList.Node`, not to `*PolyNode`.

`PolyNode` embeds it as field `node` so `std.DoublyLinkedList` can link it.

The list sends and receives `*DoublyLinkedList.Node`. `@fieldParentPtr` recovers the parent.

## Two-level @fieldParentPtr chain

Zig has no `using`. Recovery from list node to user type is two steps:

```zig
const Event = struct {
    poly: PolyNode,   // embeds PolyNode — field name used for outer @fieldParentPtr
    code: i32,
    message: []const u8,
};

// Step 1 — from DoublyLinkedList.Node to PolyNode (done inside mailbox/pool):
const poly: *PolyNode = @fieldParentPtr("node", dll_node_ptr);

// Step 2 — from PolyNode to user type (done in user code):
const ev: *Event = @fieldParentPtr("poly", poly);
```

`_Mbox.list.append(&poly.node)` passes `*DoublyLinkedList.Node`. `list.popFirst()` returns `?*DoublyLinkedList.Node`.

Step 1 always happens inside mailbox or pool.

Step 2 happens in caller code, after checking the tag.

Both field names are validated at compile time. Odin's offset-0 cast is less safe.

## polynode_reset and polynode_is_linked

```zig
pub fn polynode_reset(n: *PolyNode) void {
    n.node.prev = null;
    n.node.next = null;
}

pub fn polynode_is_linked(n: *PolyNode) bool {
    return n.node.prev != null or n.node.next != null;
}
```

## MayItem semantics

- `m != null` → you own it; transfer, recycle, or free it.
- `m == null` → not yours; the API took it or there was nothing.
- After send or put: caller must set `m = null`.

## Ownership states

```text
FREE       — not in any system
IN_FLIGHT  — owned by user code (MayItem non-null)
HELD        — owned by infrastructure (mailbox queue or pool free-list)
```

Invariants:

1. `m = null` after send or put — IN_FLIGHT → HELD.
2. `m != null` after receive or get — HELD → IN_FLIGHT.
3. A PolyNode is owned by exactly one system, or is invalid. Never double-owned.

`?*PolyNode` encodes this directly: `null` = not yours, non-null = yours.

## Node reset rule

`popFirst()` clears `prev`/`next` automatically. Single-item and batch (`std.DoublyLinkedList`) returns both auto-reset when walked with `popFirst()`:

```zig
var remaining = mbox_close(inbox);
while (remaining.popFirst()) |node| {
    const poly: *PolyNode = @fieldParentPtr("node", node);
    // popFirst already cleared prev/next — no manual polynode_reset needed
    // dispose or recycle poly here
}
```

Manual `polynode_reset` is only needed when working with raw `*Node` pointers directly — not through `popFirst()`.

---

# 4. Block 2 — Mailbox (_Mbox)

Odin reference: see Appendix.

Key invariant: data has priority over closed signals.

## Why Io.Queue cannot be used

`std.Io.Queue(Elem)` is a native MPMC queue backed by `Io.Mutex` + `Io.Condition`. It cannot serve as Mailbox's internal queue. Three reasons:

1. **Bounded vs unbounded.** `Io.Queue` uses a fixed ring buffer — `putOne` blocks when full. Mailbox is unbounded — send never blocks except on mutex acquisition. Different backpressure semantics.
2. **Different close semantics.** `Io.Queue.close()` leaves buffered elements retrievable before returning `error.Closed`. `mbox_close` must atomically snapshot and return all remaining items as a list. Different contracts.
3. **Copy-based, not intrusive.** `Io.Queue` copies values into a `[]u8` ring buffer. Mailbox nodes are intrusive — they carry their own storage and are linked, not copied. `mbox_close` depends on the intrusive list for batch return.

Mailbox needs its own implementation.

## Starting point: TypeErasedMailbox

`/home/g41797/dev/root/github.com/g41797/mailbox/src/mailbox.zig` has three mailbox variants. The third, `TypeErasedMailbox`, is the direct predecessor of `_Mbox`. It already:

- uses `Io.Mutex` + `Io.Condition`
- stores `io` in the struct
- provides idempotent close returning the remaining head pointer

## _Mbox struct

`io` is stored at init. Callers do not pass `io` per operation.

`closed` is `std.atomic.Value(bool)` — allows a fast-path check before the mutex.

```zig
pub const MailboxHandle = *PolyNode;  // opaque handle — @fieldParentPtr("poly", mbh) recovers *_Mbox

const _Mbox = struct {
    poly:        PolyNode,                  // field "poly" — MailboxHandle points here
    mutex:       Io.Mutex,                  // guards list, len
    cond:        Io.Condition,              // blocked receivers wait here
    list:        std.DoublyLinkedList,      // intrusive linked list of queued PolyNodes
    len:         usize,
    closed:      std.atomic.Value(bool),    // pre-lock fast-path; atomic swap in close
    oob_count:   usize,                      // number of OOB items at front of queue
    oob_last:    ?*std.DoublyLinkedList.Node, // last OOB node — O(1) insertion
    io:          Io,                        // captured at init; used by all operations
};
```

## API

`io` is only needed at construction. All other functions use `mbox.io`. For full signatures see `matryoshka-api-reference.md`. Implementation notes:

- `mbox_receive` takes `timeout_ns: ?u64` — `null` waits forever, value is nanoseconds.
- `mbox_close` returns a `std.DoublyLinkedList` of remaining items. Idempotent via the `closed` CAS — second call returns an empty list.
- `mbox_receive_batch` takes all currently available items in one lock acquisition without waiting. Never blocks on `Io.Condition`.

## Receive state flow

```text
pre-lock check (atomic)
    ↓ open
mutex.lock (cancel point)
    ↓
re-check closed
    ↓ open
wait loop:
    closed?   → error.Closed
    len > 0?  → dequeue
    wait (cancel point, timeout point)
```

## Receive logic

`Io.Condition` has no `waitTimeout` in 0.16 (issue #31278). Use `condition_waitTimeout`, which calls `io.futexWaitTimeout` directly.

```zig
fn mbox_receive(mbh: MailboxHandle, m: *MayItem, timeout_ns: ?u64)
    (error{ Closed, Timeout } || Cancelable)!void
{
    const mbox: *_Mbox = @fieldParentPtr("poly", mbh);

    // fast path: already closed, no lock needed (atomic read)
    if (mbox.closed.load(.acquire)) return error.Closed;
    const io = mbox.io;

    // null = wait forever (Io.Timeout.none); value = timeout in nanoseconds
    const timeout: Io.Timeout = if (timeout_ns) |ns|
        .{ .duration = .{ .raw = .{ .nanoseconds = @intCast(ns) }, .clock = .real } }
    else
        .none;
    const deadline = timeout.toDeadline(io);

    // cancellation point: futexWait fires if contended
    mbox.mutex.lock(io) catch |err| return err;   // propagates error.Canceled directly
    defer mbox.mutex.unlock(io);

    // re-check: mbox_close may have run between pre-check and lock
    if (mbox.closed.load(.monotonic)) return error.Closed;

    while (mbox.len == 0) {
        if (mbox.closed.load(.monotonic)) return error.Closed;
        condition_waitTimeout(&mbox.cond, io, &mbox.mutex, deadline) catch |err| switch (err) {
            error.Timeout   => return error.Timeout,
            error.Canceled  => return err,          // propagates error.Canceled directly
        };
    }

    // dequeue and update OOB tracking
    const node = mbox.list.popFirst().?;
    mbox.len -= 1;
    if (mbox.oob_count > 0) {
        mbox.oob_count -= 1;
        if (mbox.oob_count == 0) mbox.oob_last = null;
    }
    m.* = @as(*PolyNode, @fieldParentPtr("node", node));
}
```

## send / send_oob

`mbox_send`: appends under mutex, then `cond.signal(io)`.

`mbox_send_oob`: inserts after the last OOB node — FIFO among OOBs, all OOBs before regular items. Uses `oob_last` for O(1) insertion:

```zig
// under mutex:
if (mbox.oob_last) |last| {
    mbox.list.insertAfter(last, &poly.node);
} else {
    mbox.list.prepend(&poly.node);
}
mbox.oob_last = &poly.node;
mbox.oob_count += 1;
mbox.len += 1;
mbox.cond.signal(io);
```

For the full OOB ordering example see `matryoshka-api-reference.md` (Advanced: OOB ordering).

## receive_batch

The Zig equivalent of Odin's `try_receive_batch`. Snapshots the entire list under one lock. Returns an empty list if nothing available.

```zig
fn mbox_receive_batch(mbh: MailboxHandle) (error{Closed} || Cancelable)!std.DoublyLinkedList {
    const mbox: *_Mbox = @fieldParentPtr("poly", mbh);

    if (mbox.closed.load(.acquire)) return error.Closed;

    mbox.mutex.lock(mbox.io) catch |err| return err;   // cancel point
    defer mbox.mutex.unlock(mbox.io);

    if (mbox.closed.load(.acquire)) return error.Closed;

    // snapshot entire list without closing
    const result = mbox.list;
    mbox.list = .{};
    mbox.len = 0;
    mbox.oob_count = 0;
    mbox.oob_last = null;
    return result;
}
```

The caller walks the returned list via `popFirst()` — which clears `prev`/`next` on each node.

## mbox_close

CAS for idempotency, then `lockUncancelable` to acquire the mutex regardless of cancel state.

```zig
pub fn mbox_close(mbh: MailboxHandle, io: Io) std.DoublyLinkedList {
    const mbox: *_Mbox = @fieldParentPtr("poly", mbh);

    // CAS: only one caller ever does the work; others return empty list
    if (mbox.closed.cmpxchgStrong(false, true, .acq_rel, .acquire) != null)
        return .{ .first = null, .last = null };

    mbox.mutex.lockUncancelable(io);   // blocks until acquired, never returns error.Canceled
    defer mbox.mutex.unlock(io);

    // snapshot the list under lock
    const result = mbox.list;
    mbox.list = .{};
    mbox.len = 0;
    mbox.oob_count = 0;
    mbox.oob_last = null;

    // wake any workers waiting in condition_waitTimeout
    mbox.cond.broadcast(io);

    return result;
}
```

Workers waiting in `cond.wait` wake on broadcast. They see `closed = true` and return `error.Closed`.

Workers acquiring the lock after close releases it see `closed = true` on the post-lock check.

Workers calling `mbox_receive` after close completes hit the pre-lock fast path.

For cancel protection rationale, see Section 7.

---

# 5. Block 3 — Pool (_Pool)

Odin reference: see Appendix.

## _Pool struct

Same pattern as `_Mbox`: `io` stored at init, `closed` is atomic for the pre-lock fast path.

```zig
pub const PoolHandle = *PolyNode;  // opaque handle — @fieldParentPtr("poly", ph) recovers *_Pool

const _Pool = struct {
    poly:   PolyNode,                                    // field "poly" — PoolHandle points here
    mutex:  Io.Mutex,                                    // guards lists, counts
    cond:   Io.Condition,                                // pool_get_wait blocks here; pool_close broadcasts
    lists:  std.AutoHashMapUnmanaged(*const anyopaque, std.DoublyLinkedList), // per-tag free-lists
    counts: std.AutoHashMapUnmanaged(*const anyopaque, usize),    // per-tag counts
    hooks:  PoolHooks,
    alloc:  std.mem.Allocator,
    closed: std.atomic.Value(bool),                               // pre-lock fast-path; atomic swap in close
    io:     Io,                                                   // captured at init; used by all operations
};

pub const PoolHooks = struct {
    ctx:      *anyopaque,
    tags:     []const *const anyopaque,
    on_get:   *const fn(ctx: *anyopaque, tag: *const anyopaque, in_pool_count: usize, m: *MayItem) void,
    on_put:   *const fn(ctx: *anyopaque, in_pool_count: usize, m: *MayItem) void,
    on_close: *const fn(ctx: *anyopaque, list: *std.DoublyLinkedList) void,  // called once with all remaining items
};

pub const GetMode = enum { available_or_new, new_only, available_only };
pub const GetError = error{ Closed, NotAvailable, NotCreated, AlreadyInUse };
```

## API

For full signatures see `matryoshka-api-reference.md`. `io` is only needed at construction; all other functions use `p.io`.

## pool_get_wait logic

Symmetric with `mbox_receive`: takes `timeout_ns: ?u64` (`null` = forever), converts to a deadline, uses `condition_waitTimeout`. `error.Timeout` is propagated directly — not remapped to `error.Closed`.

```zig
fn pool_get_wait(ph: PoolHandle, tag: *const anyopaque, m: *MayItem, timeout_ns: ?u64) (GetError || Cancelable || error{Timeout})!void {
    const p: *_Pool = @fieldParentPtr("poly", ph);

    // fast path: already closed, no lock needed (atomic read)
    if (p.closed.load(.acquire)) return error.Closed;
    const io = p.io;

    // null = wait forever; value = timeout in nanoseconds
    const timeout: Io.Timeout = if (timeout_ns) |ns|
        .{ .duration = .{ .raw = .{ .nanoseconds = @intCast(ns) }, .clock = .real } }
    else
        .none;
    const deadline = timeout.toDeadline(io);

    // cancellation point: futexWait fires if contended
    p.mutex.lock(io) catch |err| return err;   // propagates error.Canceled directly
    defer p.mutex.unlock(io);

    while (true) {
        if (p.closed.load(.acquire)) return error.Closed;
        if (p.lists.getPtr(tag)) |list| {
            if (list.popFirst()) |node| {
                m.* = @as(*PolyNode, @fieldParentPtr("node", node));
                p.counts.getPtr(tag).?.* -= 1;
                return;  // on_get hook called outside lock after return
            }
        }
        condition_waitTimeout(&p.cond, io, &p.mutex, deadline) catch |err| switch (err) {
            error.Timeout  => return error.Timeout,
            error.Canceled => return err,
        };
    }
}
```

`pool_put`: appends to the tag's free-list under mutex, then `p.cond.signal(p.io)`.

## pool_close

Takes no `io` parameter — uses `p.io`. Unlike `mbox_close`, it returns `void`: `on_close` receives the full collected list, so there is nothing to return.

```zig
pub fn pool_close(ph: PoolHandle) void {
    const p: *_Pool = @fieldParentPtr("poly", ph);

    // CAS: only one caller ever does the work; others return immediately
    if (p.closed.cmpxchgStrong(false, true, .acq_rel, .acquire) != null) return;

    p.mutex.lockUncancelable(p.io);   // blocks until acquired, never returns error.Canceled

    // collect all items from all per-tag lists under lock
    var collected: std.DoublyLinkedList = .{};
    var it = p.lists.iterator();
    while (it.next()) |entry| {
        collected.concatByMoving(entry.value_ptr);
    }
    p.lists.clearRetainingCapacity();
    p.counts.clearRetainingCapacity();

    // wake any workers waiting in pool_get_wait
    p.cond.broadcast(p.io);

    p.mutex.unlock(p.io);

    // one call with the full collected list — hook walks and frees; runs outside lock
    p.hooks.on_close(p.hooks.ctx, &collected);
}
```

`concatByMoving` splices each per-tag list into one collected list without copying nodes.

`on_close` receives a `*std.DoublyLinkedList`. The hook walks via `popFirst()` (which clears `prev`/`next`) and frees each item.

Workers waiting in `p.cond.wait` wake on broadcast, see `closed = true`, return `error.Closed`. Workers acquiring the lock after close, or calling `pool_get_wait` after close, hit the pre-lock fast path.

## Closed pool on put (shutdown race)

If `pool_put` is called after `pool_close`, it must not panic. It returns the item to the caller (`m` stays non-null). A worker may hold an item when `pool_close` fires.

The worker's cleanup path handles this with `on_close`:

```zig
pool_put(m.pool, &item);
if (item != null) {
    // pool was closed — recycle refused — wrap as single-item list and pass to on_close
    var single: std.DoublyLinkedList = .{};
    single.append(&item.?.node);
    m.hooks.on_close(m.hooks.ctx, &single);
}
```

Same `on_close` code path for single-item and bulk cases.

## Pool asymmetry

Pool is not a symmetric acquire/release pair:

- `pool_get` / `pool_get_wait` — acquisition; always produces an owned object.
- `pool_put` — disposal policy decision; may recycle OR destroy.

The `on_put` hook decides fate: set `m.* = null` to destroy, leave non-null to keep in pool.

See `matryoshka-architecture-foundation-4.md` for the rationale.

## Hook discipline

For the hook contract see `matryoshka-api-reference.md`. Zig-specific notes:

- Hooks run outside the pool mutex (same as Odin). Hooks must not call pool APIs on the same pool instance — a contract violation, not a deadlock.
- Get path: release lock → call `on_get` → caller proceeds.
- Put path: call `on_put` → re-acquire lock → insert returned item.
- `on_get` must always define the ownership outcome: set `m.*` to a node, or leave it unchanged. No third state.

For cancel protection rationale, see Section 7.

---

# 6. Block 4 — Infrastructure as Items

`MailboxHandle` and `PoolHandle` are themselves `*PolyNode`.

The same `?*PolyNode` ownership rules apply:

- A mailbox can be sent through a mailbox.
- A pool handle can be stored in an ownership graph.

Tag checks identify them:

```zig
if (mailbox_is_it_you(poly.tag)) { ... }
else if (pool_is_it_you(poly.tag)) { ... }
```

There is no generic dispose. Use `mbox.destroy` and `pool.destroy` directly. Application types destroy themselves.

For the rationale see `matryoshka-architecture-foundation-4.md`, section 10.

# 7. Cancellation

This section consolidates everything about cancellation in one place.

In Odin there is no cancellation. In Zig 0.16 any code that touches `Io` primitives participates in it.

## 7.1 How Zig cancellation works

Cancellation points are the waiting operations:

```zig
mutex.lock(io) catch ...           // cancellation point — returns Cancelable!void
cond.wait(io, &mutex) catch ...    // cancellation point — returns Cancelable!void
cond.broadcast(io)                 // NOT a cancellation point — returns void
cond.signal(io)                    // NOT a cancellation point — returns void
mutex.unlock(io)                   // NOT a cancellation point — returns void
```

Only waits return `error.Canceled`.

Signal, broadcast, and unlock never do.

A worker blocked in an Io wait wakes immediately when canceled:

```
future.cancel(io) called
    ↓
Zig Io runtime marks task as canceled
    ↓
worker is blocked in Io.Condition.wait
    ↓
Io.Condition.wait returns error.Canceled
    ↓
caller handles error.Canceled
```

A worker that is not blocked sees it at its next wait:

```
future.cancel(io) called
    ↓
Zig Io runtime marks task as canceled
    ↓
worker reaches next Io wait (e.g. mutex.lock at start of next operation)
    ↓
mutex.lock returns error.Canceled
    ↓
caller handles error.Canceled
```

Cancellation is never missed.

It takes effect at whichever Io wait the worker hits next.

## 7.2 Two delivery mechanisms

Zig 0.16 offers two ways to unblock a worker. Both are valid. They differ in who initiates the unblock.

```
Broadcast path              Future.cancel path
─────────────              ──────────────────
mbox_close / pool_close    future.cancel(io)
     ↓                          ↓
cond.broadcast             Io marks task canceled
     ↓                          ↓
worker wakes               worker hits next Io wait
     ↓                          ↓
error.Closed               error.Canceled
     ↓                          ↓
worker exits loop          worker exits loop
```

Broadcast path: `mbox_close` / `pool_close` call `cond.broadcast(io)` internally.

Future.cancel path: spawn the worker with `io.concurrent()` and call `future.cancel(io)` on shutdown.

Both require `mbox_close` and `pool_close` afterward. `future.cancel` stops the worker. It does not close anything.

## 7.3 Cancel-protected vs cancelable operations

Receive operations must be cancelable — the worker must wake when canceled.

Close and put operations must be cancel-protected — they are cleanup paths that must complete.

Two mechanisms make operations cancel-protected.

`lockUncancelable` — for a single lock acquisition:

```zig
mbox.mutex.lockUncancelable(io);   // blocks until acquired, never returns error.Canceled
defer mbox.mutex.unlock(io);
```

Used by `mbox_close`, `pool_close`, `pool_put`, and `pool_put_all`.

`CancelProtection` — for a larger region:

```zig
pub const CancelProtection = enum(u1) {
    unblocked = 0,  // default: Io functions are cancellation points
    blocked   = 1,  // no Io function returns error.Canceled
};

const old = io.swapCancelProtection(.blocked);
defer _ = io.swapCancelProtection(old);
// inside here: error.Canceled is unreachable from any Io call
```

Use `lockUncancelable` when only the lock acquisition needs protection.

Use `swapCancelProtection` when several Io calls in a region all need protection.

`pool_put` MUST be cancel-protected.

A worker that receives `error.Canceled` from `mbox_receive` must return its item reliably. If `pool_put` could itself fail with `error.Canceled`, the item would be lost with no owner. `pool_put` returns `void` and uses `lockUncancelable` internally.

## 7.4 Cancel contract

Every public function declares whether it is cancelable or cancel-protected.

See `matryoshka-api-reference.md`, Cancel contract summary table, for the complete list.

Implementation note: all cancel-protected operations use `mutex.lockUncancelable(io)` — simpler and more explicit than `swapCancelProtection(.blocked)` plus `mutex.lock(io) catch unreachable`.

## 7.5 `error.Canceled` ≠ `error.Closed`

These are distinct. Do not remap one to the other.

- `error.Closed` — `mbox_close` or `pool_close` was called.
- `error.Canceled` — the task was canceled while the mailbox or pool was still open.

Different causes. Different meaning. Propagate `error.Canceled` directly from `mbox_receive` and `pool_get_wait`.

Both cause the worker to exit its loop. The worker may handle them differently.

## 7.6 Post-wakeup check sequence

A return from `Io.Condition.wait` is just a wakeup. It carries no application meaning.

The scheduler resumed the task. What the code finds after waking is the event.

In `mbox_receive` the check sequence enforces this:

```zig
while (mbox.len == 0) {
    if (mbox.closed.load(.monotonic)) return error.Closed;    // mailbox shut down
    condition_waitTimeout(...) catch |err| switch (err) {
        error.Timeout  => return error.Timeout,               // caller's deadline
        error.Canceled => return err,                         // task canceled — propagated directly
    };
    // loop: woke up, check again — wakeup itself told us nothing
}
// data available — dequeue immediately
// OOB items arrive via send_oob (prepend) — they're just PolyNodes with specific tags
```

The order: closed? → `len > 0`? → dequeue / loop.

The loop re-evaluates state on every wakeup. No single wakeup short-circuits to a conclusion.

## 7.7 Odin comparison

Odin has no cancellation.

`sync.mutex_lock` and `sync.cond_wait` never return errors.

The only way to wake a blocked Odin worker is the `mbox_close` / `pool_close` broadcast.

There is no injection mechanism and no `CancelProtection`.

`Future.cancel` is new in Zig.

---

# 8. Master Patterns

## 8.1 Master is a role, not a type

Mailbox and Pool are concrete infrastructure — specific structs, specific APIs.

Master is different. Master is a coordination boundary. A role, not a required type.

See the architecture foundation document for the full treatment.

A Master may own any combination:

- pool + Io.Select — lifecycle + event sources, no mailbox
- mailbox + pool — transport + lifecycle
- mailbox only — transport without lifecycle
- pool only — lifecycle without transport

Both mailbox and pool are optional.

A Master may be a struct, a `fn main()`, or any other shape.

Mailbox and Pool are infrastructure. Master is architecture.

## 8.2 Master struct shapes

Two shapes, one per delivery mechanism.

Broadcast path — a flag lets the worker loop detect shutdown between operations:

```zig
const Master = struct {
    inbox:   MailboxHandle,
    pool:    PoolHandle,
    closing: std.atomic.Value(bool),  // loop check between operations
    hooks:   PoolHooks,
    alloc:   std.mem.Allocator,
};
```

Future.cancel path — the worker's Future replaces the flag:

```zig
const Master = struct {
    inbox:  MailboxHandle,
    pool:   PoolHandle,
    hooks:  PoolHooks,
    alloc:  std.mem.Allocator,
    worker: Io.Future(Cancelable!void),  // spawned by io.concurrent()
};
```

## 8.3 Worker loop

One canonical worker loop handles both shutdown signals.

```zig
fn worker_proc(io: Io, m: *Master) !void {
    while (true) {
        var item: MayItem = null;

        mbox_receive(m.inbox, io, &item, timeout_ns) catch |err| switch (err) {
            error.Closed     => break,
            error.Canceled   => break,
            error.Timeout    => continue,
        };

        // OOB handling: check item tag — send_oob items arrive at front of queue
        // if (FooNode.isIt(item.?.tag)) { handleOob(m, item); continue; }

        // worker owns item here
        processItem(m, io, item) catch |err| switch (err) {
            error.Canceled => {
                // task was canceled mid-processing; return item if pool open, destroy if closed
                pool_put(m.pool, &item);
                if (item != null) {
                    var single: std.DoublyLinkedList = .{};
                    single.append(&item.?.node);
                    m.hooks.on_close(m.hooks.ctx, &single);
                }
                break;
            },
            else => |e| return e,
        };
    }
}
```

- `error.Closed` → break
- `error.Canceled` → break
- `error.Timeout` → continue

Both `error.Closed` and `error.Canceled` are clean exits. The worker must not return an error for either.

Item-on-exit pattern: whenever the worker exits while holding an item, try `pool_put` first. If the pool was already closed, wrap the item in a single-item `std.DoublyLinkedList` and call `on_close`.

## 8.4 Shutdown: broadcast path

Master closes both mbox and pool before joining the worker.

The close broadcasts wake the worker regardless of which operation it is blocked in.

```
Master decides to stop
    │
    ├─ pool_close(m.pool)       — sets closed, calls on_close with full item list, broadcasts
    │       worker in pool_get_wait wakes → error.Closed → exits loop
    │
    ├─ mbox_close(m.inbox)      — sets closed, snapshots, broadcasts
    │       worker in mbox_receive wakes → error.Closed → exits loop
    │
    ├─ join worker (await future or group)
    │
    ├─ walk mbox list → free each node
    └─ free Master
```

Both closes must run before join — the worker may be blocked in either.

`pool_close` calls `on_close` for its items — no list to walk after.

## 8.5 Shutdown: Future.cancel path

Master cancels the worker task first, then closes mbox and pool.

```
Master decides to stop
    │
    ├─ future.cancel(io)
    │       worker task marked canceled
    │       worker blocked in mbox_receive or pool_get_wait → error.Canceled → exits loop
    │       future.cancel awaits worker completion, returns
    │
    ├─ pool_close(m.pool)       — calls on_close for remaining items (worker already exited)
    ├─ mbox_close(m.inbox)      — snapshot remaining items
    │
    ├─ walk mbox list → free each node
    └─ free Master
```

`future.cancel` returns only after the worker has exited.

`pool_close` and `mbox_close` run after join — no race with the worker.

## 8.6 Shutdown ordering and teardown

Both paths converge on the same teardown.

```
Broadcast path:
    pool_close + mbox_close → join → walk mbox list → free Master

Future.cancel path:
    future.cancel → pool_close + mbox_close → walk mbox list → free Master
```

Key rule: `mbox_close` and `pool_close` are always required.

Without them, items in the queue or pool are lost.

- `mbox_close` returns remaining items as a `std.DoublyLinkedList` — caller walks via `popFirst()`.
- `pool_close` calls `on_close` once with the full remaining list — nothing returned.

Order between the two closes does not affect correctness.

In the broadcast path, calling `mbox_close` before `pool_close` lets the worker return its item via `pool_put` while the pool is still open. If `pool_close` fires first, the worker wraps the item in a single-item list and calls `on_close` directly. Same result, different path.

## 8.7 Multiple workers: Io.Group

```zig
var group: Io.Group = .init;
try group.concurrent(io, worker_proc, .{master_ptr});
// on shutdown:
group.cancel(io);   // cancels all members, awaits all, returns void
```

`group.cancel(io)` replaces `Thread.Pool` + `Thread.WaitGroup`, both removed in 0.16.0.

After `group.cancel`, call `pool_close` and `mbox_close` to reclaim remaining items.

## 8.8 Mailbox and Pool as event sources

`_Mbox` and `_Pool` store `io: Io` internally.

Their blocking operations wait on `Io.Condition` — real Io waits.

They can spawn concurrent tasks and participate directly in `Io.Select` as event sources.

Without library helpers, every application writes identical adapter functions. The library provides them.

**Result by value, not out-pointer.**

The synchronous `mbox_receive` takes `m: *MayItem`. In the concurrent case a worker task would write through this pointer from a different thread — a cross-thread reference to stack memory.

The adapters eliminate this by returning the item by value inside a tagged union:

```zig
pub const ReceiveResult = union(enum) {
    item: MayItem,      // ownership transferred inside the result
    closed: void,
    timeout: void,
    canceled: void,
};
```

The local never escapes the worker's stack. When `select.await()` returns `.item`, the Master is sole owner.

`PoolResult` is symmetric, with one extra arm: `not_created`.

**Cancel never triggers close.**

Cancel is an Io scheduler operation. Close is a Master decision.

On `error.Canceled`, adapters return `.canceled`. The mailbox or pool stays open. The Master decides what to do.

**Adapter pattern.**

```zig
pub fn receive_select(mbh: MailboxHandle, timeout_ns: ?u64) ReceiveResult {
    var item: MayItem = null;
    mbox_receive(mbh, &item, timeout_ns) catch |err| switch (err) {
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

The pool adapter is symmetric: `get_wait_select` calls `pool_get_wait` and maps errors to `PoolResult` arms. `get_wait_future` recovers `_Pool` via `@fieldParentPtr` and calls `self.io.concurrent`.

**Job-pool pattern: pool availability as an event.**

The `.item` arm of `PoolResult` hands ownership to the Master. The `pool_get_wait` that produced it has already removed the item from the pool.

```
worker puts finished item back
    ↓
pool_get_wait event source fires
    ↓
Master gets the item
    ↓
Master fills and submits new work
    ↓
re-spawn the event source
```

Re-spawn the event source only after deciding the item's fate.

**When to use Select vs fan-in mailbox.**

When items carry ownership: use fan-in. Many senders send tagged PolyNodes to one mailbox. Master dispatches on tag. One queue, one ownership model, one shutdown model. No additional threads.

Bridging to external Io: use Select event sources. Mailbox traffic alongside timers, sockets, files, or pool availability in one `Io.Select` loop.

**Thread cost.**

On the Threaded backend, each `select.concurrent` call may allocate a worker thread. This is a property of `Io.Select` and `io.concurrent`, not of Matryoshka. Managing that cost is the developer's responsibility.

On `global_single_threaded`, `receive_future` and `get_wait_future` return `error.ConcurrencyUnavailable`. The synchronous API remains available.

See `matryoshka-api-reference.md` for the type and function signatures.

**Mailbox-less coordination.**

Mailbox is optional. Pool + Io can be the primary coordination model.

When `Io.Future` or `Io.Select` already deliver results, adding a mailbox duplicates transport.

Pool + Select is sufficient for:

- job scheduling — pool controls capacity, Select waits for available items
- resource management — workers get/put, Master reacts to availability
- capacity-controlled pipelines — pool limits how many items exist

```text
Pool + Select (no mailbox)

                ┌── Pool ────→ available items
Master ←── wait ┤
                ├── Timer ───→ periodic work
                └── Network ─→ external data
```

Add mailbox when independent senders need to deliver ownership-carrying items:

- many producers send to one consumer (fan-in)
- items flow through a chain (pipeline)
- the receiver does not know the senders in advance

---

# 9. Rules — What to Avoid, What to Reuse

### What to reuse

- `TypeErasedMailbox` → starting point for `_Mbox`
- `condition_waitTimeout` → private helper for both `_Mbox` and `_Pool`
- `std.DoublyLinkedList` → intrusive list for all batch operations
- `std.AutoHashMapUnmanaged` → per-tag free-lists in `_Pool`

### What to avoid

1. **Do NOT conflate OOB signals with cancel.**
   OOB signals are application events: PolyNodes with tags, handled by the dispatch loop.
   Cancel is a scheduler signal: terminal for the current task.
   OOB items are data. Cancel is not.

2. **Do NOT conflate scheduler wakeup with application events.**
   A return from `Io.Condition.wait` is just a resume.
   Always re-check `len` and `closed` after every wakeup.
   Never treat the wakeup itself as the signal.

3. **Do NOT remap `error.Canceled` to `error.Closed`.**
   `error.Canceled`: task canceled while mailbox or pool was open.
   `error.Closed`: mailbox or pool was explicitly closed.
   Different causes. Propagate `error.Canceled` directly.

4. **Do NOT redesign Mailbox as a stream or Pool as an Io primitive.**
   Mailbox is ownership transfer.
   Pool is lifecycle management.
   `std.Io` is the scheduling carrier, not their abstraction.

5. **Do NOT pool infrastructure** (Mailbox or Pool instances).
   They contain the synchronization primitives that make pooling safe.
   Pooling them is self-defeating.

6. **Do NOT make Pool interpret CANCEL or OOB.**
   Pool is a lifecycle layer only.
   Shutdown sequencing and cancel propagation are Master's responsibility.

7. **Do NOT use `anytype` for polymorphism** where tag dispatch covers the use case.
   `anytype` removes the runtime type identity that `tag: *const anyopaque` provides.

8. **Do NOT skip nil-out after transfer.**
   `m = null` after send or put is the ownership invariant.
   Skipping it means the caller still believes they own the node.

9. **Do NOT add vtables** unless implementing dynamic plugins.
   Comptime switch dispatch is preferred for all known-type scenarios.

10. **Do NOT pool items containing `Io.Mutex`, `Io.Condition`, OS handles, or any stateful resource.**
    Synchronization primitives carry state that survives the request and cause silent deadlocks under load.
    `std.Thread.Mutex` and `std.Thread.Condition` do not exist in 0.16.0.

11. **Do NOT create infrastructure ownership cycles.**
    A Mailbox may be transported through another Mailbox. A Pool may hold a Mailbox as an item.
    Forbidden is implicit retention: a data item holding a reference back to the Mailbox or Pool that delivered it.
    Infrastructure may be transported. It must never be implicitly retained by the items it carries.

12. **Do NOT use a cancelable lock in close/put operations.**
    `mbox_close`, `pool_close`, `pool_put`, and `pool_put_all` must complete regardless of cancel state.
    Use `mutex.lockUncancelable(io)`.
    The cancelable variant means a canceled task fails to close/put and leaks items.

13. **Do NOT call pool APIs on the same pool from inside hooks.**
    Hooks run outside the mutex. Calling back is not a deadlock — it is a contract violation.
    Hooks are policy; pool is infrastructure. Mixing them collapses the separation.

14. **Do NOT expose `error.Canceled` from `pool_put` or `pool_put_all`.**
    These are cleanup paths — a worker returning its item after `error.Canceled` from `mbox_receive`.
    If `pool_put` could fail with `error.Canceled`, the item would be lost with no owner.
    Both use `mutex.lockUncancelable(io)` and return `void`.

---

# 10. Zig-Specific Opportunities

These are gains Zig's type system and comptime enable that Odin cannot express.

### Comptime `NodeMixin` — generated tag identity per PolyNode type

In Odin every PolyNode-based type manually declares its tag identity. The block is identical for every type — only the name changes. Odin cannot generate it.

Zig's comptime generates it once and derives it for any `T`. This adds compile-time validation Odin cannot express.

`usingnamespace` was removed in 0.16.0, so the generated namespace cannot live inside the struct. Define it as a file-level `const` after the struct:

```zig
pub fn NodeMixin(comptime T: type) type {
    comptime validateNodeType(T);  // see below
    return struct {
        var _tag: PolyTag = .{};
        pub const TAG: *const anyopaque = &_tag;

        pub inline fn isIt(tag: *const anyopaque) bool {
            return tag == TAG;
        }

        pub fn cast(node: *PolyNode) ?*T {
            if (node.tag != TAG) return null;
            return @fieldParentPtr("poly", node);
        }

        pub fn init(self: *T) void {
            self.poly = .{ .node = .{}, .tag = TAG };
        }
    };
}

fn validateNodeType(comptime T: type) void {
    if (!@hasField(T, "poly"))
        @compileError(@typeName(T) ++ ": must have field 'poly: PolyNode'");
    if (@TypeOf(@field(@as(T, undefined), "poly")) != PolyNode)
        @compileError(@typeName(T) ++ ": field 'poly' must be PolyNode");
}
```

Usage — the generated namespace lives alongside the struct, not inside it:

```zig
pub const Foo = struct {
    poly: PolyNode,   // validated at comptime (field existence and type)
    data: u32,
};
pub const FooNode = NodeMixin(Foo);

// At call sites:
FooNode.TAG           // unique *const anyopaque
FooNode.isIt(tag)     // tag check
FooNode.cast(node)    // ?*Foo — recovers via @fieldParentPtr
FooNode.init(&foo)    // sets poly.tag at construction
```

Why `var _tag` and not `const`: a mutable global has a guaranteed unique runtime address. `const` may be deduplicated by the linker.

Why uniqueness holds: Zig memoizes comptime function results by argument. `NodeMixin(Foo)` and `NodeMixin(Bar)` are different types. Each has its own `_tag` global.

Why `validateNodeType` does not check offset: `@fieldParentPtr("poly", ptr)` computes the correct offset at compile time. Offset 0 is not required. Placing `poly` first matches Odin's convention but is not a correctness constraint in Zig.

Naming convention: `XxxNode = NodeMixin(Xxx)` — consistent, readable at dispatch call sites.

### Comptime tag dispatch with two-level recovery

Odin uses runtime `rawptr` comparison for tag dispatch. Zig makes the recovery comptime-safe:

```zig
fn recoverAs(comptime T: type, comptime field: []const u8, poly: *PolyNode, expected_tag: *const anyopaque) ?*T {
    if (poly.tag != expected_tag) return null;
    return @fieldParentPtr(field, poly);
}

// usage:
const ev: *Event = recoverAs(Event, "poly", poly, EVENT_TAG) orelse @panic("wrong tag");
```

Runtime cost is identical to Odin's. The field name is validated at compile time.

### Typed `MayItem(T)` — preserve source type through ownership transfer

Odin's `MayItem :: Maybe(^PolyNode)` erases the concrete type. Downcasting requires a manual tag check and cast.

Zig can keep the type at the API boundary:

```zig
fn MayItem(comptime T: type) type { return ?*T; }
```

Send and receive signatures become typed at callers:

```zig
fn send(mbh: MailboxHandle, item: MayItem(Foo)) !void
fn receive(mbh: MailboxHandle) !MayItem(Foo)
```

The internal queue still stores `*PolyNode` — the typed wrapper handles the cast at the boundary:

```zig
// send: upcast *Foo -> *PolyNode
fn send(mbh: MailboxHandle, item: MayItem(Foo)) !void {
    const node: ?*PolyNode = if (item) |p| &p.poly else null;
    return mbox_send(mbh, node);
}

// receive: downcast *PolyNode -> ?*Foo via FooNode.cast
fn receive(mbh: MailboxHandle) !MayItem(Foo) {
    const node = try mbox_receive(mbh);
    return FooNode.cast(node);
}
```

The ownership semantics (`non-null = yours, null = not yours`) are preserved exactly.

The gain: type errors at send/receive are compile-time, not runtime tag-mismatch panics.

When to use: typed wrappers suit single-type mailboxes. Polymorphic mailboxes carrying mixed types retain `?*PolyNode` and dispatch via `NodeMixin.isIt` after receive.

### Comptime closed-type Pool — eliminate the hashmap for known type sets

Pool uses a runtime hash map keyed on tag pointers. Necessary when the type set is open.

If all types are known at compile time, replace the `AutoHashMapUnmanaged` with a comptime-generated switch:

```zig
fn TypedPool(comptime types: []const type) type {
    return struct {
        // one DoublyLinkedList per type, laid out as a tuple
        lists: std.meta.Tuple(blk: {
            var fields: [types.len]type = undefined;
            for (types, 0..) |_, i| fields[i] = std.DoublyLinkedList;
            break :blk &fields;
        }),

        fn get(self: *@This(), tag: *const anyopaque) ?*PolyNode {
            inline for (types, 0..) |T, i| {
                const Meta = NodeMixin(T);
                if (tag == Meta.TAG) {
                    const node = self.lists[i].popFirst() orelse return null;
                    return @fieldParentPtr("node", node);  // DoublyLinkedList.Node → PolyNode
                }
            }
            return null;
        }
    };
}
```

The `inline for` unrolls into a chain of tag comparisons — no hash map, no allocation, no runtime dispatch overhead.

When to use: only when the type set is fully known at compile time and cannot grow at runtime. For the general Pool (open type set, hooks, runtime registration), `AutoHashMapUnmanaged` remains correct. `TypedPool` is an optimization for closed subsystems.

### Comptime pool item alignment validation

A Pool's slab allocator may have alignment constraints. Validate them at compile time rather than hitting misaligned-pointer UB at runtime:

```zig
fn validatePoolable(comptime T: type, comptime slab_align: u29) void {
    if (@alignOf(T) > slab_align)
        @compileError(@typeName(T) ++ ": alignment " ++
            std.fmt.comptimePrint("{}", .{@alignOf(T)}) ++
            " exceeds pool slab alignment " ++
            std.fmt.comptimePrint("{}", .{slab_align}));
}
```

Call inside `NodeMixin` or at pool registration:

```zig
comptime validatePoolable(Foo, pool_slab_align);
```

This catches alignment mismatches at build time. Without it, the bug is invisible until load.

### Comptime hook signature validation

Zig can assert hook function signatures at `pool_init` time rather than discovering mismatches at runtime:

```zig
fn pool_init(ph: PoolHandle, hooks: PoolHooks) !void {
    comptime {
        const on_get_T = *const fn(*anyopaque, *const anyopaque, usize, *MayItem) void;
        const on_put_T = *const fn(*anyopaque, usize, *MayItem) void;
        if (@TypeOf(hooks.on_get) != on_get_T) @compileError("on_get signature mismatch");
        if (@TypeOf(hooks.on_put) != on_put_T) @compileError("on_put signature mismatch");
    }
    ...
}
```

In practice `PoolHooks` already enforces this via its field types — this is belt-and-suspenders for dynamic hook construction.

### Atomic pre-lock fast-path

Both `_Mbox` and `_Pool` use `closed: std.atomic.Value(bool)` to check closed state before acquiring the mutex. This avoids lock contention on the common post-close path:

```zig
if (mbox.closed.load(.acquire)) return error.Closed;   // no mutex acquired (fast path)
mbox.mutex.lock(io) catch |err| return err;            // propagates error.Canceled directly
defer mbox.mutex.unlock(io);
if (mbox.closed.load(.monotonic)) return error.Closed; // re-check under lock
```

The double check prevents a race: close may fire between the first check and the lock acquire.

---

# Appendix A — Odin to Zig Idiom Mapping

This appendix maps every Odin language idiom used in matryoshka sources and examples to its Zig 0.16 equivalent. Examples are drawn directly from the Odin source.

---

### 1. `using` embedding vs `@fieldParentPtr`

**Odin** — `using` at offset 0 promotes fields and makes direct pointer casts safe:

```odin
Event :: struct {
    using poly: PolyNode,  // offset 0 — required
    code:       int,
    message:    string,
}

// Recovery: cast is safe because poly is at offset 0
ev := (^Event)(poly)
```

**Zig** — no `using`; embed as a named field and recover with `@fieldParentPtr`:

```zig
pub const Event = struct {
    poly:    PolyNode,
    code:    i64,
    message: []const u8,
};

// Recovery: field name validated at compile time
const ev: *Event = @fieldParentPtr("poly", poly);
```

**Key difference**: Odin's `using` promotes fields — you write `event.tag` not `event.poly.tag` — and makes the raw cast safe by guaranteeing offset 0. Zig requires explicit field access (`event.poly.tag`) and `@fieldParentPtr` for recovery. The Zig version is safer: the compiler checks the field name and enforces correct types.

**Two-level chain in matryoshka** (required because `PolyNode` embeds `std.DoublyLinkedList.Node`):

```zig
// Step 1: *DoublyLinkedList.Node → *PolyNode  (inside mailbox/pool implementation)
const poly: *PolyNode = @fieldParentPtr("node", dll_node);

// Step 2: *PolyNode → *UserType  (in user dispatch code)
const ev: *Event = @fieldParentPtr("poly", poly);
```

---

### 2. `rawptr` vs `*const anyopaque`

**Odin** — `rawptr` is the untyped pointer:

```odin
PolyTag :: struct { _: u8 }

@(private)
event_tag: PolyTag = {}
EVENT_TAG: rawptr = &event_tag

event_is_it_you :: #force_inline proc(tag: rawptr) -> bool {
    return tag == EVENT_TAG
}
```

**Zig** — `*const anyopaque` is the untyped pointer; `const` because tags are never mutated:

```zig
pub const PolyTag = struct { _: u8 = 0 };

var event_tag: PolyTag = .{};
pub const EVENT_TAG: *const anyopaque = &event_tag;

pub inline fn event_is_it_you(tag: *const anyopaque) bool {
    return tag == EVENT_TAG;
}
```

**Note**: Odin uses `rawptr` for all untyped pointers. Zig distinguishes `*anyopaque` (mutable) from `*const anyopaque` (read-only). Use `*const anyopaque` for tags — tags are never mutated.

---

### 3. `Maybe(T)` vs `?T` — ownership state

**Odin** — `Maybe(^PolyNode)` with `.?` destructuring:

```odin
MayItem :: Maybe(^PolyNode)

m: MayItem = &ev.poly       // take ownership
ptr, ok := m^.?             // destructure (ok == true if non-nil)
m^ = nil                    // release ownership
```

**Zig** — `?*PolyNode` with `orelse`/`if` unwrapping:

```zig
pub const MayItem = ?*PolyNode;

var m: MayItem = &ev.poly;          // take ownership
const ptr = m orelse return;        // unwrap or bail
// or: if (m) |ptr| { ... }
m = null;                           // release ownership
```

**Key difference**: The semantics are identical. The syntax differs. Odin uses `.?` suffix; Zig uses `orelse` or `if (opt) |val|`. Odin's multi-return destructuring (`ptr, ok := m^.?`) becomes Zig's `if (m.*) |ptr| { ... }`.

**At API boundaries** — Odin passes `^MayItem` (pointer to the optional); Zig passes `*MayItem`:

```odin
mbox_send :: proc(mb: Mailbox, m: ^MayItem) -> SendResult
```
```zig
pub fn mbox_send(mbh: MailboxHandle, m: *MayItem) error{Closed}!void
```

---

### 4. Pointer syntax: `^T` / `m^` vs `*T` / `m.*`

| Odin | Zig | Meaning |
|------|-----|---------|
| `^T` | `*T` | pointer to T |
| `^^T` | `**T` | pointer to pointer to T |
| `m^` | `m.*` | dereference pointer |
| `m^ = nil` | `m.* = null` | write through pointer |
| `nil` | `null` | null pointer / absent optional |

Odin uses `^` as both pointer-type sigil and dereference operator. Zig uses `*` for pointer types and `.*` for dereference.

---

### 5. Explicit casts: `cast(T)` vs `@ptrCast` / `@fieldParentPtr`

**Odin** — `cast(^T)ptr` for bare pointer reinterpretation:

```odin
// offset-0 cast: works because _Mbox has 'using poly: PolyNode' first
mbx_Ptr := cast(^_Mbox)mb

// in _pop: list.Node cast to PolyNode
result := cast(^PolyNode)raw
```

**Zig** — `@ptrCast` for raw reinterpretation, `@fieldParentPtr` for struct recovery:

```zig
// Preferred: field-based recovery (type-safe, compile-checked)
const mbox: *_Mbox = @fieldParentPtr("poly", mb);
const poly: *PolyNode = @fieldParentPtr("node", dll_node);

// Only when you truly need raw reinterpretation (rare in matryoshka)
const ptr: *_Mbox = @ptrCast(@alignCast(raw));
```

**Rule**: In matryoshka, `cast(^_Mbox)mb` → `@fieldParentPtr("poly", mb)`. Never use `@ptrCast` where `@fieldParentPtr` applies — `@fieldParentPtr` validates field existence and type at compile time.

---

### 6. Opaque handle pattern: `Mailbox :: ^PolyNode`

This is matryoshka's central idiom — the handle IS the embedded `PolyNode` pointer.

**Odin**:

```odin
Mailbox :: ^PolyNode  // type alias

mbox_new :: proc(alloc: mem.Allocator) -> Mailbox {
    mbx, _ := new(_Mbox, alloc)     // _Mbox has 'using poly: PolyNode' at offset 0
    mbx^.tag = MAILBOX_TAG
    return cast(Mailbox)mbx         // safe: poly is at offset 0
}

_unwrap :: proc(m: Mailbox) -> ^_Mbox {
    return cast(^_Mbox)m            // safe: reverse of the above cast
}
```

**Zig**:

```zig
pub const MailboxHandle = *PolyNode;      // same type alias concept

pub fn mbox_new(io: Io, alloc: std.mem.Allocator) !MailboxHandle {
    const mbx = try alloc.create(_Mbox);
    mbx.* = .{ .poly = .{ .node = .{}, .tag = MAILBOX_TAG }, .io = io, ... };
    return &mbx.poly;               // return pointer to the embedded PolyNode
}

fn unwrap(mbh: MailboxHandle) *_Mbox {
    return @fieldParentPtr("poly", mbh);  // recover _Mbox from its poly field
}
```

**Key difference**: In Odin, `cast(Mailbox)mbx` works because of offset-0 `using`. In Zig, `return &mbx.poly` makes the pointer explicit. `@fieldParentPtr` recovers the parent. Semantics are identical. The Zig version is explicit about what address is returned.

---

### 7. `sync.Mutex` / `sync.Cond` vs `Io.Mutex` / `Io.Condition`

**Odin** — OS-backed, no cancellation awareness:

```odin
import "core:sync"

sync.mutex_lock(&mbx^.mutex)
defer sync.mutex_unlock(&mbx^.mutex)
sync.cond_wait(&mbx^.cond, &mbx^.mutex)
sync.cond_wait_with_timeout(&mbx^.cond, &mbx^.mutex, remaining)
sync.cond_signal(&mbx^.cond)
sync.cond_broadcast(&ptr^.cond)
```

**Zig** — IO-scheduled, every wait is a cancellation point:

```zig
mbox.mutex.lock(io) catch |err| return err;               // propagates error.Canceled directly
defer mbox.mutex.unlock(io);
try mbox.cond.wait(io, &mbox.mutex);                      // Cancelable!void
condition_waitTimeout(&mbox.cond, io, &mbox.mutex, dl)    // workaround for missing waitTimeout
    catch |err| switch (err) { ... };
mbox.cond.signal(io);
mbox.cond.broadcast(io);
```

| Odin | Zig | Notes |
|------|-----|-------|
| `sync.mutex_lock(&m)` | `m.lock(io) catch ...` | Zig returns `Cancelable!void` |
| `sync.mutex_unlock(&m)` | `m.unlock(io)` | same semantics |
| `sync.cond_wait(&c, &m)` | `c.wait(io, &m)` | cancellation point in Zig |
| `sync.cond_wait_with_timeout(...)` | `condition_waitTimeout(...)` | Zig gap: no native waitTimeout (issue #31278) |
| `sync.cond_signal(&c)` | `c.signal(io)` | — |
| `sync.cond_broadcast(&c)` | `c.broadcast(io)` | — |

**Critical**: `std.Thread.Mutex` and `std.Thread.Condition` must NOT be used in `_Mbox` or `_Pool`. They do not go through the IO vtable and cannot return `error.Canceled`.

---

### 8. Intrusive list: `core:container/intrusive/list` vs `std.DoublyLinkedList`

**Odin**:

```odin
import list "core:container/intrusive/list"

l: list.List
list.push_back(&l, &ev.poly.node)
list.push_front(&l, &node.node)
raw := list.pop_front(&l)      // returns ^list.Node
result = mbx^.list             // list copy = atomic snapshot
mbx^.list = list.List{}        // reset to empty
```

**Zig**:

```zig
var l: std.DoublyLinkedList = .{};
l.append(&ev.poly.node);       // push_back
l.prepend(&node.node);         // push_front
const raw = l.popFirst();      // returns ?*std.DoublyLinkedList.Node
var result = l;                // copy struct = snapshot
l = .{};                       // reset to empty
```

| Odin | Zig |
|------|-----|
| `list.List` | `std.DoublyLinkedList` |
| `list.Node` | `std.DoublyLinkedList.Node` |
| `list.push_back(&l, &node)` | `l.append(&node)` |
| `list.push_front(&l, &node)` | `l.prepend(&node)` |
| `list.pop_front(&l)` | `l.popFirst()` |
| copy struct by value | same in Zig |
| `list.List{}` | `.{}` |

**Node definition is identical in concept**:

```odin
// Odin core:container/intrusive/list Node
Node :: struct { next, prev: ^Node }
```
```zig
// Zig std.DoublyLinkedList Node
pub const Node = struct { prev: ?*Node = null, next: ?*Node = null };
```

---

### 9. `map[rawptr]T` vs `std.AutoHashMapUnmanaged(*const anyopaque, T)`

**Odin** — built-in map, garbage-collected key/value:

```odin
lists:  map[rawptr]list.List
counts: map[rawptr]int

p^.lists  = make(map[rawptr]list.List, 16, alloc)
p^.counts = make(map[rawptr]int,       16, alloc)

p^.lists[tag]  = l           // store
p^.counts[tag] -= 1          // update
delete(p.lists)              // free
delete(p.counts)             // free

// iteration
for tag in ptr.lists {
    if list_ptr, ok := ptr.lists[tag]; ok { ... }
}
```

**Zig 0.16.0** — use `AutoHashMapUnmanaged`; explicit allocator per operation; init with `.empty`:

```zig
lists:  std.AutoHashMapUnmanaged(*const anyopaque, std.DoublyLinkedList),
counts: std.AutoHashMapUnmanaged(*const anyopaque, usize),

// Init: .empty (zero struct literal, no allocator stored in map)
p.lists  = .empty;
p.counts = .empty;

try p.lists.put(alloc, tag, l);   // allocator first
p.counts.getPtr(tag).?.* -= 1;   // read-only lookup, no alloc needed
p.lists.deinit(alloc);           // free
p.counts.deinit(alloc);          // free

// iteration (unchanged)
var it = p.lists.iterator();
while (it.next()) |entry| {
    const tag = entry.key_ptr.*;
    var list = entry.value_ptr;
    ...
}
```

**Key differences**: Odin map operations are infallible. Zig `put(alloc, k, v)` returns an error on OOM. In 0.16.0 all mutating operations take the allocator explicitly — the map does not store it. `getPtr(key)` and `get(key)` are read-only and need no allocator. The managed `ArrayHashMap`/`AutoArrayHashMap` variants were removed in 0.16.0. `std.AutoHashMap` (managed) and `std.AutoHashMapUnmanaged` both remain; `_Pool` uses `AutoHashMapUnmanaged` since it already holds `alloc: std.mem.Allocator`.

---

### 10. `[dynamic]rawptr` vs `std.ArrayList(*const anyopaque)`

**Odin** — built-in dynamic array:

```odin
tags: [dynamic]rawptr

append(&hooks.tags, EVENT_TAG)
defer delete(hooks.tags)
slice.contains(ptr.hooks.tags[:], tag)
```

**Zig 0.16.0** — `std.ArrayList`; `.init(allocator)` is gone, allocator passed per-operation:

```zig
tags: std.ArrayList(*const anyopaque),

// Init: .empty (no allocator stored in struct)
hooks.tags = .empty;

try hooks.tags.append(alloc, EVENT_TAG);   // allocator first
defer hooks.tags.deinit(alloc);            // allocator required
std.mem.indexOfScalar(*const anyopaque, hooks.tags.items, tag) != null
```

For fixed-size tag lists (common case), a `[]const *const anyopaque` slice avoids `ArrayList` entirely:

```zig
// Static tag list — no allocation needed
const TAGS = [_]*const anyopaque{ &event_tag, &sensor_tag };
hooks.tags = &TAGS;
```

---

### 11. `new` / `free` vs `alloc.create` / `alloc.destroy`

**Odin**:

```odin
mbx, err := new(_Mbox, alloc)
if err != .None { return nil }
// ...
free(mb, alloc)
```

**Zig**:

```zig
const mbx = try alloc.create(_Mbox);
mbx.* = std.mem.zeroes(_Mbox);  // explicit zero-init (or use .{} literal)
// ...
alloc.destroy(mb);
```

| Odin | Zig |
|------|-----|
| `new(T, alloc)` | `try alloc.create(T)` |
| `free(ptr, alloc)` | `alloc.destroy(ptr)` |
| auto zero-initialized | requires `= .{}` or `= std.mem.zeroes(T)` |
| returns `(^T, Allocator_Error)` | returns `Allocator.Error!*T` |

---

### 12. Enum result types vs error unions

**Odin** — enum result codes, checked with `==`:

```odin
SendResult :: enum { Ok, Closed, Invalid }

mbox_send :: proc(mb: Mailbox, m: ^MayItem) -> SendResult

if mbox_send(inbox, &mi) != .Ok { ... }
```

**Zig** — error union, checked with `try` / `catch` / `switch`:

```zig
pub fn mbox_send(mbh: MailboxHandle, m: *MayItem) error{Closed}!void

try mbox_send(inbox, &mi);                              // propagate
mbox_send(inbox, &mi) catch |err| { ... };              // handle
```

**Mapping of specific enums**:

| Odin Result | Zig Equivalent |
|------------|----------------|
| `SendResult.Ok` | `void` (success) |
| `SendResult.Closed` | `error.Closed` |
| `SendResult.Invalid` | `error.Invalid` or `@panic` |
| `RecvResult.Ok` | `void` (single item) or `?*std.DoublyLinkedList.Node` (batch — `mbox_receive_batch`) |
| `RecvResult.Closed` | `error.Closed` |
| `RecvResult.Interrupted` | removed — OOB via `mbox_send_oob` |
| `RecvResult.Timeout` | `error.Timeout` |
| `RecvResult.Already_In_Use` | `@panic` (precondition violation) |
| `Pool_Get_Result.Ok` | `void` |
| `Pool_Get_Result.Not_Available` | `error.NotAvailable` |
| `Pool_Get_Result.Not_Created` | `null` (hook returned nothing) or `error` |
| `Pool_Get_Result.Closed` | `error.Closed` |
| `Pool_Get_Result.Timeout` | `error.Timeout` (from `pool_get_wait` with `timeout_ns`) |
| `Pool_Get_Result.Already_In_Use` | `@panic` (precondition violation) |

**Note on nil returns**: Odin's `mbox_new` returns `nil` on allocation failure. Zig returns `error.OutOfMemory` via `!MailboxHandle`. This makes failure explicit and composable.

---

### 13. `#partial switch` vs exhaustive `switch`

**Odin** — `#partial switch` handles a subset of enum cases; unhandled fall through silently:

```odin
#partial switch res {
case .Ok:
    ...
case .Closed:
    return
case:
    fmt.printfln("unexpected: %v", res)
    return
}
```

**Zig** — `switch` is exhaustive by default; use `else` for unhandled cases:

```zig
switch (res) {
    .ok      => { ... },
    .closed  => return,
    else     => |err| { std.debug.print("unexpected: {}\n", .{err}); return err; },
}
```

With error unions:

```zig
mbox_receive(inbox, &mi, timeout_ns) catch |err| switch (err) {
    error.Closed       => return,
    error.Canceled     => return,
    error.Timeout      => continue,
};
```

**Key difference**: Zig's exhaustive switch catches missed cases at compile time. `#partial switch` silently ignores unhandled values. For error handling, Zig's `catch |err| switch` is more natural than Odin's switch on a result enum.

---

### 14. `@(private)` vs implicit file-scope privacy

**Odin** — `@(private)` makes a declaration private to the package:

```odin
@(private)
mailbox_tag: PolyTag = {}
MAILBOX_TAG: rawptr = &mailbox_tag

@(private)
_Mbox :: struct { ... }

@(private)
_unwrap :: proc(m: Mailbox) -> ^_Mbox { ... }
```

**Zig** — declarations without `pub` are private by default:

```zig
var mailbox_tag: PolyTag = .{};         // private: no pub
pub const MAILBOX_TAG: *const anyopaque = &mailbox_tag;

const _Mbox = struct { ... };            // private: no pub

fn unwrap(m: Mailbox) *_Mbox { ... }    // private: no pub
```

**Note**: In Zig, `pub` is explicit — you must mark things public. In Odin, symbols are public by default and made private with `@(private)`. The visibility model is inverted.

---

### 15. `#force_inline proc` vs `inline fn`

**Odin**:

```odin
mailbox_is_it_you :: #force_inline proc(tag: rawptr) -> bool {
    return tag == MAILBOX_TAG
}
```

**Zig**:

```zig
pub inline fn mailbox_is_it_you(tag: *const anyopaque) bool {
    return tag == MAILBOX_TAG;
}
```

`#force_inline` → `inline fn`. Both guarantee the function is always inlined.

---

### 16. `panic` vs `@panic`

**Odin**:

```odin
panic("mbox_send: node is still linked — detach before sending")
panic("non-mailbox is used for mailbox operations")
```

**Zig**:

```zig
@panic("mbox_send: node is still linked — detach before sending");
@panic("non-mailbox is used for mailbox operations");
```

Direct substitution. Both abort with a message. In Zig, `@panic` is a builtin; in Odin, `panic` is a procedure from the `builtin` package.

---

### 17. `context.allocator` vs explicit allocator parameter

**Odin** — implicit `context` threading:

```odin
alloc := context.allocator
p := matryoshka.pool_new(alloc)
```

**Zig** — no implicit context; allocator passed explicitly:

```zig
// Caller holds the allocator and passes it where needed
const p = try pool_new(io, allocator);
```

**Impact**: Every function that allocates in Odin can use `context.allocator` without a parameter. In Zig, any function that allocates must receive `alloc: std.mem.Allocator` explicitly. This is already reflected in the Zig API: `mbox_new(io, alloc)` and `pool_new(io, alloc)`.

---

### 18. Thread API: `core:thread` vs `std.Thread`

**Odin**:

```odin
import "core:thread"

t := thread.create(worker_proc)  // worker_proc :: proc(t: ^thread.Thread)
t.data = m                        // pass data via thread.data field
thread.start(t)
defer thread.destroy(t)
thread.join(t)
```

**Zig**:

```zig
const t = try std.Thread.spawn(.{}, worker_proc, .{m});
// worker_proc :: fn (m: *Master) void  — args passed directly, no .data field
defer t.join();
```

**Key difference**: Odin passes data through `thread.data: rawptr`. Zig passes arguments directly to the thread function as a tuple — no side-channel needed. `thread.destroy` is implicit when the thread handle is no longer used (or explicit via detach/join).

---

### 19. Map / list iteration

**Odin**:

```odin
// Map iteration — keys and values
for tag in ptr.lists {
    if list_ptr, ok := ptr.lists[tag]; ok {
        for {
            node := list.pop_front(&list_ptr)
            if node == nil { break }
            list.push_back(&all_items, node)
        }
    }
}

// walk intrusive list and free each node
for {
    raw := list.pop_front(&remaining)
    if raw == nil { break }
    poly := (^PolyNode)(raw)
    // ...
}
```

**Zig**:

```zig
// Map iteration — valueIterator or full iterator
var it = p.lists.iterator();
while (it.next()) |entry| {
    var list = entry.value_ptr;
    while (list.popFirst()) |node| {
        result.append(node);
    }
}

// walk intrusive list and free each node
while (remaining.popFirst()) |dll_node| {
    const poly: *PolyNode = @fieldParentPtr("node", dll_node);
    // ...
}
```

Odin's `for ... { if raw == nil { break } }` pattern maps to Zig's `while (expr) |val| {}` loop — more idiomatic and avoids the explicit nil check.

---

### 20. Zero initialization

**Odin** — all struct values are zero-initialized by default:

```odin
result := list.List{}    // explicit zero struct literal
// or:
_mbox: _Mbox            // also zero-initialized (without =)
```

**Zig** — must be explicit:

```zig
var result: std.DoublyLinkedList = .{};   // zero struct literal
const mbox = try alloc.create(_Mbox);
mbox.* = .{};                             // must zero-init after create
```

Zig's `undefined` is deliberately NOT zero — it triggers safety checks in debug mode. Always use `.{}` or `std.mem.zeroes(T)` after `alloc.create(T)`.

---

### 21. Type-checking dispatch patterns

**Odin** — raw tag comparison then cast:

```odin
if event_is_it_you(poly.tag) {
    ev := (^Event)(poly)
    // use ev
} else if sensor_is_it_you(poly.tag) {
    s := (^Sensor)(poly)
    // use s
} else {
    panic("unknown tag")
}
```

**Zig** — same logic, `@fieldParentPtr` for recovery:

```zig
if (event_is_it_you(poly.tag)) {
    const ev: *Event = @fieldParentPtr("poly", poly);
    // use ev
} else if (sensor_is_it_you(poly.tag)) {
    const s: *Sensor = @fieldParentPtr("poly", poly);
    // use s
} else {
    @panic("unknown tag");
}
```

The pattern is structurally identical. The only difference is `@fieldParentPtr` replacing the bare cast.

---

### Quick Reference Table

| Odin idiom | Zig 0.16 equivalent |
|-----------|---------------------|
| `PolyTag :: struct { _: u8 }` | `const PolyTag = struct { _: u8 = 0 }` — unique address per instance |
| `using poly: PolyNode` at offset 0 | embed as named field `poly: PolyNode`; recover with `@fieldParentPtr("poly", p)` |
| `(^UserType)(poly)` | `@fieldParentPtr("poly", poly)` — two-level chain validated at compile time |
| `rawptr` | `*const anyopaque` (for tags); `*anyopaque` (for mutable ctx) |
| `Maybe(^PolyNode)` | `?*PolyNode` |
| `ptr, ok := m^.?` | `if (m.*) \|ptr\| { ... }` |
| `m^` | `m.*` |
| `^T` | `*T` |
| `nil` | `null` |
| `Mailbox :: ^PolyNode` opaque handle | `MailboxHandle = *PolyNode` |
| `Pool :: ^PolyNode` opaque handle | `PoolHandle = *PolyNode` |
| `cast(^T)ptr` | `@fieldParentPtr("field", ptr)` or `@ptrCast(@alignCast(ptr))` |
| `#force_inline proc` | `inline fn` |
| `@(private)` | omit `pub` |
| `panic(msg)` | `@panic(msg)` |
| `io` passed at each call | `io: Io` stored in `_Mbox` and `_Pool` at init |
| `context.allocator` implicit | explicit `alloc: std.mem.Allocator` parameter |
| `sync.Mutex` + `sync.Cond` | `Io.Mutex` + `Io.Condition` (IO-aware, cancellable) |
| `sync.cond_wait_with_timeout(...)` | `condition_waitTimeout(...)` (workaround for Zig issue #31278) |
| `list.List` / `list.Node` | `std.DoublyLinkedList` / `std.DoublyLinkedList.Node` |
| `list.push_back(&l, &node)` | `l.append(&node)` |
| `list.pop_front(&l)` | `l.popFirst()` |
| `map[rawptr]T` | `std.AutoHashMapUnmanaged(*const anyopaque, T)` — `ArrayHashMap`/`AutoArrayHashMap` managed variants removed in 0.16.0; `AutoHashMap` (managed) still exists |
| `make(map[...], cap, alloc)` | `var m: std.AutoHashMapUnmanaged(K,V) = .empty;` — allocator passed per-op, not stored in map |
| `m[tag] = v` | `try m.put(alloc, tag, v)` — allocator is first arg |
| `delete(map)` | `map.deinit(alloc)` — allocator required |
| `[dynamic]rawptr` | `std.ArrayList(*const anyopaque)` — `.init(alloc)` gone; use `.empty` + `append(alloc, item)` / `deinit(alloc)` |
| `new(T, alloc)` | `try alloc.create(T)` |
| `free(ptr, alloc)` | `alloc.destroy(ptr)` |
| auto zero-initialized | explicit `.{}` or `std.mem.zeroes(T)` |
| result enum (Ok/Closed/...) | `error{Closed,...}!void` error union |
| `#partial switch res { case .X: ... }` | `switch (res) { .x => ..., else => ... }` |
| `closed: bool` under mutex | `closed: std.atomic.Value(bool)` — pre-lock fast-path |
| `thread.create(proc)` + `t.data = ptr` | `std.Thread.spawn(.{}, proc, .{ptr})` or `io.concurrent(proc, .{ptr})` |
| `for tag in map { ... }` | `var it = map.iterator(); while (it.next()) \|e\| { ... }` |
| `for { raw := pop(); if raw == nil { break } }` | `while (list.popFirst()) \|node\| { ... }` |
| `try_receive_batch(mb)` | `mbox_receive_batch(mb)` — returns `std.DoublyLinkedList` (empty list if nothing) |
| `pool_put_all(p, m: ^MayItem)` | `pool_put_all(pool, list: *std.DoublyLinkedList)` — explicit list struct; same operation |
| `mbox_interrupt(mb)` | `mbox_send_oob(mb, m)` — OOB signal is a PolyNode prepended to front |
| `mailbox_is_it_you(tag)` | `mailbox_is_it_you(tag: *const anyopaque) bool` |
| `pool_is_it_you(tag)` | `pool_is_it_you(tag: *const anyopaque) bool` |
| `pool_close(p) -> (list.List, ^PoolHooks)` | `pool_close(pool) void` — on_close receives `*std.DoublyLinkedList`; caller retains hooks reference |
| `panic` on misuse | `@panic` or `unreachable` |
