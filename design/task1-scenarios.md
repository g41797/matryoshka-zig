# Task 1 — Test and Example Scenarios for Layers 1–3

Intents with short descriptions. No code.

Master, Cancel, Futures, Io.Group, and subsystem coordination
are intentionally excluded. Layers 1–3 must be fully testable without them.

---

## Layer 1 — Ownership (PolyNode + MayItem + Tags)

### Tests

1. **Tag uniqueness** — two different types produce different TAG addresses; same type always returns same TAG
2. **Tag init** — after setting `foo.poly.tag = EVENT_TAG`, verify `foo.poly.tag == EVENT_TAG`
3. **Tag identity check** — `tag == EVENT_TAG` is true; `tag == SENSOR_TAG` is false
4. **@fieldParentPtr cast success** — given a `*PolyNode` with correct tag, `@fieldParentPtr("poly", poly)` recovers `*Event`
5. **@fieldParentPtr cast wrong tag** — given a `*PolyNode` with wrong tag, tag check fails before cast (user code responsibility)
6. **Two-level @fieldParentPtr chain** — DoublyLinkedList.Node → PolyNode → UserType, verify field values survive the roundtrip
7. **polynode.reset clears links** — after reset, `node.prev == null` and `node.next == null`
8. **polynode.is_linked detection** — linked node returns true; reset node returns false
9. **MayItem null semantics** — `null` means not owned; non-null means owned; assignment to null releases ownership handle
10. **Multiple types in one list** — push Event and Sensor into same `std.DoublyLinkedList`, pop and dispatch on tag, verify correct recovery via `@fieldParentPtr`. Demonstrates stdlib compatibility: PolyNode-based items participate in standard lists with no adapter

### Tests — Ownership State Transitions

11. **FREE → IN_FLIGHT** — allocate item, set tag; MayItem is non-null; item is not linked; this is IN_FLIGHT
12. **IN_FLIGHT → HELD (list)** — push item to intrusive list, nil-out MayItem; item is linked; this is HELD
13. **HELD → IN_FLIGHT (list)** — pop from list; MayItem is non-null; item is unlinked after reset; this is IN_FLIGHT
14. **IN_FLIGHT → FREE** — free item, set MayItem to null; ownership released

### Tests — Ownership Violation Detection

15. **Send linked item panics** — item is in a list (polynode_is_linked == true); attempt to push again; expect panic or assertion failure
16. **Double list insertion** — push same item twice without popping; expect panic or assertion failure
17. **Use after nil-out** — set MayItem to null (ownership released); verify the handle is null; attempting to use it is a bug (document this invariant)

### Tests — Infrastructure as Items (Layer 1 level)

18. **MailboxHandle is a PolyNode** — `MailboxHandle = *PolyNode`; verify `mbox.is_it_you(mbh.tag)` returns true
19. **PoolHandle is a PolyNode** — `PoolHandle = *PolyNode`; verify `pool.is_it_you(ph.tag)` returns true
20. **Per-module destroy** — `mbox.destroy(mbh, alloc)` frees a closed mailbox. `pool.destroy(ph, alloc)` frees a closed pool

### Examples

21. **Define a PolyNode type** — show how to define a user struct with `poly: PolyNode` field, unique tag, and tag check/cast helpers
22. **Ownership transfer via MayItem** — create item, wrap in MayItem, transfer to list, nil-out, pop, unwrap, verify, free
23. **Tag-dispatch consume loop** — mixed-type list, pop each, check tag with `== EVENT_TAG`, cast with `@fieldParentPtr`, process, free
24. **Builder pattern** — ctor/dtor factory that creates/destroys items by tag, demonstrating the Zig equivalent of Odin's builder
25. **Produce-consume with defer cleanup** — push N items, consume with tag dispatch, defer a cleanup function for the list on any exit path

---

## Layer 2 — Movement (Mailbox)

### Tests

