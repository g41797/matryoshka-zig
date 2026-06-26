# Matryoshka API Reference — Zig 0.16

> Function descriptions in this reference serve as the source for `///` Zig doc comments in the implementation.

Matryoshka is a small ownership-oriented infrastructure toolkit.
It provides three independent building blocks:

- **polynode** — ownership identity
- **mailbox** — ownership transport
- **pool** — ownership lifecycle

Applications combine these blocks to create:
- coordinators
- workers
- services
- pipelines
- other higher-level architectures

All objects follow the same ownership rules based on `PolyNode` and `NodeHandle`.

Matryoshka moves ownership of handles.
Everything transported is a `NodeHandle` (`*PolyNode`):
- events
- requests
- mailboxes
- pools

A `Slot` (`?NodeHandle`) is where a handle lives while you own it.

Module: `@import("matryoshka")`

---

## Prolog: std.Io

Zig 0.16 provides `std.Io` — the runtime's interface for concurrent and I/O operations.

- `Io` — passed around to anything that needs threads, timers, or waiting. Think of it as "access to the runtime."
- `Future(T)` — a result that isn't ready yet. You get the value by calling `.await()`.
- `Io.Select` — waits on several Futures at once. Returns the first one that completes.
- `Io.Group` — runs several tasks. Waits for all of them to finish.
- `io.concurrent()` — runs a blocking function in a separate task. Returns a Future for the result.
- `ConcurrentError` — spawning a task failed (e.g. single-threaded backend, no threads available).

### Event sources

An event source is anything that produces a `Future`.

```text
  Timer ─────────► Future(void)
  Socket read ───► Future([]u8)
  File I/O ──────► Future([]u8)
  concurrent() ──► Future(T)
                        │
                        ▼
                   Io.Select
                      │   │
                      ▼   ▼
               completed  canceled
               (result)   (error.Canceled)
```

### Cancel

A function that waits — for data, for a timeout, for a condition — can be canceled by the runtime.
- If a function can be canceled, its return type includes `Cancelable` in the error union.
- `Cancelable` comes from `std.Io`.

Cancel is something you do to a Future, not something that happens on its own:

```text
  concurrent() ──► Future(T)
                      │
              ┌───────┼───────┐
              ▼               ▼
          .await()        .cancel(io)
              │               │
              ▼               ▼
           result      error.Canceled
```

---

## Ownership model

```text
Slot (holds a handle)            Empty Slot

+-------------------+            +-------------------+
|                   |            |                   |
|    NodeHandle     |            |       null        |
|                   |            |                   |
+-------------------+            +-------------------+

  Slot = ?NodeHandle               Slot = null
```

### send — ownership moves out

```text
Before                           After

sender Slot                      sender Slot
+-------------------+            +-------------------+
|    NodeHandle     |            |       null        |
+-------------------+            +-------------------+

mailbox.send(mbh, &slot)  ───►      Mailbox owns NodeHandle
```

### receive — ownership moves in

```text
Before                           After

receiver Slot                    receiver Slot
+-------------------+            +-------------------+
|       null        |            |    NodeHandle     |
+-------------------+            +-------------------+

mailbox.receive(mbh, &slot, null)   Receiver owns NodeHandle
```

### What is a NodeHandle?

`NodeHandle` is a pointer to an embedded `PolyNode`.
- Every user type embeds a `PolyNode`.
- `NodeHandle` points to that embedded node.
- Matryoshka only sees the handle — not the surrounding type.

```text
User object                      Infrastructure object

+------------------+             +------------------+
|      Event       |             |     Mailbox      |
|------------------|             |------------------|
| poly: PolyNode   |             | poly: PolyNode   |
| code: i32        |             | ...              |
+------------------+             +------------------+
        |                                |
        v                                v
   NodeHandle                     MailboxHandle
   (*PolyNode)                    (= NodeHandle)
```

All handles are `NodeHandle`. Specialized names are aliases:

```text
NodeHandle = *PolyNode
    ├── MailboxHandle = NodeHandle
    ├── PoolHandle    = NodeHandle
    └── (any user handle)

Slot = ?NodeHandle
```

---

## polynode

Types and functions for ownership identity.

```zig
const polynode = @import("matryoshka").polynode;

// typical usage:
var slot: polynode.Slot = &event.poly;   // owns the node
slot = null;                              // releases ownership
```

### Types

```zig
pub const PolyTag = struct { _: u8 = 0 };

pub const PolyNode = struct {
    node: std.DoublyLinkedList.Node,
    tag:  *const anyopaque,
};

pub const NodeHandle = *PolyNode;
pub const Slot = ?NodeHandle;
```

### Functions

```zig
pub fn reset(n: *PolyNode) void
```
- Clears intrusive link pointers (`prev`, `next` to null).

```zig
pub fn is_linked(n: *PolyNode) bool
```
- Returns true if node is currently linked into a list.

### Ownership rule

These operations never transfer ownership:
- tag checks
- typed casts
- `@fieldParentPtr` recovery

Read-only inspections of an existing node.

### Defining user types — manual step by step

Every PolyNode-based type needs four things:
- A struct with an embedded `poly: PolyNode` field.
- A unique tag address for runtime type identity.
- A way to check the tag before casting.
- A way to cast from `*PolyNode` back to `*YourType`.

This section builds each piece manually. Understanding this is the foundation
for everything in Matryoshka.

---

#### Step 1 — Define the struct

Embed `poly: PolyNode`. This is the hook that lets Matryoshka see your type.

```zig
pub const Event = struct {
    poly: PolyNode,
    code: i32,
};
```

What the memory looks like:

```text
Event instance
+---------------------------+
| poly: PolyNode            |
|   +---------------------+ |
|   | node: DLL.Node      | |
|   |   prev: ?*DLL.Node  | |
|   |   next: ?*DLL.Node  | |
|   | tag: *const anyopaque| |
|   +---------------------+ |
| code: i32                 |
+---------------------------+
```

Why: Matryoshka never sees `Event`. It only sees `*PolyNode`.
The `poly` field is the bridge between your type and the infrastructure.

---

#### Step 2 — Create a unique tag

A tag is just an address. Two different variables have two different addresses.
Same variable always has the same address.

```zig
var _event_tag: PolyTag = .{};
pub const EVENT_TAG: *const anyopaque = &_event_tag;
```

Why `var` not `const`: a mutable global has a guaranteed unique runtime address.
`const` may be deduplicated by the linker.

Why it's unique: each `var` declaration occupies its own memory location.
`&_event_tag` is that location's address. No two `var` declarations share an address.

```text
Memory layout (two types):

_event_tag:  [address 0x1000]  PolyTag
_sensor_tag: [address 0x1008]  PolyTag

EVENT_TAG  = 0x1000   (unique)
SENSOR_TAG = 0x1008   (unique, different from EVENT_TAG)
```

