# Task 2 — Test Scenarios for Layer 4 and Cross-Layer

Extracted from `task2-scenarios-001.md`. Scenario numbers preserved.

Tests check implementation: correctness, edge cases, error paths, contract violations.

All Layer 4 tests use real `Io.Threaded.init(gpa, .{})` — concurrency, cancellation, real I/O.

---

## Layer 4 — Coordination (Master) + Real Io

### Tests — Worker Lifecycle

1. **Single worker spawn and join** — Master spawns worker via `io.concurrent()`, worker receives one item, exits. Master awaits Future. `[io.concurrent, Future.await]`
2. **Worker group spawn and join** — Master spawns 3 workers via `Io.Group.concurrent()`, all process items, Master calls `group.await()`. `[Io.Group, group.concurrent, group.await]`
3. **Future.cancel stops blocked worker** — Worker blocked in `mailbox.receive`, Master calls `future.cancel(io)`. Worker receives `error.Canceled`, exits. Future.cancel returns after worker exits. `[Future.cancel, error.Canceled propagation through mailbox.receive]`
4. **Group.cancel stops all workers** — 3 workers blocked in `mailbox.receive`, Master calls `group.cancel(io)`. All workers exit. `[Io.Group, group.cancel, error.Canceled broadcast]`
5. **Worker not blocked when cancel fires** — Worker is between `mailbox.receive` and `pool.put`. Cancel takes effect at next Io wait (`pool.put` is cancel-protected, so at next `mailbox.receive`). `[error.Canceled deferred to next cancellation point]`

### Tests — Shutdown Ordering

6. **Broadcast shutdown: mailbox.close before join** — Master closes mailbox (broadcasts), worker wakes with `error.Closed`, exits. Master joins, then closes pool, walks remaining items. `[mailbox.close broadcast, error.Closed, lockUncancelable]`
7. **Cancel shutdown: future.cancel before close** — Master calls `future.cancel(io)`, worker exits. Then Master calls `pool.close` and `mailbox.close` to reclaim items. No race — worker already exited. `[Future.cancel, pool.close, mailbox.close after join]`
8. **pool.put on closed pool** — Worker holds item when `pool.close` fires. `pool.put` returns item to caller (MayItem stays non-null). Worker disposes item via on_close hook. `[pool.put cancel-protected, closed pool rejection]`
9. **mailbox.close returns remaining items** — Send 10 items, close after 3 consumed. Walk returned `std.DoublyLinkedList` via `popFirst()`, verify 7 items recovered. `[mailbox.close snapshot, batch cleanup]`
10. **pool.close calls on_close with all items** — Put 5 items, `pool.close`. on_close receives `*std.DoublyLinkedList` with 5 items. Hook walks via `popFirst()` and frees. `[pool.close, on_close hook]`

### Tests — Cancellation Mechanics

11. **error.Canceled distinct from error.Closed in mailbox.receive** — Cancel worker task while mailbox is open. Worker sees `error.Canceled`, not `error.Closed`. Then close mailbox separately. `[error.Canceled vs error.Closed distinction]`
12. **error.Canceled distinct from error.Closed in pool.get_wait** — Same test for pool. Cancel task while pool is open. `[error.Canceled vs error.Closed in pool]`
13. **pool.put is cancel-protected** — Worker receives `error.Canceled` from `mailbox.receive`, then calls `pool.put` to return item. `pool.put` must succeed (uses `lockUncancelable`). Item not lost. `[pool.put lockUncancelable, cleanup after cancel]`
14. **mailbox.close uses lockUncancelable** — Close mailbox from a canceled task. Close must complete — `std.DoublyLinkedList` returned, broadcast sent. `[mailbox.close lockUncancelable]`
15. **recancel propagation** — Worker catches `error.Canceled`, does cleanup, calls `io.recancel()`, next Io call returns `error.Canceled` again. `[recancel]`
16. **checkCancel in CPU-bound work** — Worker does long computation between `mailbox.receive` calls. Calls `io.checkCancel()` periodically. Cancel fires at checkCancel. `[checkCancel]`

### Cross-Layer Integration Tests (Layers 1-3)

32. **Pool → Mailbox → Pool roundtrip** — `pool.get`, fill, `mailbox.send`, `mailbox.receive`, verify data, `pool.put` back. Single-threaded. Verify same pointer returned on second get. `[cross-layer ownership flow, no concurrency]`
33. **Mixed types through shared mailbox** — Send Event and Sensor PolyNodes through same mailbox via `mailbox.send`. Receive, dispatch on tag (`== EVENT_TAG`), cast via `@fieldParentPtr`, verify data. `[Layer 1 tags + Layer 2 transport]`
34. **Batch receive + pool return** — Send 10 items, `mailbox.receive_batch` returns `std.DoublyLinkedList`, walk via `popFirst()`, `pool.put_all` back to pool. Verify pool count. Same `std.DoublyLinkedList` flows from mailbox to pool — stdlib compatibility connects the layers. `[mailbox.receive_batch + pool.put_all integration, stdlib list]`
35. **Pool hooks + mailbox flow** — on_get creates/reinits, `mailbox.send`, `mailbox.receive`, on_put decides keep/destroy. Full lifecycle through both layers. `[pool hooks + mailbox transport]`
36. **Close ordering: pool then mailbox** — `pool.close` first (on_close frees stored items), then `mailbox.close` (returns `std.DoublyLinkedList`), walk via `popFirst()` and free. Verify no leaks. `[shutdown ordering, cross-layer cleanup]`
37. **Close ordering: mailbox then pool** — `mailbox.close` first (worker returns item via `pool.put` while pool open), then `pool.close` (includes returned item in on_close). Verify same total items. `[alternative shutdown order, same correctness]`
38. **Pool + Mailbox flow** — `pool.get`, fill, `mailbox.send`, `mailbox.receive`, `pool.put` back (single-threaded or two-thread). `[cross-layer ownership flow]`

---

## Reference

- Io as an Interface: https://ziglang.org/download/0.16.0/release-notes.html#IO-as-an-Interface
- std.Io overview: https://ziggit.dev/t/std-io-overview/
- Discussion about Io and Zig: https://ziggit.dev/t/discussion-about-io-and-zig/
