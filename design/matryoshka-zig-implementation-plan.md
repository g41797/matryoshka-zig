# Matryoshka Zig 0.16 — Staged Implementation Plan

Plan document only. No code here.
The specs are already written. This document tells the implementer how to
build from them, in what order, and how to know each step is done.

- New repo: `matryoshka-zig`. Module name: `matryoshka`.
- Zig 0.16.0. Target backend: `Io.Threaded`.
- 147 scenarios are the test plan: 86 in task1, 61 in task2.
- Both Mailbox and Pool are optional.
- `TypeErasedMailbox` in the legacy mailbox repo is the starting point for `_Mbox`.
- Human handles all git. No git operations in any stage.

---

## 1. Process Rules

### Behaviour (MUST)
- Read `design/STATUS.md` Session Log first. It says where we are and what is next.
- Show intent before execution. Owner approves before code is written.
- One stage at a time. Do not skip stages. Each stage must pass before the next starts.
- Do not write real code before the build/test infrastructure is verified (Stage 0).
- Iterative: build a stage, checkpoint, rethink, then plan the next stage.

### Git (MUST)
- Do not use git directly. All git operations go through the owner.

### Code Change Approval (MUST)
- Show intent. Describe what, why, which files.
- Wait for owner to say "yes", "approved", "do it", or equivalent.
- Only then write or edit any source file.
- Plan approval does NOT count as code change approval.
- Each fix in a multi-fix plan needs its own approval.

