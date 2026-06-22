# Collected Context for Matryoshka Zig Implementation

## Key Paths

### Zig 0.16 Standard Library
- `Io.zig`: `/home/g41797/dev/langs/zig-x86_64-linux-0.16.0/lib/std/Io.zig`
- `Io/` directory: `/home/g41797/dev/langs/zig-x86_64-linux-0.16.0/lib/std/Io/`
- `DoublyLinkedList.zig`: `/home/g41797/dev/langs/zig-x86_64-linux-0.16.0/lib/std/DoublyLinkedList.zig`

### Odin Matryoshka (reference implementation)
- Root: `/home/g41797/dev/root/github.com/g41797/matryoshka`
- Core files: `polynode.odin`, `mailbox.odin`, `pool.odin`, `poolhooks.odin`, `dispose.odin`
- Examples: `examples/block1/` through `examples/block4/`
- Tests: `tests/block1/` through `tests/block4/`
- Functional tests use examples as working code

### Legacy Mailbox Repo (development target for Matryoshka Zig)
- Root: `/home/g41797/dev/root/github.com/g41797/mailbox`
- GitHub: 118 stars, used by the author in production projects
- Source: `src/mailbox.zig` (all 3 variants in one file), `src/mailbox_tests.zig`, `build.zig`
- Standard Zig 0.16 module structure: `b.addModule("mailbox", ...)`, tests via `zig build test`

**Three mailbox variants** (all share Io.Mutex + Io.Condition, closed atomic, interrupted bool, condition_waitTimeout):
1. `MailBox(Letter)` — generic, non-intrusive. Envelope wraps user Letter type with prev/next
2. `MailBoxIntrusive(Envelope)` — user type IS the envelope (must have prev/next). Same API
3. `TypeErasedMailbox` — intrusive, type-erased via `std.DoublyLinkedList.Node`. Direct predecessor to `_Mbox`

**API** (same for all three): `init(io)`, `send`, `receive(timeout_ns)`, `interrupt`, `close`, `letters`

**What TypeErasedMailbox has that _Mbox needs**:
- `Io.Mutex` + `Io.Condition` ✓
- `closed: std.atomic.Value(bool)` with pre-lock fast path ✓
- `interrupted: bool` under mutex ✓
- `io: ?Io` stored at init ✓
- `condition_waitTimeout` workaround for Zig issue #31278 ✓
- Idempotent close returning remaining list head ✓

**What TypeErasedMailbox lacks (Matryoshka additions)**:
- PolyNode (tag-based runtime type identity)
- MayItem ownership semantics (null-after-send)
- `send_oob` with oob_count/oob_last (FIFO OOB ordering)
- `receive_batch` (non-blocking batch snapshot)
- `?u64` timeout (currently `u64`, no "wait forever")
- `std.DoublyLinkedList` return from close (currently `?*Node`)
- `lockUncancelable` for close (currently `mutex.lock catch return error.Closed`)
- `error.Canceled` propagation (currently remaps to `error.Closed`)

**Decision**: Use this repo as the development target for Matryoshka Zig implementation. TypeErasedMailbox evolves into `_Mbox`, PolyNode/Pool/dispose added alongside. Legacy variants (MailBox, MailBoxIntrusive) remain for backward compatibility.

### Tofu Project (scaffolding reference — not a template to copy)
- Root: `/home/g41797/dev/root/github.com/g41797/tofu`
- Purpose: reference for project organization patterns; actual Matryoshka scaffolding to be designed separately
- Structure: `src/` (library + subdirs), `tests/` (mirrors src), `recipes/` (usage examples), `docs_site/` (MkDocs Material), `docs/` (generated output for GitHub Pages), `design/`
- Build: `build.zig` with separate modules (library, test, recipes, cookbook); `zig build docs` generates autodocs via `getEmittedDocs()`; recipes get their own docs
- Docs pipeline: `docs_zig.sh` (autodoc) → `docs_site.sh` (autodoc + MkDocs build); MkDocs Material with search, mermaid, code highlight
- CI: `.github/workflows/` — per-platform test (linux, mac, windows) + docs deployment on push to main
- Already uses `mailbox` as a dependency (`b.dependency("mailbox", ...)`)

