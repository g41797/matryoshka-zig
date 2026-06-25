// SPDX-FileCopyrightText: Copyright (c) 2026 g41797
// SPDX-License-Identifier: MIT

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

- `matryoshka-api-reference-007.md` — **primary source of truth**: signatures, types, error sets, cancel contract, PolyHelper. Wins over all other sources on any conflict.
- `matryoshka-architecture-001.md` — why, concepts, flows
- `matryoshka-architecture-foundation-4-001.md` — language-independent architecture
- `matryoshka-zig-0.16-implementation-guide-001.md` — **OLD, do not trust directly**. Useful only as a hint for Zig-specific patterns (struct layout, condition_waitTimeout, cancel mechanics). Every signature, type, error set, and assert from this file must be verified against the API reference before use.
- `collected-context-002.md` — master reference, proposals, decisions
- `task1-scenarios-001.md` — 86 scenarios (Layers 1-3) — historical source
- `task2-scenarios-001.md` — 61 scenarios (Layer 4+) — historical source
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
- After each completed stage, create a new plan version (e.g., plan-004 → plan-005).
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
- Source of truth for signatures, types, errors: `matryoshka-api-reference-007.md`. Wins over all other sources.
- Implementation guide (`matryoshka-zig-0.16-implementation-guide-001.md`) is OLD — verify every detail against the API reference before use.
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
│   ├── mailbox.zig           # Block 2 — _Mailbox, MailboxHandle, send/receive/...
│   ├── pool.zig              # Block 3 — _Pool, PoolHandle, get/put/...
│   └── internal/
│       └── cond_timeout.zig  # condition_waitTimeout helper (shared by mailbox + pool)
├── tests/
│   ├── matryoshka_tests.zig  # test root: imports all suites below
│   ├── layer1_polynode.zig   # Layer 1 test scenarios
│   ├── layer1_examples.zig   # Layer 1 example test wrappers
│   ├── layer2_mailbox.zig    # Layer 2 test scenarios
│   ├── layer2_examples.zig   # Layer 2 example test wrappers
│   ├── layer3_pool.zig       # Layer 3 test scenarios
│   ├── layer3_examples.zig   # Layer 3 example test wrappers
│   ├── layer4_master.zig     # Layer 4 test scenarios
│   └── crosslayer.zig        # cross-layer test scenarios
├── helpers/
│   ├── helpers.zig           # shared test/example types (Event, Sensor, PolyHelper derivatives)
│   └── types.zig             # Event, Sensor structs + PolyHelper instances
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
│   ├── STATUS.md             # status + session log
│   └── *.md                  # spec docs
└── docs/                     # generated autodocs output (gh-pages), later stage
```

Notes:
- `src/internal/` holds shared private helpers. Not exported from the root.
- `helpers/` at repo root holds shared test/example types.
  Created via `createModule` (not `addModule`) — private, not exported to dependents.
  Both `tmod` (tests) and `emod` (examples) get `addImport("helpers", helpers)`.
- `tmod` (tests) also uses `createModule` — tests are not exported.
- Only `matryoshka` itself uses `addModule` (public, exported to dependents).
- Examples are a separate module so production builds exclude them.
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

### Stage 0 — Infrastructure. DONE. See Session 1 (2026-06-25).

### Stage 0.5 — Re-partition scenarios. DONE. See Session 2 (2026-06-25).

### Stage 1.a — PolyNode impl + tests. DONE. See Session 3 (2026-06-25).

### Stage 1.b — PolyNode examples. DONE. See Session 4 (2026-06-25).

---

### Stage 2 — Block 2: Mailbox

**Purpose**: ownership transport, FIFO with an OOB front.

**Sub-stages**:
- Stage 2.a — implementation + tests. Verify via all kitchen scripts.
- Stage 2.b — examples with test wrappers. Verify via all kitchen scripts.

#### Stage 2.a — Mailbox impl + tests

**What to build** (api-reference-007.md mailbox section; guide Section 4 for Zig patterns — verify all details against API reference)

- Evolve `TypeErasedMailbox` into `_Mailbox`. Add: `poly` field (mailbox is itself a PolyNode), `oob_count`, `oob_last`, `?u64` timeout, `std.DoublyLinkedList` returns.
- `new`, `destroy`, `send`, `send_oob`, `receive`, `try_receive`, `receive_batch`, `close`, `is_it_you`.
- Atomic `closed` fast path. `lockUncancelable` in `close` and `destroy`.
- Use `cond_timeout.zig` helper in `receive`.
- Do NOT add `receive_future` yet (Stage 7).

**Files**:
- `src/mailbox.zig` — create
- `tests/layer2_mailbox.zig` — create (scenarios 26-49)
- `tests/matryoshka_tests.zig` — add layer2_mailbox import

**Scenarios to verify**: task1-scenarios-001.md Layer 2 Tests (26-49).

**Checkpoint**
- All Stage 2.a test scenarios pass.
- No `error.Canceled` remapped to `error.Closed`.
- All 4 optimization modes pass.

**Risks / dependencies**
- Scenarios 32, 36 need a second thread — use `std.Thread.spawn` (Open Item 10).
- Idempotent close: `cmpxchgStrong(false, true, .acq_rel, .acquire)`.
- OOB reset on close: not a correctness requirement — `closed = true` gates all paths.

#### Stage 2.b — Mailbox examples

**What to build**: examples 50-56 (task1-scenarios-001.md Layer 2 Examples), each with a test wrapper.

**Files**:
- `examples/block2/block2.zig` — re-exports all mailbox examples
- `examples/block2/simple_send_receive.zig` — scenario 50
- `examples/block2/worker_loop.zig` — scenario 51
- `examples/block2/oob_signal.zig` — scenario 52
- `examples/block2/pipeline.zig` — scenario 53
- `examples/block2/request_response.zig` — scenario 54
- `examples/block2/fan_in.zig` — scenario 55
- `examples/block2/shutdown_cleanup.zig` — scenario 56
- `tests/layer2_examples.zig` — test wrappers for all 7 examples
- `tests/matryoshka_tests.zig` — add layer2_examples import
- `examples/examples.zig` — add block2 re-export

**Scenarios 53, 55** (pipeline, fan-in) need real threads — `std.Thread.spawn` (Open Item 10).

---

### Stage 3 — Block 3: Pool

**Purpose**: lifecycle by tag, hooks decide fate.

**What to build** (api-reference-007.md pool section; guide Section 5 for Zig patterns — verify all details against API reference)
- `_Pool` with `std.AutoHashMapUnmanaged` per-tag lists + counts.
- `PoolHooks` (on_get / on_put / on_close), `GetMode`, `GetError`.
- `new`, `init`, `destroy`, `get`, `get_wait`, `put`, `put_all`, `close`, `is_it_you`.
- `lockUncancelable` in `put`, `put_all`, `close`. `cond_timeout` in `get_wait`.
- Hooks run outside the mutex. Closed-pool-on-put returns item to caller.
- Do NOT add `get_wait_future` yet (Stage 7).

**Scenarios to verify**: task1-scenarios-001.md Layer 3 Tests.

**Checkpoint**
- All Stage 3 test scenarios pass.
- Stage 3 examples pass via test wrappers.
- All task1 tests and examples green. Layers 1-3 done.

**Risks / dependencies**
- `concatByMoving` for `close` collecting all per-tag lists.
- `on_close` called once with the full list, outside the lock.

---

### Stage 4 — Block 4: Infrastructure as Items

**Purpose**: mailboxes and pools are themselves PolyNodes, transportable.

**What to build** (guide Section 6)
- Confirm `MailboxHandle` / `PoolHandle` are `*PolyNode` and carry tags.
- Tag dispatch: send a mailbox through a mailbox; hold a pool as a pool item.
- No generic dispose — per-module `destroy` only.

**Checkpoint**
- A mailbox sent through a mailbox is received, recovered by tag, and used.
- A pool transported as an item is recovered and used.

---

### Stage 5 — Layer 4: Master (composition)

**Purpose**: compose blocks into a coordinator. No cancellation yet.

**What to build** (api-reference-007.md Master section)
- Master is a role, not a type. Examples, not a `Master` struct in `src/`.
- Worker spawned via `io.async` / `io.concurrent`, joined via `Future.await`.
- `Io.Group` for multiple workers, `group.await`.
- Single-source and fan-in patterns. Timer-as-mailbox-item (no Select).

**Scenarios to verify**: task2-scenarios-001.md Stage 5 rows.

**Checkpoint**
- All Stage 5 test scenarios pass.
- `error.Canceled` paths NOT yet required (Stage 6).

---

### Stage 6 — Cancellation + Shutdown

**Purpose**: the Zig-new behavior. Cancel vs close, clean teardown.

**What to build** (api-reference-007.md cancel contract)
- `Future.cancel`, `group.cancel` shutdown paths.
- Broadcast path vs Future.cancel path.
- Verify cancel-protected ops never leak items.

**Checkpoint**
- `error.Canceled != error.Closed` proven.
- No item lost on cancel during `pool.put`.

---

### Stage 7 — Event Sources (Select / Future)

**Purpose**: bridge blocking mailbox/pool into `Io.Select` and `Io.Future`.

**What to build** (api-reference-007.md event source helpers)
- `mailbox.ReceiveResult`, `mailbox.receive_future`.
- `pool.PoolResult`, `pool.get_wait_future`.
- Result by value inside the union — no `*Slot` crosses threads.
- Cancel returns `.canceled`; never closes.
- `error.ConcurrencyUnavailable` on single-threaded backends.

**Checkpoint**
- Single-threaded returns `error.ConcurrencyUnavailable`.
- Cancel/close separation proven.

---

### Stage 8 — Mailbox-less Patterns + Cross-Layer

**Purpose**: prove Pool + Io is a complete coordination model without Mailbox.

**Checkpoint**
- All Stage 8 test scenarios pass.
- All 147 scenarios green (tests + examples).

---

### Stage 9 — Docs + README + Autodocs

**Purpose**: each block usable standalone; site published.

**What to build** (tofu docs pipeline)
- `zig build docs` via `getEmittedDocs()` → `docs/`.
- Root `README.md` as a library index: polynode, mailbox, pool, with a copy-pasteable snippet per block.
- Final AI-sh scan across all `*.md` and `*.zig`.

---

## 4. Scenario → Stage Map

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

---

## 5. Existing Specs Index (what each doc owns)

| Doc | Owns |
|-----|------|
| collected-context-002.md | Master reference. Paths, 27 proposals, decisions, open items, scenario counts. Read first. |
| matryoshka-api-reference-007.md | **Primary source of truth.** Signatures, types, error sets, cancel contract, ownership lifecycle, contract violations, PolyHelper. Wins over all other sources. |
| matryoshka-zig-0.16-implementation-guide-001.md | **OLD — verify all details against API reference before use.** Zig how-to patterns: struct layout, condition_waitTimeout, cancel mechanics, Odin→Zig appendix. |
| matryoshka-architecture-001.md | Architecture introduction. Why matryoshka exists, concept progression, flows, layer map. MkDocs source. |
| matryoshka-architecture-foundation-4-001.md | Language-independent architecture. Layers, channels, patterns, rationale. |
| task1-scenarios-001.md | 86 scenarios, Layers 1-3. Tests and examples labeled within each layer section. |
| task2-scenarios-001.md | 61 scenarios, Layer 4 + cross-layer + event sources + mailbox-less. |
| task1-examples-001.md | Example/story scenarios extracted from task1. |
| task2-examples-001.md | Example/story scenarios extracted from task2. |

This plan owns: stage order, folder structure, checkpoints, status tracking.
It does not repeat API, architecture, or scenario detail — those live above.
