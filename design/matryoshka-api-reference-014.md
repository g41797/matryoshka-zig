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
- `Io.Select` — coordinates multiple concurrent event sources. Internally: `queue: Queue(U)` + `group: Group`. `select.await()` reads the next completed result from the queue.
- `Io.Group` — runs several tasks. Waits for all of them to finish.
- `io.concurrent()` — runs a blocking function in a separate task. Returns a Future for the result.
- `ConcurrentError` — spawning a task failed (e.g. single-threaded backend, no threads available).

### Event sources

An event source is a blocking function passed to `select.concurrent`. When it returns,
the result is wrapped in the Select union and placed in the internal queue.

Two patterns for producing Select events:

1. `select.concurrent(field, blockingFn, args)` — spawn a blocking function; result goes into the queue when done.
2. `select.queue.putOneUncancelable(io, value)` — push directly from any thread without spawning.

`io.concurrent` and `select.concurrent` copy the args before returning — stack-allocated args are safe.

```text
  blockingFn ────► select.concurrent(field, blockingFn, args)
                        │
                        ▼ (fn runs, result → queue)
                   Io.Select.queue
                      │   │
                      ▼   ▼
               completed  canceled
               (result)   (error.Canceled)
```

`io.concurrent(fn, args)` — standalone version. Returns `Io.Future(T)` for direct await or `Io.Group` use.

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

## Slot-based programming

The slot rule governs every acquisition and transfer.

The slot rule:
- Never overwrite a non-null slot.
- Always start with `var slot: Slot = null`.
- All acquisition APIs assert `slot.* == null` on entry. Writing to a non-null slot panics.
- Transfer clears the slot: sender sets `slot.* = null`. After transfer, slot is null.
- Applies universally: pool get/put, mailbox receive, heap allocation — every combination.

### Why acquisition APIs assert null

Every acquisition API has this check:

```zig
std.debug.assert(slot.* == null);
```

Overwriting a non-null slot would lose the previous item with no error signal.
The assert catches this immediately.

### Why cleanup operations accept null

`pool.put` and `PolyHelper.destroy` check null and return early:

```zig
if (slot.* == null) return;
```

This makes defer-before-acquisition safe.

### Slot lifecycle

```text
Slot lifecycle

  null ──── acquire ────► non-null
    ▲                        │
    │                        │
    ├──── transfer ──────────┘   (sender clears: slot.* = null)
    │
    └──── cleanup (no-op) ──────  (pool.put, PolyHelper.destroy: null → return)
```

### Ownership transfer clears the slot

```text
Before transfer                  After transfer

  Slot (sender)                    Slot (sender)
  ┌─────────────┐                  ┌─────────────┐
  │ NodeHandle  │                  │    null     │
  └─────────────┘                  └─────────────┘
                                           │
  mailbox.send(mbh, &slot)                    │ slot.* = null
                                           │
                     Mailbox ◄─────────────┘
                     now owns NodeHandle
```

### Defer-before-acquisition is safe

```text
Code order:                      Execution when acquire fails:

  var slot: Slot = null;              slot = null
  defer pool.put(ph, &slot);          acquire fails
  try pool.get(..., &slot);           defer runs: pool.put sees null → no-op
  // work                          ✓ nothing lost

                                 Execution when item is transferred:

                                   slot = null (after acquire: slot is non-null)
                                   mailbox.send(mbh, &slot)  → slot = null
                                   defer runs: pool.put sees null → no-op
                                   ✓ item transferred, not double-recycled
```

---

## Cooperative cleanup patterns

These patterns follow from the slot rule.
Place cleanup before acquisition.
The defer becomes a no-op when the slot is null — either because acquisition failed, or because the item was transferred.

### Pattern 1 — defer-put-early (pool item)

```zig
var slot: Slot = null;
defer pool.put(ph, &slot);              // no-op if slot == null
try pool.get(ph, TAG, .new_only, &slot);
// ... work ...
// on transfer: slot = null → defer runs as no-op
// on no transfer: defer recycles item
```