---

#### Step 3 — Set the tag at construction

When you create an instance, store the tag in `poly.tag`.

```zig
var ev: Event = .{ .code = 42 };
ev.poly = .{ .node = .{}, .tag = EVENT_TAG };
```

What happened:

```text
Before                          After

Event                           Event
+------------------+            +------------------+
| poly: PolyNode   |            | poly: PolyNode   |
|   node: {null}   |            |   node: {null}   |
|   tag: undefined  |            |   tag: EVENT_TAG  |
| code: 42         |            | code: 42         |
+------------------+            +------------------+
```

Why: the tag is how you identify what type a `*PolyNode` points into.
Without it, you cannot safely cast.

---

#### Step 4 — Get a pointer to the embedded PolyNode

This is how your type enters the Matryoshka world.

```zig
const poly: *PolyNode = &ev.poly;
```

Now Matryoshka can work with `poly`. It does not know about `Event`.

```text
ev: Event                        poly: *PolyNode
+------------------+                    |
| poly: PolyNode   | <-----------------+
|   node: {null}   |
|   tag: EVENT_TAG |
| code: 42         |
+------------------+
```

---

#### Step 5 — Check the tag before casting

You have a `*PolyNode`. You need to know what it points into.
Compare the tag:

```zig
if (poly.tag == EVENT_TAG) {
    // safe to cast to *Event
}
```

Why check first: `@fieldParentPtr` does not validate anything.
If you cast a Sensor's PolyNode to `*Event`, you get garbage.
The tag check is the only runtime safety you have.

```text
poly.tag == EVENT_TAG ?

  YES → this PolyNode is inside an Event → safe to cast
  NO  → this PolyNode is inside something else → do not cast
```

---

#### Step 6 — Cast back to the outer type

`@fieldParentPtr` recovers the containing struct from a pointer to its field.

```zig
const recovered: *Event = @fieldParentPtr("poly", poly);
```

What `@fieldParentPtr` does:

```text
poly: *PolyNode
      |
      v
+------------------+
| poly: PolyNode   |  <-- poly points here
|   ...            |
| code: 42         |
+------------------+
^
|
recovered: *Event      <-- @fieldParentPtr subtracts the field offset
```

The field name `"poly"` is validated at compile time.
The offset calculation is done at compile time.
Runtime cost: one pointer subtraction.

---

#### Step 7 — Two-level recovery (from list node)

Inside a mailbox or pool, items are linked via `std.DoublyLinkedList`.
The list operates on `*DoublyLinkedList.Node`, not `*PolyNode`.

Recovery is two steps:

```zig
// Step 1: DLL.Node → PolyNode (done inside mailbox/pool)
const poly: *PolyNode = @fieldParentPtr("node", dll_node_ptr);

// Step 2: PolyNode → user type (done in user code, after tag check)
const ev: *Event = @fieldParentPtr("poly", poly);
```

```text
dll_node_ptr: *DLL.Node
      |
      v
+---------------------------+
| poly: PolyNode            |
|   +---------------------+ |
|   | node: DLL.Node      | | <-- dll_node_ptr points here
|   |   prev, next        | |
|   | tag: EVENT_TAG       | |
|   +---------------------+ |
| code: 42                 |
+---------------------------+
^           ^
|           |
|           poly: *PolyNode    (Step 1: @fieldParentPtr("node", dll_node_ptr))
|
ev: *Event                     (Step 2: @fieldParentPtr("poly", poly))
```

---

#### Complete manual example

All steps together:

```zig
// Define type
pub const Event = struct {
    poly: PolyNode,
    code: i32,
};

// Create unique tag
var _event_tag: PolyTag = .{};
pub const EVENT_TAG: *const anyopaque = &_event_tag;

// Create and initialize
var ev: Event = .{ .code = 42 };
ev.poly = .{ .node = .{}, .tag = EVENT_TAG };

// Get PolyNode pointer
const poly: *PolyNode = &ev.poly;

// Check tag
if (poly.tag == EVENT_TAG) {
    // Cast back
    const recovered: *Event = @fieldParentPtr("poly", poly);
    // recovered.code == 42
}
```

This works. But every type needs the same boilerplate:
- A `var _xxx_tag` declaration.
- A `const XXX_TAG` pointer.
- A tag check before every cast.
- An init that sets the tag.

---

### PolyHelper — all of the above, generated

`PolyHelper` generates the tag, check, cast, and init for any PolyNode type.
One call replaces all the manual boilerplate.

```zig
pub fn PolyHelper(comptime T: type) type
```

- `T` must have a field `poly: PolyNode`. Compile error otherwise.
- Returns a namespace with four members.

#### What PolyHelper generates

```zig
pub const TAG: *const anyopaque
```
- Unique runtime address for type `T`.
- Same as the manual `var _tag: PolyTag = .{}; const TAG = &_tag;` pattern.

```zig
pub fn isIt(tag: *const anyopaque) bool
```
- Returns `tag == TAG`.
- Same as the manual `poly.tag == EVENT_TAG` check.

```zig
pub fn cast(node: *PolyNode) ?*T
```
- Returns `null` if tag does not match.
- Returns `@fieldParentPtr("poly", node)` if it does.
- Combines the tag check and the cast in one safe call.

```zig
pub fn init(self: *T) void
```
- Sets `self.poly = .{ .node = .{}, .tag = TAG }`.
- Same as the manual init in Step 3.

#### Usage

```zig
pub const Event = struct {
    poly: PolyNode,
    code: i32,
};

pub const EventPolyHelper = polynode.PolyHelper(Event);
```

Naming convention: `XxxPolyHelper = polynode.PolyHelper(Xxx)`.

#### The same example, now with PolyHelper

```zig
// Create and initialize (Step 3 is now one call)
var ev: Event = .{ .code = 42 };
EventPolyHelper.init(&ev);

// Get PolyNode pointer (same as before)
const poly: *PolyNode = &ev.poly;

// Check and cast (Steps 5+6 combined, returns null on wrong tag)
const recovered: *Event = EventPolyHelper.cast(poly) orelse unreachable;
// recovered.code == 42
```

```text
Manual                              With PolyHelper

var _event_tag: PolyTag = .{};      (generated inside PolyHelper)
const EVENT_TAG = &_event_tag;      EventPolyHelper.TAG

poly.tag == EVENT_TAG               EventPolyHelper.isIt(poly.tag)

if (poly.tag == EVENT_TAG)          EventPolyHelper.cast(poly)
  @fieldParentPtr("poly", poly)       → ?*Event (null if wrong tag)

ev.poly = .{.node=.{},.tag=TAG};    EventPolyHelper.init(&ev)
```

