# Matryoshka API Reference — Zig 0.16

Matryoshka is a small ownership-oriented infrastructure toolkit. It provides three independent building blocks:

- **polynode** — ownership identity
- **mbox** — ownership transport
- **pool** — ownership lifecycle

Applications combine these blocks to create coordinators, workers, services, pipelines, and other higher-level architectures. All objects follow the same ownership rules based on `PolyNode` and `MayItem`.

Matryoshka uses move semantics. Whenever ownership is transferred, the source `MayItem` becomes `null` and the destination becomes the sole owner.

Module: `@import("matryoshka")`

---

## polynode

Types and functions for ownership identity.

```zig
const polynode = @import("matryoshka").polynode;

// typical usage:
var item: polynode.MayItem = &event.poly;   // owns the node
item = null;                                 // releases ownership
```

### Types

```zig
pub const PolyTag = struct { _: u8 = 0 };

pub const PolyNode = struct {
    node: std.DoublyLinkedList.Node,
    tag:  *const anyopaque,
};

pub const MayItem = ?*PolyNode;
```

### Functions

```zig
pub fn reset(n: *PolyNode) void
```
Clears intrusive link pointers (`prev`, `next` to null).

```zig
pub fn is_linked(n: *PolyNode) bool
```
Returns true if node is currently linked into a list.

### Ownership rule

Tag checks, typed casts, and `@fieldParentPtr` recovery never transfer ownership. These are read-only inspections of an existing node.

### Defining user types

User types embed `poly: PolyNode` and define a unique tag address for runtime identity:

```zig
pub const Event = struct {
    poly: PolyNode,
    code: i32,
};

var _event_tag: PolyTag = .{};
pub const EVENT_TAG: *const anyopaque = &_event_tag;
```

Tag check, typed cast, and initialization are user code — see `tests/helpers/types.zig` for the pattern.

### stdlib compatibility

PolyNode embeds `std.DoublyLinkedList.Node`. Every PolyNode-based item participates in standard `std.DoublyLinkedList` operations — no custom list type, no adapter.

Batch operations like `mbox.close()`, `mbox.receive_batch()`, and `pool.put_all()` use plain `std.DoublyLinkedList`. Walk results with `popFirst()` — standard Zig, nothing Matryoshka-specific.

---

## mbox

Ownership transport between execution contexts.

```zig
const mbox = @import("matryoshka").mbox;

// typical usage:
try mbox.send(inbox, &item);              // item is now null
try mbox.receive(inbox, &item, null);     // item is now non-null
```

### Types

```zig
pub const MailboxHandle = *PolyNode;
```

MailboxHandle is itself a PolyNode. A mailbox can be sent through another mailbox, stored in pools, or embedded into larger ownership graphs using the same rules as application objects.

### Functions

```zig
pub fn new(io: Io, alloc: std.mem.Allocator) !MailboxHandle
```
Creates a new mailbox. Stores `io` internally.

```zig
pub fn destroy(mbh: MailboxHandle, alloc: std.mem.Allocator) void
```
Frees the mailbox. Must be closed first. Calling destroy on an open mailbox is a programming error (panic).

```zig
pub fn send(mbh: MailboxHandle, m: *MayItem) error{Closed}!void
```
Appends item to tail. Transfers ownership — `m.*` set to null. Cancelable (work path).

```zig
pub fn send_oob(mbh: MailboxHandle, m: *MayItem) error{Closed}!void
```
Inserts item after last OOB item (FIFO among OOBs, all OOBs before regular items). Transfers ownership — `m.*` set to null. Cancelable (work path).

```zig
pub fn receive(mbh: MailboxHandle, m: *MayItem, timeout_ns: ?u64) (error{ Closed, Timeout } || Cancelable)!void
```
Blocks until item available. `null` timeout = wait forever. Transfers ownership — `m.*` set to non-null. OOB items arrive first (front of queue).

```zig
pub fn try_receive(mbh: MailboxHandle, m: *MayItem) error{Closed}!bool
```
Non-blocking. Returns true if item received, false if queue empty.

```zig
pub fn receive_batch(mbh: MailboxHandle) (error{Closed} || Cancelable)!std.DoublyLinkedList
```
Non-blocking. Snapshots entire queue under one lock acquisition. Returns empty `std.DoublyLinkedList` if queue is currently empty — does not wait, does not return error for empty. Resets OOB tracking.