Put before get — safe because pool.put is a no-op on null.

### Pattern 2 — defer-destroy-early (heap item via PolyHelper)

```zig
var slot: Slot = null;
defer EventPolyHelper.destroy(allocator, &slot);   // no-op if slot == null
try EventPolyHelper.create(allocator, &slot);
// ... work ...
// on transfer: slot = null → defer runs as no-op
// on no transfer: defer frees item
```

Destroy before create — safe because PolyHelper.destroy is a no-op on null.

### Pattern 3 — defer for received mailbox item

```zig
var slot: Slot = null;
defer if (slot) |poly| helpers.freeItem(poly, allocator);
try mailbox.receive(mbh, &slot, null);
// dispatch on slot.?.*.tag, process item
// item stays non-null until explicitly transferred or freed
```

Cleanup covers both the error path (receive failed) and the normal path (item processed and freed).

### Pattern 4 — transfer clears the slot

```zig
var slot: Slot = null;
defer pool.put(ph, &slot);
try pool.get(ph, TAG, .new_only, &slot);
// fill item ...
try mailbox.send(mbh, &slot);   // send sets slot.* = null
// defer runs: pool.put sees null → no-op
// result: item is in mailbox, not recycled to pool
```

Transfer and cleanup are not in conflict — transfer pre-empts cleanup by clearing the slot.

### Pattern summary

```text
Pattern 1 (pool item)            Pattern 2 (heap item)

  null ──► get ──► non-null        null ──► create ──► non-null
    ▲                │               ▲                   │
    │    put (defer) │               │  destroy (defer)  │
    └────────────────┘               └───────────────────┘
         (recycle)                          (free)

         transfer →                         transfer →
         slot = null                           slot = null
         defer: no-op                       defer: no-op
```

### No raw allocator calls on PolyNode-based types

In examples and tests, never use `allocator.create` / `allocator.destroy` directly on
PolyNode-based user types (Event, Sensor, Timer, ShutdownCommand).

Use `PolyHelper.create`, `PolyHelper.destroy`, or `helpers.freeSlot` instead.

#### Violation

```zig
// WRONG — raw allocator on PolyNode-based type
const ev = try alloc.create(Event);
ev.* = .{};
EventPolyHelper.init(ev);
slot.* = &ev.poly;
// ... later ...
alloc.destroy(EventPolyHelper.cast(slot.?).?);
slot.* = null;
```

#### Correct

```zig
// CORRECT — PolyHelper.create/destroy
var slot: Slot = null;
defer EventPolyHelper.destroy(alloc, &slot);
try EventPolyHelper.create(alloc, &slot);
// ... dispatch: use helpers.freeSlot(&slot, alloc) per branch ...
```

#### Exempt

- `mailbox.zig`, `pool.zig` — allocating/freeing their own internal structs.
- `PolyHelper.create` / `PolyHelper.destroy` implementations.
- Pool hook bodies (`on_get`, `on_close`) — manage raw memory on behalf of pool.
- Non-PolyNode structs: worker context, hook context, allocator wrappers.

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
|   | node: List.Node     | |
|   |   prev: ?*List.Node | |
|   |   next: ?*List.Node | |
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
// Step 1: List.Node → PolyNode (done inside mailbox/pool)
const poly: *PolyNode = @fieldParentPtr("node", list_node_ptr);

// Step 2: PolyNode → user type (done in user code, after tag check)
const ev: *Event = @fieldParentPtr("poly", poly);
```

```text
list_node_ptr: *List.Node
      |
      v
+---------------------------+
| poly: PolyNode            |
|   +---------------------+ |
|   | node: List.Node     | | <-- list_node_ptr points here
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

### PolyHelper — create and destroy

