# Task 2 — Example Scenarios for Layer 4 and Cross-Layer

Extracted from `task2-scenarios-001.md`. Scenario numbers preserved.

Examples show stories: real usage patterns, stress-test API in realistic composed ways.
Each example has a test wrapper.

All Layer 4 examples use real `Io.Threaded.init(gpa, .{})` — concurrency, cancellation, real I/O.

Master is a concept, not a type. Each example may structure its coordination boundary differently.

---

## Master Patterns

17. **Minimal Master** — Master struct with inbox (`mailbox.MailboxHandle`) + alloc. Spawns one worker via `io.concurrent()`. Sends items, `mailbox.close`, awaits worker, walks remaining list via `popFirst()`. The simplest complete Layer 4 example. Shutdown cleanup uses plain stdlib list — no Matryoshka-specific cleanup API. `[io.concurrent, Future.await, mailbox.close, stdlib list]`
18. **Master with Pool** — Master with inbox + pool + hooks. Worker uses `pool.get`, `mailbox.receive`, processes, `pool.put` back. Shutdown via `future.cancel`. `[io.concurrent, Future.cancel, pool lifecycle]`
19. **Multi-worker Master** — Master spawns N workers via `Io.Group`. All receive from shared mailbox. Shutdown via `group.cancel`. `[Io.Group, group.cancel, shared mailbox]`
20. **Pipeline of Masters** — 3 Masters chained: producer → transformer → consumer. Each has its own worker. Items flow through mailboxes. Producer closes downstream mailbox to signal completion. `[multi-Master, cross-mailbox ownership transfer]`
21. **Request-response between Masters** — Master A sends request to Master B's inbox. Master B processes, sends response to Master A's inbox. Bidirectional ownership transfer. `[two Masters, bidirectional mailbox]`

---

## Mailbox as Multiplexer

22. **Timer via mailbox** — Separate timer task sends TimerPolyNode to Master's inbox periodically. Worker dispatches on tag: data items vs timer ticks. No Select needed. `[io.concurrent for timer task, tag dispatch, fan-in mailbox]`
23. **OOB via send_oob** — Sender sends OOB signal PolyNode via `mailbox.send_oob`. Worker's next receive gets OOB item immediately (front of queue), handles it, resumes normal processing. `[mailbox.send_oob, OOB handling, tag dispatch]`
24. **Multiple event sources, one mailbox** — Timer task + data producer + signal source all send to one mailbox with different tags. Worker has single receive loop, dispatches on tag. `[fan-in mailbox, multiple concurrent senders]`

---

## Io Integration (timer + mailboxes)

25. **Two mailboxes + timer in Select** — Master defines event union with `.inbox1`, `.inbox2`, `.timer`. Both mailboxes use `mailbox.receive_select` as event sources, wait forever (`null` timeout). Timer fires first. Master handles timer event, re-spawns timer, continues. Items from either mailbox handled as they arrive. `[Io.Select, Io.sleep, two mailbox.receive_select event sources, basic integration]`
26. **Timer cancel → close → walk remaining** — Two mailboxes + timer in Select. Timer fires → Master calls `select.cancel()`. Both blocked `receive_select` event sources get `error.Canceled` → return `.canceled`. Master then calls `mailbox.close` on both → walks returned `std.DoublyLinkedList` lists. All items accounted for. Cancel and close are separate operations. `[cancel propagation, mailbox.close after cancel, no item loss, cancel/close separation]`
27. **Cancel reports, Master decides** — Two mailboxes in Select via `mailbox.receive_select`. `select.cancel()` fires. Both event sources return `.canceled` (mailboxes remain open). Master decides: close inbox1 immediately, re-spawn inbox2 for graceful drain. Cancel never triggers close — Master owns shutdown decisions. `[Proposal 26, cancel/close separation, Master controls shutdown]`
28. **Multiple event source types in one Select** — inbox uses `mailbox.receive_select`, job pool uses `pool.get_wait_select`, timer uses `Io.sleep`. Master handles each in one switch. All three are event sources with uniform result handling. `[Proposal 26, mixed mailbox + pool + timer event sources]`
29. **Cancel → Master close → pool.put_all** — Select cancel fires. Master receives `.canceled` from event sources. Master then closes mailbox, passes returned list to `pool.put_all` — items recycled, not freed. Close is Master's explicit decision after cancel. `[cancel then close, pool lifecycle, stdlib list bridges layers]`
30. **Timeout on mailbox** — Worker uses `mailbox.receive` with non-null `?u64` timeout. Timeout fires → `error.Timeout`. Worker does alternative work (e.g., `Io.sleep` then retry). `[mailbox.receive ?u64 timeout, Io.sleep retry]`
31. **Graceful shutdown with in-flight items** — Master has 2 event sources via Select. `select.cancel()` fires. Event sources at different stages: one blocked in `mailbox.receive_select`, one between operations. All return `.canceled`. Master closes mailboxes and collects remaining items. `[Io.Select cancel, mixed cancellation points, no item loss]`