### Odin Matryoshka Scaffolding (borrowable ideas)
- Root: `/home/g41797/dev/root/github.com/g41797/matryoshka`
- Key idea: `kitchen/` folder holds ALL housekeeping — source code at top level stays clean
- `kitchen/docs/` — markdown docs (block deepdives, quickrefs, API reference, design hub, addendums)
- `kitchen/docs/apidocs/` — generated API docs (Odin doc tool output)
- `kitchen/docs/assets/` — doc images
- `kitchen/_logo/` — logos and generation scripts
- `kitchen/tools/` — build_site.sh, generate_apidocs.sh, preview scripts, doc tools
- `kitchen/mkdocs.yml` — MkDocs Material config
- `kitchen/build_and_test*.sh` — build/test scripts
- CI: `.github/workflows/ci.yml` (tests), `docs.yml` (site deployment)
- Source layout at top level is Odin-specific; Zig source layout to be decided separately

### Architecture Documents
- `/home/g41797/dev/root/github.com/g41797/tofusite/root/mailbox/matryoshka-architecture-foundation-4.md`
- `/home/g41797/dev/root/github.com/g41797/tofusite/root/mailbox/matryoshka-zig-0.16-implementation-guide.md`

### Zig 0.16 Io Source (read for Master/cancellation design)
- `Io.zig` (3461 lines): Future, Group, Select, Queue, CancelProtection, Mutex, Condition, recancel, checkCancel
- `Io/Threaded.zig` (18902 lines): how concurrent/async spawn OS threads, cancel via signals, thread pool management
- Key line ranges: Future (1176-1206), Group (1218-1303), Select (1367-1537), CancelProtection (1322-1358), Mutex (1587-1651), Condition (1653-1763), io.concurrent (2365-2389), Threaded.concurrent (2130-2174)

### Reference Projects
- ICE agent (Io.Select + concurrent pattern): `/home/g41797/Downloads/media-protocols-master/src/ice/agent.zig`

### External Resources
- Release notes (Io section): https://ziglang.org/download/0.16.0/release-notes.html#IO-as-an-Interface
- Discussion about Io and Zig: https://ziggit.dev/t/discussion-about-io-and-zig/
- std.Io overview: https://ziggit.dev/t/std-io-overview/
- File I/O basics (0.16): https://ziggit.dev/t/file-i-o-basics-0-16/14968

### Working Folder
- All planning/tracking docs: `/home/g41797/dev/root/github.com/g41797/tofusite/root/mailbox/`
- `task1-scenarios.md` — Layer 1-3 test/example scenarios (86 items, revised against API reference)
- `task2-scenarios.md` — Layer 4 scenarios + Io findings + design decisions (61 items, includes cross-layer + stdlib + Select event sources + Proposal 26 + communication patterns + mailbox-less patterns)
- `matryoshka-api-reference.md` — clean API reference, source of truth for implementation (Proposal 8, created 2026-06-20)
- `proposal-26-async-integration.md` — Mailbox and Pool as event sources for Io.Select (Proposal 26, created 2026-06-22)
- `matryoshka-zig-implementation-plan.md` — staged implementation plan: 10 stages, 147 scenarios mapped, STATUS.md template, repo folder structure (created 2026-06-22, updated with tofu project rules: 4-mode verification, coding style, code change approval, session history template)

## Task Docs Revision (2026-06-20)

Both task scenario docs revised against `matryoshka-api-reference.md`:

### Changes applied to task1-scenarios.md (80 → 86 items)
- All function names → module-function style (`mbox.send`, `pool.get`, `polynode.reset`)
- `mailbox_is_it_you` → `mbox.is_it_you`, `pool_is_it_you` → `pool.is_it_you`
- `matryoshka_dispose` → per-module `mbox.destroy`/`pool.destroy`
- Return types: `std.DoublyLinkedList` not `?*Node`, empty list not `null`
- Batch walk: `popFirst()` auto-clears prev/next — no manual `polynode.reset`
- Timeout: `?u64` with null (wait forever) and non-null scenarios added
- Added scenarios: `mbox.new`/`mbox.destroy` (26), `mbox.receive` null timeout (32), `mbox.try_receive` empty/success (45-46), `pool.new`/`pool.init`/`pool.destroy` (57), `pool.get_wait` timeout/forever (77-78)
- Cross-layer notes updated with API convention references (Proposals 2, 3, 4, 6)