These two functions exist only when `T` does not declare `no_create_destroy`.
They collapse the three-step alloc+init+slot pattern into one call.

```zig
pub fn create(allocator: std.mem.Allocator, slot: *Slot) !void
```
- Asserts `slot.* == null`.
- Allocates `T`.
- Zero-initializes.
- Calls `init`.
- Sets `slot.*` to point to the new node.

```zig
pub fn destroy(allocator: std.mem.Allocator, slot: *Slot) void
```
- If `slot.* == null`: returns immediately (no-op).
- Asserts node is not linked.
- Sets `slot.*` to null before freeing — prevents use-after-free.
- Frees the memory.

#### Old pattern vs new

```text
Old (manual):                        New (PolyHelper.create):

  const ev = try alloc.create(T);     try EventPolyHelper.create(alloc, &slot);
  ev.* = .{};
  EventPolyHelper.init(ev);
  slot.* = &ev.poly;
```

```text
Old (manual):                        New (PolyHelper.destroy):

  alloc.destroy(                       EventPolyHelper.destroy(alloc, &slot);
    EventPolyHelper.cast(slot.?).?);      // null-safe, clears slot
  slot.* = null;
```

#### comptime selection — no_create_destroy

Some types must not expose `create`/`destroy`.

```zig
const no_create_destroy = void{};
```

If `T` declares this field, `PolyHelper(T)` generates only: `TAG`, `isIt`, `cast`, `mustCast`, `init`.

Infrastructure types (`_Mailbox`, `_Pool`) declare `no_create_destroy`.
They manage their own lifecycle.
Generating `create`/`destroy` for them would be wrong.

```text
PolyHelper(T)
  │
  ├── @hasDecl(T, "no_create_destroy") == false
  │     → TAG, isIt, cast, mustCast, init, create, destroy
  │
  └── @hasDecl(T, "no_create_destroy") == true
        → TAG, isIt, cast, mustCast, init     (create/destroy absent)
```

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
pub fn send(mbh: MailboxHandle, slot: *Slot) error{Closed}!void
```
- Appends handle to tail.
- Transfers ownership — `slot.*` set to null.
- Assert:
  - `mailbox.is_it_you(mbh.*.tag)`
  - `slot.* != null`
  - `!polynode.is_linked(slot.*)`

```zig
pub fn receive(mbh: MailboxHandle, slot: *Slot, timeout_ns: ?u64) (error{ Closed, Timeout } || Cancelable)!void
```
- Blocks until handle available.
- `null` timeout = wait forever.
- `timeout_ns = 0` returns `error.Timeout` immediately — equivalent to `try_receive`.
- Transfers ownership — `slot.*` set to non-null.
- OOB handles arrive first (front of queue).
- Multiple concurrent receivers compete for each handle. One receiver gets it. Scheduling order among waiters depends on the Io runtime and is not guaranteed FIFO.
- Assert:
  - `mailbox.is_it_you(mbh.*.tag)`
  - `slot.* == null`

```zig
pub fn try_receive(mbh: MailboxHandle, slot: *Slot) error{Closed}!bool
```
- Non-blocking.
- Returns true if handle received, false if queue empty.
- Assert:
  - `mailbox.is_it_you(mbh.*.tag)`
  - `slot.* == null`

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

Mailbox as event source for `Io.Select` and `Io.Future`.

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
pub fn receiveResult(mbh: MailboxHandle, timeout_ns: ?u64) ReceiveResult
```
- Blocking function. No error return — maps all outcomes to `ReceiveResult` variants.
- Primary building block for Select integration:
  ```zig
  try select.concurrent(.inbox, mailbox.receiveResult, .{mbh, null});
  ```
- Also usable with `io.concurrent` or `group.concurrent`.