```zig
pub fn close(mbh: MailboxHandle) std.DoublyLinkedList
```
Idempotent. Snapshots remaining items, broadcasts to wake blocked receivers. Returns remaining items as list (empty list on second call). Uses `lockUncancelable`. Resets OOB tracking.

```zig
pub fn is_it_you(tag: *const anyopaque) bool
```
Returns true if tag identifies a MailboxHandle.

### Error sets

| Error | Meaning |
|-------|---------|
| `error.Closed` | mailbox was closed via `close()` |
| `error.Timeout` | `timeout_ns` expired (only when non-null) |
| `error.Canceled` | Waiting operation was canceled |

### Integration with std.Io

`mbox.receive` may be used from tasks spawned through `io.concurrent()`, `Io.Group`, or `Io.Select`. When a mailbox is closed, blocked receivers wake with `error.Closed`. When a task is canceled while blocked in `mbox.receive`, the operation returns `error.Canceled`. This allows mailbox operations to compose naturally with Zig's `std.Io` concurrency primitives.

### Event source helpers

Mailbox can participate directly in `Io.Select` as an event source. These helpers bridge the blocking API to the Future/Select world.

#### Types

```zig
pub const ReceiveResult = union(enum) {
    item: MayItem,
    closed: void,
    timeout: void,
    canceled: void,
};
```

Result carries the item by value — no cross-thread `*MayItem` pointer. When `select.await()` returns `.item`, the caller is sole owner.

#### Functions

```zig
pub fn receive_select(mbh: MailboxHandle, timeout_ns: ?u64) ReceiveResult
```
Adapter from error-union API to `ReceiveResult`. Creates a local `MayItem`, calls `receive`, maps the result to the union. Use as a Select event source via `select.concurrent(.tag, mbox.receive_select, .{mbh, timeout})`.

```zig
pub fn receive_future(mbh: MailboxHandle, timeout_ns: ?u64) ConcurrentError!Io.Future(ReceiveResult)
```
Spawns `receive_select` as a concurrent task using the mailbox's stored `io`. Returns a Future that can be awaited directly, fed to Select, or fed to Group. Returns `error.ConcurrencyUnavailable` on single-threaded backends.

#### Cancel behavior

Cancel never triggers close. On `error.Canceled`, the adapter returns `.canceled` — the mailbox remains open. Closing is the Master's responsibility.

#### When to use

**Inside Matryoshka**: when items carry ownership, use fan-in — many senders send tagged PolyNodes to one mailbox, Master dispatches on tag. One queue, one ownership model, one shutdown model.

**Bridging to external Io**: use `receive_select` / `receive_future` — mailbox traffic alongside timers, sockets, files, or pool availability in one `Io.Select` loop.

### Advanced: OOB ordering

```
send(R1), send(R2):       [R1, R2]                oob=0
send_oob(O1):             [O1, R1, R2]            oob=1
send(R3):                 [O1, R1, R2, R3]        oob=1
send_oob(O2):             [O1, O2, R1, R2, R3]   oob=2
receive → O1:             [O2, R1, R2, R3]        oob=1
receive → O2:             [R1, R2, R3]            oob=0
```

---

## pool

Lifecycle management with hooks.

```zig
const pool = @import("matryoshka").pool;

// typical usage:
try pool.get(ph, EVENT_TAG, .available_or_new, &item);   // item is now non-null
pool.put(ph, &item);                                      // item is now null (if kept)
```

### Types

```zig
pub const PoolHandle = *PolyNode;
```

PoolHandle is itself a PolyNode. A pool can be sent through a mailbox or embedded into larger ownership graphs using the same rules as application objects.

```zig
pub const GetMode = enum {
    available_or_new,    // use stored item if available, otherwise call on_get to create
    new_only,            // always call on_get with m.* == null to create fresh
    available_only,      // use stored item only; if empty, return error.NotAvailable
};

pub const GetError = error{
    Closed,
    NotAvailable,
    NotCreated,
    AlreadyInUse,
};
```

### PoolHooks

```zig
pub const PoolHooks = struct {
    ctx:      *anyopaque,
    tags:     []const *const anyopaque,
    on_get:   *const fn (ctx: *anyopaque, tag: *const anyopaque, in_pool_count: usize, m: *MayItem) void,
    on_put:   *const fn (ctx: *anyopaque, in_pool_count: usize, m: *MayItem) void,
    on_close: *const fn (ctx: *anyopaque, list: *std.DoublyLinkedList) void,
};
```

### Functions

```zig
pub fn new(io: Io, alloc: std.mem.Allocator) !PoolHandle
```
Creates a new pool. Stores `io` internally.

