# Task 2 — Layer 4 (Master) and Cross-Layer Scenarios

## External Resources

- Release notes (Io section): https://ziglang.org/download/0.16.0/release-notes.html#IO-as-an-Interface
- Discussion about Io and Zig: https://ziggit.dev/t/discussion-about-io-and-zig/
- std.Io overview: https://ziggit.dev/t/std-io-overview/

## Io Primitives for Master (from Io.zig source + web resources)

### Io as an Interface
- `Io` is a vtable-based interface — all blocking/nondeterministic operations go through it
- Multiple backends: `Io.Threaded` (production), `Io.Evented` (WIP), `Io.Uring` (PoC), `Io.Kqueue` (PoC)
- Application's `main` chooses the backend; libraries accept `Io` as parameter
- `Io` is not just file/network I/O — it is the complete concurrency and scheduling interface

### How to get an Io instance
- `pub fn main(init: std.process.Init) !void` — `init.io` (the "juicy main")
- `std.Io.Threaded.init(gpa, .{})` — multi-threaded, supports concurrency + cancellation
- `std.Io.Threaded.init_single_threaded` — comptime const, no concurrency, no cancellation
- `std.Io.Threaded.global_single_threaded` — mutable global pointer to above, for testing/debugging
- `std.testing.io` — for unit tests

### io.async(fn, args) → Future(Result)
- May execute synchronously (e.g., single-threaded, OOM, or limit reached)
- When it does run concurrently: allocates a Future, spawns an OS thread if pool exhausted, puts task on run queue
- More portable than `concurrent` — works on all backends
- `Future.await(io)` blocks until completion, returns result. Idempotent, not threadsafe
- `Future.cancel(io)` requests cancellation + awaits, returns result. Idempotent, not threadsafe

### io.concurrent(fn, args) → ConcurrentError!Future(Result)
- Guarantees actual concurrency — fails with `error.ConcurrencyUnavailable` if impossible
- `single_threaded` always returns `error.ConcurrencyUnavailable`
- Spawns OS thread via `std.Thread.spawn` if worker pool is exhausted (Threaded backend)
- Thread is detached — Threaded manages its own thread pool internally
- Subject to `concurrent_limit` — returns `error.ConcurrencyUnavailable` if at capacity

### Future resource management
- Futures are resources — must call `await` or `cancel` to release
- Recommended pattern: `defer if (future.cancel(io)) |resource| resource.deinit() else |_| {};`
- After `cancel`/`await`, `any_future` is set to null — subsequent calls return cached result