Same operations. Same runtime cost. Less boilerplate. Compile-time validation.

See `helpers/types.zig` for the pattern.

### stdlib compatibility

PolyNode embeds `std.DoublyLinkedList.Node`.
- No custom list type.
- No adapter.
- Every PolyNode-based item participates in standard `std.DoublyLinkedList` operations.

Batch operations use plain `std.DoublyLinkedList`:
- `mailbox.close()`
- `mailbox.receive_batch()`
- `pool.put_all()`

Walk results with `popFirst()` — standard Zig, nothing Matryoshka-specific.

### Tag identity — class, not instance

`PolyHelper(T)` generates one static `_tag: PolyTag` per type `T` at comptime.
`TAG` is a pointer to that static — the same address for every instance of `T`.

Tag dispatch (`is_it_you`, `isIt`, `cast`) answers one question: **"is this a T?"**
It does not answer: "which T?" or "what role does this T play?"

For user-defined types (Event, Sensor, etc.):
- Tag identifies the class.
- Instance fields carry the role. The user adds a `kind` or `role` field to discriminate.

For infra handles (MailboxHandle, PoolHandle):
- `_Mailbox` and `_Pool` are private structs. The user cannot add fields.
- Tag identifies the class only. No per-instance role information is accessible.
- **Instance identity**: resolved by pointer comparison against known handles.
  E.g. `received == worker_mbh` identifies which specific mailbox arrived.
- **Role**: established by protocol — the channel the handle arrived on, message
  ordering, or prior agreement between sender and receiver.

#### Transporting infra handles — valid patterns

**Worker-finish-signal pattern**

Master creates `worker_mbh`, spawns a worker thread and passes `worker_mbh` as parameter.
Worker processes items until a shutdown signal, then:
- Sends `worker_mbh` back to master's inbox (unclosed) as the finish signal.
- Exits.

Master receives a PolyNode from its inbox:
- `mailbox.is_it_you(received.*.tag)` — confirms class (it is a mailbox).
- `received == worker_mbh` — confirms instance (it is the expected worker mailbox).
- Master closes and destroys `worker_mbh`.
- Master joins the thread (OS resource cleanup only — the mailbox return was the logical finish signal).

This pattern replaces a thread join or a separate shutdown message with ownership transfer.

**Wrapper pattern** (for tag-level role discrimination)

When tag dispatch must distinguish roles, wrap the handle in a user-defined PolyNode struct:

```zig
const WorkerInbox = struct {
    poly: PolyNode,
    handle: mailbox.MailboxHandle,
};
pub const WorkerInboxPolyHelper = polynode.PolyHelper(WorkerInbox);
```

`WorkerInboxPolyHelper.TAG` is distinct from `MailboxPolyHelper.TAG`.
The receiver dispatches on `WorkerInboxPolyHelper.TAG` and finds the embedded handle.

---

## mailbox

Ownership transport between execution contexts.

```zig
const mailbox = @import("matryoshka").mailbox;

// typical usage:
var slot: polynode.Slot = &event.poly;
try mailbox.send(inbox, &slot);              // slot is now null
try mailbox.receive(inbox, &slot, null);     // slot is now non-null
```

### Types

```zig
pub const MailboxHandle = NodeHandle;
```

MailboxHandle is itself a *PolyNode.
A mailbox can be:
- sent through another mailbox
- stored in pools
- embedded into larger ownership graphs

Same rules as application objects.

### Functions

```zig
pub fn new(io: Io, alloc: std.mem.Allocator) !MailboxHandle
```
- Creates a new mailbox.
- Stores `io` internally.

```zig
pub fn send(mbh: MailboxHandle, m: *Slot) error{Closed}!void
```
- Appends handle to tail.
- Transfers ownership — `m.*` set to null.
- Assert:
  - `mailbox.is_it_you(mbh.*.tag)`
  - `m.* != null`
  - `!polynode.is_linked(m.*)`

```zig
pub fn receive(mbh: MailboxHandle, m: *Slot, timeout_ns: ?u64) (error{ Closed, Timeout } || Cancelable)!void
```
- Blocks until handle available.
- `null` timeout = wait forever.
- `timeout_ns = 0` returns `error.Timeout` immediately — equivalent to `try_receive`.
- Transfers ownership — `m.*` set to non-null.
- OOB handles arrive first (front of queue).
- Multiple concurrent receivers compete for each handle. One receiver gets it. Scheduling order among waiters depends on the Io runtime and is not guaranteed FIFO.
- Assert:
  - `mailbox.is_it_you(mbh.*.tag)`
  - `m.* == null`

```zig
pub fn try_receive(mbh: MailboxHandle, m: *Slot) error{Closed}!bool
```
- Non-blocking.
- Returns true if handle received, false if queue empty.
- Assert:
  - `mailbox.is_it_you(mbh.*.tag)`
  - `m.* == null`

```zig
pub fn receive_batch(mbh: MailboxHandle) error{Closed}!std.DoublyLinkedList
```
- Non-blocking.
- Takes everything from the queue at once.
- Returns empty `std.DoublyLinkedList` if queue is currently empty.
- Does not wait. Does not return error for empty.
- Assert:
  - `mailbox.is_it_you(mbh.*.tag)`

```zig
pub fn close(mbh: MailboxHandle) std.DoublyLinkedList
```
- Can be called more than once.
- Returns remaining handles as list (empty list on second call).
- Collects all handles still in the queue.
- Wakes up any receivers waiting on the mailbox.
- Assert:
  - `mailbox.is_it_you(mbh.*.tag)`

```zig
pub fn destroy(mbh: MailboxHandle, alloc: std.mem.Allocator) void
```
- Frees the mailbox.
- Must be closed first.
- Calling destroy on an open mailbox is a programming error (panic).
- Assert:
  - `mailbox.is_it_you(mbh.*.tag)`

```zig
pub fn is_it_you(tag: *const anyopaque) bool
```
- Returns true if tag identifies a MailboxHandle.

### Error sets

| Error | Meaning |
|-------|---------|
| `error.Closed` | Mailbox was closed via `close()` |
| `error.Timeout` | `timeout_ns` expired (only when non-null) |
| `error.Canceled` | Waiting operation was canceled |

### Event source helpers

Mailbox as event source via `Future`.
- `receive_future` converts blocking `receive` to a Future result.

Cancel and close in concurrent tasks:
- Mailbox closed — blocked receivers wake with `error.Closed`.
- Task canceled — the operation returns `error.Canceled`.

#### Types

```zig
pub const ReceiveResult = union(enum) {
    item: NodeHandle,
    closed: void,
    timeout: void,
    canceled: void,
};
```

- The handle is inside the result, not behind a pointer. No `*Slot` is shared across threads.
- When you get `.item`, the handle is yours. The mailbox no longer holds it.