---

## stdlib Compatibility (Master-level)

39. **Master shutdown: close → stdlib walk → free** — Master closes mailbox and pool. Walks both returned `std.DoublyLinkedList` results with `popFirst()`. Entire cleanup is standard Zig — no Matryoshka-specific drain/flush API needed. `[Master shutdown, stdlib list, no framework cleanup]`
40. **Master batch drain: receive_batch → put_all** — Master calls `mailbox.receive_batch`, passes the returned `std.DoublyLinkedList` directly to `pool.put_all`. The stdlib list flows between layers without conversion. `[Master coordination, stdlib list bridges layers]`
41. **Master pre-shutdown collect** — Master builds a `std.DoublyLinkedList` from multiple sources (close multiple mailboxes), then walks the combined list with `popFirst()` to free all items. Standard `concatByMoving` merges lists. `[Master multi-mailbox, stdlib list merge]`

---

## Mailbox as Select Event Source (Master + external Io)

42. **Mailbox receive as Select event source** — Master defines `MasterEvent` union with `.inbox: mailbox.ReceiveResult` and `.timer: void`. Spawns via `select.concurrent(.inbox, mailbox.receive_select, .{inbox, null})`. Timer spawned as `.timer`. `select.await()` returns whichever completes first. Re-spawn event source after each item. `[Io.Select, mailbox.receive_select event source, tagged union dispatch, Proposal 26]`
43. **Select + mailbox + socket** — Master uses Select with three event sources: mailbox receive (`.inbox` via `mailbox.receive_select`), socket receive (`.network`), timer (`.timer`). All three compete in one `select.await()` loop. Demonstrates Matryoshka items and external Io in one event loop. `[Io.Select, mailbox + socket + timer, unified event loop]`
44. **Select mailbox close propagation** — Master spawns `mailbox.receive_select` as Select event source. Another task calls `mailbox.close` (broadcasts). Blocked receive returns `error.Closed` → adapter returns `.closed`. Master handles it in the `switch`. `[mailbox.close → Select, .closed propagation]`
45. **Select cancel propagation** — Master spawns `mailbox.receive_select` as Select event source. `select.cancel()` propagates to all event sources. Blocked receive gets `error.Canceled` injected at `Io.Condition.wait`. Adapter returns `.canceled`. Master handles it in the `switch`. `[Io.Select cancel, .canceled through mailbox.receive_select]`

---

## Pool as Select Event Source

46. **Pool get_wait as Select event source** — Master defines event union with `.pool: pool.PoolResult` and `.timer: void`. Spawns via `select.concurrent(.pool, pool.get_wait_select, .{job_pool, JOB_TAG, null})`. When item becomes available, `.pool` fires with `.item`. Master re-spawns event source after handling. `[Proposal 26, pool.get_wait_select, pool availability as event]`
47. **Job pool pattern** — Worker finishes job, calls `pool.put`. Master has `pool.get_wait_select` as event source in Select. `pool.put` wakes the blocked `get_wait` → adapter returns `.item`. Master fills and submits new work, re-spawns event source. Pool availability drives the work pipeline. `[Proposal 26, job pool pattern, pool as event source]`
48. **Mixed mailbox + pool event sources in Select** — Master uses Select with `.inbox` (`mailbox.receive_select`), `.pool` (`pool.get_wait_select`), `.timer` (`Io.sleep`). Mailbox delivers commands, pool signals resource availability, timer triggers maintenance. One event loop handles all three. `[Proposal 26, mailbox + pool + timer, unified event loop]`