### Changes applied to task2-scenarios.md (37 → 38 items)
- All scenario descriptions → module-function style
- Return types → `std.DoublyLinkedList`, walked via `popFirst()`
- All `mbox_close`/`pool_close`/`pool_put` → `mbox.close`/`pool.close`/`pool.put`
- Scenario 38 added: "Pool + Mailbox flow" moved from task1 Layer 3 (cross-layer, not pure pool)

### Total: 147 scenarios (86 + 61), all consistent with API reference

### Changes applied for Proposal 26 (2026-06-22)
- "leg" → "event source" throughout
- Scenarios 25-28, 42-48 updated for Proposal 26 (library adapters, cancel/close separation)
- Scenarios 46-48 replaced: old wrapper cancel policies → pool as event source + mixed event sources
- Scenarios 49-52 added: receive_future/get_wait_future direct await, timeout, single-threaded constraint
- Scenarios 53-56 added: communication patterns — pool fan-in, pool fan-out, producer→consumer with recycling, job pool circular flow

## Key Decisions

### Layer Boundaries
- Layers 1-3 (PolyNode, Mailbox, Pool): pure building blocks, no Master, no cancellation
- Layer 4 (Master): coordination concept, where `std.Io` concurrency primitives live
- The term "Master" must not appear in layers 1-3 examples/tests
- Cancellation (`error.Canceled`, `Future.cancel`, `Io.Group`) belongs exclusively to layer 4

### Cancellation is New
- Odin has no cancellation — `sync.mutex_lock`/`sync.cond_wait` never return errors
- Zig 0.16 `Io.Mutex.lock()` and `Io.Condition.wait()` return `Cancelable!void`
- This is driven by `std.Io` features, not by Matryoshka architecture changes

### Threading in Examples
- Layer 2-3 examples may use threads to demonstrate ownership movement
- But should use `Io.Threaded.global_single_threaded` (no cancellation support)
- Layer 4 examples use real `io.concurrent()` / `Future` / `Io.Group` with cancellation

### Terminology
- **Layer** = architectural concept (what problem is solved): Ownership, Movement, Lifecycle, Coordination
- **Block** = implementation component (what solves it): PolyNode, Mailbox, Pool
- **Master** = Layer 4 coordination role — applications compose blocks into Masters
- Infrastructure-as-items is a property of handles (Proposal 13), not a separate block
- "Doll" not used as a technical term — matryoshka is the module name only

### Mailbox Is Optional (2026-06-22)
- In Zig 0.16, `io.concurrent` + `Future` + `Io.Select` + `Io.Group` already coordinate tasks
- Mailbox is no longer mandatory — Pool + Io can be the primary coordination model
- Pool provides what Io does not: reuse, capacity control, lifecycle policy
- Mailbox is the right choice for: fan-in from independent senders, pipelines, heterogeneous ownership streams
- Mailbox is not needed when: Future delivers results directly, Select waits on external sources, no queued ownership transfer
- Valid combinations: PolyNode only, PolyNode+Mailbox, PolyNode+Pool, PolyNode+Pool+Select, full stack
- Scenarios 57-61 added for mailbox-less patterns

### Cancel Never Triggers Close (Proposal 26)
- Cancel (`error.Canceled`) is an Io/scheduler operation
- Close (`mbox.close` / `pool.close`) is a Master/application decision
- Adapters return `.canceled` with void payload — mailbox/pool remains open
- Master decides whether to close after receiving cancel
- Applies equally to Mailbox and Pool (extends Rule 6 principle to Mailbox)

### Two Tasks
- **Task 1**: Layers 1-3 test/example scenario lists (intents, not code)
- **Task 2**: Layer 4 scenarios + additional cross-layer tests for 1-3; requires understanding Master's role in Io world
- Tasks are sequential; knowledge from Task 1 feeds Task 2

## Mailbox Design Decisions (Zig divergences from Odin)

### Interrupt replaced by send_oob
- Odin: `mbox_interrupt` sets `interrupted: bool`, receiver checks in wait loop, `error.Interrupted`
- Zig: `mbox_send_oob` prepends a PolyNode to front of queue
- Rationale: with PolyNode-based mailbox, any signal IS a PolyNode with a tag. OOB items carry actual data. True front-of-queue priority (interrupt was only checked when queue empty). No `interrupted` field, no `error.Interrupted`, no `error.AlreadyInterrupted`
- Impact: 3-channel contract (DATA/INTERRUPT/CANCEL) → 2-channel contract (DATA/CANCEL). INTERRUPT merged into DATA via send_oob