#### Functions

```zig
pub fn receive_future(mbh: MailboxHandle, timeout_ns: ?u64) ConcurrentError!Io.Future(ReceiveResult)
```
- Spawns a concurrent task that:
  - Creates a local `Slot`
  - Calls `receive`
  - Converts the result to `ReceiveResult`
- Uses the mailbox's stored `io`.
- Returns a Future that can be:
  - Awaited directly
  - Passed to `Io.Select`
  - Passed to `Io.Group`
- Returns `error.ConcurrencyUnavailable` on single-threaded backends.

#### Cancel behavior

- On `error.Canceled`, the adapter returns `.canceled` — the mailbox remains open.
- Closing is the Master's responsibility.

#### When to use

**Inside Matryoshka**: many senders push tagged PolyNodes into one mailbox.
- Master reads them all from one place.
- One queue, one ownership model, one shutdown path.

**Bridging to external Io**: use `receive_future`.
- Combines mailbox traffic with other sources in one `Io.Select` loop:
  - timers
  - sockets
  - files
  - pool availability

### Advanced: OOB (out of the box)

```zig
pub fn send_oob(mbh: MailboxHandle, m: *Slot) error{Closed}!void
```
- Inserts handle after last OOB handle.
- FIFO among OOBs, all OOBs before regular handles.
- Transfers ownership — `m.*` set to null.
- Assert:
  - `mailbox.is_it_you(mbh.*.tag)`
  - `m.* != null`
  - `!polynode.is_linked(m.*)`


OOB ordering:

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

Lifecycle management with user supplied hooks.

```zig
const pool = @import("matryoshka").pool;

// typical usage:
var slot: polynode.Slot = null;
try pool.get(ph, EVENT_TAG, .available_or_new, &slot);   // slot is now non-null
pool.put(ph, &slot);                                      // slot is now null (if kept)
```

### Ownership flow

```text
new()
  ↓
EMPTY pool

get() [available_or_new, pool empty]     get() [available_or_new, pool has items]
  ↓ on_get creates item                    ↓ item moved from free-list
IN_FLIGHT (user owns)                    IN_FLIGHT (user owns)

put() [on_put keeps]      put() [on_put destroys]
  ↓                         ↓
HELD (pool free-list)     FREE (caller frees)

get() [available_only or available_or_new]
  ↓
IN_FLIGHT (user owns)

close()
  ↓ on_close receives full list of HELD items → caller frees each
FREE
```

### Types

```zig
pub const PoolHandle = NodeHandle;
```

PoolHandle is itself a *PolyNode.
A pool can be:
- sent through a mailbox
- embedded into larger ownership graphs

Same rules as application objects.

```zig
pub const GetMode = enum {
    available_or_new,    // use stored handle if available, otherwise call on_get to create
    new_only,            // always call on_get with m.* == null to create fresh
    available_only,      // use stored handle only; if empty, return error.NotAvailable
};

pub const GetError = error{
    Closed,
    NotAvailable,
    NotCreated,
};
```

### PoolHooks

```zig
pub const PoolHooks = struct {
    ctx:      *anyopaque,
    tags:     []const *const anyopaque,
    on_get:   *const fn (ctx: *anyopaque, tag: *const anyopaque, in_pool_count: usize, m: *Slot) void,
    on_put:   *const fn (ctx: *anyopaque, in_pool_count: usize, m: *Slot) void,
    on_close: *const fn (ctx: *anyopaque, list: *std.DoublyLinkedList) void,
};
```

### Functions

```zig
pub fn new(io: Io, alloc: std.mem.Allocator) !PoolHandle
```
- Creates a new pool.
- Stores `io` internally.

```zig
pub fn destroy(ph: PoolHandle, alloc: std.mem.Allocator) void
```
- Frees the pool.
- Must be closed first.
- Calling destroy on an open pool is a programming error (panic).
- Assert:
  - `pool.is_it_you(ph.*.tag)`

```zig
pub fn init(ph: PoolHandle, hooks: PoolHooks) !void
```
- Registers hooks.
- Called once after `new`.
- Assert:
  - `pool.is_it_you(ph.*.tag)`
  - Hooks tags not empty, each tag not null.
  - Pool not already closed.

```zig
pub fn get(ph: PoolHandle, tag: *const anyopaque, mode: GetMode, m: *Slot) GetError!void
```
- Non-blocking acquisition.
- Calls `on_get` hook.
- Transfers ownership — `m.*` set to non-null on success.
- Assert:
  - `pool.is_it_you(ph.*.tag)`
  - `m.* == null`
  - Pool initialized.
  - Tag registered.

```zig
pub fn get_wait(ph: PoolHandle, tag: *const anyopaque, m: *Slot, timeout_ns: ?u64) (GetError || Cancelable || error{Timeout})!void
```
- Blocking acquisition.
- `null` timeout = wait forever.
- `timeout_ns = 0` returns `error.Timeout` immediately — equivalent to `get` with `available_only`.
- Calls `on_get` hook.
- Assert:
  - `pool.is_it_you(ph.*.tag)`
  - `m.* == null`
  - Pool initialized.
  - Tag registered.

```zig
pub fn put(ph: PoolHandle, m: *Slot) void
```
- Returns handle to pool.
- **Open pool**:
  - Calls `on_put` hook.
  - Policy decides keep or destroy.
  - Keep: `m.*` stays non-null, pool owns it.
  - Destroy: `m.*` set to null.
- **Closed pool**:
  - Returns immediately, no hook call.
  - `m.*` stays non-null — caller retains ownership.
- Assert:
  - `pool.is_it_you(ph.*.tag)`
  - `m.* != null`
  - `!polynode.is_linked(m.*)`

```zig
pub fn put_all(ph: PoolHandle, list: *std.DoublyLinkedList) void
```
- Returns batch of handles to pool.
- Pops from caller's list.
- Transfer is not atomic with respect to `close()`. If the pool closes mid-batch, items already transferred are passed to `on_close`; items not yet transferred remain in the caller's list.
- Restoration order when closed mid-batch may differ from original order.
- Assert:
  - `pool.is_it_you(ph.*.tag)`
  - Each node's tag registered in pool's tag set.

```zig
pub fn close(ph: PoolHandle) void
```
- Can be called more than once.
- Collects all handles from all per-tag free-lists.
- Calls `on_close` once with the full list.
- Broadcasts to wake blocked `get_wait` callers.
- Assert:
  - `pool.is_it_you(ph.*.tag)`

```zig
pub fn is_it_you(tag: *const anyopaque) bool
```
- Returns true if tag identifies a PoolHandle.

### Error sets