---

## Event Source Futures

49. **receive_future awaited directly** — Master calls `mailbox.receive_future(inbox, null)`, gets `Io.Future(ReceiveResult)`. Calls `fut.await(io)` — blocks until item arrives. No Select needed. Useful for simple single-source coordination. `[Proposal 26, receive_future, direct await]`
50. **get_wait_future awaited directly** — Master calls `pool.get_wait_future(pool, TAG, null)`, gets `Io.Future(PoolResult)`. Awaits directly. Simple pool acquisition as a future. `[Proposal 26, get_wait_future, direct await]`
51. **receive_future with timeout** — Master calls `mailbox.receive_future(inbox, 5 * std.time.ns_per_s)`. Future resolves to `.timeout` if no item within 5 seconds, `.item` if received. `[Proposal 26, receive_future, timeout]`
52. **ConcurrencyUnavailable on single-threaded** — Master on `global_single_threaded` calls `mailbox.receive_future`. Returns `error.ConcurrencyUnavailable`. Synchronous `mailbox.receive` remains available. `[Proposal 26, single-threaded constraint]`

---

## Communication Patterns

53. **Pool fan-in: many workers return** — 3 workers each process items and call `pool.put`. One Master calls `pool.get` to acquire returned items. Verify all 3 items arrive. Ownership flows from many workers into one pool, then to one Master. `[pool fan-in, many put, one get]`
54. **Pool fan-out: many workers acquire** — Master seeds pool with N items. 3 workers each call `pool.get`. Each gets a different item. No item is shared. Verify N items distributed, pool count decreases correctly. `[pool fan-out, one pool, many get]`
55. **Producer → consumer with recycling** — Pool → Producer fills → Mailbox → Consumer processes → Pool. Full cycle. Verify same item survives the roundtrip. Ownership always clear at each step. `[combined pattern, pool + mailbox circular flow]`
56. **Job pool circular flow** — Master gets item from pool, fills it, sends to worker via mailbox. Worker processes, puts back to pool. Master uses `pool.get_wait_select` as event source. Verify items cycle continuously. Pool controls the pace. `[job pool, circular ownership, event source]`

---

## Mailbox-less Patterns

57. **Pool + Future: simple worker** — Master spawns worker via `io.concurrent`. Worker gets item from pool, processes, puts back. Result returned via `Future.await`. No mailbox involved. Verify item cycles through pool correctly. `[mailbox-less, Pool + Future, simple coordination]`
58. **Pool + Select: job scheduler** — Master uses `pool.get_wait_select` as event source + timer in Select. When pool item available, Master fills and submits work. When timer fires, Master does maintenance. No mailbox. `[mailbox-less, Pool + Select, job scheduling]`
59. **Pool + Group: worker pool** — Master spawns N workers via `Io.Group`. All workers get/put from shared pool. Master cancels all via `group.cancel`. Workers exit, remaining items collected via `pool.close`. No mailbox. `[mailbox-less, Pool + Group, worker lifecycle]`
60. **Pool + Select + Network** — Master uses Select with `pool.get_wait_select` + network socket read. Incoming data from network, processed items recycled via pool. No mailbox. Two event sources: pool availability + network data. `[mailbox-less, Pool + Select + external Io]`
61. **When to add Mailbox** — Same setup as scenario 60, but now multiple independent external clients send work items. Fan-in to mailbox becomes necessary. Add mailbox as third event source in Select. Show the transition: mailbox-less → mailbox needed when senders are independent and unknown. `[transition point, fan-in triggers mailbox addition]`

---

## Reference

- ICE agent pattern: `/home/g41797/Downloads/media-protocols-master/src/ice/agent.zig`
- Io as an Interface: https://ziglang.org/download/0.16.0/release-notes.html#IO-as-an-Interface
- std.Io overview: https://ziggit.dev/t/std-io-overview/
- Discussion about Io and Zig: https://ziggit.dev/t/discussion-about-io-and-zig/