```zig
pub fn receive_future(mbh: MailboxHandle, timeout_ns: ?u64) ConcurrentError!Io.Future(ReceiveResult)
```
- Thin wrapper: `return mbx.*.io.concurrent(receiveResult, .{mbh, timeout_ns})`.
- No heap allocation — args copied by the runtime before `concurrent` returns.
- Returns a Future for direct await or `Io.Group` use.
- Returns `error.ConcurrencyUnavailable` on single-threaded backends.

#### Cancel behavior

- On `error.Canceled`, returns `.canceled` — the mailbox remains open.
- Closing is the Master's responsibility.

#### When to use

**`select.concurrent` pattern** (primary):
```zig
try select.concurrent(.inbox, mailbox.receiveResult, .{mbh, null});
const event = try select.await();
switch (event) {
    .inbox => |r| switch (r) { ... },
    ...
}
```

**`receive_future` pattern** (direct await or Group):
```zig
const fut = try mailbox.receive_future(mbh, null);
const result = try fut.await(io);
```

**Bridging to external Io**: one `Io.Select` loop combines mailbox, timers, sockets, pool availability.
- Matryoshka sources use `receiveResult` / `getWaitResult` via `select.concurrent`.
- External sources use their own blocking functions via `select.concurrent`.
- Direct push: `select.queue.putOneUncancelable(io, value)` for immediate events.

### Advanced: OOB (out of the box)

```zig
pub fn send_oob(mbh: MailboxHandle, slot: *Slot) error{Closed}!void
```
- Inserts handle after last OOB handle.
- FIFO among OOBs, all OOBs before regular handles.
- Transfers ownership — `slot.*` set to null.
- Assert:
  - `mailbox.is_it_you(mbh.*.tag)`
  - `slot.* != null`
  - `!polynode.is_linked(slot.*)`


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
    new_only,            // always call on_get with slot.* == null to create fresh
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
    on_get:   *const fn (ctx: *anyopaque, tag: *const anyopaque, in_pool_count: usize, slot: *Slot) void,
    on_put:   *const fn (ctx: *anyopaque, in_pool_count: usize, slot: *Slot) void,
    on_close: *const fn (ctx: *anyopaque, list: *std.DoublyLinkedList) void,
};
```

**`in_pool_count` semantics**
- `on_get`: count **after** removal — items remaining with this tag.
- `on_put`: count **before** addition — items already stored with this tag.
- Both values are **hints** — read under lock, passed to a hook running without lock;
  the pool may have changed by the time the hook reads the value.

**Hook concurrency**
- Hooks are called **outside the pool mutex**.
- Multiple threads may invoke hooks simultaneously — the pool does not serialize them.

**Advice for hook implementers**
- If your hook touches shared state, protect it.
- Example: use `Io.Mutex` and call `lockUncancelable` to acquire it.
  Hooks return `void` — `lock` (cancelable) is not an option here.
- Obtain `io` from the surrounding context that owns the pool; do not acquire it inside the hook.
- `CappedPoolCtx` in `helpers/helpers.zig` is the reference implementation of these rules.

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
pub fn get(ph: PoolHandle, tag: *const anyopaque, mode: GetMode, slot: *Slot) GetError!void
```
- Non-blocking acquisition.
- Calls `on_get` hook.
- Transfers ownership — `slot.*` set to non-null on success.
- Assert:
  - `pool.is_it_you(ph.*.tag)`
  - `slot.* == null`
  - Pool initialized.
  - Tag registered.

```zig
pub fn get_wait(ph: PoolHandle, tag: *const anyopaque, slot: *Slot, timeout_ns: ?u64) (GetError || Cancelable || error{Timeout})!void
```
- Blocking acquisition.
- `null` timeout = wait forever.
- `timeout_ns = 0` returns `error.Timeout` immediately — equivalent to `get` with `available_only`.
- Calls `on_get` hook.
- Assert:
  - `pool.is_it_you(ph.*.tag)`
  - `slot.* == null`
  - Pool initialized.
  - Tag registered.

