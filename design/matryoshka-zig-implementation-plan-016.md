# Matryoshka Zig 0.16 — Staged Implementation Plan (016)

Plan document only. No code here.
The specs are already written. This document tells the implementer how to
build from them, in what order, and how to know each step is done.

- New repo: `matryoshka-zig`. Module name: `matryoshka`.
- Zig 0.16.0. Target backend: `Io.Threaded`.
- 153 scenarios are the test plan: 92 in task1, 61 in task2.
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

- `matryoshka-api-reference-014.md` — **primary source of truth**: signatures, types, error sets, cancel contract, ownership lifecycle, contract violations, PolyHelper (create/destroy/no_create_destroy), slot-based programming, cooperative cleanup patterns, tag identity, infra transport patterns, io.concurrent and Io.Group verified call syntax, receiveResult/getWaitResult/receive_future/get_wait_future. Wins over all other sources on any conflict.
- `matryoshka-architecture-001.md` — why, concepts, flows
- `matryoshka-architecture-foundation-4-001.md` — language-independent architecture
- `matryoshka-zig-0.16-implementation-guide-001.md` — **OLD, do not trust directly**. Useful only as a hint for Zig-specific patterns (struct layout, condition_waitTimeout, cancel mechanics). Every signature, type, error set, and assert from this file must be verified against `matryoshka-api-reference-014.md` before use.
- `collected-context-003.md` — master reference, proposals, decisions
- `task1-scenarios-001.md` — 92 scenarios (Layers 1-3) — historical source
- `task2-scenarios-001.md` — 61 scenarios (Layer 4+) — historical source
- `context.md` — entry point

---

## 1. Process Rules

### Strong notice - don't remove

These rules are writen in blood. Follow them

### Behaviour (MUST)
- Read `design/STATUS.md` Session Log first. It says where we are and what is next.
- Show intent before execution. Owner approves before code is written.
- One stage at a time. Do not skip stages. Each stage must pass before the next starts.
- Do not write real code before the build/test infrastructure is verified (Stage 0).
- Iterative: build a stage, checkpoint, rethink, then plan the next stage.

### Coding Style (MUST)
- Little-endian imports: imports at the bottom of the file, after the code. Within the import block, package/local imports come first; `const std = @import("std")` is always last.
- Explicit typing: `const x: T = ...` not `const x = ...` where type is known.
- Explicit dereference: `ptr.*.field` for pointer access.
- Standard library: check stdlib before adding custom definitions.
- `errdefer` after every `alloc.create` or `try` that acquires a resource.
- `defer` for cleanup that must run on all exit paths.

### Naming and Terminology (MUST)
- Use "layer" not "block" for the three matryoshka layers (polynode, mailbox, pool). Applies to all `.zig` and `.md` files. Directory paths in the Odin reference (`block1/`, `block2/`) are exceptions — they are quoted literals naming Odin's own directories.
- Banned words in identifiers, comments, and docs (beyond AI-sh list):
  - `drain` — use `clear`, `reset`, `empty`, or a domain verb. Example: `clearList` not `drainList`.
  - `dll` / `DLL` — abbreviation for DoublyLinkedList. Confusing (clash with Windows DLL). Use `List.Node`, `list_node_ptr`, or spell out `DoublyLinkedList`.

### Examples (MUST)
- **ASCII ownership diagram in every example**: Every file under `examples/` must have an ASCII ownership circuit diagram as a comment block at the top of the file. No example is complete without it.
- Format: box-and-arrow, single comment block, no prose.
- Absence of a diagram = example not done.

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
- **Doc link rule**: When creating any new version of any document, automatically update all cross-references to the old version across all other documents. No exception. Owner must never need to do this manually.
- `design/context.md` is the stable entry point — always points to the latest `collected-context-NNN.md`.

