# Task 1 — Example Scenarios for Layers 1–3

Extracted from `task1-scenarios-001.md`. Scenario numbers preserved.

Examples show stories: real usage patterns, stress-test API in realistic composed ways.
Each example has a test wrapper.

Master, Cancel, Futures, Io.Group, and subsystem coordination
are intentionally excluded. Layers 1–3 must be fully testable without them.

---

## Layer 1 — Ownership (PolyNode + MayItem + Tags)

21. **Define a PolyNode type** — show how to define a user struct with `poly: PolyNode` field, unique tag, and tag check/cast helpers
22. **Ownership transfer via MayItem** — create item, wrap in MayItem, transfer to list, nil-out, pop, unwrap, verify, free
23. **Tag-dispatch consume loop** — mixed-type list, pop each, check tag with `== EVENT_TAG`, cast with `@fieldParentPtr`, process, free
24. **Builder pattern** — ctor/dtor factory that creates/destroys items by tag, demonstrating the Zig equivalent of Odin's builder
25. **Produce-consume with defer cleanup** — push N items, consume with tag dispatch, defer a cleanup function for the list on any exit path

---

## Layer 2 — Movement (Mailbox)

50. **Simple send-receive** — one thread sends, same thread receives (single-threaded Io), verify roundtrip
51. **Worker loop pattern** — thread receives in a loop via `mailbox.receive(mb, &item, null)`, processes each item, exits on `error.Closed`
52. **OOB via send_oob** — sender sends a signal PolyNode (e.g., FLUSH_TAG) via `mailbox.send_oob`; receiver gets it at front of queue, dispatches on tag, handles OOB inline
53. **Pipeline** — chain of mailboxes: producer → transformer → consumer, items flow through, each stage closes the next
54. **Request-response** — two mailboxes, send request to one, receive response from the other
55. **Fan-in** — multiple senders to one mailbox, single receiver processes all
56. **Shutdown with remaining item cleanup** — `mailbox.close` returns `std.DoublyLinkedList`, walk via `popFirst()`, free each item. Close returns a plain stdlib list — cleanup code is standard Zig

---

## Layer 3 — Lifecycle (Pool)

83. **Basic recycler** — create pool with hooks, `pool.get`/`pool.put`/`pool.get` roundtrip, verify reuse
84. **Backpressure pool** — on_put caps pool at N items, excess destroyed
85. **Pool seeding** — pre-populate pool, then use `.available_only` to consume without allocation
86. **Pool teardown** — `pool.close`, on_close receives `*std.DoublyLinkedList`, walks via `popFirst()`, frees all items

---

## Cross-Layer Notes

- All examples are single-threaded or use `std.Thread.spawn` — no `io.concurrent()`
- Each example has a test wrapper that calls the example and verifies it works
- Examples demonstrate working API — they cannot be written until tests prove the API
- Examples become docs — verified examples are pulled into documentation