26. **mbox.new and mbox.destroy** — create mailbox, verify handle is non-null and `mbox.is_it_you` returns true; close then destroy, verify freed
27. **Send and receive single item** — `mbox.send` one PolyNode, `mbox.receive` it, verify tag and data intact
28. **FIFO ordering** — send 3 items, receive 3, verify order preserved
29. **Send to closed mailbox returns error.Closed** — close first, then send, verify error
30. **Receive from closed mailbox returns error.Closed** — close first, then receive, verify error
31. **Receive timeout (non-null ?u64)** — `mbox.receive` on empty open mailbox with `timeout_ns = 1000`, verify `error.Timeout`
32. **Receive wait forever (null ?u64)** — `mbox.receive` with `timeout_ns = null` on a mailbox that gets an item sent from another context; verify item received, no `error.Timeout`
33. **Close returns remaining items as std.DoublyLinkedList** — send 3 items, `mbox.close` without receiving, verify returned list has 3 items via `popFirst()` loop
34. **Close is idempotent** — second `mbox.close` returns empty `std.DoublyLinkedList`
35. **send_oob delivers to front of queue** — send 3 normal items, then `mbox.send_oob` 1 item; receive gets the OOB item first
36. **send_oob wakes blocked receiver** — receiver blocked on empty mailbox, `mbox.send_oob` delivers item, receiver gets it
37. **Multiple send_oob items maintain FIFO among themselves** — `mbox.send_oob` A then `mbox.send_oob` B; receive gets A first, then B (OOBs inserted after previous OOBs)
38. **send_oob to closed mailbox returns error.Closed** — same as normal send
39. **Data priority over closed** — send item then close; receive gets the item first (or close returns it in remaining list)
40. **Batch receive (mbox.receive_batch)** — send 5 items, `mbox.receive_batch` gets all 5 as `std.DoublyLinkedList`, mailbox empty after
41. **Batch receive on empty returns empty list** — no items, `mbox.receive_batch` returns empty `std.DoublyLinkedList` (not error)
42. **Batch items walkable via popFirst** — `mbox.receive_batch` returns `std.DoublyLinkedList`; walk via `popFirst()` which auto-clears prev/next — no manual `polynode.reset` needed. Standard stdlib iteration, nothing Matryoshka-specific
43. **Send transfers ownership** — after `mbox.send`, caller's MayItem is null
44. **Receive transfers ownership** — after `mbox.receive`, caller's MayItem is non-null, mailbox no longer holds it
45. **try_receive on empty returns false** — `mbox.try_receive` on open empty mailbox returns false, MayItem stays null
46. **try_receive gets item** — send item, `mbox.try_receive` returns true, MayItem is non-null

### Tests — Ownership State Transitions (Mailbox)

47. **IN_FLIGHT → HELD (mbox.send)** — item owned by caller; `mbox.send` transfers to mailbox; MayItem is null; item is HELD
48. **HELD → IN_FLIGHT (mbox.receive)** — item in mailbox; `mbox.receive` transfers to caller; MayItem is non-null; item is IN_FLIGHT
49. **Send linked item panics** — item already in a list; `mbox.send` should detect `polynode.is_linked` and panic

### Examples

50. **Simple send-receive** — one thread sends, same thread receives (single-threaded Io), verify roundtrip
51. **Worker loop pattern** — thread receives in a loop via `mbox.receive(mb, &item, null)`, processes each item, exits on `error.Closed`
52. **OOB via send_oob** — sender sends a signal PolyNode (e.g., FLUSH_TAG) via `mbox.send_oob`; receiver gets it at front of queue, dispatches on tag, handles OOB inline
53. **Pipeline** — chain of mailboxes: producer → transformer → consumer, items flow through, each stage closes the next
54. **Request-response** — two mailboxes, send request to one, receive response from the other
55. **Fan-in** — multiple senders to one mailbox, single receiver processes all
56. **Shutdown with remaining item cleanup** — `mbox.close` returns `std.DoublyLinkedList`, walk via `popFirst()`, free each item. Close returns a plain stdlib list — cleanup code is standard Zig

---

## Layer 3 — Lifecycle (Pool)

### Tests