```zig
pub fn destroy(ph: PoolHandle, alloc: std.mem.Allocator) void
```
Frees the pool. Must be closed first. Calling destroy on an open pool is a programming error (panic).

```zig
pub fn init(ph: PoolHandle, hooks: PoolHooks) !void
```
Registers hooks and tag set. Called once after `new`.

```zig
pub fn get(ph: PoolHandle, tag: *const anyopaque, mode: GetMode, m: *MayItem) GetError!void
```
Non-blocking acquisition. Calls `on_get` hook. Transfers ownership — `m.*` set to non-null on success.

```zig
pub fn get_wait(ph: PoolHandle, tag: *const anyopaque, m: *MayItem, timeout_ns: ?u64) (GetError || Cancelable || error{Timeout})!void
```
Blocking acquisition. `null` timeout = wait forever. Calls `on_get` hook.

```zig
pub fn put(ph: PoolHandle, m: *MayItem) void
```
Returns item to pool. Calls `on_put` hook (policy decides keep or destroy). Cancel-protected (`lockUncancelable`). If pool is closed, `m.*` stays non-null (caller still owns it).

```zig
pub fn put_all(ph: PoolHandle, list: *std.DoublyLinkedList) void
```
Returns batch of items to pool. Cancel-protected. Pops from caller's list.

```zig
pub fn close(ph: PoolHandle) void
```
Idempotent. Collects all items from all per-tag free-lists, calls `on_close` once with the full list. Broadcasts to wake blocked `get_wait` callers. Cancel-protected (`lockUncancelable`).

```zig
pub fn is_it_you(tag: *const anyopaque) bool
```
Returns true if tag identifies a PoolHandle.

### Error sets

| Error | Meaning |
|-------|---------|
| `error.Closed` | pool was closed via `close()` |
| `error.NotAvailable` | `available_only` mode, no stored item |
| `error.NotCreated` | `on_get` was called but did not return an item |
| `error.AlreadyInUse` | Entry contract violation: `m.*` was not null on call |
| `error.Timeout` | `timeout_ns` expired (only when non-null, `get_wait` only) |
| `error.Canceled` | Waiting operation was canceled (`get_wait` only) |

### Event source helpers

Pool can participate directly in `Io.Select` as an event source. Pool availability as an event enables the job-pool pattern: worker returns an item → Master is notified → Master submits new work.

#### Types

```zig
pub const PoolResult = union(enum) {
    item: MayItem,
    closed: void,
    timeout: void,
    canceled: void,
    not_created: void,
};
```

Result carries the item by value — no cross-thread `*MayItem` pointer. The `.item` arm hands ownership to the caller: the `get_wait` that produced it has already removed the item from the pool. Re-spawn the event source only after deciding the item's fate.

#### Functions

```zig
pub fn get_wait_select(ph: PoolHandle, tag: *const anyopaque, timeout_ns: ?u64) PoolResult
```
Adapter from error-union API to `PoolResult`. Creates a local `MayItem`, calls `get_wait`, maps the result to the union. Use as a Select event source via `select.concurrent(.tag, pool.get_wait_select, .{ph, node_tag, timeout})`.

```zig
pub fn get_wait_future(ph: PoolHandle, tag: *const anyopaque, timeout_ns: ?u64) ConcurrentError!Io.Future(PoolResult)
```
Spawns `get_wait_select` as a concurrent task using the pool's stored `io`. Returns a Future. Returns `error.ConcurrencyUnavailable` on single-threaded backends.

#### Cancel behavior

Cancel never triggers close. On `error.Canceled`, the adapter returns `.canceled` — the pool remains open. Closing is the Master's responsibility.

### Hook discipline

- Hooks run outside the pool mutex
- `on_get`: must either leave `m.* == null` (creation failed) OR set `m.*` to a valid node (created or reinitialized). No other state is permitted
- `on_put`: set `m.*` to null = destroy. Leave non-null = keep in pool
- `on_close`: receives `*std.DoublyLinkedList`, walks via `popFirst()`, frees each item
- Do NOT call pool functions on the same pool from inside hooks (contract violation, not deadlock — hooks run outside the mutex, but calling back collapses the infrastructure/policy separation)

---

## matryoshka (root)

```zig
pub const polynode = @import("polynode.zig");
pub const mbox = @import("mbox.zig");
pub const pool = @import("pool.zig");
```

