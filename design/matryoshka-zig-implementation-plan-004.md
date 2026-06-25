# Matryoshka Zig 0.16 — Staged Implementation Plan

Plan document only. No code here.
The specs are already written. This document tells the implementer how to
build from them, in what order, and how to know each step is done.

- New repo: `matryoshka-zig`. Module name: `matryoshka`.
- Zig 0.16.0. Target backend: `Io.Threaded`.
- 147 scenarios are the test plan: 86 in task1, 61 in task2.
- Both Mailbox and Pool are optional.
- `TypeErasedMailbox` in the legacy mailbox repo is the starting point for `_Mailbox`.
- Human handles all git. No git operations in any stage.

---

## 0. Sources of Truth

All paths are absolute. No "see other doc" references.

### Odin matryoshka — `/home/g41797/dev/root/github.com/g41797/matryoshka/`

Proto implementation. Use as reference for logic, tests, examples.

- Sources: `polynode.odin`, `mailbox.odin`, `pool.odin`, `poolhooks.odin`, `dispose.odin`, `doc.odin`
- Tests: `tests/block1/`, `tests/block2/`, `tests/block3/`, `tests/block4/`
- Examples: `examples/block1/`, `examples/block2/`, `examples/block3/`, `examples/block4/`
- Kitchen (housekeeping): `kitchen/`
  - Build/test scripts: `build_and_test.sh`, `build_and_test_debug.sh`, `build_and_test_quick.sh`
  - MkDocs site: `mkdocs.yml`, `kitchen/docs/` (deepdives, quickrefs, API ref, addendums)
  - Tools: `kitchen/tools/` (`build_site.sh`, `preview_site.sh`, `preview_apidocs.sh`, `generate_apidocs.sh`, `count_lines.py`)
  - Logo: `kitchen/_logo/`

### tofu — `/home/g41797/dev/root/github.com/g41797/tofu/`

Zig repo with build infrastructure to adapt. Structure from Odin kitchen, real scripts from tofu.

- Zig build: `build.zig`, `build.zig.zon`
- CI/CD workflows: `.github/workflows/` (`linux.yml`, `mac.yml`, `windows.yml`, `docs.yml`)
- Build-and-test scripts: `zbta_linux.sh`, `zbta_mac.sh`, `zbta_win.cmd`
- Zig autodocs: `docs_zig.sh`, `docs_zig.cmd`
- MkDocs site: `docs_site.sh`, `docs_site/` (`mkdocs.yml`, `docs/`, `overrides/`, `scripts/`)
- Recipes (examples as module): `recipes/` (`cookbook.zig`, `recipes.zig`, etc.)
- Test helpers: `src/ampe/helpers.zig` — `RunTasks` (spawn N tasks, wait all — old thread model, adapt to `Io.Group`), `AutoArrayHashMap` (managed wrapper for unmanaged hash map), `SleepMlsec`, `semaphore_waitTimeout` (uses `condition_waitTimeout`)
- Git config: `.gitignore`, `.gitattributes`, `.gitmodules`
- JetBrains run config: `.run/*.yml`

### mailbox — `/home/g41797/dev/root/github.com/g41797/mailbox/`

Legacy Zig mailbox. Starting point for `_Mailbox`.

- `src/mailbox.zig` — `TypeErasedMailbox`, `condition_waitTimeout` helper

### Design docs — `/home/g41797/dev/root/github.com/g41797/matryoshka-zig/design/`

- `matryoshka-api-reference-007.md` — signatures, types, error sets, cancel contract, PolyHelper
- `matryoshka-architecture-001.md` — why, concepts, flows
- `matryoshka-architecture-foundation-4-001.md` — language-independent architecture
- `matryoshka-zig-0.16-implementation-guide-001.md` — Zig how-to
- `collected-context-002.md` — master reference, proposals, decisions
- `task1-scenarios-001.md` — 86 scenarios (Layers 1-3) — historical source, will be re-partitioned
- `task2-scenarios-001.md` — 61 scenarios (Layer 4+) — historical source, will be re-partitioned
- `proposal-26-async-integration-001.md` — event source adapter design
- `context.md` — entry point

---

## 1. Process Rules