57. **pool.new, pool.init, pool.destroy** — create pool, register hooks via `pool.init`, verify handle; close then destroy
58. **pool.get creates new item via on_get** — empty pool, `.available_or_new` mode, on_get called with `m.* == null`, returns new item
59. **pool.get reuses stored item** — put item back, get again, verify same pointer returned
60. **on_get reinitializes recycled item** — put item with data, get it back, verify fields were reset by on_get
61. **pool.put calls on_put** — verify on_put hook is invoked with correct in_pool_count
62. **on_put can destroy item** — on_put sets `m.* = null` (destroy policy), verify item not stored
63. **on_put can keep item** — on_put leaves `m.*` non-null (keep policy), verify item stored in pool
64. **GetMode.new_only always creates** — even with items available, `.new_only` calls on_get with null
65. **GetMode.available_only returns error.NotAvailable** — empty pool, `.available_only` mode, returns `error.NotAvailable`
66. **GetMode.available_only returns stored item** — pool has item, `.available_only` returns it
67. **Per-tag free lists** — pool stores Event and Sensor separately, `pool.get` with EVENT_TAG returns Event, not Sensor
68. **pool.close calls on_close with all items** — put 5 items, `pool.close`, on_close receives `*std.DoublyLinkedList` with 5 items
69. **pool.close is idempotent** — second close is no-op
70. **pool.get on closed pool returns error.Closed** — close first, then get, verify error
71. **pool.put on closed pool returns item to caller** — put after close, MayItem stays non-null (caller still owns it)
72. **Backpressure policy** — on_put drops items when count exceeds threshold
73. **Pool seeding** — pre-allocate N items with `.new_only` + `pool.put`, verify N available with `.available_only`
74. **in_pool_count accuracy** — track count across get/put cycles, verify on_get and on_put receive correct counts
75. **Hooks run outside lock** — verify no deadlock when on_get/on_put call into pool (indirect test via successful operation)
76. **pool.put_all** — return a batch of items via `*std.DoublyLinkedList`; callee pops from caller's list. Accepts a standard stdlib list — no conversion needed from `mbox.receive_batch` or `mbox.close` results
77. **pool.get_wait timeout (non-null ?u64)** — `pool.get_wait` with `timeout_ns = 1000` on empty pool, verify `error.Timeout`
78. **pool.get_wait forever (null ?u64)** — `pool.get_wait` with `timeout_ns = null` on pool that gets an item put from another context; verify item received

### Tests — Ownership State Transitions (Pool)

79. **HELD → IN_FLIGHT (pool.get)** — item in pool free-list; `pool.get` transfers to caller; MayItem non-null; item is IN_FLIGHT
80. **IN_FLIGHT → HELD (pool.put, keep)** — item owned by caller; `pool.put` with on_put that keeps; item back in pool; MayItem null
81. **IN_FLIGHT → FREE (pool.put, destroy)** — item owned by caller; `pool.put` with on_put that destroys; item freed; MayItem null
82. **Double pool.put** — put same item twice without getting in between; expect panic or assertion failure

### Examples

83. **Basic recycler** — create pool with hooks, `pool.get`/`pool.put`/`pool.get` roundtrip, verify reuse
84. **Backpressure pool** — on_put caps pool at N items, excess destroyed
85. **Pool seeding** — pre-populate pool, then use `.available_only` to consume without allocation
86. **Pool teardown** — `pool.close`, on_close receives `*std.DoublyLinkedList`, walks via `popFirst()`, frees all items

---

## Cross-Layer Notes

- All Layer 2-3 tests that need blocking use `Io.Threaded.global_single_threaded` — no cancellation
- Thread-based tests use `std.Thread.spawn` (still exists in 0.16), not `io.concurrent()`
- `io.concurrent()` / `Future` / `Io.Group` / `error.Canceled` reserved for Layer 4 (Task 2)
- Builder/types are shared test infrastructure, not part of any layer's public API
- Close ordering tests (pool then mailbox / mailbox then pool) are in Task 2 cross-layer section (scenarios 36-37)
- Ownership-state tests validate the architecture's core invariants, not implementation details — they should survive any internal rewrite
- API uses module-function style: `mbox.send(mb, &item)` not `mbox_send(mb, &item)` — see Proposal 4
- Handle types are already pointers: `mbh: MailboxHandle` (= `*PolyNode`), not `mbh: *MailboxHandle` — see Proposal 6, 12
- Batch returns are `std.DoublyLinkedList`, walked via `popFirst()` — no manual `polynode.reset` needed — see Proposal 2
- stdlib compatibility is a feature: PolyNode embeds `std.DoublyLinkedList.Node`, so all batch/close/put_all operations use plain stdlib lists — see Proposal 23
- Timeout is `?u64`: null = wait forever, value = nanoseconds — see Proposal 3