No generic `dispose`. Use `mbox.destroy` and `pool.destroy` directly. Application types destroy themselves.

---

## Master (Layer 4) — intentionally not part of the API

There is no `master` module. There is no `Master` struct. This is by design.

Master is an architectural role — the coordination boundary that owns and composes the lower layers. Applications build Masters from:

| What | Where it comes from |
|------|-------------------|
| Transport | `mbox.MailboxHandle` — one or more mailboxes |
| Lifecycle | `pool.PoolHandle` + `pool.PoolHooks` — item reuse and policy |
| Memory | `std.mem.Allocator` — who allocates and frees |
| Scheduling | `std.Io` — passed to `mbox.new` and `pool.new` |
| Worker coordination | `io.concurrent()` → `Future`, or `Io.Group` |
| Cancellation | `Future.cancel(io)` or `group.cancel(io)` |
| Application state | Domain-specific — whatever the subsystem needs |

Both mailbox and pool are optional. Valid combinations:

```text
PolyNode only                        ownership without infrastructure
PolyNode + Mailbox                   ownership + transport
PolyNode + Pool                      ownership + lifecycle
PolyNode + Pool + Io.Select          lifecycle + event sources (no mailbox)
PolyNode + Mailbox + Pool            transport + lifecycle
PolyNode + Mailbox + Pool + Io.Select   full stack
```

A Master may be:
```zig
const Server = struct { inbox: mbox.MailboxHandle, pool: pool.PoolHandle, ... };
const Scheduler = struct { pool: pool.PoolHandle, ... };  // no mailbox
const Pipeline = struct { stages: [3]mbox.MailboxHandle, ... };
fn main(init: std.process.Init) !void { ... }
```

Matryoshka provides the building blocks. The application assembles them.

---

## Cancel contract summary

| Function | Cancelable | Cancel-protected | Notes |
|----------|-----------|-----------------|-------|
| `mbox.send` | yes | no | work path |
| `mbox.send_oob` | yes | no | work path |
| `mbox.receive` | yes | no | primary cancel point |
| `mbox.try_receive` | yes | no | non-blocking |
| `mbox.receive_batch` | yes | no | non-blocking |
| `mbox.close` | no | yes (`lockUncancelable`) | cleanup |
| `pool.get` | yes | no | non-blocking |
| `pool.get_wait` | yes | no | primary cancel point |
| `pool.put` | no | yes (`lockUncancelable`) | cleanup |
| `pool.put_all` | no | yes (`lockUncancelable`) | cleanup |
| `pool.close` | no | yes (`lockUncancelable`) | cleanup |
| `mbox.receive_select` | yes | no | adapter — inherits from `mbox.receive` |
| `mbox.receive_future` | yes | no | spawns `receive_select` concurrently |
| `pool.get_wait_select` | yes | no | adapter — inherits from `pool.get_wait` |
| `pool.get_wait_future` | yes | no | spawns `get_wait_select` concurrently |

---

## Ownership lifecycle

```
FREE       — allocated, not in any system
IN_FLIGHT  — owned by user code (MayItem non-null)
HELD       — owned by infrastructure (in mailbox queue or pool free-list)
```

| Operation | Before → After |
|-----------|---------------|
| `mbox.send` | IN_FLIGHT → HELD |
| `mbox.receive` | HELD → IN_FLIGHT |
| `pool.get` | HELD → IN_FLIGHT |
| `pool.put` (keep) | IN_FLIGHT → HELD |
| `pool.put` (destroy) | IN_FLIGHT → FREE |
| `mbox.close` | HELD → returned to caller |
| `pool.close` | HELD → passed to on_close |

---

## Contract violations

The following are programming errors (panic):

- Double insertion — pushing a linked node into a list
- Use after free — using a node after its memory was freed
- Destroying an open mailbox or pool — must close first
- Corrupted or invalid tag — tag does not match any known type

---

## Layer dependencies

```
             Layer 4
             Master
                |
      +---------+---------+
      |                   |
   Layer 2            Layer 3
   Mailbox              Pool
      |                   |
      +---------+---------+
                |
            Layer 1
           Ownership
```

Mailbox and Pool are independent — neither depends on the other. Both depend only on the ownership model. Master is where they are combined.

Valid combinations:
- Layer 1 only — ownership without infrastructure
- Layer 1 + Layer 2 — ownership + transport, no lifecycle
- Layer 1 + Layer 3 — ownership + lifecycle, no transport
- Layer 1 + Layer 2 + Layer 3 + Io — full stack (Master)