### Behaviour (MUST)
- Read `design/STATUS.md` Session Log first. It says where we are and what is next.
- Show intent before execution. Owner approves before code is written.
- One stage at a time. Do not skip stages. Each stage must pass before the next starts.
- Do not write real code before the build/test infrastructure is verified (Stage 0).
- Iterative: build a stage, checkpoint, rethink, then plan the next stage.

### Build Order Rules (MUST)

**Helper code is part of its stage**
- Implementation guide contains code that is not part of the API (e.g. `NodeMixin`, test types like `Event`, `Sensor`).
- This code is developed in the same stage as the implementation it supports — not before.
- It is shared by both tests and examples.
- It must have a proper home and be written as good, reusable code.

**Tests are real code**
- Tests are structured, reusable, well-named.
- No throwaway test code. Same quality standards as production code.

**Tests vs examples — different jobs**
- Tests check implementation. Correctness, edge cases, error paths, state transitions, contract violations.
- Examples show stories. Real usage patterns: "how to do fan-in", "how to seed a pool". They exercise the API in realistic, composed ways — this stress-tests the implementation harder than unit tests.

**Examples must show correct resource cleanup**
- Every heap allocation needs `errdefer` for the error path.
- Every resource that must be released on all paths gets `defer`.
- Examples become docs. Readers will copy them. Leaky examples teach leaky habits.

**Examples must not use testing APIs**
- No `std.testing` anything inside example code — no `testing.allocator`, no `testing.expect*`, no `testing.log_level`.
- Example function signature: `pub fn run(allocator: std.mem.Allocator, io: std.Io) !void`.
- Use `helpers.expect(error.XxxFailed, condition, "description")` for invariant checks — works in all build modes (unlike `std.debug.assert` which is removed in ReleaseFast/ReleaseSmall).
- Use `std.log` for diagnostic output inside examples.
- Reference model: tofu `recipes/cookbook.zig`.

**Examples have test wrappers**
- Every example is runnable code.
- A test wrapper calls the example and verifies it works.
- If an example breaks, its test wrapper catches it immediately.
- Test wrappers supply `std.testing.allocator` and `std.Io` to examples.
- Test wrappers set `std.testing.log_level = .debug`.
- Test wrappers use `testing.expect` for result verification.

**Examples come after tested code**
- Examples demonstrate working API. They cannot be written until the API is proven by tests.
- Order: implementation + helper code → tests → examples (with test wrappers) → docs.
- Examples cannot start until all tests for that stage pass all kitchen scripts.
- Each stage splits into two sub-stages:
  - **Stage N.a** — implementation + helper code + tests. Verify via all kitchen scripts.
  - **Stage N.b** — examples with test wrappers. Verify via all kitchen scripts.
- No mixing tests and examples in the same work batch.

**Examples become docs**
- Verified examples are pulled into documentation (autodocs, recipes, mkdocs site).
- Docs never show broken code — test wrappers guarantee this.

**Re-partition scenarios before each stage**
- `task1-scenarios-001.md` and `task2-scenarios-001.md` were written before the test/example split was clear.
- Before coding each stage, re-examine that stage's scenarios.
- Decide which are tests (verify correctness) and which are examples (show stories).
- This re-partitioning is part of each stage's planning step.

### Document Versioning (MUST)
- Never overwrite an important design doc. Create a new file with incremented version suffix (-001, -002, etc.).
- If other docs reference the updated doc, update those links to the new version.
- `design/context.md` is the stable entry point — always points to the latest `collected-context-NNN.md`.

### Plan Versioning (MUST)
- After each completed stage, create a new plan version (e.g., plan-003 → plan-004).
- In the new version, collapse completed stages to a one-line summary: "Stage N — Name. DONE. See Session X."
- Keep active + future stages in full detail.
- Old plan versions stay as historical record. Do not delete them.
- Update `design/context.md` to point to the new plan version.
- Update `design/STATUS.md` Sources of Truth to reference the new plan version.

### Git (MUST)
- Do not use git directly. All git operations go through the owner.