### Plan Versioning (MUST)
- After each completed stage, create a new plan version (e.g., plan-015 → plan-016).
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
- Source of truth for signatures, types, errors: `matryoshka-api-reference-014.md`. Wins over all other sources.
- Implementation guide (`matryoshka-zig-0.16-implementation-guide-001.md`) is OLD — verify every detail against the API reference before use.
- Source of truth for architecture: `matryoshka-architecture-foundation-4-001.md`.
- Architecture introduction (why, concepts, flows): `matryoshka-architecture-001.md`.
- Never send a stack-allocated item. Use `alloc.create` or `pool.get`.
- After transfer (`send`, `put`), `slot.* = null`. Ownership invariant.
- After `close`, walk the returned list. Free heap items or return pool items.
- `mailbox.close`, `pool.close`, `pool.put`, `pool.put_all` use `lockUncancelable`.
- Never use `std.Thread.Mutex` / `std.Thread.Condition` in `_Mailbox` or `_Pool`.
- `error.Canceled` is never remapped to `error.Closed`.
- Copy `condition_waitTimeout` from the reference mailbox as a private helper
  for both `_Mailbox` and `_Pool` (Zig has no native `Io.Condition.waitTimeout`,
  issue codeberg/zig#31278).
- Architectural changes need explicit owner approval before implementation.
- Never use `allocator.create` / `allocator.destroy` directly on PolyNode-based user types (Event, Sensor, Timer, ShutdownCommand) in examples or tests. Use `PolyHelper.create`, `PolyHelper.destroy`, or `helpers.freeSlot`. Exempt: infrastructure internals, hook bodies, non-PolyNode structs. See `matryoshka-api-reference-014.md § Cooperative cleanup patterns`.

### Slot Rule (MUST)
- Never overwrite a non-null slot.
- Always start with `var slot: Slot = null`.
- All acquisition APIs assert `slot.* == null` on entry.
- Transfer clears the slot: `slot.* = null`.
- Cleanup operations (`pool.put`, `PolyHelper.destroy`) are no-ops on null slots.
- Use defer-before-acquisition pattern: defer cleanup before acquire — safe because cleanup is null-safe.
- Applies universally: pool get/put, mailbox receive, heap allocation, every combination.

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
- Staccato rhythm.
- No AI-sh words. After any stage that changes `*.md` or `*.zig`, scan for:
  robust, seamlessly, comprehensive, leverage, efficient, powerful, facilitate,
  utilize, ensure, performant, ergonomic, idiomatic, streamline, orchestrate,
  sophisticated, intuitive, scalable, unlock, empower, harness, deliver, drain, fed, arm, leg, idempotent, fires, faces.
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

### Prologue for every stage (MUST)

Before start of every stage ask owner whether he wants audit.
For 'yes' or similar answer:

- read design/STATUS.md and design/context.md
- read matryoshka-api-reference-014.md
- then audit all .zig files in examples/ and tests/ for violations of rules
- List every file and line, do not fix anything

Ask owner how to proceed.

---

## 2. Repo Folder Structure

Pattern borrowed from the tofu and mailbox repos. Housekeeping idea borrowed
from the Odin matryoshka `kitchen/` layout, but kept lighter.

---

## 3. Stages

Build order from the implementation guide:

```text
Stage 0     infrastructure
Stage 0.5   re-partition scenarios into tests + examples
Stage 1     Layer 1  PolyNode
Stage 2     Layer 2  Mailbox        ┐ independent siblings
Stage 3     Layer 3  Pool           ┘ (Pool may start after Stage 1)
Stage 4     Layer 2+3  Infra as items
Stage 5     Layer 4  Master (concurrency)
INTR 1      Slot-based programming retrofit (pre-Stage-6)
Stage 6     Cancellation + shutdown
INTR 2      Thread-safe hooks + multi-thread example (pre-Stage-7)
Stage 7.a   Event sources — implementation (mailbox + pool)
INTR 3      ASCII ownership diagrams retrofit (all existing examples)
Stage 7.b   Event sources — examples (Select / Future)
Stage 8     Mailbox-less patterns + cross-layer
Stage 9     Docs + README + autodocs
```

---

### Stage 0 — Infrastructure. DONE. See Session 1 (2026-06-25).
### Stage 0.5 — Re-partition scenarios. DONE. See Session 2 (2026-06-25).
### Stage 1.a — PolyNode impl + tests. DONE. See Session 3 (2026-06-25).
### Stage 1.b — PolyNode examples. DONE. See Session 4 (2026-06-25).
### Stage 2.a — Mailbox impl + tests. DONE. See Session 5 (2026-06-25).
### Stage 2.b — Mailbox examples. DONE. See Session 6 (2026-06-26).
### Stage 2.5 — Pre-Stage-3 fixes. DONE. See Session 7 (2026-06-26).
### Stage 3 — Layer 3: Pool (impl + tests + examples). DONE. See Session 8 (2026-06-26).
### Stage 4.a — Infra as Items: tests. DONE. See Session 8 (2026-06-26).
### Stage 4.b — Infra as Items: examples. DONE. See Session 9 (2026-06-26).
### Stage 5.a — Master: tests (task2 scenarios 1-2). DONE. See Session 10 (2026-06-26).
### Stage 5.b — Master: examples (task2 scenarios 17-24). DONE. See Session 11 (2026-06-26).
### INTR 1 — Slot-based programming retrofit. DONE. See Sessions 12-13 (2026-06-27). Plan version 012 created.
### Stage 6 — Cancellation + Shutdown (task2 scenarios 3-16). DONE. See Session 16 (2026-06-27). 121/121 tests.
### INTR 2 — Thread-safe hooks + multi-thread example. DONE. See Session 17 (2026-06-28). Plan version 014 created.
### Stage 7.a — Event sources: implementation. DONE. See Session 18 (2026-06-28). 121/121 tests.
### INTR 3 — ASCII ownership diagrams retrofit (all 29 existing examples). DONE. See Session 18 (2026-06-28). 121/121 tests.
### Stage 7.b — Event sources: examples (scenarios 25-31, 42-56). DONE. See Session 19 (2026-06-28). 143/143 tests.

---

### Stage 8 — Mailbox-less Patterns + Cross-Layer

**Purpose**: prove Pool + Io is a complete coordination model without Mailbox.

**Scenarios**: task2 scenarios 32-41, 57-61.

**Checkpoint**
- All Stage 8 test scenarios pass.
- All 153 scenarios green (tests + examples).
- All kitchen scripts pass.

---

### Stage 9 — Docs + README + Autodocs

**Purpose**: each layer usable standalone; site published.

**What to build** (tofu docs pipeline)
- `zig build docs` via `getEmittedDocs()` → `docs/`.
- Root `README.md` as a library index: polynode, mailbox, pool, with a copy-pasteable snippet per layer.
- Final AI-sh scan across all `*.md` and `*.zig`.

---

## 4. Scenario → Stage Map

| Stage | task1 | task2 |
|-------|-------|-------|
| 1 | 1-17, 21-25 | — |
| 2 | 18, 26-62 | — |
| 3 | 19-20, 63-92 | — |
| 4 | 18-20 (re-proves), 93-96 | — |
| 5 | — | 1-2, 17-24 |
| 6 | — | 3-16 |
| 7 | — | 25-31, 42-56 |
| 8 | — | 32-41, 57-61 |

Totals: 94 task1 (Stages 1-4), 61 task2 (Stages 5-8).

---

## 5. Existing Specs Index (what each doc owns)

| Doc | Owns |
|-----|------|
| collected-context-003.md | Master reference. Paths, proposals, decisions, open items, Stages 0-5 + INTR 1 summary. |
| matryoshka-api-reference-014.md | **Primary source of truth.** Signatures, types, error sets, cancel contract, ownership lifecycle, PolyHelper (create/destroy/no_create_destroy), slot-based programming, cooperative cleanup patterns, tag identity, infra transport patterns, thread-safety, complexity, hook concurrency contract, receiveResult/getWaitResult/receive_future/get_wait_future. Wins over all other sources. |
| matryoshka-zig-0.16-implementation-guide-001.md | **OLD — verify all details against API reference before use.** Zig how-to patterns: struct layout, condition_waitTimeout, cancel mechanics, Odin→Zig appendix. |