```zig
pub fn put(ph: PoolHandle, slot: *Slot) void
```
- Returns handle to pool.
- `slot.* == null` → returns immediately. No hook call. No assert on tag.
- **Open pool**:
  - Calls `on_put` hook.
  - Policy decides keep or destroy.
  - Keep: `slot.*` stays non-null, pool owns it.
  - Destroy: `slot.*` set to null.
- **Closed pool**:
  - Returns immediately, no hook call.
  - `slot.*` stays non-null — caller retains ownership.
- Assert (when slot.* != null):
  - `pool.is_it_you(ph.*.tag)`
  - `!polynode.is_linked(slot.*)`

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

Pool as event source for `Io.Select` and `Io.Future`.

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
- Re-spawn the event source after handling each result.

#### Functions

```zig
pub fn getWaitResult(ph: PoolHandle, tag: *const anyopaque, timeout_ns: ?u64) PoolResult
```
- Blocking function. No error return — maps all outcomes to `PoolResult` variants.
- Primary building block for Select integration:
  ```zig
  try select.concurrent(.pool, pool.getWaitResult, .{ph, TAG, null});
  ```
- Also usable with `io.concurrent` or `group.concurrent`.

```zig
pub fn get_wait_future(ph: PoolHandle, tag: *const anyopaque, timeout_ns: ?u64) ConcurrentError!Io.Future(PoolResult)
```
- Thin wrapper: `return p.*.io.concurrent(getWaitResult, .{ph, tag, timeout_ns})`.
- No heap allocation — args copied by the runtime before `concurrent` returns.
- Returns a Future for direct await or `Io.Group` use.
- Returns `error.ConcurrencyUnavailable` on single-threaded backends.

#### Cancel behavior

- On `error.Canceled`, returns `.canceled` — the pool remains open.
- Closing is the Master's responsibility.

### Hook discipline

- Hooks run outside the pool's internal lock.
- The pool updates its own state first, then releases the lock, then calls your hook.
- Your hook code does not block other pool operations.
- `on_get`:
  - Called for every `get` and `get_wait` call regardless of mode or whether an item was found in the free-list.
  - If `slot.*` is non-null on entry: the item was recycled from the free-list — reinitialize it.
  - If `slot.*` is null on entry: no item was available — create a new one or leave null (creation failed).
  - Must either leave `slot.* == null` (creation failed) OR set `slot.*` to a valid node with the same tag that was requested.
  - Returning an item with a different tag is a programming error (assert in Debug/ReleaseSafe).
- `on_put`:
  - Set `slot.*` to null = destroy.
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
- `io.concurrent` copies `args` before returning. Stack-allocated args are safe — no heap ctx needed.
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

#### Io.Select — internals

Verified from `std/Io.zig:1367`.

Public fields:

```zig
pub fn Select(comptime U: type) type {
    return struct {
        io: Io,
        group: Group,
        queue: Queue(U),
        ...
    };
}
```

- `queue: Queue(U)` — completed results land here.
- `group: Group` — owns all spawned concurrent tasks.
- `select.await()` = `queue.getOne(io)` — blocks until the next result arrives.

`select.concurrent(field, fn, args)`:
- Spawns `fn` concurrently via `group`.
- `fn` return value is wrapped: `@unionInit(U, @tagName(field), result)`.
- Wrapped value is put into `queue` via `queue.putOneUncancelable`.

Direct push (no spawn):

```zig
select.queue.putOneUncancelable(select.io, .{ .field = value }) catch {};
```

- Puts a result directly from any thread or callback.
- No concurrent task needed.
- Used when the result is already available (e.g. a close notification, an external callback).

`select.concurrent` copies `args` before returning — same guarantee as `io.concurrent`.