### Close/put operations use lockUncancelable
- Odin: `sync.mutex_lock` never returns errors — no issue
- Zig implementation guide originally proposed: `io.swapCancelProtection(.blocked)` + `mutex.lock(io) catch unreachable`
- Revised: `mutex.lockUncancelable(io)` — built-in, simpler, more explicit
- Applies to: `mbox_close`, `pool_close`, `pool_put`, `pool_put_all`

### mbox_send is cancelable (work path)
- `mutex.lock(io)` is a cancellation point — if sender's task is canceled, `error.Canceled` propagates
- Caller still owns item (MayItem not cleared) — item not lost
- Contrast: `pool_put` is cancel-protected (cleanup path — item would be lost)

### _Mbox and _Pool store `io: Io` (managed pattern)
- Zig 0.16 moved containers to "unmanaged" (allocator per-call). Does NOT apply to infrastructure objects
- Containers (ArrayList, HashMap): generic, many instances, only some ops need allocator → unmanaged
- Infrastructure (Mailbox, Pool, http.Client): long-lived, every op needs io → store io at construction
- `std.http.Client` in stdlib stores both `allocator` and `io` — same pattern

### When to use fan-in mailbox
- When items carry ownership, many senders fan into one mailbox — all sources send tagged PolyNodes to one receiver
- One queue, one ownership model, one dispatch model, one shutdown model
- On the current Threaded backend, Select may require additional worker tasks and often additional threads per event source — future backends (Evented, Uring) may behave differently
- Outside Matryoshka, `Io.Select` remains useful for integrating external Io sources — the two approaches are complementary
- `error.Canceled` propagation from `mbox_receive` (not remapped to `error.Closed`) is required for Select composability

### Mailbox and Pool as Select event sources (Proposal 26)

**When to use**: When a Master needs to coordinate mailbox items or pool availability with external Io operations (sockets, files, timers) that are not PolyNode-based. When items carry ownership, many senders fan into one mailbox — keeping ownership, shutdown, dispatch, and backpressure under one model. When items do not carry ownership, other approaches may be simpler.

**How it works**: Matryoshka provides library adapters (`mbox.receive_select`, `pool.get_wait_select`) that convert blocking APIs to `ReceiveResult`/`PoolResult` tagged unions. These are passed directly to `select.concurrent` as event sources. The blocking `Io.Condition.wait` inside the adapter is a real Io wait — Select spawns a dedicated worker that blocks until the operation completes.

```zig
const MasterEvent = union(enum) {
    inbox: mbox.ReceiveResult,
    pool: pool.PoolResult,
    timer: void,
};

try select.concurrent(.inbox, mbox.receive_select, .{ inbox, null });
try select.concurrent(.pool, pool.get_wait_select, .{ job_pool, JOB_TAG, null });

while (select.await()) |event| switch (event) {
    .inbox => |r| switch (r) {
        .item => |m| {
            processMessage(m);
            try select.concurrent(.inbox, mbox.receive_select, .{ inbox, null });
        },
        .closed => break,
        .canceled => break,
        .timeout => {},
    },
    .pool => |r| switch (r) {
        .item => |job| {
            submit(job);
            try select.concurrent(.pool, pool.get_wait_select, .{ job_pool, JOB_TAG, null });
        },
        .closed => break,
        else => {},
    },
    .timer => { ... },
}
```

**Cancel never triggers close**: On `error.Canceled`, adapters return `.canceled` — mailbox/pool remains open. Closing is the Master's explicit decision. This is consistent with Rule 6 and the 2-channel contract.

**Result by value**: Adapters return items inside the result union, not through `*MayItem` pointers. No cross-thread pointer hazards.

**Future helpers**: `mbox.receive_future` / `pool.get_wait_future` spawn the adapter concurrently using the stored `io` and return `Io.Future(ReceiveResult)` / `Io.Future(PoolResult)`. Can be awaited directly without Select.

**Pool as event source**: Pool availability becomes an event. The job-pool pattern: worker calls `pool.put` → `get_wait_select` event source fires → Master gets item → Master submits new work.

**Reference implementation**: ICE agent at `/home/g41797/Downloads/media-protocols-master/src/ice/agent.zig` uses the same Select pattern with `receiveTimeout` + `select.concurrent`.