| Error | Meaning |
|-------|---------|
| `error.Closed` | Pool was closed via `close()` |
| `error.NotAvailable` | `available_only` mode, no stored handle |
| `error.NotCreated` | `on_get` was called but did not return a handle |
| `error.Timeout` | `timeout_ns` expired (only when non-null, `get_wait` only) |
| `error.Canceled` | Waiting operation was canceled (`get_wait` only) |

### Event source helpers

Pool as event source via `Future`.
- `get_wait_future` converts blocking `get_wait` to a Future result.

Cancel and close in concurrent tasks:
- Pool closed — blocked callers wake with `error.Closed`.
- Task canceled — the operation returns `error.Canceled`.

When a handle becomes available, the Master can react. This is the job-pool pattern:
- Worker returns a handle.
- Master is notified.
- Master submits new work.

#### Types

```zig
pub const PoolResult = union(enum) {
    item: NodeHandle,
    closed: void,
    timeout: void,
    canceled: void,
    not_created: void,
};
```

- The handle is inside the result, not behind a pointer. No `*Slot` is shared across threads.
- When you get `.item`, the handle is yours. The pool no longer holds it.
- Create a new future only after you've decided what to do with this handle.

#### Functions

```zig
pub fn get_wait_future(ph: PoolHandle, tag: *const anyopaque, timeout_ns: ?u64) ConcurrentError!Io.Future(PoolResult)
```
- Spawns a concurrent task that:
  - Creates a local `Slot`
  - Calls `get_wait`
  - Converts the result to `PoolResult`
- Uses the pool's stored `io`.
- Returns a Future that can be:
  - Awaited directly
  - Passed to `Io.Select`
  - Passed to `Io.Group`
- Returns `error.ConcurrencyUnavailable` on single-threaded backends.

#### Cancel behavior

- On `error.Canceled`, the adapter returns `.canceled` — the pool remains open.
- Closing is the Master's responsibility.

### Hook discipline

- Hooks run outside the pool's internal lock.
- The pool updates its own state first, then releases the lock, then calls your hook.
- Your hook code does not block other pool operations.
- `on_get`:
  - Called for every `get` and `get_wait` call regardless of mode or whether an item was found in the free-list.
  - If `m.*` is non-null on entry: the item was recycled from the free-list — reinitialize it.
  - If `m.*` is null on entry: no item was available — create a new one or leave null (creation failed).
  - Must either leave `m.* == null` (creation failed) OR set `m.*` to a valid node with the same tag that was requested.
  - Returning an item with a different tag is a programming error (assert in Debug/ReleaseSafe).
- `on_put`:
  - Set `m.*` to null = destroy.
  - Leave non-null = keep in pool.
- `on_close`:
  - Receives `*std.DoublyLinkedList`.
  - Walks via `popFirst()`, frees each handle.
- Hook reentrancy is forbidden. From inside any hook, do not:
  - call `get`, `get_wait`, `put`, `put_all`, `close`, or `destroy` on the same pool
  - block or wait on any condition
  - allocate in a way that could recursively trigger pool operations
  - Not a deadlock — hooks run outside the lock.
  - Contract violation — the pool cannot manage what it holds if hooks change it concurrently.

---

## matryoshka (root)

```zig
pub const polynode = @import("polynode.zig");
pub const mailbox = @import("mailbox.zig");
pub const pool = @import("pool.zig");
```

---

## Master (Layer 4) — intentionally not part of the API

No `master` module.
No `Master` struct.
By design.

Master is an architectural role — the coordination boundary.
It owns and composes the lower layers.

Applications build Masters from:

| What | Where it comes from |
|------|-------------------|
| Transport | `mailbox.MailboxHandle` — one or more mailboxes |
| Lifecycle | `pool.PoolHandle` + `pool.PoolHooks` — handle reuse and policy |
| Memory | `std.mem.Allocator` — who allocates and frees |
| Scheduling | `std.Io` — passed to `mailbox.new` and `pool.new` |
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
const Server = struct { inbox: mailbox.MailboxHandle, pool: pool.PoolHandle, ... };
const Scheduler = struct { pool: pool.PoolHandle, ... };  // no mailbox
const Pipeline = struct { stages: [3]mailbox.MailboxHandle, ... };
fn main(init: std.process.Init) !void { ... }
```

Matryoshka provides the building blocks.
The application assembles them.

### io.concurrent and Io.Group — verified call syntax

Verified from `std/Io.zig` (Zig 0.16.0) and confirmed against the ICE agent reference implementation.

#### io.concurrent

Spawns one task, returns a `Future` for its result.

```zig
// Signature (from Io.zig line 2365):
pub fn concurrent(
    io: Io,
    function: anytype,
    args: std.meta.ArgsTuple(@TypeOf(function)),
) ConcurrentError!Future(@typeInfo(@TypeOf(function)).@"fn".return_type.?)
```

Call pattern:

```zig
var fut = try io.concurrent(workerFn, .{&ctx});
// ... do other work ...
try fut.await(io);   // blocks until worker exits; returns worker's return type
```

- `args` is a tuple — `.{arg1, arg2, ...}` — passed verbatim to `function`.
- No `io` is injected. The worker receives exactly what is in `args`.
- If the worker needs `io`, pass it explicitly: `.{io, &ctx}`.
- `fut.await(io)` returns the worker's return type directly. Use `try` if it is an error union.
- `fut.cancel(io)` injects `error.Canceled` at the worker's next cancellation point, then awaits.
- `Future` is a resource — must call `await` or `cancel` exactly once.

Worker function for `io.concurrent`:

```zig
fn workerFn(ctx: *WorkerCtx) !void {
    // worker logic — mailbox.receive, pool.get_wait, etc.
    // io is accessed through the mailbox/pool (they store it internally)
}
```

#### Io.Group

Runs multiple tasks. Awaits or cancels all at once.

```zig
// Signature (from Io.zig line 1218):
pub const Group = struct {
    pub const init: Group  // compile-time constant, not a function call

    pub fn concurrent(g: *Group, io: Io, function: anytype,
        args: std.meta.ArgsTuple(@TypeOf(function))) ConcurrentError!void

    pub fn await(g: *Group, io: Io) Cancelable!void   // wait for all
    pub fn cancel(g: *Group, io: Io) void              // cancel all, then wait
};
```

Call pattern:

```zig
var group: std.Io.Group = .init;
defer group.cancel(io);   // safe: no-op if already awaited

try group.concurrent(io, workerFn, .{&ctx1});
try group.concurrent(io, workerFn, .{&ctx2});
try group.concurrent(io, workerFn, .{&ctx3});