### Implementation (MUST)
- Source of truth for signatures, types, errors: `matryoshka-api-reference.md`.
- Source of truth for Zig details: `matryoshka-zig-0.16-implementation-guide.md`.
- Source of truth for architecture: `matryoshka-architecture-foundation-4.md`.
- Never send a stack-allocated item. Use `alloc.create` or `pool.get`.
- After transfer (`send`, `put`), set `m.* = null`. Ownership invariant.
- After `close`, drain the returned list. Free heap items or return pool items.
- `mbox.close`, `pool.close`, `pool.put`, `pool.put_all` use `lockUncancelable`.
- Never use `std.Thread.Mutex` / `std.Thread.Condition` in `_Mbox` or `_Pool`.
- `error.Canceled` is never remapped to `error.Closed`.
- Copy `condition_waitTimeout` from the reference mailbox as a private helper
  for both `_Mbox` and `_Pool` (Zig has no native `Io.Condition.waitTimeout`,
  issue codeberg/zig#31278).
- Architectural changes need explicit owner approval before implementation.

### Coding Style (MUST)
- Little-endian imports: imports at the bottom of the file, after the code.
- Explicit typing: `const x: T = ...` not `const x = ...` where type is known.
- Explicit dereference: `ptr.*.field` for pointer access.
- Standard library first: check stdlib before adding custom definitions.

### Verification (MUST)
- Build before test: `zig build` must succeed before `zig build test`.
- Debug first, then ReleaseFast.
- Full verification requires all 4 optimization modes:
  1. `zig build test` (Debug)
  2. `zig build test -Doptimize=ReleaseSafe`
  3. `zig build test -Doptimize=ReleaseFast`
  4. `zig build test -Doptimize=ReleaseSmall`
- A stage is only complete when all 4 modes pass.
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
1. Build: `zig build` succeeds.
2. Test Debug: `zig build test` passes.
3. Test ReleaseSafe: `zig build test -Doptimize=ReleaseSafe` passes.
4. Test ReleaseFast: `zig build test -Doptimize=ReleaseFast` passes.
5. Test ReleaseSmall: `zig build test -Doptimize=ReleaseSmall` passes.
6. Update `design/STATUS.md` Session Log (newest entry at top, use template).
7. Update this plan file (full plan, not a diff) if anything changed.
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
│   ├── matryoshka.zig        # root: re-exports polynode, mbox, pool
│   ├── polynode.zig          # Block 1 — PolyNode, MayItem, PolyTag, reset, is_linked
│   ├── mbox.zig              # Block 2 — _Mbox, MailboxHandle, send/receive/...
│   ├── pool.zig              # Block 3 — _Pool, PoolHandle, get/put/...
│   └── internal/
│       └── cond_timeout.zig  # condition_waitTimeout helper (shared by mbox + pool)
├── tests/
│   ├── matryoshka_tests.zig  # test root: imports all suites below
│   ├── helpers/
│   │   └── types.zig         # Event, Sensor test types; NodeMixin; tag helpers
│   ├── layer1_polynode.zig   # task1 scenarios 1-25
│   ├── layer2_mbox.zig       # task1 scenarios 26-56
│   ├── layer3_pool.zig       # task1 scenarios 57-86
│   ├── layer4_master.zig     # task2 scenarios 1-31
│   ├── crosslayer.zig        # task2 scenarios 32-41
│   ├── event_source.zig      # task2 scenarios 42-56
│   └── mailbox_less.zig      # task2 scenarios 57-61
├── examples/                 # runnable Master patterns (Layer 4)
│   └── examples.zig          # built as its own module, imported by tests
├── design/
│   ├── STATUS.md             # status + session log (created in Stage 0)
│   └── *.md                  # the existing spec docs, copied in by the owner
└── docs/                     # generated autodocs output (gh-pages), later stage
```

Notes:
- `src/internal/` holds shared private helpers. Not exported from the root.
- `tests/helpers/types.zig` holds the `NodeMixin` and the `Event`/`Sensor`
  test types referenced by the API reference ("see tests/helpers/types.zig").
- Examples are a separate module so production builds exclude them, and so the
  docs step can emit them as recipes (tofu pattern).

---

## 3. Stages

Build order from the implementation guide:

```text
Stage 0   infrastructure
Stage 1   Block 1  PolyNode
Stage 2   Block 2  Mailbox        ┐ independent siblings
Stage 3   Block 3  Pool           ┘ (Pool may start after Stage 1)
Stage 4   Block 4  Infra as items
Stage 5   Layer 4  Master (single-thread + concurrency)
Stage 6   Cancellation + shutdown
Stage 7   Event sources (Select / Future)
Stage 8   Mailbox-less patterns + cross-layer
Stage 9   Docs + README + autodocs
```

---

### Stage 0 — Infrastructure

**Purpose**: a buildable empty repo with a passing test step.

**What to build**
- `build.zig` + `build.zig.zon`. Base on the mailbox `build.zig` (simple
  `addModule` + test step). Module name `matryoshka`, root `src/matryoshka.zig`.
- Stub `src/matryoshka.zig` re-exporting empty `polynode`, `mbox`, `pool` files.
- `tests/matryoshka_tests.zig` with one trivial passing test.
- `design/STATUS.md` from the template in Section 5.
- Copy `condition_waitTimeout` from `mailbox/src/mailbox.zig` into
  `src/internal/cond_timeout.zig`, unmodified for now (Open Item 5).

**Scenarios to verify**: none yet.

**Checkpoint**
- `zig build` succeeds.
- `zig build test` runs and passes the trivial test.
- `zig version` reports 0.16.0.

**Risks / dependencies**
- `build.zig.zon` schema for 0.16. Mirror the mailbox repo exactly.
- Do not write block code before this passes (process rule).

---

### Stage 1 — Block 1: PolyNode

**Purpose**: the ownership atom and its test types.

**What to build** (guide Section 3, api-reference `polynode`)
- `PolyTag`, `PolyNode` (embeds `std.DoublyLinkedList.Node`), `MayItem`.
- `reset`, `is_linked`.
- `tests/helpers/types.zig`: `Event`, `Sensor`, tags, and the `NodeMixin`
  comptime helper (guide Section 10) — `TAG`, `isIt`, `cast`, `init`.
- Two-level `@fieldParentPtr` recovery demonstrated in helpers.

**Scenarios to verify** (task1)
- Tags + casts: 1-6
- reset / is_linked: 7-8
- MayItem + multi-type list: 9-10
- Ownership state transitions: 11-14
- Ownership violation panics: 15-17 (see Open Item 11 — decide panic test style)
- Infra-as-item at Layer 1: 18-20 (needs mbox/pool handles — defer 18-19 to
  Stage 2/3, keep 20 once destroy exists; mark partial)
- Examples: 21-25

**Checkpoint**
- All task1 scenarios 1-17 and 21-25 pass.
- 18-20 marked deferred (depend on later blocks).

**Risks / dependencies**
- Open Item 11: how to test a panic in Zig. Decide: `std.testing` panic capture
  vs. `std.debug.assert` (`unreachable` in ReleaseSafe). Settle before 15-17.
- `NodeMixin` uses `var _tag` for unique address — confirm linker does not
  dedup (guide Section 10).

---

### Stage 2 — Block 2: Mailbox

**Purpose**: ownership transport, FIFO with an OOB front.

**What to build** (guide Section 4, api-reference `mbox`)
- Evolve `TypeErasedMailbox` into `_Mbox`. Add: `poly` field, `oob_count`,
  `oob_last`, `?u64` timeout, `std.DoublyLinkedList` returns.
- `new`, `destroy`, `send`, `send_oob`, `receive`, `try_receive`,
  `receive_batch`, `close`, `is_it_you`.
- Atomic `closed` fast path. `lockUncancelable` in `close`.
- Use `cond_timeout.zig` helper in `receive`.
- Do NOT add `receive_select` / `receive_future` yet (Stage 7).

**Scenarios to verify** (task1)
- Core send/receive/FIFO/closed: 26-34
- OOB ordering and wake: 35-39
- Batch: 40-42
- Ownership transfer + try_receive: 43-46
- State transitions + violation: 47-49
- Examples: 50-56 (single-thread where possible; fan-in/pipeline may need
  real threads — Open Item 10)
- Now also complete task1 scenario 18 (MailboxHandle is a PolyNode).

**Checkpoint**
- task1 scenarios 26-56 pass.
- task1 scenario 18 passes.
- No `error.Canceled` remapped to `error.Closed`.

**Risks / dependencies**
- Open Item 10: which mailbox examples need real threads vs
  `global_single_threaded`. fan-in (55) and pipeline (53) likely need
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

**Scenarios to verify** (task1)
- get modes + on_get/on_put: 57-66
- per-tag lists: 67
- close + idempotency + closed behavior: 68-71
- backpressure / seeding / counts / hooks-outside-lock: 72-75
- put_all + get_wait timeout/forever: 76-78
- state transitions + double-put: 79-82
- Examples: 83-86
- Now also complete task1 scenario 19 (PoolHandle is a PolyNode) and 20.

**Checkpoint**
- task1 scenarios 57-86 pass.
- task1 scenarios 19-20 pass.
- All 86 task1 scenarios green. Layers 1-3 done.

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
- Covered by task1 18-20 (already) plus cross-layer checks proven again here.
- No new numbered scenarios own this block alone. Add a focused unit test:
  mailbox-through-mailbox roundtrip, pool-as-item roundtrip (Open Item 8 —
  no Zig examples written yet; this stage writes the first).

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

**Scenarios to verify** (task2)
- Worker lifecycle: 1-2
- Master patterns: 17-21
- Mailbox as fan-in: 22-24

**Checkpoint**
- task2 1-2 and 17-24 pass.
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

**Scenarios to verify** (task2)
- Worker cancel mechanics: 3-5
- Shutdown ordering: 6-10
- Cancellation mechanics: 11-16

**Checkpoint**
- task2 3-16 pass.
- `error.Canceled != error.Closed` proven (11-12).
- No item lost on cancel during `pool.put` (13).

**Risks / dependencies**
- Cancel injection timing (5): takes effect at next Io wait.
- Both closes must run before join in the broadcast path.

---

### Stage 7 — Event Sources (Select / Future)

**Purpose**: bridge blocking mailbox/pool into `Io.Select` and `Io.Future`.

**What to build** (Proposal 26, api-reference event source helpers)
- `mbox.ReceiveResult`, `mbox.receive_select`, `mbox.receive_future`.
- `pool.PoolResult`, `pool.get_wait_select`, `pool.get_wait_future`.
- Result by value inside the union — no `*MayItem` crosses threads.
- Cancel returns `.canceled`; never closes. Master decides shutdown.
- `error.ConcurrencyUnavailable` on single-threaded backends.

**Scenarios to verify** (task2)
- Select event sources: 25-31, 42-48
- Future helpers: 49-52
- Communication patterns: 53-56

**Checkpoint**
- task2 25-31, 42-56 pass.
- Single-threaded returns `error.ConcurrencyUnavailable` (52).
- Cancel/close separation proven (26, 27, 44, 45).

**Risks / dependencies**
- Open Item 6: only Threaded backend tested. Note thread cost in code + docs.
- Open Item 12: socket/network scenarios (43, 60) need real Io — integration
  tests, gate on platform if needed.

---

### Stage 8 — Mailbox-less Patterns + Cross-Layer

**Purpose**: prove Pool + Io is a complete coordination model without Mailbox.

**What to build**
- Pool + Future, Pool + Select, Pool + Group examples.
- Cross-layer ownership flows and shutdown ordering.

**Scenarios to verify** (task2)
- Cross-layer: 32-41
- Mailbox-less: 57-61

**Checkpoint**
- task2 32-41 and 57-61 pass.
- All 61 task2 scenarios green. All 147 scenarios green.

**Risks / dependencies**
- Scenario 61 documents the transition point (when to add a mailbox).
- Scenario 60 needs real network Io (Open Item 12).

---

### Stage 9 — Docs + README + Autodocs

**Purpose**: each block usable standalone; site published.

**What to build** (tofu docs pipeline)
- `zig build docs` via `getEmittedDocs()` → `docs/`.
- Root `README.md` as a library index: polynode, mbox, pool, with a
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

## Constraints for Next Agent (MUST)
- Git disabled. Do NOT run any git commands.
- Coding style: LE imports, explicit types, explicit dereference, stdlib first.
- Doc style: short sentences, bullets, no AI-sh words. See plan Section 1.
- 4-mode verification: Debug, ReleaseSafe, ReleaseFast, ReleaseSmall.
- Build before test. Debug first.
- AI-sh scan after every stage that changes *.md or *.zig.

## Sources of Truth
- API: matryoshka-api-reference.md
- Zig details: matryoshka-zig-0.16-implementation-guide.md
- Architecture: matryoshka-architecture-foundation-4.md
- Scenarios: task1-scenarios.md (86), task2-scenarios.md (61)
- Legacy mailbox: /home/g41797/dev/root/github.com/g41797/mailbox/
- This file + the plan file.

## Participants
- Owner: g41797 (human)
- Claude: implementation, tests

## Project
Ownership-transfer and lifecycle toolkit for Zig 0.16.
Three blocks: polynode, mbox, pool. Both mbox and pool optional.

## Folder Structure
(see plan, Section 2; update after Stage 0)

## Decisions
- STATUS.md first, updated after every stage.
- Document rules apply to all markdown.
- condition_waitTimeout copied from legacy mailbox (Open Item 5).

## Open Items (carried from collected-context.md)
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
| collected-context.md | Master reference. Paths, 26 proposals, decisions, open items, scenario counts. Read first. |
| matryoshka-api-reference.md | Source of truth. Signatures, types, error sets, cancel contract, ownership lifecycle, contract violations. |
| matryoshka-zig-0.16-implementation-guide.md | Zig how-to. Blocks 1-4, cancellation, Master patterns, rules, comptime opportunities, Odin→Zig appendix. |
| matryoshka-architecture-foundation-4.md | Language-independent architecture. Layers, channels, patterns, rationale. |
| task1-scenarios.md | 86 scenarios, Layers 1-3. The Stage 1-3 test plan. |
| task2-scenarios.md | 61 scenarios, Layer 4 + cross-layer + event sources + mailbox-less. The Stage 5-8 test plan. |
| proposal-26-async-integration.md | Event source adapter design. The Stage 7 spec. |

This plan owns: stage order, folder structure, checkpoints, status tracking.
It does not repeat API, architecture, or scenario detail — those live above.