**Internals to understand deeper** (for implementation phase):
- `Io.Queue` mechanics (ring buffer, blocking, capacity)
- Thread cost per `select.concurrent` event source (thread pool vs one-shot)
- Multiple event sources completing simultaneously
- Cancel propagation: Select → Group → individual workers

## Proposal 26 Design Findings (2026-06-22)

### Io.Select mechanics (from stdlib source)
- `Io.Select(U)` where U is a tagged union — each field is one event source type
- `select.concurrent(.field_name, function, args)` spawns a concurrent task as an event source
- `select.await()` blocks until any event source completes, returns tagged union result
- Function return type must match the corresponding union field type
- `select.cancel()` / `select.cancelDiscard()` cancels remaining event sources
- Internally uses `Io.Group` + `Io.Queue` — each event source is a Group member, results go to Queue

### Why Variant 1 (`mbox.concurrent`) was rejected
- Hard-wires one adapter per call — no flexibility for different cancel handling
- Uses `anytype` for Select and tag parameters — couples Layer 2/3 to Layer 4's union shape
- Reuses name `concurrent` with different semantics from `io.concurrent` — confusing
- Makes mbox/pool module reach *up* into Master's Select union — inverts layer dependency

### Why Variant 2 (`receive_future`) was chosen
- Returns `Io.Future(ReceiveResult)` — caller decides how to use it (await, Select, Group)
- No `anytype` — fully concrete signatures
- Layer 2/3 remain self-contained — caller feeds result to Select using stock Io API
- Adapters (`receive_select`, `get_wait_select`) can be passed directly to `select.concurrent`

### Cross-thread ownership safety
- Synchronous `mbox.receive` takes `m: *MayItem` — pointer to caller's stack variable
- In async case, concurrent task writes through this pointer from a different thread
- Solution: result carries item by value inside tagged union — no `*MayItem` crosses thread boundary
- Adapter creates local `MayItem`, calls blocking API, packages result into union
- When `select.await()` returns `.item`, Master is sole owner with no aliasing

### Cancel/Close separation principle
- Cancel (`error.Canceled`) is Io scheduler operation — external to application
- Close (`mbox.close`/`pool.close`) is Master/application decision — explicit action
- Adapters never close on cancel — they return `.canceled` and let Master decide
- This eliminates `receiveOrClose` wrapper from the original external proposal
- One adapter per operation, not a policy choice
- Extends Rule 6 ("Pool must NOT interpret CANCEL") equally to Mailbox