### Io.Group
- Unordered set of tasks, can only be awaited/canceled as a whole
- `group.concurrent(io, fn, args)` adds a task; `group.async(io, fn, args)` for weaker guarantee
- `group.cancel(io)` cancels all members + awaits all (returns void)
- `group.await(io)` waits for all (returns Cancelable!void — propagates if the awaiter itself is canceled)
- Worker function must return `Cancelable!void` — Group **swallows** `error.Canceled` from workers (line 1245: `catch {}`)
- Resources associated with each task released when individual task returns, not when group completes
- Threadsafe for concurrent additions while awaiting (provided group doesn't complete before add returns)
- Replaces `std.Thread.Pool` + `std.Thread.WaitGroup` (both removed in 0.16)

### Io.Select(U)
- Combination of Group + Queue + metaprogramming
- Spawn tasks of different return types, each mapped to a field of tagged union U
- `select.await()` returns whichever finishes first as U
- `select.awaitMany(buffer, min)` waits for at least `min` results
- `select.cancel()` cancels remaining + returns results one at a time (needs buffer space)
- `select.cancelDiscard()` cancels remaining + discards results (no buffer needed)
- Threadsafe for async/concurrent calls
- Use case: Master waiting on multiple event sources (mailbox, timer, external signal)

### Io.Queue(T)
- Multi-producer, multi-consumer FIFO queue
- Backed by a buffer, blocks when full/empty
- `putOne`/`getOne` and `put`/`get` (batch) operations
- Can be closed — remaining items still retrievable
- Used internally by Select

### Cancellation System
- Cancellation = request to interrupt, non-binding
- `error.Canceled` returned from the next "cancellation point" (any Io function with Cancelable in error set)
- Only the **next** cancellation point returns `error.Canceled` — subsequent ones do NOT re-signal
- Threaded backend: implemented via OS signals (EINTR on POSIX)
- Three handling strategies:
  1. Propagate `error.Canceled` up
  2. `io.recancel()` — re-arm so next point fires again (cleanup-then-propagate)
  3. `io.swapCancelProtection(.blocked)` — block all cancellation points in a region

### Mutex.lockUncancelable / Condition.waitUncancelable
- Built-in uncancelable variants — alternative to swapCancelProtection pattern
- Close operations can use `lockUncancelable` directly
- `Condition.waitInner` takes `uncancelable: bool` internally — uses `futexWaitUncancelable` when true

### recancel(io)
- Re-arms a consumed `error.Canceled` so the next cancellation point fires again
- Asserts that `error.Canceled` was previously returned — panics if called without prior cancellation
- For cleanup-then-propagate patterns in worker code

### checkCancel(io)
- Pure cancellation point, no other effect
- For long CPU-bound work between Io calls
- Rarely needed — most code has enough Io calls as natural cancellation points

### CancelProtection
- `io.swapCancelProtection(.blocked)` blocks all cancellation points
- `io.swapCancelProtection(.unblocked)` restores (use with defer)
- Alternative to lockUncancelable/waitUncancelable for protecting whole code regions
- Per-task state — stored in Thread struct (Threaded backend)

### global_single_threaded specifics
- `concurrent_limit = .nothing` — all `io.concurrent()` calls return `error.ConcurrencyUnavailable`
- `async_limit = .nothing` — all `io.async()` calls execute synchronously (start function called inline)
- Does NOT support cancellation
- Suitable for Layer 1-3 tests that don't need concurrency

### Threaded backend internals (from Threaded.zig)
- Manages an internal thread pool — spawns OS threads via `std.Thread.spawn` on demand, detaches them
- `busy_count` tracks active tasks against `async_limit` / `concurrent_limit`
- Tasks go on a `run_queue` (intrusive linked list); worker threads pull from it
- `io.async()` degrades gracefully: OOM → run inline, limit reached → run inline
- `io.concurrent()` fails hard: OOM → `ConcurrencyUnavailable`, limit reached → `ConcurrencyUnavailable`
- Cancellation via signals: `Future.cancel` sets canceled status, signals the thread, waits for completion
- `groupCancel` sets canceled flag on group status, then signals all member threads and waits

---

## Select + Mailbox/Pool: the Key Insight

`mbox_receive` and `pool_get_wait` block internally on `Io.Condition.wait`. They are not raw Io operations composable into a Batch.

To use them inside `Io.Select`:
- Each event source is a concurrent task calling `mbox_receive` or `pool_get_wait`
- When one completes, Select returns its result
- The others get canceled via `group.cancel` → `error.Canceled` propagates into the blocked `Io.Condition.wait` inside the unfinished calls

**This is why `mbox_receive` and `pool_get_wait` must propagate `error.Canceled` directly** — not remap to `error.Closed`. If they remapped, Select could not distinguish "task was canceled because another event source won" from "mailbox/pool was shut down."

Example pattern (intent, not code):
- Master uses Select to wait on: mailbox receive OR timer OR external signal
- Whichever fires first, the others are canceled
- Worker sees `error.Canceled` from the lost event sources, not `error.Closed`

**However**: On the current Threaded backend, Select may require additional worker tasks and often additional threads per event source. Future backends (Evented, Uring) may behave differently. When items carry ownership, use fan-in to one mailbox — no Select overhead needed. Select is appropriate when composing Matryoshka with external Io operations (network, file, timers managed outside Matryoshka).

---

## Mailbox Design Decisions

### mbox_send is cancelable
`mbox_send` acquires `mutex.lock(io)` which is a cancellation point. If the sender's task is canceled, `error.Canceled` propagates. The caller still owns the item (MayItem not cleared) — item is not lost. This is correct: send is a work-path operation, cancellation is safe.

Contrast with `pool_put` which is cancel-protected (cleanup path — item would be lost if put failed).

### mbox_close uses lockUncancelable
`mbox_close` must complete regardless of cancellation state. Uses `mutex.lockUncancelable(io)` directly — simpler and more explicit than the `swapCancelProtection(.blocked)` + `mutex.lock(io) catch unreachable` pattern. Same applies to `pool_close` and `pool_put`.

### _Mbox and _Pool store `io: Io` ("managed" pattern)
Zig 0.16 moved containers (ArrayList, HashMap) to "unmanaged" — allocator passed per-call, not stored. This does NOT apply to infrastructure objects.

Distinction:
- **Containers** (ArrayList, HashMap): generic building blocks, many instances, only some operations need allocator. Unmanaged is correct.
- **Infrastructure objects** (MailboxHandle, PoolHandle, http.Client): long-lived, created once, EVERY operation needs `io` (all acquire mutex). Storing `io` is correct.

`std.http.Client` in stdlib stores both `allocator` and `io`. Same pattern for `_Mbox` and `_Pool`. Pass `io` once at construction (`mbox_new(io, alloc)`, `pool_new(io, alloc)`).

### When to use fan-in mailbox
When items carry ownership, many senders fan into one mailbox. All sources send tagged PolyNodes to one receiver:
- Data arrives → send DataPolyNode
- Timer fires → send TimerPolyNode
- External signal → send SignalPolyNode
- OOB → `send_oob` with OobPolyNode

Master has one receive loop, dispatches on tag. One mailbox. One ownership model. Tag dispatch handles the rest.

Benefits:
- One queue, one ownership model, one dispatch model, one shutdown model
- No additional worker tasks for waiting — receiver blocks on one `mbox_receive`
- Consistent with Matryoshka's ownership-first philosophy

Outside Matryoshka, `Io.Select` remains useful for integrating external Io sources (network, file system, timers not managed through Matryoshka). The two approaches are complementary, not exclusive.

---

## Master is a Concept, not a Type

Mailbox and Pool are concrete infrastructure objects — they have specific structs, specific APIs, specific ownership semantics.

Master is different. Master is a coordination boundary — a role, not a required type.

The architecture requires that **something** owns:
- mailbox (transport)
- lifecycle policy (pool + hooks)
- cancellation policy (when to stop)
- worker coordination (spawn, join, cancel)

That something is called Master. A developer may implement it as:

```text
const Master = struct { inbox, pool, hooks, ... };
const Server = struct { ... };
const Runtime = struct { ... };
const WorkerGroup = struct { ... };
main()
```

Master is not a mandatory PolyNode. Master is not a mandatory struct. Master is not a mandatory runtime object.

Mailbox and Pool are infrastructure. Master is architecture.

This distinction matters for Layer 4 examples: they demonstrate Master patterns, not a Master type. Each example may structure its coordination boundary differently.

---

## Layer 4 — Coordination (Master) + Real Io

All Layer 4 examples use real `Io.Threaded.init(gpa, .{})` — concurrency, cancellation, real I/O.

### Tests — Worker Lifecycle

1. **Single worker spawn and join** — Master spawns worker via `io.concurrent()`, worker receives one item, exits. Master awaits Future. `[io.concurrent, Future.await]`
2. **Worker group spawn and join** — Master spawns 3 workers via `Io.Group.concurrent()`, all process items, Master calls `group.await()`. `[Io.Group, group.concurrent, group.await]`
3. **Future.cancel stops blocked worker** — Worker blocked in `mbox.receive`, Master calls `future.cancel(io)`. Worker receives `error.Canceled`, exits. Future.cancel returns after worker exits. `[Future.cancel, error.Canceled propagation through mbox.receive]`
4. **Group.cancel stops all workers** — 3 workers blocked in `mbox.receive`, Master calls `group.cancel(io)`. All workers exit. `[Io.Group, group.cancel, error.Canceled broadcast]`
5. **Worker not blocked when cancel fires** — Worker is between `mbox.receive` and `pool.put`. Cancel takes effect at next Io wait (`pool.put` is cancel-protected, so at next `mbox.receive`). `[error.Canceled deferred to next cancellation point]`

### Tests — Shutdown Ordering

6. **Broadcast shutdown: mbox.close before join** — Master closes mailbox (broadcasts), worker wakes with `error.Closed`, exits. Master joins, then closes pool, walks remaining items. `[mbox.close broadcast, error.Closed, lockUncancelable]`
7. **Cancel shutdown: future.cancel before close** — Master calls `future.cancel(io)`, worker exits. Then Master calls `pool.close` and `mbox.close` to reclaim items. No race — worker already exited. `[Future.cancel, pool.close, mbox.close after join]`
8. **pool.put on closed pool** — Worker holds item when `pool.close` fires. `pool.put` returns item to caller (MayItem stays non-null). Worker disposes item via on_close hook. `[pool.put cancel-protected, closed pool rejection]`
9. **mbox.close returns remaining items** — Send 10 items, close after 3 consumed. Walk returned `std.DoublyLinkedList` via `popFirst()`, verify 7 items recovered. `[mbox.close snapshot, batch cleanup]`
10. **pool.close calls on_close with all items** — Put 5 items, `pool.close`. on_close receives `*std.DoublyLinkedList` with 5 items. Hook walks via `popFirst()` and frees. `[pool.close, on_close hook]`

### Tests — Cancellation Mechanics

11. **error.Canceled distinct from error.Closed in mbox.receive** — Cancel worker task while mailbox is open. Worker sees `error.Canceled`, not `error.Closed`. Then close mailbox separately. `[error.Canceled vs error.Closed distinction]`
12. **error.Canceled distinct from error.Closed in pool.get_wait** — Same test for pool. Cancel task while pool is open. `[error.Canceled vs error.Closed in pool]`
13. **pool.put is cancel-protected** — Worker receives `error.Canceled` from `mbox.receive`, then calls `pool.put` to return item. `pool.put` must succeed (uses `lockUncancelable`). Item not lost. `[pool.put lockUncancelable, cleanup after cancel]`
14. **mbox.close uses lockUncancelable** — Close mailbox from a canceled task. Close must complete — `std.DoublyLinkedList` returned, broadcast sent. `[mbox.close lockUncancelable]`
15. **recancel propagation** — Worker catches `error.Canceled`, does cleanup, calls `io.recancel()`, next Io call returns `error.Canceled` again. `[recancel]`
16. **checkCancel in CPU-bound work** — Worker does long computation between `mbox.receive` calls. Calls `io.checkCancel()` periodically. Cancel fires at checkCancel. `[checkCancel]`

### Examples — Master Patterns

17. **Minimal Master** — Master struct with inbox (`mbox.MailboxHandle`) + alloc. Spawns one worker via `io.concurrent()`. Sends items, `mbox.close`, awaits worker, walks remaining list via `popFirst()`. The simplest complete Layer 4 example. Shutdown cleanup uses plain stdlib list — no Matryoshka-specific cleanup API. `[io.concurrent, Future.await, mbox.close, stdlib list]`
18. **Master with Pool** — Master with inbox + pool + hooks. Worker uses `pool.get`, `mbox.receive`, processes, `pool.put` back. Shutdown via `future.cancel`. `[io.concurrent, Future.cancel, pool lifecycle]`
19. **Multi-worker Master** — Master spawns N workers via `Io.Group`. All receive from shared mailbox. Shutdown via `group.cancel`. `[Io.Group, group.cancel, shared mailbox]`
20. **Pipeline of Masters** — 3 Masters chained: producer → transformer → consumer. Each has its own worker. Items flow through mailboxes. Producer closes downstream mailbox to signal completion. `[multi-Master, cross-mailbox ownership transfer]`
21. **Request-response between Masters** — Master A sends request to Master B's inbox. Master B processes, sends response to Master A's inbox. Bidirectional ownership transfer. `[two Masters, bidirectional mailbox]`

### Examples — Mailbox as Multiplexer

22. **Timer via mailbox** — Separate timer task sends TimerPolyNode to Master's inbox periodically. Worker dispatches on tag: data items vs timer ticks. No Select needed. `[io.concurrent for timer task, tag dispatch, fan-in mailbox]`
23. **OOB via send_oob** — Sender sends OOB signal PolyNode via `mbox.send_oob`. Worker's next receive gets OOB item immediately (front of queue), handles it, resumes normal processing. `[mbox.send_oob, OOB handling, tag dispatch]`
24. **Multiple event sources, one mailbox** — Timer task + data producer + signal source all send to one mailbox with different tags. Worker has single receive loop, dispatches on tag. `[fan-in mailbox, multiple concurrent senders]`

### Examples — Io Integration (timer + mailboxes)

25. **Two mailboxes + timer in Select** — Master defines event union with `.inbox1`, `.inbox2`, `.timer`. Both mailboxes use `mbox.receive_select` as event sources, wait forever (`null` timeout). Timer fires first. Master handles timer event, re-spawns timer, continues. Items from either mailbox handled as they arrive. `[Io.Select, Io.sleep, two mbox.receive_select event sources, basic integration]`
26. **Timer cancel → close → walk remaining** — Two mailboxes + timer in Select. Timer fires → Master calls `select.cancel()`. Both blocked `receive_select` event sources get `error.Canceled` → return `.canceled`. Master then calls `mbox.close` on both → walks returned `std.DoublyLinkedList` lists. All items accounted for. Cancel and close are separate operations. `[cancel propagation, mbox.close after cancel, no item loss, cancel/close separation]`
27. **Cancel reports, Master decides** — Two mailboxes in Select via `mbox.receive_select`. `select.cancel()` fires. Both event sources return `.canceled` (mailboxes remain open). Master decides: close inbox1 immediately, re-spawn inbox2 for graceful drain. Cancel never triggers close — Master owns shutdown decisions. `[Proposal 26, cancel/close separation, Master controls shutdown]`
28. **Multiple event source types in one Select** — inbox uses `mbox.receive_select`, job pool uses `pool.get_wait_select`, timer uses `Io.sleep`. Master handles each in one switch. All three are event sources with uniform result handling. `[Proposal 26, mixed mbox + pool + timer event sources]`
29. **Cancel → Master close → pool.put_all** — Select cancel fires. Master receives `.canceled` from event sources. Master then closes mailbox, passes returned list to `pool.put_all` — items recycled, not freed. Close is Master's explicit decision after cancel. `[cancel then close, pool lifecycle, stdlib list bridges layers]`
30. **Timeout on mailbox** — Worker uses `mbox.receive` with non-null `?u64` timeout. Timeout fires → `error.Timeout`. Worker does alternative work (e.g., `Io.sleep` then retry). `[mbox.receive ?u64 timeout, Io.sleep retry]`
31. **Graceful shutdown with in-flight items** — Master has 2 event sources via Select. `select.cancel()` fires. Event sources at different stages: one blocked in `mbox.receive_select`, one between operations. All return `.canceled`. Master closes mailboxes and collects remaining items. `[Io.Select cancel, mixed cancellation points, no item loss]`

### Cross-Layer Integration Tests (Layers 1-3)

32. **Pool → Mailbox → Pool roundtrip** — `pool.get`, fill, `mbox.send`, `mbox.receive`, verify data, `pool.put` back. Single-threaded. Verify same pointer returned on second get. `[cross-layer ownership flow, no concurrency]`
33. **Mixed types through shared mailbox** — Send Event and Sensor PolyNodes through same mailbox via `mbox.send`. Receive, dispatch on tag (`== EVENT_TAG`), cast via `@fieldParentPtr`, verify data. `[Layer 1 tags + Layer 2 transport]`
34. **Batch receive + pool return** — Send 10 items, `mbox.receive_batch` returns `std.DoublyLinkedList`, walk via `popFirst()`, `pool.put_all` back to pool. Verify pool count. Same `std.DoublyLinkedList` flows from mailbox to pool — stdlib compatibility connects the layers. `[mbox.receive_batch + pool.put_all integration, stdlib list]`
35. **Pool hooks + mailbox flow** — on_get creates/reinits, `mbox.send`, `mbox.receive`, on_put decides keep/destroy. Full lifecycle through both layers. `[pool hooks + mailbox transport]`
36. **Close ordering: pool then mailbox** — `pool.close` first (on_close frees stored items), then `mbox.close` (returns `std.DoublyLinkedList`), walk via `popFirst()` and free. Verify no leaks. `[shutdown ordering, cross-layer cleanup]`
37. **Close ordering: mailbox then pool** — `mbox.close` first (worker returns item via `pool.put` while pool open), then `pool.close` (includes returned item in on_close). Verify same total items. `[alternative shutdown order, same correctness]`
38. **Pool + Mailbox flow** — `pool.get`, fill, `mbox.send`, `mbox.receive`, `pool.put` back (single-threaded or two-thread). `[cross-layer ownership flow]`

### stdlib compatibility (Master-level examples)

39. **Master shutdown: close → stdlib walk → free** — Master closes mailbox and pool. Walks both returned `std.DoublyLinkedList` results with `popFirst()`. Entire cleanup is standard Zig — no Matryoshka-specific drain/flush API needed. `[Master shutdown, stdlib list, no framework cleanup]`
40. **Master batch drain: receive_batch → put_all** — Master calls `mbox.receive_batch`, passes the returned `std.DoublyLinkedList` directly to `pool.put_all`. The stdlib list flows between layers without conversion. `[Master coordination, stdlib list bridges layers]`
41. **Master pre-shutdown collect** — Master builds a `std.DoublyLinkedList` from multiple sources (close multiple mailboxes), then walks the combined list with `popFirst()` to free all items. Standard `concatByMoving` merges lists. `[Master multi-mailbox, stdlib list merge]`

### Mailbox as Select Event Source (Master + external Io)

42. **Mailbox receive as Select event source** — Master defines `MasterEvent` union with `.inbox: mbox.ReceiveResult` and `.timer: void`. Spawns via `select.concurrent(.inbox, mbox.receive_select, .{inbox, null})`. Timer spawned as `.timer`. `select.await()` returns whichever completes first. Re-spawn event source after each item. `[Io.Select, mbox.receive_select event source, tagged union dispatch, Proposal 26]`
43. **Select + mailbox + socket** — Master uses Select with three event sources: mailbox receive (`.inbox` via `mbox.receive_select`), socket receive (`.network`), timer (`.timer`). All three compete in one `select.await()` loop. Demonstrates Matryoshka items and external Io in one event loop. `[Io.Select, mbox + socket + timer, unified event loop]`
44. **Select mailbox close propagation** — Master spawns `mbox.receive_select` as Select event source. Another task calls `mbox.close` (broadcasts). Blocked receive returns `error.Closed` → adapter returns `.closed`. Master handles it in the `switch`. `[mbox.close → Select, .closed propagation]`
45. **Select cancel propagation** — Master spawns `mbox.receive_select` as Select event source. `select.cancel()` propagates to all event sources. Blocked receive gets `error.Canceled` injected at `Io.Condition.wait`. Adapter returns `.canceled`. Master handles it in the `switch`. `[Io.Select cancel, .canceled through mbox.receive_select]`

### Pool as Select Event Source

46. **Pool get_wait as Select event source** — Master defines event union with `.pool: pool.PoolResult` and `.timer: void`. Spawns via `select.concurrent(.pool, pool.get_wait_select, .{job_pool, JOB_TAG, null})`. When item becomes available, `.pool` fires with `.item`. Master re-spawns event source after handling. `[Proposal 26, pool.get_wait_select, pool availability as event]`
47. **Job pool pattern** — Worker finishes job, calls `pool.put`. Master has `pool.get_wait_select` as event source in Select. `pool.put` wakes the blocked `get_wait` → adapter returns `.item`. Master fills and submits new work, re-spawns event source. Pool availability drives the work pipeline. `[Proposal 26, job pool pattern, pool as event source]`
48. **Mixed mbox + pool event sources in Select** — Master uses Select with `.inbox` (`mbox.receive_select`), `.pool` (`pool.get_wait_select`), `.timer` (`Io.sleep`). Mailbox delivers commands, pool signals resource availability, timer triggers maintenance. One event loop handles all three. `[Proposal 26, mbox + pool + timer, unified event loop]`

### Event Source Futures

49. **receive_future awaited directly** — Master calls `mbox.receive_future(inbox, null)`, gets `Io.Future(ReceiveResult)`. Calls `fut.await(io)` — blocks until item arrives. No Select needed. Useful for simple single-source coordination. `[Proposal 26, receive_future, direct await]`
50. **get_wait_future awaited directly** — Master calls `pool.get_wait_future(pool, TAG, null)`, gets `Io.Future(PoolResult)`. Awaits directly. Simple pool acquisition as a future. `[Proposal 26, get_wait_future, direct await]`
51. **receive_future with timeout** — Master calls `mbox.receive_future(inbox, 5 * std.time.ns_per_s)`. Future resolves to `.timeout` if no item within 5 seconds, `.item` if received. `[Proposal 26, receive_future, timeout]`
52. **ConcurrencyUnavailable on single-threaded** — Master on `global_single_threaded` calls `mbox.receive_future`. Returns `error.ConcurrencyUnavailable`. Synchronous `mbox.receive` remains available. `[Proposal 26, single-threaded constraint]`

### Communication Patterns

53. **Pool fan-in: many workers return** — 3 workers each process items and call `pool.put`. One Master calls `pool.get` to acquire returned items. Verify all 3 items arrive. Ownership flows from many workers into one pool, then to one Master. `[pool fan-in, many put, one get]`
54. **Pool fan-out: many workers acquire** — Master seeds pool with N items. 3 workers each call `pool.get`. Each gets a different item. No item is shared. Verify N items distributed, pool count decreases correctly. `[pool fan-out, one pool, many get]`
55. **Producer → consumer with recycling** — Pool → Producer fills → Mailbox → Consumer processes → Pool. Full cycle. Verify same item survives the roundtrip. Ownership always clear at each step. `[combined pattern, pool + mailbox circular flow]`
56. **Job pool circular flow** — Master gets item from pool, fills it, sends to worker via mailbox. Worker processes, puts back to pool. Master uses `pool.get_wait_select` as event source. Verify items cycle continuously. Pool controls the pace. `[job pool, circular ownership, event source]`

### Mailbox-less Patterns

57. **Pool + Future: simple worker** — Master spawns worker via `io.concurrent`. Worker gets item from pool, processes, puts back. Result returned via `Future.await`. No mailbox involved. Verify item cycles through pool correctly. `[mailbox-less, Pool + Future, simple coordination]`
58. **Pool + Select: job scheduler** — Master uses `pool.get_wait_select` as event source + timer in Select. When pool item available, Master fills and submits work. When timer fires, Master does maintenance. No mailbox. `[mailbox-less, Pool + Select, job scheduling]`
59. **Pool + Group: worker pool** — Master spawns N workers via `Io.Group`. All workers get/put from shared pool. Master cancels all via `group.cancel`. Workers exit, remaining items collected via `pool.close`. No mailbox. `[mailbox-less, Pool + Group, worker lifecycle]`
60. **Pool + Select + Network** — Master uses Select with `pool.get_wait_select` + network socket read. Incoming data from network, processed items recycled via pool. No mailbox. Two event sources: pool availability + network data. `[mailbox-less, Pool + Select + external Io]`
61. **When to add Mailbox** — Same setup as scenario 60, but now multiple independent external clients send work items. Fan-in to mailbox becomes necessary. Add mailbox as third event source in Select. Show the transition: mailbox-less → mailbox needed when senders are independent and unknown. `[transition point, fan-in triggers mailbox addition]`

Reference: ICE agent pattern at `/home/g41797/Downloads/media-protocols-master/src/ice/agent.zig`