try group.await(io);   // blocks until all workers exit
```

- Worker return type must be coercible to `Cancelable!void`.
  - `void`, `!void`, `Cancelable!void` all work.
  - `error.Canceled` returned by a worker is swallowed — it is a cancellation propagation boundary.
- `group.await(io)` returns `Cancelable!void` — use `try`.
- `group.cancel(io)` injects `error.Canceled` into all running workers, then waits. Returns `void`.
- `group.cancel(io)` is safe to call if already awaited — it is a no-op.
- `group.concurrent` after `group.await` starts a new round of tasks in the same group.

#### Io backend for Layer 4 tests and examples

Layer 1-3 tests use `std.Io.Threaded.global_single_threaded.*.io()` — no concurrency needed.

Layer 4 tests and examples need real concurrency (`io.concurrent`, `Io.Group`):
- Use `std.Io.Threaded.init(allocator, .{})` to get a real backend.
- Call `.deinit()` when done.

```zig
// In a Layer 4 test:
var threaded = try std.Io.Threaded.init(std.testing.allocator, .{});
defer threaded.deinit();
const io: std.Io = threaded.io();
```

```zig
// In a Layer 4 example (run function):
pub fn run(allocator: std.mem.Allocator, io: std.Io) !void {
    // io is passed in — examples never create the backend themselves
}
```

```zig
// In the test wrapper for a Layer 4 example:
test "17 - minimal master" {
    std.testing.log_level = .debug;
    var threaded = try std.Io.Threaded.init(std.testing.allocator, .{});
    defer threaded.deinit();
    const io: std.Io = threaded.io();
    try layer4.minimal_master.run(std.testing.allocator, io);
}
```

Key rules:
- `std.testing.io` — not used in this project, even in test files.
- `global_single_threaded` — Layer 1-3 only. Returns `error.ConcurrencyUnavailable` for `io.concurrent`.
- `Io.Threaded.init` — Layer 4 tests and example wrappers.
- Examples receive `std.Io` as a parameter. They never import or reference `std.testing`.

### Event sources

See **Prolog: std.Io** for the general `Future` → `Io.Select` pattern.

Matryoshka plugs into the same pattern:

```text
  receive_future ──► Future(ReceiveResult) ──┐
  get_wait_future ─► Future(PoolResult)    ──┼──► Io.Select ──► Master dispatch
  Timer ───────────► Future(void)          ──┤
  Socket read ─────► Future([]u8)          ──┘
```

- `mailbox.receive_future` — mailbox as event source.
- `pool.get_wait_future` — pool as event source.
- Master calls `select.await()`, handles the result, re-arms the source.

---

## Cancel model

Only functions that wait on a condition can be canceled.
Everything else runs to completion.

- A waiting function blocks until a handle becomes available or a timeout expires.
- While waiting, the runtime can cancel the operation. The function returns `error.Canceled`.
- All other functions do their work and return. They cannot be canceled.

A function is cancelable if and only if its return type includes `Cancelable` in the error union.
The signature is the single source of truth.

## Cancel contract summary

| Function | Cancelable | Notes |
|----------|-----------|-------|
| `mailbox.send` | no | non-blocking |
| `mailbox.send_oob` | no | non-blocking |
| `mailbox.receive` | **yes** | waits for a handle |
| `mailbox.try_receive` | no | non-blocking |
| `mailbox.receive_batch` | no | non-blocking |
| `mailbox.close` | no | non-blocking |
| `pool.get` | no | non-blocking |
| `pool.get_wait` | **yes** | waits for a handle |
| `pool.put` | no | non-blocking |
| `pool.put_all` | no | non-blocking |
| `pool.close` | no | non-blocking |
| `mailbox.receive_future` | **yes** | spawns `receive` concurrently |
| `pool.get_wait_future` | **yes** | spawns `get_wait` concurrently |

---

## Ownership lifecycle

```
FREE       — allocated, not in any system
IN_FLIGHT  — owned by user code (Slot non-null)
HELD       — owned by infrastructure (in mailbox queue or pool free-list)
```

| Operation | Before → After |
|-----------|---------------|
| `mailbox.send` | IN_FLIGHT → HELD |
| `mailbox.receive` | HELD → IN_FLIGHT |
| `pool.get` | HELD → IN_FLIGHT |
| `pool.put` (keep) | IN_FLIGHT → HELD |
| `pool.put` (destroy) | IN_FLIGHT → FREE |
| `mailbox.close` | HELD → returned to caller |
| `pool.close` | HELD → passed to on_close |

---

## Ownership invariants

These hold at all times, for every node in the system:

- A linked node belongs to exactly one container (mailbox queue or pool free-list). Never two at once.
- A Slot owns exactly one node. A null Slot owns nothing.
- A pool never owns a linked node — items in its free-lists are unlinked relative to other pools.
- A mailbox never owns a free node — only nodes currently in its queue.
- Every node has exactly one owner at all times: either user code (via Slot) or infrastructure (in queue or free-list). Never both.
- Tag identity is determined by pointer address alone. Never compare tag contents or names — compare only `==` on the pointer value.

---

## Cancellation ownership contract

When a cancellable operation returns `error.Canceled`:

- `mailbox.receive`: slot is unchanged — `m.*` was `null` on entry and remains `null`. The mailbox retains any queued items.
- `pool.get_wait`: slot is unchanged — `m.*` was `null` on entry and remains `null`. The pool retains all free-list items.

Cancellation never closes the mailbox or pool. Closing is the caller's responsibility.

---

## Thread-safety contract

| Function | Concurrent callers | Notes |
|----------|--------------------|-------|
| `mailbox.send` | yes | Multiple senders safe |
| `mailbox.send_oob` | yes | Multiple senders safe |
| `mailbox.receive` | yes | One handle per waiter; scheduling order is runtime-dependent |
| `mailbox.try_receive` | yes | |
| `mailbox.receive_batch` | yes | Transfers whole queue atomically |
| `mailbox.close` | yes — once | Second call returns empty list |
| `mailbox.destroy` | no | Must happen after all users have stopped |
| `pool.get` | yes | |
| `pool.get_wait` | yes | One handle per waiter; scheduling order is runtime-dependent |
| `pool.put` | yes | |
| `pool.put_all` | yes | Batch is atomic |
| `pool.close` | yes — once | Second call is a no-op |
| `pool.destroy` | no | Must happen after all users have stopped |

---

## Complexity guarantees

| Function | Time complexity |
|----------|----------------|
| `mailbox.send` | O(1) |
| `mailbox.send_oob` | O(1) |
| `mailbox.receive` | O(1) |
| `mailbox.try_receive` | O(1) |
| `mailbox.receive_batch` | O(1) — transfers whole queue atomically |
| `mailbox.close` | O(n) — walks the queue |
| `pool.get` | O(1) |
| `pool.get_wait` | O(1) |
| `pool.put` | O(1) |
| `pool.put_all` | O(k) — k is the number of items in the list |
| `pool.close` | O(n) — walks all per-tag free-lists |

---

## Contract violations

Programming errors.
Checked via `std.debug.assert`:
- Active in Debug and ReleaseSafe.
- Removed in ReleaseFast and ReleaseSmall.

- **Wrong handle type** — passing a PoolHandle where MailboxHandle is expected, or vice versa.
  - Checked via `is_it_you` on every API call.
- **Non-empty slot on receive/get** — slot must be null before receiving or getting a handle.
- **Linked node on send/put** — node must not be linked into a list before transfer.
- **Foreign tag** — pool operation with a tag not registered in the pool's tag set.
- **Uninitialized pool** — calling get/get_wait before init.
- **Double insertion** — pushing a linked node into a list.
- **Corrupted or invalid tag** — tag does not match any known type.

The following are unconditional panics (all build modes):

- **Destroying an open mailbox or pool** — must close first.
- **Use after free** — using a node after its memory was freed.

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

Dependencies:
- Mailbox and Pool are independent — neither depends on the other.
- Both depend only on the ownership model.
- Master is where they are combined.

Valid combinations:
- Layer 1 only — ownership without infrastructure
- Layer 1 + Layer 2 — ownership + transport, no lifecycle
- Layer 1 + Layer 3 — ownership + lifecycle, no transport
- Layer 1 + Layer 2 + Layer 3 + Io — full stack (Master)

---

## Change log

| Version | Date | Changes |
|---------|------|---------|
| 010 | 2026-06-26 | New `### io.concurrent and Io.Group — verified call syntax` subsection in Master section. Covers exact call patterns (verified from std/Io.zig + ICE agent), no-io-injection rule, worker return type constraint, Future resource rules, Io backend selection for Layer 4 tests and examples. |
| 009 | 2026-06-26 | Tag identity section: class vs instance, infra handles have no user-visible fields, worker-finish-signal pattern, wrapper pattern for role discrimination. |
| 008 | 2026-06-26 | Pool ownership flow diagram. Ownership invariants section. Cancellation ownership contract section. Thread-safety contract table. Complexity guarantees table. Zero timeout semantics in receive and get_wait. Multiple waiter fairness note. Strengthened hook reentrancy rules. |
| 001 | 2026-06-20 | Initial API reference (Proposal 8) |
| 002 | 2026-06-23 | Proposal 27: `MayItem` → `Slot`, `*PolyNode` → `NodeHandle`. Visual ownership model added to intro. `MailboxHandle = NodeHandle`, `PoolHandle = NodeHandle`. All "item" language updated to "handle" in descriptions. |
| 003 | 2026-06-23 | Proposal 28: Validation/assert specifications. `std.debug.assert` on every API function. `AlreadyInUse` removed from `GetError` (contract violation, not runtime error). Contract Violations section expanded. |
| 004 | 2026-06-23 | Proposal 29: `pool.put` open/closed behavior clarified. Proposal 30: `receive_select` and `get_wait_select` removed — `Future` composes directly with `Io.Select`, dedicated Select adapters are unnecessary API surface. |
| 005 | 2026-06-24 | Proposal 31: Reformat for readability and `///` doc comment use. Cancel indicator rule. Cancel table corrected. Event source concept added to Master with diagrams. Mailbox Integration section merged into Event source helpers. Informal terms cleaned up. |
| 006 | 2026-06-24 | Proposal 32: Staccato rhythm for all prose. Every non-function section reformatted: short intro then bullets. Comma-separated lists broken into bullet lists. |