### Pool as event source — novel contribution
- Pool availability becomes a reactive event, not just a blocking call
- Job-pool pattern: worker `pool.put` → `get_wait_select` fires → Master gets item → submits new work
- `.item` arm hands ownership — `get_wait` already removed item from pool
- Must re-spawn event source only after deciding item's fate
- `PoolResult` omits `not_available` (doesn't arise on wait path) and `already_in_use` (panic per Proposal 14)

### Documentation notes (developer's responsibility)
- **Thread cost**: each Select event source may consume a worker thread on Threaded backend. Note in code, API reference, README.
- **ConcurrencyUnavailable**: `receive_future`/`get_wait_future` fail on `global_single_threaded`. Note in code and docs.
- **Evented backend**: design is backend-independent but only Threaded tested in 0.16. Note in README and docs.

### Proposal 25 relationship
- Proposal 25's insight about per-event-source flexibility is preserved
- Cancel/close mixing (receiveOrClose) is eliminated — cancel never closes
- Caller can still write custom adapters with any behavior and pass them to `select.concurrent`
- Library provides the two standard adapters; custom adapters are the extension point

### Implementation guide restructured (2026-06-22)
- Reorganized from 22 sections (3068 lines) to 12 sections (2186 lines) — 29% reduction
- New reading order: What → Zig 0.16 constraints → Blocks 1-4 → Cancellation → Master → Rules → Opportunities → Appendix
- Hard constraints (removed Thread primitives, Io as concurrency interface) moved from buried addendums to Section 2 (up front)
- Cancellation consolidated from 4 scattered sections into ONE section (Section 7)
- Shutdown/teardown deduplicated — one copy of each path
- Removed: Verdict (feasibility confirmed → one line), Architectural Mental Model addendum (duplicates foundation-4), Finalized Design Changes (all in blocks)
- matryoshka_dispose dropped from Block 4 — API reference says "no generic dispose"
- Style converted to human-oriented: short sentences, bullets, ASCII diagrams
- Odin→Zig idiom mapping preserved as Appendix A (340 lines, reference material)
- Backup at matryoshka-zig-0.16-implementation-guide.md.bak

### Communication patterns added (2026-06-22)
- "multiplexer" replaced with established pattern names: fan-in, fan-out, pipeline, job pool
- Mailbox patterns added to foundation doc Section 6: fan-in, fan-out, pipeline
- Pool patterns added to foundation doc Section 7: fan-in (many return), fan-out (many acquire), job pool (circular)
- Combined patterns added to foundation doc Section 8: producer→consumer with recycling, fan-in with lifecycle, job pool with event sources
- Scenarios 53-56 added to task2 for pool-specific patterns
- "multiplexer" removed from all docs (was jargon; patterns are clearer)

### Architecture foundation doc updated (2026-06-22)
- Section 9 (Concurrency Contract): added "When INTERRUPT Becomes Unnecessary" — explains how tagged items reduce 3-channel to 2-channel model. Both models documented.
- Section 8 (Layer 4): added event source subsections — Mailbox and Pool as event sources, pool availability as reactive signal, two coordination models (fan-in mailbox vs event sources), cancel/close separation.
- Summary updated to show both 3-channel and 2-channel models.
- Open Item 7 resolved.

## Io Primitives Summary (for Layer 4 / Master)

### Task spawning
- `io.async(fn, args)` → `Future(Result)` — may run synchronously; portable
- `io.concurrent(fn, args)` → `ConcurrentError!Future(Result)` — guarantees concurrency; fails if unavailable
- `Future.cancel(io)` — injects `error.Canceled` at next cancellation point + awaits completion
- `Future.await(io)` — waits for completion without cancellation

### Groups and Select
- `Io.Group` — unordered task set; `group.cancel(io)` cancels all + awaits; workers must return `Cancelable!void`
- `Io.Select(U)` — Group + Queue; spawn typed tasks, await whichever finishes first as tagged union
- `Io.Queue(T)` — bounded MPMC FIFO; used internally by Select

### Cancellation
- `error.Canceled` from next cancellation point only — does NOT re-signal
- `io.recancel()` — re-arms for next point (cleanup-then-propagate)
- `io.checkCancel()` — pure cancellation point for CPU-bound work
- `io.swapCancelProtection(.blocked)` — block all cancellation points in a region
- `Mutex.lockUncancelable(io)` / `Condition.waitUncancelable(io, mutex)` — per-operation uncancelable variants

### How to get Io
- `main(init: std.process.Init)` → `init.io` (juicy main)
- `Io.Threaded.init(gpa, .{})` — multi-threaded, concurrency + cancellation
- `Io.Threaded.global_single_threaded` — no concurrency, no cancellation, for tests
- `std.testing.io` — for unit tests

### Threaded backend
- Spawns OS threads via `std.Thread.spawn` on demand, detaches them
- Thread pool with `busy_count` against `async_limit` / `concurrent_limit`
- `global_single_threaded`: both limits = `.nothing` → concurrent returns error, async runs inline
- Cancellation via OS signals (EINTR on POSIX)

## Task 2 Review Findings (external AI review of task2-scenarios.md)

### Confirmed correct
- Io as the concurrency abstraction (Io == scheduling + synchronization + cancellation + I/O)
- Cancellation and Close are different (`error.Canceled` vs `error.Closed`)
- Fan-in mailbox — strongest Matryoshka-specific insight
- Storing Io in _Mbox and _Pool (infrastructure, not container)

### Corrected
- Select/thread claim reworded: "may require additional worker tasks and often additional threads" — not "one OS thread per event source" (backend-dependent)
- Fan-in mailbox presented as design preference for ownership-carrying items, not "Select is wrong" — the two are complementary
- Timeout scenario (31) resolved — `?u64` parameter accepted, scenario undeferred

### Added: Master is a Concept, not a Type
- Master is a coordination boundary — a role, not a required struct/type/PolyNode
- The architecture requires something that owns: mailbox, lifecycle policy, cancellation policy, worker coordination
- A developer may implement this as `Master`, `Server`, `Runtime`, `WorkerGroup`, or even `main()`
- Mailbox and Pool are infrastructure. Master is architecture
- Layer 4 examples demonstrate Master patterns, not a Master type
- Added to implementation guide as opening subsection of "Master as the Correct Abstraction"

## Scenario Review Findings (external AI review of task1-scenarios.md)

### Added: Ownership-state transition tests
- Layer 1: FREE → IN_FLIGHT → HELD → IN_FLIGHT → FREE (explicit state machine)
- Layer 2: IN_FLIGHT → HELD (send), HELD → IN_FLIGHT (receive)
- Layer 3: HELD → IN_FLIGHT (get), IN_FLIGHT → HELD/FREE (put keep/destroy)
- These are executable documentation of the ownership model — validate architecture, not implementation

### Added: Ownership violation detection tests
- Send linked item (polynode_is_linked == true) → panic
- Double list insertion → panic
- Double pool_put → panic
- These catch the biggest class of Matryoshka bugs: double-transfer, use-after-transfer

### Added: Infrastructure-as-item tests (Layer 1)
- Mailbox handle is a PolyNode — `mailbox_is_it_you(mb.tag)` returns true
- Pool handle is a PolyNode — `pool_is_it_you(pool.tag)` returns true
- `matryoshka_dispose` dispatches correctly on tag — Mailbox, Pool, unknown (panics)
- Tests the unique Matryoshka idea at Layer 1 without needing Layer 4

### Strengthened exclusion statement
- "Master, Cancel, Futures, Io.Group, and subsystem coordination are intentionally excluded. Layers 1–3 must be fully testable without them."

### Close ordering tests
- Already covered in task2-scenarios.md cross-layer section (items 36-37)
- Not duplicated in task1 — they require concurrency (worker thread returning items during close)

### Architecture doc (foundation-4.md)
- Updated 2026-06-22: 2-channel model added to Section 9 (tagged items make INTERRUPT unnecessary), event sources added to Section 8 (Layer 4), cancel/close separation added
- Zig-specific details (send_oob, lockUncancelable, specific API) remain in the implementation guide
- Architecture doc now documents both 3-channel and 2-channel models — 3-channel remains valid for non-tagged transports

## Odin Examples Summary

### Block 1 (PolyNode)
- `types.odin` — Event/Sensor structs with PolyNode, tags, is_it_you checks
- `builder.odin` — ctor/dtor factory using tag dispatch
- `ownership.odin` — push to list, pop, verify, free
- `poly_maybe_example.odin` — MayItem wrap/unwrap through intrusive list
- `produce_consume.odin` — mixed Event+Sensor list, tag-dispatch consume
- `example_builder.odin` — builder roundtrip

### Block 2 (Mailbox)
- `master.odin` — Master struct (inbox + builder + alloc), newMaster/freeMaster
- `readme_worker.odin` — basic worker loop with mbox_wait_receive, close+join
- `shutdown_exit.odin` — exit via sentinel message (EXIT_TAG)
- `pipeline.odin` — producer → transformer → consumer chain, 3 Masters
- `request_response.odin` — two Masters exchanging items bidirectionally
- `fan_in_out.odin` — shared mailbox, multiple workers, atomic counter
- `interrupt_oob.odin` — OOB signaling via interrupt + secondary mailbox
- `batch_processing.odin` — try_receive_batch usage

### Block 3 (Pool)
- `recycler.odin` — on_get/on_put hooks, roundtrip reuse verification
- `backpressure.odin` — capped on_put that drops excess items
- `seeding.odin` — pre-allocate pool with New_Only, verify with Available_Only
- `master_with_pool.odin` — full Master with Mailbox+Pool+worker thread

### Block 4 (Infrastructure as Items)
- `infra_as_item_example.odin` — mailbox transported through another mailbox
- `pool_as_item_example.odin` — pool transported as item

---

## Proposals — all resolved and applied

All decisions applied to API reference, implementation guide, task1, and task2.

| # | Decision | Key detail |
|---|----------|-----------|
| 1 | send_oob replaces interrupt | FIFO among OOBs via oob_count + oob_last |
| 2 | std.DoublyLinkedList for batches | close, receive_batch, on_close, put_all all use linked list |
| 3 | Timeout as `?u64` | null = wait forever, value = nanoseconds |
| 4 | Module-function API style | `mbox.send(mbh, &item)` not `mbox_send(mbh, &item)` |
| 5 | Module naming | polynode.zig, mbox.zig, pool.zig, matryoshka.zig root |
| 6 | Handle param type | `mbh: MailboxHandle` (already a pointer, no extra `*`) |
| 7 | Drop dispose.zig | Per-module destroy only, no generic dispatch |
| 8 | API reference document | matryoshka-api-reference.md is source of truth |
| 9 | pool.put returns void | Caller checks `m.*` after call; hook decides fate |
| 10 | Handle type not opaque | Resolved by Proposal 13 |
| 11 | NodeMixin to test helpers | Core polynode exports: PolyNode, PolyTag, MayItem, reset, is_linked |
| 12 | MailboxHandle / PoolHandle | Renamed from Mailbox/Pool; params mbh/ph |
| 13 | Handles are PolyNode items | Not opaque — transportable as items |
| 14 | INVALID ownership state | Double insertion, use-after-free, corrupted tag = panic |
| 15 | Cast doesn't transfer ownership | Tag checks and @fieldParentPtr are read-only |
| 16 | destroy-on-open = panic | Calling destroy on open handle is programming error |
| 17 | Diamond layer dependencies | Mailbox and Pool are independent siblings |
| 18 | dispose removed from API | Confirms Proposal 7 |
| 19 | Review round 2 summary | Proposals 13-18 from external AI review |
| 20 | Hook reentry = contract violation | Not deadlock; optional debug_hook_depth assertion |
| 21 | Terminology: Layer vs Block | Layer = problem, Block = component, Master = role; no "Doll" |
| 22 | API reference round 3 polish | Intro paragraph, move semantics, examples, no Layer refs in errors, Contract violations section, OOB to Advanced |
| 23 | stdlib compatibility as a feature | PolyNode embeds std.DoublyLinkedList.Node — items work with stdlib out of the box |
| 24 | Avoid "DLL" abbreviation | DLL = Dynamic Link Library to Windows devs; use full name or "linked list" |
| 25 | Wrapper encapsulates cancel policy | Superseded by Proposal 26 for cancel/close mixing; adapter pattern preserved |
| 26 | Mailbox and Pool as event sources | `receive_select`/`receive_future` + `get_wait_select`/`get_wait_future`; cancel never triggers close; result by value; "event source" replaces "leg" |

Note - 24 applied (2026-06-22): all "DLL" abbreviations replaced with full name or "linked list"

## Open Items

### Implementation

5. **condition_waitTimeout workaround** — Zig 0.16 `Io.Condition` has no `waitTimeout` (open issue codeberg/zig#31278). Workaround exists in reference mailbox (`mailbox.zig`). Must be copied as private helper for both `_Mbox` and `_Pool`. May become unnecessary if upstream fixes the issue.

6. **Io.Evented backend** — WIP in 0.16, not production-ready. Design targets both Threaded and Evented, but testing is Threaded-only for now. Select cost claims are backend-dependent.

### Architecture

7. **Architecture foundation doc (foundation-4.md)** — ~~still describes original 3-channel model only~~ **RESOLVED (2026-06-22)**: Updated with 2-channel model explanation (tagged items make INTERRUPT unnecessary), event sources section (Mailbox/Pool as event sources for Master coordination), cancel/close separation principle, pool availability as reactive signal. Both 3-channel and 2-channel models documented — 3-channel remains valid for non-tagged transports.

8. **Infrastructure-as-items in Zig** — handle transportability property (mailbox/pool as PolyNode-based items, Proposal 13) carries over unchanged. No open design questions, but no Zig examples written yet. Deferred to implementation phase.

### Testing

10. **Layer 2-3 tests with threads** — scenarios say "use `Io.Threaded.global_single_threaded`" but some examples need actual threads (fan-in, pipeline). Clarify which tests are single-threaded vs multi-threaded. `global_single_threaded` does not support concurrency — thread-based tests may need `Io.Threaded.init(gpa, .{})` without cancellation testing.

11. **Ownership violation behavior** — scenarios 15-17 (task1) test panics on double-insert, send-linked-item, etc. Zig behavior on panic in tests: `@panic` aborts the process. Need `std.testing.expectPanic` or equivalent? Or test via `std.debug.assert` which is `unreachable` in ReleaseSafe?

12. **Real Io examples feasibility** — task2 scenarios 25-30 require real network/file Io. These depend on having a working Matryoshka implementation first (layers 1-3). They are end-to-end integration tests, not unit tests. Implementation order: layers 1-3 → layer 4 unit tests → layer 4 real Io examples.