ICE agent reference (`src/ice/agent.zig`):
- Line 134: `select.concurrent(.connectivity_check, Io.sleep, ...)` — blocking fn
- Lines 241-242: `select.queue.putOneUncancelable(...)` — direct push from external goroutine
- Line 273: direct push from close callback

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
  mailbox.receiveResult ──► select.concurrent(.inbox, ...)  ──┐
  pool.getWaitResult    ──► select.concurrent(.pool, ...)   ──┼──► Io.Select.queue ──► Master dispatch
  Io.sleep              ──► select.concurrent(.timer, ...)  ──┤
  direct push           ──► select.queue.putOneUncancelable ──┘
```

- `mailbox.receiveResult` + `select.concurrent` — mailbox as Select event source.
- `pool.getWaitResult` + `select.concurrent` — pool as Select event source.
- `mailbox.receive_future` / `pool.get_wait_future` — Future wrappers for direct await or `Io.Group`.
- Master calls `select.await()`, handles the result, re-spawns the source.

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
| `mailbox.receiveResult` | **yes** | blocking; cancelable via task cancel |
| `mailbox.receive_future` | **yes** | thin wrapper around `io.concurrent(receiveResult, ...)` |
| `pool.getWaitResult` | **yes** | blocking; cancelable via task cancel |
| `pool.get_wait_future` | **yes** | thin wrapper around `io.concurrent(getWaitResult, ...)` |

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

- `mailbox.receive`: slot is unchanged — `slot.*` was `null` on entry and remains `null`. The mailbox retains any queued items.
- `pool.get_wait`: slot is unchanged — `slot.*` was `null` on entry and remains `null`. The pool retains all free-list items.

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
| 013 | 2026-06-28 | `## Prolog: std.Io` — corrected `Io.Select` description (Queue(U)+Group, not Future container). Updated event source diagram and added direct push pattern. Added `receiveResult` and `getWaitResult` as primary blocking functions. Updated `receive_future` and `get_wait_future` as thin wrappers (no heap allocation). Updated cancel contract table. Updated Master event source diagram. Added `#### Io.Select — internals` subsection (verified fields, select.concurrent mechanics, direct push, ICE agent reference). Added args-copying note to `#### io.concurrent`. Fixed `fires` → `runs` ×5 in slot-based programming code comments. |
| 012 | 2026-06-27 | New rule `### No raw allocator calls on PolyNode-based types` in `## Cooperative cleanup patterns`. Violation/correct/exempt code examples. |
| 011 | 2026-06-27 | New `## Slot-based programming` section: slot rule, lifecycle diagram, ownership-transfer diagram, defer-before-acquisition diagram. New `## Cooperative cleanup patterns` section: four patterns with code + diagrams. New `### PolyHelper — create and destroy` subsection: create/destroy functions, old-vs-new comparison, no_create_destroy comptime selection. Updated pool.put: null slot is now a no-op (no-op bullet added, assert clarified). |
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

## Change manifest (013) — for downstream propagation

### Prolog: std.Io — corrected

- `Io.Select` bullet: replaced "waits on several Futures at once" with accurate description (Queue(U)+Group).
- Event source section: replaced "anything that produces a Future" with blocking-function + select.concurrent model.
- Event source diagram: replaced Future-centric diagram with select.concurrent + direct push diagram.
- Added: `io.concurrent` / `select.concurrent` copy args before returning — stack args are safe.

### mailbox — Event source helpers

- Added `receiveResult(mbh, timeout_ns) ReceiveResult` — primary public blocking function.
- Updated `receive_future` description: thin wrapper, no heap allocation.
- Updated "When to use" section: select.concurrent pattern shown first, receive_future second.

### pool — Event source helpers

- Added `getWaitResult(ph, tag, timeout_ns) PoolResult` — primary public blocking function.
- Updated `get_wait_future` description: thin wrapper, no heap allocation.

### Cancel contract summary

- Added rows for `receiveResult` and `getWaitResult`.

### Master section — event source diagram

- Replaced Future-centric diagram with select.concurrent + direct push model.

### io.concurrent and Io.Group section — two additions