---

## Change manifest (010) — for downstream propagation

### io.concurrent and Io.Group — verified call syntax

New `### io.concurrent and Io.Group — verified call syntax` subsection in `## Master (Layer 4)`.

Source: `std/Io.zig` (Zig 0.16.0) lines 2326–2380 (`async`, `concurrent`) and 1218–1309 (`Group`). Cross-checked against ICE agent reference implementation (`media-protocols-master/src/ice/agent.zig`).

- `io.concurrent(fn, .{args...})` — exact tuple syntax. Returns `ConcurrentError!Future(ReturnType)`.
- No io injection into workers. Args passed verbatim via `@call(.auto, function, args.*)`.
- `fut.await(io)` returns `ReturnType` directly. Use `try` when `ReturnType` is an error union.
- `fut.cancel(io)` injects `error.Canceled`, then awaits. Returns `ReturnType`.
- `Future` is a resource — call `await` or `cancel` exactly once.
- `Io.Group = .init` — compile-time constant, not a function call.
- `group.concurrent(io, fn, .{args...})` — same tuple syntax as `io.concurrent`.
- Worker return type for Group must coerce to `Cancelable!void`. `void` and `!void` both work.
- `group.await(io)` returns `Cancelable!void`.
- `group.cancel(io)` returns `void`. Safe to call after `await` (no-op).
- Layer 4 tests: use `std.Io.Threaded.init(allocator, .{})` — not `global_single_threaded`, not `testing.io`.
- Examples: receive `std.Io` as parameter, never create the backend, never import `std.testing`.

---

## Change manifest (009) — for downstream propagation

### Tag identity — class, not instance

New `### Tag identity — class, not instance` subsection in `## polynode`, after `### stdlib compatibility`.

- Explains that `PolyHelper(T).TAG` is a comptime-generated static — one per type, shared by all instances.
- Tag dispatch answers "is this a T?" not "which T?" or "what role?".
- User-defined types: user adds `kind`/`role` fields for per-instance discrimination.
- Infra handles (`_Mailbox`, `_Pool` are private): no user-visible fields; tag identifies class only.
- Instance identity: pointer comparison against known handles.
- Role: established by protocol between sender and receiver.
- Worker-finish-signal pattern documented with full flow.
- Wrapper pattern documented for tag-level role discrimination.

---

## Change manifest (008) — for downstream propagation

### Pool ownership flow diagram

New `### Ownership flow` subsection in `## pool`, before `### Types`.
Shows FREE → IN_FLIGHT → HELD → FREE cycle for get/put/close.

### Ownership invariants section

New `## Ownership invariants` section after `## Ownership lifecycle`.
Six invariants: one-container rule, Slot exclusivity, pool/mailbox non-overlap, single-owner rule, tag pointer-equality rule.

### Cancellation ownership contract section

New `## Cancellation ownership contract` section.
Documents that `error.Canceled` leaves slot unchanged for `receive` and `get_wait`.
Clarifies that cancel does not close the mailbox or pool.

### Thread-safety contract section

New `## Thread-safety contract` table.
Per-function: which calls may run concurrently, which must not race.
Notes: close is safe to call once concurrently; destroy requires exclusive access.

### Complexity guarantees section

New `## Complexity guarantees` table.
All operations O(1) except close (O(n)) and put_all (O(k)).

### Zero timeout semantics