### Code Change Approval (MUST)
- Show intent. Describe what, why, which files.
- Wait for owner to say "yes", "approved", "do it", or equivalent.
- Only then write or edit any source file.
- Plan approval does NOT count as code change approval.
- Each fix in a multi-fix plan needs its own approval.

### Implementation (MUST)
- Source of truth for signatures, types, errors: `matryoshka-api-reference-007.md`.
- Source of truth for Zig details: `matryoshka-zig-0.16-implementation-guide-001.md`.
- Source of truth for architecture: `matryoshka-architecture-foundation-4-001.md`.
- Architecture introduction (why, concepts, flows): `matryoshka-architecture-001.md`.
- Never send a stack-allocated item. Use `alloc.create` or `pool.get`.
- After transfer (`send`, `put`), set `m.* = null`. Ownership invariant.
- After `close`, drain the returned list. Free heap items or return pool items.
- `mailbox.close`, `pool.close`, `pool.put`, `pool.put_all` use `lockUncancelable`.
- Never use `std.Thread.Mutex` / `std.Thread.Condition` in `_Mailbox` or `_Pool`.
- `error.Canceled` is never remapped to `error.Closed`.
- Copy `condition_waitTimeout` from the reference mailbox as a private helper
  for both `_Mailbox` and `_Pool` (Zig has no native `Io.Condition.waitTimeout`,
  issue codeberg/zig#31278).
- Architectural changes need explicit owner approval before implementation.

### Coding Style (MUST)
- Little-endian imports: imports at the bottom of the file, after the code.
- Explicit typing: `const x: T = ...` not `const x = ...` where type is known.
- Explicit dereference: `ptr.*.field` for pointer access.
- Standard library first: check stdlib before adding custom definitions.
- `errdefer` after every `alloc.create` or `try` that acquires a resource.
- `defer` for cleanup that must run on all exit paths.

### Verification (MUST)
- Run verification via kitchen scripts, not manual zig commands.
  - `kitchen/build_and_test_debug.sh` — quick check: build + test Debug only.
  - `kitchen/build_and_test_all.sh` — full check: build + test all 4 optimization modes.
  - `kitchen/build_cross_debug.sh` — cross-compile Debug for mac + windows (build only, no test).
- Build before test: `zig build` must succeed before `zig build test`.
- Debug first, then ReleaseFast.
- Full verification requires all 4 optimization modes:
  1. `zig build test` (Debug)
  2. `zig build test -Doptimize=ReleaseSafe`
  3. `zig build test -Doptimize=ReleaseFast`
  4. `zig build test -Doptimize=ReleaseSmall`
- A stage is only complete when all 4 modes pass.
- Cross-compile check: `zig build` for macOS and Windows targets must succeed.
- Redirect build/test output to `zig-out/` log files. Analyze via files, not shell stdout.

### Documents (MUST)
- Simple English. Short sentences. Bullets over long sentences.
- No AI-sh words. After any stage that changes `*.md` or `*.zig`, scan for:
  robust, seamlessly, comprehensive, leverage, efficient, powerful, facilitate,
  utilize, ensure, performant, ergonomic, idiomatic, streamline, orchestrate,
  sophisticated, intuitive, scalable, unlock, empower, harness, deliver.
- Show the list to the owner. Do not fix without approval.
- When appending to a doc, match the heading levels already in use.

### Per-stage finish steps
1. Run `kitchen/build_and_test_debug.sh` — quick build + Debug test.
2. Run `kitchen/build_and_test_all.sh` — full build + all 4 optimization modes.
3. Run `kitchen/build_cross_debug.sh` — cross-compile Debug for mac + windows.
4. Post-stage cleanup: revise all existing code for obsolete parts, wrong comments, repeated code that can be extracted into reusable sources. Fix what you find.
5. Re-run all three kitchen scripts after cleanup fixes.
6. Update `design/STATUS.md` Session Log (newest entry at top, use template). Session log must include a "Post-stage cleanup" row in the Verification table — what was found, what was fixed, re-run results. If nothing found, the row says "nothing to clean." Absence of this row means the rule was skipped.
7. Create new plan version: collapse completed stages to one-line summaries, keep active + future stages in full. Update `design/context.md` and `design/STATUS.md` to point to new plan version.
8. Sync `README.md` and any per-module README touched.
9. Comments check. AI-sh scan. Report to owner.
10. Rethink the next stage before starting it.

---

## 2. Repo Folder Structure

Pattern borrowed from the tofu and mailbox repos. Housekeeping idea borrowed
from the Odin matryoshka `kitchen/` layout, but kept lighter.

```text
matryoshka-zig/
├── build.zig                 # addModule("matryoshka", ...), test step, docs step
├── build.zig.zon             # name = matryoshka, version, no deps at start
├── README.md                 # library index, short usage per block
├── src/
│   ├── matryoshka.zig        # root: re-exports polynode, mailbox, pool
│   ├── polynode.zig          # Block 1 — PolyNode, Slot, PolyTag, reset, is_linked
│   ├── mailbox.zig              # Block 2 — _Mailbox, MailboxHandle, send/receive/...
│   ├── pool.zig              # Block 3 — _Pool, PoolHandle, get/put/...
│   └── internal/
│       └── cond_timeout.zig  # condition_waitTimeout helper (shared by mailbox + pool)
├── tests/
│   ├── matryoshka_tests.zig  # test root: imports all suites below
│   ├── helpers/
│   │   └── types.zig         # Event, Sensor test types; NodeMixin; tag helpers
│   ├── layer1_polynode.zig   # task1 test scenarios
│   ├── layer2_mailbox.zig    # task1 test scenarios
│   ├── layer3_pool.zig       # task1 test scenarios
│   ├── layer4_master.zig     # task2 test scenarios
│   ├── crosslayer.zig        # task2 test scenarios
│   ├── event_source.zig      # task2 test scenarios
│   └── mailbox_less.zig      # task2 test scenarios
├── helpers/
│   └── helpers.zig           # shared test/example types (Event, Sensor, NodeMixin derivatives)
├── examples/                 # runnable usage stories, imported by test wrappers
│   ├── examples.zig          # root: re-exports per-block example modules
│   ├── block1/               # polynode usage stories
│   ├── block2/               # mailbox usage stories
│   ├── block3/               # pool usage stories
│   └── block4/               # composition, master, cross-layer stories
├── kitchen/
│   ├── build_and_test_debug.sh   # build + test Debug only
│   ├── build_and_test_all.sh     # build + test all 4 optimization modes
│   └── build_cross_debug.sh      # cross-compile Debug for mac + windows (build only)
├── design/
│   ├── STATUS.md             # status + session log (created in Stage 0)
│   └── *.md                  # the existing spec docs, copied in by the owner
└── docs/                     # generated autodocs output (gh-pages), later stage
```

Notes:
- `src/internal/` holds shared private helpers. Not exported from the root.
- `helpers/` at repo root holds shared test/example types (`Event`, `Sensor`, `NodeMixin` derivatives).
  Created via `createModule` (not `addModule`) — private, not exported to dependents.
  Both `tmod` (tests) and `emod` (examples) get `addImport("helpers", helpers)`.
  The API reference references these as "see helpers/helpers.zig".
- `tmod` (tests) also uses `createModule` — tests are not exported.
- Only `matryoshka` itself uses `addModule` (public, exported to dependents).
- Examples are a separate module so production builds exclude them, and so the
  docs step can emit them as recipes (tofu pattern).
- Each example has a test wrapper that calls it and verifies it works.

---

## 3. Stages

Build order from the implementation guide:

```text
Stage 0     infrastructure
Stage 0.5   re-partition scenarios into tests + examples
Stage 1     Block 1  PolyNode
Stage 2     Block 2  Mailbox        ┐ independent siblings
Stage 3     Block 3  Pool           ┘ (Pool may start after Stage 1)
Stage 4     Block 4  Infra as items
Stage 5     Layer 4  Master (single-thread + concurrency)
Stage 6     Cancellation + shutdown
Stage 7     Event sources (Select / Future)
Stage 8     Mailbox-less patterns + cross-layer
Stage 9     Docs + README + autodocs
```

---

### Stage 0 — Infrastructure

**Purpose**: a buildable empty repo with a passing test step.

**What to build**
- `build.zig` + `build.zig.zon`. Base on the mailbox `build.zig` (simple
  `addModule` + test step). Module name `matryoshka`, root `src/matryoshka.zig`.
- Stub `src/matryoshka.zig` re-exporting empty `polynode`, `mailbox`, `pool` files.
- `tests/matryoshka_tests.zig` with one trivial passing test.
- `design/STATUS.md` from the template in Section 5.
- Copy `condition_waitTimeout` from `mailbox/src/mailbox.zig` into
  `src/internal/cond_timeout.zig`, unmodified for now (Open Item 5).
- `kitchen/build_and_test_debug.sh` — build + test Debug only.
- `kitchen/build_and_test_all.sh` — build + test all 4 optimization modes.
- `kitchen/build_cross_debug.sh` — cross-compile Debug for mac + windows (build only).

**Scenarios to verify**: none yet.

**Checkpoint**
- `kitchen/build_and_test_debug.sh` passes.
- `kitchen/build_and_test_all.sh` passes.
- `kitchen/build_cross_debug.sh` passes.
- `zig version` reports 0.16.0.

**Risks / dependencies**
- `build.zig.zon` schema for 0.16. Mirror the mailbox repo exactly.
- Do not write block code before this passes (process rule).

---

### Stage 0.5 — Re-partition scenarios

After Stage 0 skeleton is built, before Stage 1 coding.

- `task1-scenarios-001.md` and `task2-scenarios-001.md` stay as-is (historical source).
- **Create** `design/task1-tests-001.md` — test scenarios extracted from task1. Check implementation: correctness, edge cases, error paths, contract violations.
- **Create** `design/task1-examples-001.md` — example/story scenarios extracted from task1. Show usage patterns, stress-test API in realistic composed ways.
- **Create** `design/task2-tests-001.md` — test scenarios extracted from task2.
- **Create** `design/task2-examples-001.md` — example/story scenarios extracted from task2.
- Update `design/context.md` to point to new docs.

---

### Stage 1 — Block 1: PolyNode

**Purpose**: the ownership atom and its test types.

**What to build** (guide Section 3, api-reference `polynode`)
- `PolyTag`, `PolyNode` (embeds `std.DoublyLinkedList.Node`), `Slot`.
- `reset`, `is_linked`.
- `tests/helpers/types.zig`: `Event`, `Sensor`, tags, and the `NodeMixin`
  comptime helper (guide Section 10) — `TAG`, `isIt`, `cast`, `init`.
- Two-level `@fieldParentPtr` recovery demonstrated in helpers.

**Scenarios to verify**: per task1-tests-001.md and task1-examples-001.md (Stage 1 rows).

**Checkpoint**
- All Stage 1 test scenarios pass.
- Stage 1 examples pass via test wrappers.
- Deferred scenarios (depend on later blocks) marked.

**Risks / dependencies**
- Open Item 11: how to test a panic in Zig. Decide: `std.testing` panic capture
  vs. `std.debug.assert` (`unreachable` in ReleaseSafe). Settle before panic tests.
- `NodeMixin` uses `var _tag` for unique address — confirm linker does not
  dedup (guide Section 10).

---

### Stage 2 — Block 2: Mailbox

**Purpose**: ownership transport, FIFO with an OOB front.

**What to build** (guide Section 4, api-reference `mailbox`)
- Evolve `TypeErasedMailbox` into `_Mailbox`. Add: `poly` field, `oob_count`,
  `oob_last`, `?u64` timeout, `std.DoublyLinkedList` returns.
- `new`, `destroy`, `send`, `send_oob`, `receive`, `try_receive`,
  `receive_batch`, `close`, `is_it_you`.
- Atomic `closed` fast path. `lockUncancelable` in `close`.
- Use `cond_timeout.zig` helper in `receive`.
- Do NOT add `receive_select` / `receive_future` yet (Stage 7).

**Scenarios to verify**: per task1-tests-001.md and task1-examples-001.md (Stage 2 rows).

**Checkpoint**
- All Stage 2 test scenarios pass.
- Stage 2 examples pass via test wrappers.
- No `error.Canceled` remapped to `error.Closed`.

**Risks / dependencies**
- Open Item 10: which mailbox examples need real threads vs
  `global_single_threaded`. fan-in and pipeline likely need
  `Io.Threaded.init(gpa, .{})`.
- Idempotent close + OOB reset must both happen under one lock.

---

### Stage 3 — Block 3: Pool

**Purpose**: lifecycle by tag, hooks decide fate.

**What to build** (guide Section 5, api-reference `pool`)
- `_Pool` with `std.AutoHashMapUnmanaged` per-tag lists + counts.
- `PoolHooks` (on_get / on_put / on_close), `GetMode`, `GetError`.
- `new`, `init`, `destroy`, `get`, `get_wait`, `put`, `put_all`, `close`,
  `is_it_you`.
- `lockUncancelable` in `put`, `put_all`, `close`. `cond_timeout` in `get_wait`.
- Hooks run outside the mutex. Closed-pool-on-put returns item to caller.
- Do NOT add `get_wait_select` / `get_wait_future` yet (Stage 7).

**Scenarios to verify**: per task1-tests-001.md and task1-examples-001.md (Stage 3 rows).

**Checkpoint**
- All Stage 3 test scenarios pass.
- Stage 3 examples pass via test wrappers.
- All task1 tests and examples green. Layers 1-3 done.

**Risks / dependencies**
- `concatByMoving` for `close` collecting all per-tag lists (guide Section 5).
- on_close called once with the full list, outside the lock.

---

### Stage 4 — Block 4: Infrastructure as Items

**Purpose**: mailboxes and pools are themselves PolyNodes, transportable.

**What to build** (guide Section 6)
- Confirm `MailboxHandle` / `PoolHandle` are `*PolyNode` and carry tags.
- Tag dispatch: send a mailbox through a mailbox; hold a pool as a pool item.
- No generic dispose — per-module `destroy` only.

**Scenarios to verify**
- Covered by deferred Stage 1 scenarios plus cross-layer checks.
- Add focused tests and examples: mailbox-through-mailbox roundtrip, pool-as-item roundtrip.

**Checkpoint**
- A mailbox sent through a mailbox is received, recovered by tag, and used.
- A pool transported as an item is recovered and used.

**Risks / dependencies**
- Rule 11: no ownership cycles. An item must not retain the mailbox/pool that
  delivered it.

---

### Stage 5 — Layer 4: Master (composition)

**Purpose**: compose blocks into a coordinator. No cancellation yet.

**What to build** (guide Section 8, api-reference Master section)
- Master is a role, not a type. Examples, not a `Master` struct in `src/`.
- Worker spawned via `io.async` / `io.concurrent`, joined via `Future.await`.
- `Io.Group` for multiple workers, `group.await`.
- Single-source and fan-in patterns. Timer-as-mailbox-item (no Select).

**Scenarios to verify**: per task2-tests-001.md and task2-examples-001.md (Stage 5 rows).

**Checkpoint**
- All Stage 5 test scenarios pass.
- Stage 5 examples pass via test wrappers.
- `error.Canceled` paths NOT yet required (Stage 6).

**Risks / dependencies**
- Needs real concurrency: `Io.Threaded.init(gpa, .{})`, not single-threaded.
- "Master" term must not leak into Layer 1-3 tests.

---

### Stage 6 — Cancellation + Shutdown

**Purpose**: the Zig-new behavior. Cancel vs close, clean teardown.

**What to build** (guide Section 7, cancel contract table)
- `Future.cancel`, `group.cancel` shutdown paths.
- Broadcast path vs Future.cancel path (guide 8.4, 8.5).
- `recancel`, `checkCancel` usage in workers.
- Verify cancel-protected ops never leak items.

**Scenarios to verify**: per task2-tests-001.md and task2-examples-001.md (Stage 6 rows).

**Checkpoint**
- All Stage 6 test scenarios pass.
- Stage 6 examples pass via test wrappers.
- `error.Canceled != error.Closed` proven.
- No item lost on cancel during `pool.put`.

**Risks / dependencies**
- Cancel injection timing: takes effect at next Io wait.
- Both closes must run before join in the broadcast path.

---

### Stage 7 — Event Sources (Select / Future)

**Purpose**: bridge blocking mailbox/pool into `Io.Select` and `Io.Future`.

**What to build** (Proposal 26, api-reference event source helpers)
- `mailbox.ReceiveResult`, `mailbox.receive_select`, `mailbox.receive_future`.
- `pool.PoolResult`, `pool.get_wait_select`, `pool.get_wait_future`.
- Result by value inside the union — no `*Slot` crosses threads.
- Cancel returns `.canceled`; never closes. Master decides shutdown.
- `error.ConcurrencyUnavailable` on single-threaded backends.

**Scenarios to verify**: per task2-tests-001.md and task2-examples-001.md (Stage 7 rows).

**Checkpoint**
- All Stage 7 test scenarios pass.
- Stage 7 examples pass via test wrappers.
- Single-threaded returns `error.ConcurrencyUnavailable`.
- Cancel/close separation proven.

**Risks / dependencies**
- Open Item 6: only Threaded backend tested. Note thread cost in code + docs.
- Open Item 12: socket/network scenarios need real Io — integration
  tests, gate on platform if needed.

---

### Stage 8 — Mailbox-less Patterns + Cross-Layer

**Purpose**: prove Pool + Io is a complete coordination model without Mailbox.

**What to build**
- Pool + Future, Pool + Select, Pool + Group examples.
- Cross-layer ownership flows and shutdown ordering.

**Scenarios to verify**: per task2-tests-001.md and task2-examples-001.md (Stage 8 rows).

**Checkpoint**
- All Stage 8 test scenarios pass.
- Stage 8 examples pass via test wrappers.
- All 147 scenarios green (tests + examples).

**Risks / dependencies**
- Scenario 61 documents the transition point (when to add a mailbox).
- Scenario 60 needs real network Io (Open Item 12).

---

### Stage 9 — Docs + README + Autodocs

**Purpose**: each block usable standalone; site published.

**What to build** (tofu docs pipeline)
- `zig build docs` via `getEmittedDocs()` → `docs/`.
- Root `README.md` as a library index: polynode, mailbox, pool, with a
  copy-pasteable snippet per block.
- Optional MkDocs Material site (kitchen/tools pattern), owner decides.
- Final AI-sh scan across all `*.md` and `*.zig`.

**Scenarios to verify**: none (docs).

**Checkpoint**
- `zig build docs` produces autodocs.
- README snippets compile (smoke-build them).
- AI-sh scan clean and reported.

**Risks / dependencies**
- Keep README snippets in sync with the API reference.

---

## 4. Scenario → Stage Map

Will be updated after Stage 0.5 re-partition.
Original mapping (from task1/task2 before split):

| Stage | task1 | task2 |
|-------|-------|-------|
| 1 | 1-17, 21-25 | — |
| 2 | 18, 26-56 | — |
| 3 | 19-20, 57-86 | — |
| 4 | (re-proves 18-20) | — |
| 5 | — | 1-2, 17-24 |
| 6 | — | 3-16 |
| 7 | — | 25-31, 42-56 |
| 8 | — | 32-41, 57-61 |

Totals: 86 task1 (Stages 1-3), 61 task2 (Stages 5-8).

After Stage 0.5, this table will be replaced with test/example split per stage.

---

## 5. STATUS.md Template

Create `design/STATUS.md` in Stage 0. Newest session entry at top.

```markdown
# matryoshka-zig STATUS

## Rules
- Read Session Log first. It says where we are and what is next.
- No git directly. Owner does git.
- No skipping stages. Each stage passes before the next.
- No real code before infrastructure (Stage 0) is verified.
- Show intent before code changes. Get owner approval.
- Plan approval is NOT code change approval.
- Architectural changes need explicit owner approval.
- Never overwrite important docs. New version with incremented suffix (-001, -002, etc.). Update cross-references.
- Post-stage cleanup: after all kitchen scripts pass, revise all code for obsolete parts, wrong comments, repeated code extractable to reusable sources. Fix, re-run all three scripts. Session log must have a "Post-stage cleanup" row — its absence means the rule was skipped.

## Constraints for Next Agent (MUST)
- Git disabled. Do NOT run any git commands.
- Coding style: LE imports, explicit types, explicit dereference, stdlib first.
- Doc style: short sentences, bullets, no AI-sh words. See plan Section 1.
- 4-mode verification: Debug, ReleaseSafe, ReleaseFast, ReleaseSmall.
- Build before test. Debug first.
- AI-sh scan after every stage that changes *.md or *.zig.

## Sources of Truth
- API: matryoshka-api-reference-006.md
- Zig details: matryoshka-zig-0.16-implementation-guide-001.md
- Architecture: matryoshka-architecture-foundation-4-001.md
- Architecture introduction: matryoshka-architecture-001.md
- Tests: task1-tests-001.md, task2-tests-001.md
- Examples: task1-examples-001.md, task2-examples-001.md
- Scenarios (historical): task1-scenarios-001.md (86), task2-scenarios-001.md (61)
- Legacy mailbox: /home/g41797/dev/root/github.com/g41797/mailbox/
- Odin proto: /home/g41797/dev/root/github.com/g41797/matryoshka/
- tofu (build infra): /home/g41797/dev/root/github.com/g41797/tofu/
- This file + the plan file.

## Participants
- Owner: g41797 (human)
- Claude: implementation, tests

## Project
Ownership-transfer and lifecycle toolkit for Zig 0.16.
Three blocks: polynode, mailbox, pool. Both mailbox and pool optional.

## Folder Structure
(see plan, Section 2; update after Stage 0)

## Decisions
- STATUS.md first, updated after every stage.
- Document rules apply to all markdown.
- condition_waitTimeout copied from legacy mailbox (Open Item 5).
- Tests check implementation. Examples show stories and stress-test.
- Examples have test wrappers. Examples come after tested code.
- Scenarios re-partitioned into tests + examples (Stage 0.5).

## Open Items (carried from collected-context-001.md)
- 5  condition_waitTimeout workaround
- 6  Io.Evented backend not tested
- 10 which Layer 2-3 examples need real threads
- 11 panic test style in Zig
- 12 real-Io examples are integration tests, gate by platform

## Stages
Next: Stage 0 — Infrastructure.

## Session Log

### YYYY-MM-DD — Session N
**Participants**: human + Claude

**Summary**
One paragraph. What was done and why.

**Changes**
- `path/to/file` — what changed

**Verification**

| Check | Result |
| :---- | :----- |
| `zig build` | |
| `zig build test` (Debug) | |
| `zig build test -Doptimize=ReleaseSafe` | |
| `zig build test -Doptimize=ReleaseFast` | |
| `zig build test -Doptimize=ReleaseSmall` | |

**Next**: (what comes next)
```

---

## 6. Existing Specs Index (what each doc owns)

| Doc | Owns |
|-----|------|
| collected-context-002.md | Master reference. Paths, 27 proposals, decisions, open items, scenario counts. Read first. |
| matryoshka-api-reference-007.md | Source of truth. Signatures, types, error sets, cancel contract, ownership lifecycle, contract violations, PolyHelper. |
| matryoshka-zig-0.16-implementation-guide-001.md | Zig how-to. Blocks 1-4, cancellation, Master patterns, rules, comptime opportunities, Odin→Zig appendix. |
| matryoshka-architecture-001.md | Architecture introduction. Why matryoshka exists, concept progression, flows, layer map. MkDocs source. |
| matryoshka-architecture-foundation-4-001.md | Language-independent architecture. Layers, channels, patterns, rationale. |
| task1-scenarios-001.md | 86 scenarios, Layers 1-3. Historical source for re-partition. |
| task2-scenarios-001.md | 61 scenarios, Layer 4 + cross-layer + event sources + mailbox-less. Historical source for re-partition. |
| task1-tests-001.md | Test scenarios extracted from task1. Created in Stage 0.5. |
| task1-examples-001.md | Example/story scenarios extracted from task1. Created in Stage 0.5. |
| task2-tests-001.md | Test scenarios extracted from task2. Created in Stage 0.5. |
| task2-examples-001.md | Example/story scenarios extracted from task2. Created in Stage 0.5. |
| proposal-26-async-integration-001.md | Event source adapter design. The Stage 7 spec. |

This plan owns: stage order, folder structure, checkpoints, status tracking.
It does not repeat API, architecture, or scenario detail — those live above.