- `#### io.concurrent`: added args-copying bullet — `io.concurrent` copies args before returning; stack args safe; no heap ctx needed.
- `#### Io.Select — internals`: new subsection. Verified public fields (`queue: Queue(U)`, `group: Group`), `select.await()` mechanics, `select.concurrent` wrapping logic, direct push pattern, ICE agent reference.

### Slot-based programming — `fires` fixed

- `defer fires` → `defer runs` in 5 code comment annotations (lines 234, 241, 260, 273, 299).

---

## Change manifest (012) — for downstream propagation

### No raw allocator calls on PolyNode-based types (new rule)

New `### No raw allocator calls on PolyNode-based types` subsection in `## Cooperative cleanup patterns`, placed after Pattern summary.

- Rule: in examples and tests, never use `allocator.create` / `allocator.destroy` on Event, Sensor, Timer, ShutdownCommand.
- Violation code snippet: old manual alloc+init+slot-assign and manual destroy+null pattern.
- Correct code snippet: `PolyHelper.create` + `defer PolyHelper.destroy` pattern.
- Exempt cases: infrastructure internals, PolyHelper implementations, hook bodies, non-PolyNode structs.

---

## Change manifest (011) — for downstream propagation

### Slot-based programming (new section)

New `## Slot-based programming` section, placed after `## Ownership model`.

- The slot rule: never overwrite non-null.
- Why acquisition APIs assert null (would lose item silently).
- Why cleanup operations accept null (enables defer-before-acquisition).
- Three ASCII diagrams: slot lifecycle, ownership transfer, defer-before-acquisition safety.

### Cooperative cleanup patterns (new section)

New `## Cooperative cleanup patterns` section, placed after `## Slot-based programming`.

- Pattern 1: defer-put-early (pool item) — pool.put before pool.get.
- Pattern 2: defer-destroy-early (heap item) — PolyHelper.destroy before PolyHelper.create.
- Pattern 3: defer for mailbox receive — cleanup on both error and normal paths.
- Pattern 4: transfer clears slot — send/put sets slot.* = null, pre-empts defer.
- Each pattern: code snippet + one-line explanation.
- Pattern summary ASCII diagram.

### PolyHelper create and destroy (new subsection)

New `### PolyHelper — create and destroy` subsection in `## polynode`, placed after `### PolyHelper — all of the above, generated`.

- create: alloc + zero-init + init + slot-assign in one call. Asserts slot null.
- destroy: null-safe, clears slot before free, asserts not linked.
- Old-vs-new code comparison for both.
- no_create_destroy comptime selection: explained with ASCII diagram of the two branches.

### pool.put — null slot is now a no-op

Updated `pub fn put` in `## pool`:
- Added: `slot.* == null` → returns immediately, no hook, no assert.
- Assert block clarified: is_linked check applies only when slot.* is non-null.

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
| `mailbox.send` | `is_it_you(mbh)`, `slot.* != null`, `!is_linked(slot.*)` |
| `mailbox.send_oob` | `is_it_you(mbh)`, `slot.* != null`, `!is_linked(slot.*)` |
| `mailbox.receive` | `is_it_you(mbh)`, `slot.* == null` |
| `mailbox.try_receive` | `is_it_you(mbh)`, `slot.* == null` |
| `mailbox.receive_batch` | `is_it_you(mbh)` |
| `mailbox.close` | `is_it_you(mbh)` |
| `mailbox.destroy` | `is_it_you(mbh)` |
| `pool.destroy` | `is_it_you(ph)` |
| `pool.init` | `is_it_you(ph)`, hooks tags not empty, each tag not null, not closed |
| `pool.get` | `is_it_you(ph)`, `slot.* == null`, initialized, tag registered |
| `pool.get_wait` | `is_it_you(ph)`, `slot.* == null`, initialized, tag registered |
| `pool.put` | `is_it_you(ph)`, `!is_linked(slot.*)` |
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