Added to `mailbox.receive`: `timeout_ns = 0` returns `error.Timeout` immediately — equivalent to `try_receive`.
Added to `pool.get_wait`: `timeout_ns = 0` returns `error.Timeout` immediately — equivalent to `get` with `available_only`.

### Multiple waiter fairness note

Added to `mailbox.receive`: multiple concurrent receivers compete for each handle; scheduling order is runtime-dependent, not guaranteed FIFO.

### Hook reentrancy rules strengthened

`### Hook discipline` in `## pool`: replaced single "Do NOT call pool functions" bullet with explicit list of forbidden actions (get/get_wait/put/put_all/close/destroy on same pool; block; wait; recursive allocation).

---

## Change manifest (006) — for downstream propagation

### Staccato rhythm for all prose (Proposal 32)

All non-function sections reformatted to follow: short intro, then bullets.

Sections changed:
- Document intro — comma-list of architectures broken into bullets, transported items broken into bullets.
- "What is a NodeHandle?" — prose → intro + bullets.
- Ownership rule — prose → intro + bullets.
- "Defining user types" — dense sentences → bullets.
- stdlib compatibility — prose paragraph → intro + bullets.
- ReceiveResult description — prose → bullets.
- PoolResult description — prose → bullets.
- Event source helpers (mailbox) — prose → intro + bullets.
- Event source helpers (pool) — prose → intro + bullets.
- Event source explanation (Master) — tightened.
- matryoshka root — prose → bullets.
- Master intro — tightened.
- Layer dependencies — prose → intro + bullets.
- Contract violations intro — tightened.
- Hook discipline "Do NOT" — split dense sub-bullet.
- "When to use" bridging — comma-list → bullets.

---

## Change manifest (005) — for downstream propagation

### Readability reformat (Proposal 31)

- All function descriptions reformatted: one fact per bullet, nested sub-bullets for asserts and lists.
- Descriptions are now `///` Zig doc comment ready.
- Added doc-comment source note in document header.

### Event source concept added to Master

- New subsection "Event sources" in Master section.
- ASCII diagram: general `Future` → `Io.Select` → dispatch pattern.
- Second diagram: mailbox and pool as event sources alongside timers and sockets.
- Explains how blocking operations become event sources via `io.concurrent()`.

### Mailbox "Integration with std.Io" merged into "Event source helpers"

- Removed standalone "Integration with std.Io" section.
- Cancel/close behavior moved into "Event source helpers" intro.
- Removed vague "compose with concurrency primitives" sentence.

### Pool event source intro updated

- Added cancel/close behavior parallel to mailbox.
- Consistent structure between mailbox and pool event source sections.

### Cancel indicator rule added

- New section "Cancel indicator" before "Cancel contract summary".
- Rule: a function is cancelable if and only if its return type includes `Cancelable`.

### Cancel contract table corrected

| Function | Was | Now | Reason |
|----------|-----|-----|--------|
| `mailbox.send` | Cancelable: yes | Cancelable: no | Signature has no `Cancelable` |
| `mailbox.send_oob` | Cancelable: yes | Cancelable: no | Signature has no `Cancelable` |
| `mailbox.try_receive` | Cancelable: yes | Cancelable: no | Signature has no `Cancelable` |
| `pool.get` | Cancelable: yes | Cancelable: no | Signature has no `Cancelable` |

### False annotations removed

- `send` description: "Cancelable (work path)." removed.
- `send_oob` description: "Cancelable (work path)." removed.

### Informal terms cleaned up

| Was | Now |
|-----|-----|
| "fed to `Io.Select`" | "passed to `Io.Select`" |
| "bridges the blocking API to the Future world" | "converts blocking calls to Future results" |
| "maps the result to" | "converts the result to" |

---

## Change manifest (004) — for downstream propagation

### pool.put behavior clarified (Proposal 29)

- `put` description split into open/closed paths
- **Open pool**: calls `on_put` hook, policy decides keep or destroy
- **Closed pool**: returns immediately, no hook call, caller retains ownership
- No signature change — `put` remains `void` return (defer-compatible)

### Select adapters removed (Proposal 30)

| Removed | Replacement |
|---------|-------------|
| `mailbox.receive_select` | `mailbox.receive_future` (Future composes with Select directly) |
| `pool.get_wait_select` | `pool.get_wait_future` (Future composes with Select directly) |

- `receive_future` description updated — no longer references `receive_select`
- `get_wait_future` description updated — no longer references `get_wait_select`
- Cancel contract summary: 2 rows removed (`receive_select`, `get_wait_select`), 2 rows updated
- "When to use" section: `receive_select` reference removed
- Rationale: `Future` is the fundamental `Io` abstraction. It composes with `Io.Select`, `Io.Group`, and plain `await`. A dedicated Select adapter adds API surface and couples Matryoshka to a specific coordination pattern without additional capability.

---

## Change manifest (003) — for downstream propagation

### New asserts added

| Function | Asserts |
|----------|---------|
| `mailbox.send` | `is_it_you(mbh)`, `m.* != null`, `!is_linked(m.*)` |
| `mailbox.send_oob` | `is_it_you(mbh)`, `m.* != null`, `!is_linked(m.*)` |
| `mailbox.receive` | `is_it_you(mbh)`, `m.* == null` |
| `mailbox.try_receive` | `is_it_you(mbh)`, `m.* == null` |
| `mailbox.receive_batch` | `is_it_you(mbh)` |
| `mailbox.close` | `is_it_you(mbh)` |
| `mailbox.destroy` | `is_it_you(mbh)` |
| `pool.destroy` | `is_it_you(ph)` |
| `pool.init` | `is_it_you(ph)`, hooks tags not empty, each tag not null, not closed |
| `pool.get` | `is_it_you(ph)`, `m.* == null`, initialized, tag registered |
| `pool.get_wait` | `is_it_you(ph)`, `m.* == null`, initialized, tag registered |
| `pool.put` | `is_it_you(ph)`, `m.* != null`, `!is_linked(m.*)` |
| `pool.put_all` | `is_it_you(ph)`, each node tag registered |
| `pool.close` | `is_it_you(ph)` |

### Errors removed

- `error.AlreadyInUse` removed from `GetError` and pool error sets table
- Non-empty slot is now a contract violation (`std.debug.assert`), not a runtime error

### Contract violations section changes

- Split into `std.debug.assert` (Debug/ReleaseSafe) and unconditional panic categories
- Added: wrong handle type, non-empty slot, linked node, foreign tag, uninitialized pool
- Moved: destroy-on-open and use-after-free to unconditional panic

### Principle

Errors for runtime conditions (Closed, Timeout, NotAvailable, NotCreated, Canceled). Asserts for contract violations (wrong type, wrong state, programming bugs).
