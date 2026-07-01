# Task 1 — Example Scenarios for Layers 1–3 (002)

Extracted from `task1-scenarios-001.md`. Scenario numbers preserved.

Examples show real usage patterns, stress-test API in realistic composed ways.
Each example has a test wrapper.

All scenarios comply with the example completeness rule in [rules-002.md](rules-002.md):
each example shows origin of work input, what the worker does, and where results go.

Master, Cancel, Futures, Io.Group, and subsystem coordination
are intentionally excluded. Layers 1–3 must be fully testable without them.

---

## Layer 1 — Ownership (PolyNode + Slot + Tags)

21. **Define a PolyNode type** — show how to define a user struct with `poly: PolyNode` field, unique tag, and tag check/cast helpers
22. **Ownership transfer via Slot** — create item, wrap in Slot, transfer to list, nil-out, pop, unwrap, verify, free
23. **Tag-dispatch consume loop** — mixed-type list, pop each, check tag with `== EVENT_TAG`, cast with `@fieldParentPtr`, process, free
24. **Builder pattern** — ctor/dtor factory that creates/destroys items by tag, demonstrating the Zig equivalent of Odin's builder
25. **Produce-consume with defer cleanup** — push N items, consume with tag dispatch, defer a cleanup function for the list on any exit path

---

## Layer 2 — Movement (Mailbox)

53. **Simple send-receive** — one thread sends, same thread receives (single-threaded Io), verify roundtrip
54. **Worker loop pattern** — thread receives in a loop via `mailbox.receive(mb, &item, null)`, processes each item, exits on `error.Closed`
55. **OOB via send_oob** — sender sends a signal PolyNode (e.g., FLUSH_TAG) via `mailbox.send_oob`; receiver gets it at front of queue, dispatches on tag, handles OOB inline
56. **Pipeline** — chain of mailboxes: producer → transformer → consumer, items flow through, each stage closes the next
57. **Request-response** — two mailboxes, send request to one, receive response from the other
58. **Fan-in** — multiple senders to one mailbox, single receiver processes all
59. **Shutdown with remaining item cleanup** — `mailbox.close` returns `std.DoublyLinkedList`, walk via `popFirst()`, free each item. Close returns a plain stdlib list — cleanup code is standard Zig
60. **Batch processing** — worker blocks on first item, then drains backlog with `mailbox.receive_batch`; shows the receive + batch pattern
61. **Fan-out** — multiple workers share one mailbox; each processes items until `error.Closed`; main closes to stop all workers
62. **Shutdown via ShutdownCommand** — local `ShutdownCommand` PolyNode type sent as sentinel; worker exits on receipt; remaining Events counted

---

## Layer 3 — Lifecycle (Pool)

89. **Basic recycler** — create pool with hooks, `pool.get`/`pool.put`/`pool.get` roundtrip, verify reuse
90. **Backpressure pool** — on_put caps pool at N items, excess destroyed
91. **Pool seeding** — pre-populate pool, then use `.available_only` to consume without allocation
92. **Pool teardown** — `pool.close`, on_close receives `*std.DoublyLinkedList`, walks via `popFirst()`, frees all items

---

## Layer 4 — Infra as Items

Infra handles (MailboxHandle, PoolHandle) are PolyNodes and can be transported as items.
Tag dispatch confirms class. Pointer comparison identifies instance. Role is established by protocol.

95. **Worker finish signal via mailbox return** — Master creates `worker_mbh`, spawns a real thread (`std.Thread.spawn`). Master sends work items + ShutdownCommand sentinel to `worker_mbh`. Worker processes items; on sentinel, sends `worker_mbh` back to master's inbox (unclosed) and exits. Master receives the PolyNode: `mailbox.is_it_you` confirms class; `received == worker_mbh` confirms instance. Master closes and destroys `worker_mbh`, then joins the thread (OS cleanup only — the mailbox return was the logical finish signal).

96. **Pool holds pools at teardown** — Carrier pool whose hooks accept `PoolPolyHelper.TAG`. Two inner pools stored as items via `pool.put`. On `pool.close(carrier)`, `on_close` walks the returned list, calls `pool.close` + `pool.destroy` on each inner pool. Shows uniform cleanup of infra handles with no per-instance role discrimination needed.

---

## Cross-Layer Notes

- All examples are single-threaded or use `std.Thread.spawn` — no `io.concurrent()`
- Each example has a test wrapper that calls the example and verifies it works
- Examples demonstrate working API — they cannot be written until tests prove the API
- Examples become docs — verified examples are pulled into documentation
