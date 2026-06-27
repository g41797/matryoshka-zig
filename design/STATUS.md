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
- Plan versioning: after each completed stage, create new plan version. Collapse done stages to one-line summaries. Update context.md and STATUS.md to point to new version.
- Tests before examples: examples cannot start until all tests pass all kitchen scripts. Stage N.a = impl + tests, Stage N.b = examples. No mixing.

## Constraints for Next Agent (MUST)
- Git disabled. Do NOT run any git commands.
- Coding style: LE imports, explicit types, explicit dereference, stdlib first, errdefer/defer for resource cleanup.
- Doc style: short sentences, bullets, no AI-sh words. See plan Section 1.
- Run verification via kitchen scripts, not manual zig commands.
- AI-sh scan after every stage that changes *.md or *.zig.

## Sources of Truth
- API: matryoshka-api-reference-012.md
- Zig details: matryoshka-zig-0.16-implementation-guide-001.md
- Architecture: matryoshka-architecture-foundation-4-001.md
- Architecture introduction: matryoshka-architecture-001.md
- Tests: task1-tests-001.md, task2-tests-001.md
- Examples: task1-examples-001.md, task2-examples-001.md
- Scenarios (historical): task1-scenarios-001.md (92), task2-scenarios-001.md (61)
- Legacy mailbox: /home/g41797/dev/root/github.com/g41797/mailbox/
- Odin proto: /home/g41797/dev/root/github.com/g41797/matryoshka/
- tofu (build infra): /home/g41797/dev/root/github.com/g41797/tofu/
- Plan: matryoshka-zig-implementation-plan-013.md

## Participants
- Owner(g41797-human): design, decision-making
- Claude: implementation, tests

## Project
Ownership-transfer and lifecycle toolkit for Zig 0.16.
Three layers: polynode, mailbox, pool. Both mailbox and pool optional.

## Folder Structure
```
matryoshka-zig/
├── build.zig
├── build.zig.zon
├── README.md
├── src/
│   ├── matryoshka.zig
│   ├── polynode.zig
│   ├── mailbox.zig
│   ├── pool.zig
│   └── internal/
│       └── cond_timeout.zig
├── tests/
│   └── matryoshka_tests.zig
├── kitchen/
│   ├── build_and_test_debug.sh
│   ├── build_and_test_all.sh
│   └── build_cross_debug.sh
└── design/
    ├── STATUS.md
    └── *.md
```

## Decisions
- STATUS.md first, updated after every stage.
- Document rules apply to all markdown.
- condition_waitTimeout copied from legacy mailbox (Open Item 5).
- Tests check implementation. Examples show stories and stress-test.
- Examples have test wrappers. Examples come after tested code.
- Scenarios re-partitioned into tests + examples (Stage 0.5).
- Helper code (NodeMixin, Event, Sensor) developed in same stage as the code it supports.

## Open Items (carried from collected-context-001.md)
- 5  condition_waitTimeout workaround
- 6  Io.Evented backend not tested
- 10 which Layer 2-3 examples need real threads
- 11 panic test style in Zig
- 12 real-Io examples are integration tests, gate by platform

## Stages
Stage 0 — Infrastructure. DONE.
Stage 0.5 — Re-partition scenarios. DONE.
Stage 1.a — PolyNode (impl + tests). DONE.
Stage 1.b — PolyNode examples. DONE.
Stage 2.a — Mailbox (impl + tests). DONE.
Stage 2.b — Mailbox examples. DONE.
Stage 2.5 — Pre-Stage-3 fixes. DONE.
Stage 3 — Pool (impl + tests + examples). DONE.
Stage 4 — DONE (97/97 tests).
Stage 5.a — DONE (99/99 tests).
Stage 5.b — DONE (107/107 tests).
INTR 1 — DONE (107/107 tests). Plan version 011 created.
Stage 6 — DONE (121/121 tests). Plan version 013 created.
Current: Stage 6 complete. Cancellation + Shutdown tests done (14 tests, scenarios 3-16).
Next: Stage 7 — Select + Future APIs. Show intent first.

## Session Log

### 2026-06-27 — Session 16 (Stage 6 — Cancellation + Shutdown)
**Participants**: human + Claude

**Summary**
Stage 6 complete. 14 new tests (scenarios 3-16) in `tests/layer4_cancel.zig`.

Coverage:
- Scenarios 3-4: `Future.cancel` and `Group.cancel` stop blocked workers.
- Scenario 5: cancel deferred past `pool.put` (lockUncancelable); item not lost.
- Scenario 6: broadcast shutdown via `mailbox.close` before join.
- Scenario 7: cancel-first shutdown; pool and mailbox closed after worker exits.
- Scenario 8: `pool.put` on closed pool; slot stays non-null; caller frees via defer.
- Scenario 9: `mailbox.close` returns remaining items; verified 7 of 10.
- Scenario 10: `pool.close` calls `on_close` with all 5 items.
- Scenario 11: `error.Canceled` vs `error.Closed` in `mailbox.receive` (distinct).
- Scenario 12: `error.Canceled` vs `error.Closed` in `pool.get_wait` (distinct).
- Scenario 13: `pool.put` cancel-protected; `recancel()` + defer put succeeds.
- Scenario 14: `mailbox.close` uses `lockUncancelable`; completes despite re-armed cancel.
- Scenario 15: `recancel()` propagation — second `receive` also gets `error.Canceled`.
- Scenario 16: `io.checkCancel()` in CPU-bound loop fires on cancel.

**Fix during verification**: test 14 had a race — 3 items pre-loaded in the listen mailbox let the worker receive before cancel fired. Fixed by using two mailboxes: `mbh_listen` (always empty, guarantees block) and `mbh_data` (pre-loaded; closed by worker on cancel).

**Changes**
- `tests/layer4_cancel.zig` — new file: 14 tests (scenarios 3-16)
- `tests/matryoshka_tests.zig` — added `@import("layer4_cancel.zig")`

**Verification**

| Check | Result |
| :---- | :----- |
| `kitchen/build_and_test_debug.sh` | pass (121/121 tests) |
| `kitchen/build_and_test_all.sh` | pass (121/121 tests, all 4 modes) |
| `kitchen/build_cross_debug.sh` | pass (mac x86_64, mac aarch64, windows x86_64) |
| Post-stage cleanup | nothing to clean — no obsolete parts, no repeated code |
| AI-sh + banned words scan | clean |
| Plan version 013 | created `design/matryoshka-zig-implementation-plan-013.md` |
| context.md | plan → 013 |
| STATUS.md | sources → 013; stages line updated |

**Next**: Stage 7 — Select + Future APIs. Show intent first.

### 2026-06-27 — Session 15 (doc update: PolyHelper.create/destroy rule)
**Participants**: human + Claude

**Summary**
Doc-only update. No code changes. No kitchen scripts.

Added `### No raw allocator calls on PolyNode-based types` rule to `## Cooperative cleanup patterns` in api-reference-012.md. Same rule as one bullet in `### Implementation (MUST)` in plan-012.md. Collapsed INTR 1.d to one-line summary in plan-012.md.

**Changes**
- `design/matryoshka-api-reference-012.md` — new version; rule + violation/correct/exempt + change log + manifest
- `design/matryoshka-zig-implementation-plan-012.md` — new version; Implementation MUST bullet added; INTR 1.d collapsed
- `design/context.md` — api-ref → 012, plan → 012
- `design/STATUS.md` — sources → 012; this entry

**Verification**

| Check | Result |
| :---- | :----- |
| Kitchen scripts | not run — doc-only stage |
| Post-stage cleanup | doc-only — no code to clean |
| AI-sh + banned words scan | pending — see below |

**AI-sh scan** (new .md content):
- No hits found in added sections.

**Next**: Audit all `.zig` files in `examples/` and `tests/` for violations of rules. List every file and line. No fixes.

### 2026-06-27 — Session 14 (post-INTR audit + fixes)
**Participants**: human + Claude

**Summary**
Full source audit (`.zig` + `.md`) and comprehensive fix pass. All four findings applied.

**Allocator audit + bug fixes**
- `examples/layer2/worker_loop.zig` — `defer mailbox.destroy` → `defer { close + freeList + destroy }`; added `errdefer alloc.destroy(ev/sn)` in sender loops.
- `examples/layer2/fan_in.zig` — same `defer { close + freeList + destroy }` fix; removed redundant explicit close+freeList.
- `examples/layer2/oob_signal.zig` — `var out: Slot` → `var slot`; `defer helpers.freeSlot`; `helpers.freeSlot` per branch.
- `examples/layer4/pipeline_masters.zig` — `errdefer ctx.alloc.destroy(ev/cmd)` in producer loops.
- `examples/layer4/request_response.zig` — `errdefer ctx.alloc.destroy(ev)` in masterAFn; `errdefer ctx.alloc.destroy(sn)` in masterBFn.

**Doc fixes (active docs only)**
- `design/matryoshka-api-reference-012.md` — `DLL.Node` → `List.Node`; `dll_node_ptr` → `list_node_ptr` (6 occurrences).
- `design/matryoshka-api-reference-010.md` — same DLL fixes.
- `design/matryoshka-zig-implementation-plan-011.md` — LE import order rule clarified (std last); Naming and Terminology section added (banned: `drain`, `dll`/`DLL`).
- `design/collected-context-003.md` — `"block deepdives"` → `"layer deepdives"`.
- `design/STATUS.md` — `Three blocks` → `Three layers` in Project section.

**Audit findings fixed**

1. **Import order** (37 files) — moved `const std = @import("std")` to last among `@import` calls.
   - All 5 layer1 examples.
   - All 10 layer2 examples (including blank-line variants: batch_processing, shutdown_exit).
   - All 4 layer3 examples.
   - All 10 layer4 examples.
   - `helpers/helpers.zig`.
   - 8 test files (layer1_examples, layer2_examples, layer3_examples, layer4_examples, layer1_polynode, layer2_mailbox, layer3_pool, layer4_infra, layer4_master).

2. **Multi-line file-header WHAT-comments** (2 files) — removed.
   - `examples/layer4/pipeline_masters.zig` — 7-line pipeline description removed.
   - `examples/layer4/request_response.zig` — 3-line master A/B description removed.

3. **Inline WHAT-comments** (8 files) — removed.
   - `examples/layer2/request_response.zig` — 3 defer-mechanism comments.
   - `examples/layer4/master_with_pool.zig` — "Seed mailbox:" and "On send success:" comments.
   - `examples/layer4/multi_source_mailbox.zig` — "defer fires:" comment.
   - `examples/layer4/timer_via_mailbox.zig` — "defer fires:" comment.
   - `examples/layer4/pipeline_masters.zig` — slot-state explanation comments in transformerFn.
   - `examples/layer2/fan_in.zig` — "All senders done." comment.
   - `examples/layer3/basic_recycler.zig` — "First get:", "Second get:", "Free item" comments.

4. **Multi-line WHY comment blocks** (2 test files) — condensed to single lines.
   - `tests/layer2_mailbox.zig` — Scenario 49 block; OOB counter invariant block.
   - `tests/layer3_pool.zig` — capped pool block; hooks-outside-lock block; Scenario 88 block; 2-node list block.

**AI-sh + banned word scan**
- Found `drain` in `tests/layer3_pool.zig:519` comment — removed.

**Verification**

| Check | Result |
| :---- | :----- |
| `kitchen/build_and_test_debug.sh` | pass (107/107 tests) |
| Post-stage cleanup | import order + comment cleanup |
| AI-sh + banned words scan | clean |

**Next**: Stage 6 — Cancellation + Shutdown. Show intent first.

### 2026-06-27 — Session 13 (INTR 1.d)
**Participants**: human + Claude

**Summary**
INTR 1.d — slot-based cleanup patterns applied to all remaining layers (layer1, layer2, layer4).

**Layer 1**
- `examples/layer1/ownership_transfer.zig` — rewritten with `PolyHelper.create/destroy` + `freeSlot`. Removed errdefer/list dangling-node risk.

**Layer 2 (all 5 files)**
- `examples/layer2/simple_send_receive.zig` — scoped sender/receiver blocks; defer freeSlot.
- `examples/layer2/worker_loop.zig` — `out` → `slot`; defer freeSlot; removed manual destroys.
- `examples/layer2/request_response.zig` — rewritten; defer freeSlot; send via `&slot` directly.
- `examples/layer2/fan_out.zig` — `out` → `slot`; defer freeSlot; removed freeItem call.
- `examples/layer2/shutdown_exit.zig` — `out` → `slot`; defer freeSlot; removed per-type destroys; `|_|` for ShutdownCommand.

**Layer 4 (9 files)**
- `examples/layer4/minimal_master.zig` — defer freeSlot; removed manual freeItem call.
- `examples/layer4/master_with_pool.zig` — workerFn: defer pool.put; seed loop: defer pool.put before pool.get (bug fix — item leaked on send failure).
- `examples/layer4/multi_worker_master.zig` — defer freeSlot; removed manual freeItem.
- `examples/layer4/pipeline_masters.zig` — transformerFn: defer freeSlot; explicit freeSlot in Event branch before creating sn; send via `&slot` for ShutdownCommand forward. consumerFn: defer freeSlot; freeSlot per branch.
- `examples/layer4/timer_via_mailbox.zig` — workerFn: defer freeSlot; `|_|` for Timer; removed per-type destroys.
- `examples/layer4/mailbox_as_item.zig` — workerFn: defer freeSlot; freeSlot before ShutdownCommand forward. main: `received` → `slot`; defer close+destroy guard; `slot = null` after manual cleanup.
- `examples/layer4/oob_signal.zig` — for loop: defer freeSlot; `|_|` for ShutdownCommand; freeSlot per branch (bug fix — item leaked if helpers.expect returned error before destroy).
- `examples/layer4/multi_source_mailbox.zig` — workerFn: defer freeSlot; `|_|` for Timer and ShutdownCommand; removed per-type destroys.
- `examples/layer4/request_response.zig` — masterAFn: `resp_slot` → `slot`; defer freeSlot; freeSlot per branch. masterBFn: `req_slot` → `slot`; defer freeSlot; errdefer for sn allocation; freeSlot per branch.

**helpers/helpers.zig**
- Added `freeSlot(slot: *Slot, alloc: Allocator)` — null-safe: calls freeItem then sets slot.* = null. Replaces scattered `alloc.destroy + slot = null` sequences.

**Changes**
- `helpers/helpers.zig` — freeSlot added
- `examples/layer1/ownership_transfer.zig` — PolyHelper.create/destroy + freeSlot
- `examples/layer2/simple_send_receive.zig` — scoped blocks + defer freeSlot
- `examples/layer2/worker_loop.zig` — defer freeSlot; removed destroys
- `examples/layer2/request_response.zig` — defer freeSlot; &slot for send
- `examples/layer2/fan_out.zig` — defer freeSlot; removed freeItem
- `examples/layer2/shutdown_exit.zig` — defer freeSlot; |_| for ShutdownCommand
- `examples/layer4/minimal_master.zig` — defer freeSlot
- `examples/layer4/master_with_pool.zig` — defer pool.put (workerFn + seed loop bug fix)
- `examples/layer4/multi_worker_master.zig` — defer freeSlot
- `examples/layer4/pipeline_masters.zig` — defer freeSlot; explicit freeSlot in Event branch; &slot for ShutdownCommand forward
- `examples/layer4/timer_via_mailbox.zig` — defer freeSlot; |_| for Timer
- `examples/layer4/mailbox_as_item.zig` — defer freeSlot; slot rename; defer guard in main
- `examples/layer4/oob_signal.zig` — defer freeSlot; freeSlot per branch; bug fix
- `examples/layer4/multi_source_mailbox.zig` — defer freeSlot; removed per-type destroys
- `examples/layer4/request_response.zig` — defer freeSlot; errdefer for sn; slot renames

**Verification**

| Check | Result |
| :---- | :----- |
| `kitchen/build_and_test_debug.sh` | pass (107/107 tests) |
| `kitchen/build_and_test_all.sh` | pass (107/107 tests, all 4 modes) |
| `kitchen/build_cross_debug.sh` | pass (mac x86_64, mac aarch64, windows x86_64) |
| Post-stage cleanup | retrofit only — no obsolete parts found |
| AI-sh + banned words scan | clean |

**Next**: Stage 6 — Cancellation + Shutdown. Show intent first.

### 2026-06-27 — Session 12 (INTR 1)
**Participants**: human + Claude

**Summary**
INTR 1 — Slot-based programming retrofit (pre-Stage-6).

Three sub-stages completed:

**INTR 1.a** — `design/collected-context-003.md` written.
- Full context for Opus: Stages 4-5 findings, owner API changes, Slot Rule, new idiom patterns, INTR 1 plan.
- `design/context.md` updated to point to collected-context-003.

**INTR 1.b** — `design/matryoshka-api-reference-012.md` written (Opus).
- New section: `## Slot-based programming` — Slot Rule, 3 ASCII diagrams (lifecycle, transfer, defer-safety).
- New section: `## Cooperative cleanup patterns` — 4 patterns with code snippets.
- New subsection: `### PolyHelper — create and destroy` — signatures, old-vs-new, no_create_destroy diagram.
- Updated: `pool.put` null no-op, `PoolHooks` and function signatures.

**INTR 1.c** — Code retrofit + rename (`m` → `slot`) + verification.
- `src/mailbox.zig` — `m` → `slot` in all public signatures and bodies.
- `src/pool.zig` — `m` → `slot` throughout.
- `helpers/helpers.zig` — `createByTag` Sensor branch completed. `destroyByTag` added. Hook ctx types updated.
- `examples/layer3/basic_recycler.zig` — `m` → `slot`, defer-early.
- `examples/layer3/capped_pool.zig` — verified (owner-applied defer-early confirmed).
- `examples/layer3/pool_seeding.zig` — `m` → `slot`, defer-early in both loops.
- `examples/layer3/pool_teardown.zig` — `m` → `slot`, defer-early.
- `design/matryoshka-api-reference-012.md` — `m` → `slot` in all code snippets and signatures.
- `design/matryoshka-zig-implementation-plan-011.md` — new plan version. INTR 1 added as completed. Slot Rule added to Process Rules.
- `design/context.md` — plan reference → 011, api-reference → 011.
- `design/STATUS.md` — Sources of Truth → 011; this entry.

Owner applied before this session:
- `src/polynode.zig` — `PolyHelper(T)` comptime branching on `no_create_destroy`. Added `create` and `destroy`.
- `src/pool.zig` — `pool.put` null-safe: `if (slot.* == null) return`.
- `_Mailbox` and `_Pool` — `const no_create_destroy = void{}` added.
- `examples/layer3/capped_pool.zig` — defer-early patterns applied.

**Changes**
- `design/collected-context-003.md` — new (INTR 1.a)
- `design/matryoshka-api-reference-012.md` — new (INTR 1.b + 1.c rename)
- `design/matryoshka-zig-implementation-plan-011.md` — new plan version
- `design/context.md` — api-ref and plan pointers → 011
- `design/STATUS.md` — sources updated; this entry
- `src/mailbox.zig` — m→slot in signatures and bodies
- `src/pool.zig` — m→slot throughout
- `helpers/helpers.zig` — createByTag completed; destroyByTag added; hook ctx m→slot
- `examples/layer3/basic_recycler.zig` — m→slot, defer-early
- `examples/layer3/pool_seeding.zig` — m→slot, defer-early
- `examples/layer3/pool_teardown.zig` — m→slot, defer-early

**Verification**

| Check | Result |
| :---- | :----- |
| `kitchen/build_and_test_debug.sh` | pass (107/107 tests) |
| `kitchen/build_and_test_all.sh` | pass (107/107 tests, all 4 modes) |
| `kitchen/build_cross_debug.sh` | pass (mac x86_64, mac aarch64, windows x86_64) |
| Post-stage cleanup | nothing to clean — retrofit only, no obsolete parts found |
| AI-sh + banned words scan | clean (false positives only: `mutex.unlock(io)` code, pre-existing comment with "ensure") |
| Plan version 011 | created `design/matryoshka-zig-implementation-plan-011.md` |
| context.md | api-ref → 011, plan → 011 |
| STATUS.md | sources → 011; stages line updated |
| README.md | no sync needed (still WIP) |

**Next**: Stage 6 — Cancellation + Shutdown. Show intent first.

### 2026-06-26 — Session 11
**Participants**: human + Claude

**Summary**
Stage 5.b (Master examples — scenarios 17–24) completed.

8 new example files added under `examples/layer4/`, covering:
- Scenario 17 (minimal_master): `io.concurrent` + `mailbox.close` → stdlib list walk + `fut.await`
- Scenario 18 (master_with_pool): pool-backed recycler + `fut.cancel` for shutdown
- Scenario 19 (multi_worker_master): `Io.Group` + shared mailbox + `mailbox.close` → `group.await`
- Scenario 20 (pipeline_masters): 3 chained workers; ShutdownCommand sentinel propagates downstream
- Scenario 21 (request_response): two workers; bidirectional Event↔Sensor ownership transfer
- Scenario 22 (timer_via_mailbox): timer task + data events → one mailbox; tag dispatch; fixed-count worker
- Scenario 23 (oob_signal): `mailbox.send_oob` queue-front ordering; sequential demo, no concurrency needed
- Scenario 24 (multi_source_mailbox): 3 concurrent senders (timer, events, signal) → one mailbox; close-based shutdown

Key findings during coding:
- `mailbox.receive` returns `error.Closed` immediately when mailbox is closed, even if items remain in queue. "Close as signal" only works if items are fully consumed before close — otherwise use ShutdownCommand sentinel.
- For fixed-count workers (receive exactly N items): safe when N is known and all N will arrive. For unknown count: use close-based loop (`catch return`).
- `helpers.freeItem` extended to handle `Timer` and `ShutdownCommand` (both were absent). `freeList` now correctly frees all four types.
- `Timer` struct + `TimerPolyHelper` added to `helpers/types.zig`.
- AI-sh scan hit: "undelivered" in `minimal_master.zig:39` (substring match on "deliver"). Natural technical vocabulary, not AI-speak. Owner to decide.

**Changes**
- `helpers/types.zig` — added `Timer` struct + `TimerPolyHelper`
- `helpers/helpers.zig` — `freeItem` extended: handles `Timer` and `ShutdownCommand`
- `examples/layer4/minimal_master.zig` — scenario 17
- `examples/layer4/master_with_pool.zig` — scenario 18
- `examples/layer4/multi_worker_master.zig` — scenario 19
- `examples/layer4/pipeline_masters.zig` — scenario 20
- `examples/layer4/request_response.zig` — scenario 21
- `examples/layer4/timer_via_mailbox.zig` — scenario 22
- `examples/layer4/oob_signal.zig` — scenario 23
- `examples/layer4/multi_source_mailbox.zig` — scenario 24
- `examples/layer4/layer4.zig` — added 8 new imports
- `tests/layer4_examples.zig` — added 8 test wrappers (tests 17–24); wrappers 17–24 use `Io.Threaded.init`; wrappers 95–96 keep `global_single_threaded`

**Verification**

| Check | Result |
| :---- | :----- |
| `kitchen/build_and_test_debug.sh` | pass (107/107 tests) |
| `kitchen/build_and_test_all.sh` | pass (107/107 tests, all 4 modes) |
| `kitchen/build_cross_debug.sh` | pass (mac x86_64, mac aarch64, windows x86_64) |
| Post-stage cleanup | nothing to clean — no repeated code, no wrong comments found |
| AI-sh + banned words scan | 1 hit: "undelivered" in minimal_master.zig:39 — natural technical vocabulary, owner to decide |
| Plan version 010 | created `design/matryoshka-zig-implementation-plan-010.md` |
| context.md | plan reference → 010; examples count 21 → 29 |
| STATUS.md | plan reference → 010; stages line updated |
| README.md | no sync needed (still WIP) |

**Next**: Stage 6 — Cancellation + Shutdown. Show intent first.

### 2026-06-26 — Session 10
**Participants**: human + Claude

**Summary**
Stage 5.a (Master — impl + tests) completed.

Two new tests using real `Io.Threaded.init` concurrency (not `global_single_threaded`):
- Scenario 1: single worker via `io.concurrent` + `Future.await`
- Scenario 2: 3-worker group via `Io.Group` + `group.concurrent` + `group.await`

Key finding during coding: `group.concurrent` worker must return exactly `error{Canceled}!void` — no other errors allowed. Worker catches `error.Closed` and `error.Timeout` from `mailbox.receive` internally; only propagates `error.Canceled`.

Pre-stage doc work (Session 9 continuation):
- `design/matryoshka-api-reference-010.md` — new version (api-ref-009 + `### io.concurrent and Io.Group — verified call syntax` subsection).
- `design/context.md`, `design/matryoshka-zig-implementation-plan-009.md`, `design/STATUS.md`, `design/matryoshka-architecture-001.md` — all updated to reference api-reference-010.

**Changes**
- `tests/layer4_master.zig` — new file: 2 tests (scenarios 1-2)
- `tests/matryoshka_tests.zig` — added layer4_master import

**Verification**

| Check | Result |
| :---- | :----- |
| `kitchen/build_and_test_debug.sh` | pass (99/99 tests) |
| `kitchen/build_and_test_all.sh` | pass (99/99 tests, all 4 modes) |
| `kitchen/build_cross_debug.sh` | not yet run — owner handles git/CI |
| Post-stage cleanup | no obsolete parts found |
| AI-sh + banned words scan | clean |

**Next**: Stage 5.b — Master examples. Show intent first.

### 2026-06-26 — Session 9
**Participants**: human + Claude

**Summary**
Stage 4.b (Infra as Items — examples) completed.

Key insight identified and documented before examples: the `tag` field identifies class (type), not instance or role. Infra handles (`_Mailbox`, `_Pool` are private) have no user-visible fields. Instance identity uses pointer comparison; role uses protocol between sender and receiver.

Doc updates:
- `design/matryoshka-api-reference-009.md`: new version with `### Tag identity — class, not instance` subsection. Documents class-vs-instance distinction, infra handle limitation, worker-finish-signal pattern, wrapper pattern for role discrimination via custom tag.
- `design/matryoshka-architecture-001.md`: Step 2 (Tag) updated with the same clarification, pointer to api-reference-009.
- `design/task1-examples-001.md`: added Layer 4 section with scenarios 95 and 96.
- `design/context.md`: api-reference pointer → 009, examples count → 21.

Examples:
- `examples/layer4/mailbox_as_item.zig` — scenario 95: master spawns real thread, worker processes 3 Events + ShutdownCommand, sends worker_mbh back to master's inbox (unclosed) as finish signal, master identifies by tag + pointer, closes+destroys, joins thread.
- `examples/layer4/pool_as_item.zig` — scenario 96: carrier pool holds 2 inner pools as items, `pool.close` triggers `on_close` which walks list and closes+destroys each inner pool (2 collected).
- `examples/layer4/layer4.zig`, `examples/examples.zig`, `tests/layer4_examples.zig`, `tests/matryoshka_tests.zig` updated.

**Changes**
- `design/matryoshka-api-reference-009.md` — new (api-ref-008 + tag identity section)
- `design/matryoshka-architecture-001.md` — Step 2 tag clarification added
- `design/task1-examples-001.md` — Layer 4 section added (scenarios 95-96)
- `design/context.md` — api-ref → 009, examples → 21
- `examples/layer4/mailbox_as_item.zig` — scenario 95
- `examples/layer4/pool_as_item.zig` — scenario 96
- `examples/layer4/layer4.zig` — re-exports
- `examples/examples.zig` — added layer4
- `tests/layer4_examples.zig` — 2 test wrappers (95-96)
- `tests/matryoshka_tests.zig` — added layer4_examples import

**Verification**

| Check | Result |
| :---- | :----- |
| `kitchen/build_and_test_debug.sh` | pass (97/97 tests) |
| `kitchen/build_and_test_all.sh` | pass (97/97 tests, all 4 modes) |
| `kitchen/build_cross_debug.sh` | not yet run — owner handles git/CI |
| Post-stage cleanup | no obsolete parts found |
| AI-sh + banned words scan | clean |

**Next**: Plan version 009. Stage 5 — show intent first.

### 2026-06-26 — Session 8
**Participants**: human + Claude

**Summary**
Stage 3 (Pool) completed across three sub-stages.

Stage 3.a — Pool impl + tests:
- `src/pool.zig`: full Pool implementation. Key design points: per-tag `AutoHashMapUnmanaged` free-lists + counts, CAS for idempotent `close()`, hooks run outside the lock (unlock → hook → relock), `lockUncancelable` for put/put_all/close, `lock(io) catch |err|` for get_wait, `ensureTotalCapacity` before init loop for atomic OOM behavior, O(1) `_concat` for close collection.
- `tests/layer3_pool.zig`: 26 tests (scenarios 63-88). Thread test (scenario 84) uses `Io.Timeout.sleep`.
- `tests/matryoshka_tests.zig`: added layer3_pool import.

Stage 3.a-cleanup (second AI review):
- `src/pool.zig`: added `if (m.*) |h| std.debug.assert(h.*.tag == tag)` after on_get in `_get_available_or_new` and `_get_new_only`. Catches hooks that return wrong-tag items before silent propagation.
- `design/matryoshka-api-reference-008.md`: added on_get always-called semantics note (prepare role, not just create); documented put_all partial-transfer contract on concurrent close.

Stage 3.b — Pool examples:
- `helpers/helpers.zig`: added `createByTag` (tag-dispatch allocator), `AlwaysCreateCtx` (create-or-reuse hooks), `CappedPoolCtx` (capped-size hooks).
- `examples/layer3/basic_recycler.zig` — scenario 89: get/put/get roundtrip, verifies recycled item retains data.
- `examples/layer3/capped_pool.zig` — scenario 90: 3 items seeded into cap-2 pool, on_put destroys excess.
- `examples/layer3/pool_seeding.zig` — scenario 91: seed with new_only, consume all with available_only.
- `examples/layer3/pool_teardown.zig` — scenario 92: close with items held; on_close frees all.
- `examples/layer3/layer3.zig`: re-exports all 4.
- `examples/examples.zig`: added layer3.
- `tests/layer3_examples.zig`: 4 test wrappers (89-92).
- `tests/matryoshka_tests.zig`: added layer3_examples import.

CI fix:
- `examples/layer2/batch_processing.zig`: race condition — main closed the mailbox before the worker thread ran. Fix: added `first_done: std.atomic.Value(bool)` to WorkerCtx; worker sets it after first `receive`; main spins with `Thread.yield()` until true, then calls close.

**Changes**
- `src/pool.zig` — full Pool implementation
- `tests/layer3_pool.zig` — 26 tests (scenarios 63-88)
- `tests/layer3_examples.zig` — 4 test wrappers (scenarios 89-92)
- `tests/matryoshka_tests.zig` — layer3_pool + layer3_examples imports
- `helpers/helpers.zig` — createByTag, AlwaysCreateCtx, CappedPoolCtx
- `examples/layer3/basic_recycler.zig` — scenario 89
- `examples/layer3/capped_pool.zig` — scenario 90
- `examples/layer3/pool_seeding.zig` — scenario 91
- `examples/layer3/pool_teardown.zig` — scenario 92
- `examples/layer3/layer3.zig` — re-exports
- `examples/examples.zig` — added layer3
- `examples/layer2/batch_processing.zig` — atomic flag for CI race fix
- `design/matryoshka-api-reference-008.md` — on_get semantics + put_all partial-transfer

**Verification**

| Check | Result |
| :---- | :----- |
| `kitchen/build_and_test_debug.sh` | pass (90/90 tests) |
| `kitchen/build_and_test_all.sh` | pass (90/90 tests, all 4 modes) |
| `kitchen/build_cross_debug.sh` | not yet run — owner handles git/CI |
| Post-stage cleanup | batch_processing.zig CI race fixed (atomic flag); tag assertion added after on_get |
| AI-sh + banned words scan | not yet run |

**Next**: Stage 4 — Infra as items. Show intent first.

### 2026-06-26 — Session 7
**Participants**: human + Claude

**Summary**
Stage 2.5 (Pre-Stage-3 fixes) completed. Based on architectural review by another AI (pass-1.md, pass-2.md, pass-3.md):
- Rejected ~60% of findings as intentional architecture (NodeHandle aliases, C-style vtable hooks, intrusive-only types, close asymmetry).
- Deferred future-adapter findings to Stage 7.
- Acted on documentation gaps and one real implementation invariant gap.

Stage 2.5a — API reference 008:
- Added pool ownership flow diagram (FREE → IN_FLIGHT → HELD → close cycle).
- Added Ownership invariants section (6 invariants including tag pointer-only comparison).
- Added Cancellation ownership contract section (slot unchanged on error.Canceled).
- Added Thread-safety contract table (per-function concurrency rules).
- Added Complexity guarantees table (O(1) everywhere except close O(n), put_all O(k)).
- Added zero timeout semantics to receive and get_wait descriptions.
- Added multiple waiter fairness note to receive.
- Strengthened hook reentrancy rules in pool Hook discipline.

Stage 2.5b — Mailbox test:
- Close idempotency: already covered by test 34. Nothing added.
- OOB counter invariant: added new test "oob last resets after last oob received, next send_oob goes to front". Tests oob_last reset when oob_count reaches 0; exercises the path where send_oob is called after receiving the only OOB item.

Plan and docs updated:
- `design/matryoshka-api-reference-008.md` — new version.
- `design/matryoshka-zig-implementation-plan-008.md` — new version; Stage 2.5 added; Stage 3 updated with implementation checklist from review.
- `design/context.md` — points to plan-008 and api-reference-008.
- `design/STATUS.md` — this entry.

**Changes**
- `design/matryoshka-api-reference-008.md` — new (based on 007, additions listed above)
- `design/matryoshka-zig-implementation-plan-008.md` — new (Stage 2.5 + Stage 3 checklist)
- `design/context.md` — api-reference and plan pointers updated to 008
- `design/STATUS.md` — API and plan pointers updated; Stage 2.5 added; this entry

**Verification**

| Check | Result |
| :---- | :----- |
| `kitchen/build_and_test_debug.sh` | pass (60/60 tests) |
| `kitchen/build_and_test_all.sh` | pass (60/60 tests, all 4 modes) |
| `kitchen/build_cross_debug.sh` | pass (x86_64-macos, aarch64-macos, x86_64-windows) |
| Post-stage cleanup | nothing to clean — no code refactoring done, doc-only additions |
| AI-sh + banned words scan | clean |

**Next**: Stage 3.a — Pool implementation + tests. Show intent first.

### 2026-06-26 — Session 6
**Participants**: human + Claude

**Summary**
Stage 2.b (Mailbox examples) completed with 59/59 tests passing. Post-stage cleanup:
- `src/mailbox.zig`: added `polynode.reset(poly)` after `popFirst()` in both `receive` and `try_receive` — critical fix for `!is_linked` assert when re-sending received items from multi-element queues.
- `helpers/helpers.zig`: added `freeItem` (tag-dispatch free for Event+Sensor) and `freeList` (walk + freeItem each node).
- `tests/layer2_mailbox.zig`: removed local `freeItem` function; added `const freeItem = helpers.freeItem` alias.
- `examples/layer2/`: 10 examples implemented (53-62): simple_send_receive, worker_loop, oob_signal, pipeline, request_response, fan_in, shutdown_cleanup, batch_processing, fan_out, shutdown_exit. Multi-threaded: 54, 56, 57, 58, 61, 62.
- `examples/layer2/shutdown_exit.zig`: local `ShutdownCommand` PolyNode type (not raw sentinel); `ShutdownCommandPolyHelper = polynode.PolyHelper(ShutdownCommand)`.
- `examples/examples.zig`: added layer2.
- `tests/layer2_examples.zig`: 10 test wrappers (tests 53-62).
- `tests/matryoshka_tests.zig`: added layer2_examples import.
- `design/task1-examples-001.md`: renumbered Layer2 examples 50-56 → 53-62; added 60-62; renumbered Layer3 examples 83-86 → 89-92.
- `design/task1-scenarios-001.md`: added examples 60-62; renumbered Layer3 tests 60-85 → 63-88; renumbered Layer3 examples 86-89 → 89-92.
- `design/matryoshka-zig-implementation-plan-007.md`: new plan version; all stages through 2.b collapsed; Stage 3 uses updated scenario numbers (63-88 tests, 89-92 examples); total 92 task1 / 153 total.
- `design/context.md`: updated plan pointer to plan-007; updated example count to 19.
- `design/STATUS.md`: this entry.

**Changes**
- `src/mailbox.zig` — `polynode.reset(poly)` added in receive + try_receive after popFirst
- `helpers/helpers.zig` — added freeItem and freeList
- `tests/layer2_mailbox.zig` — local freeItem removed; const freeItem = helpers.freeItem alias added
- `examples/layer2/simple_send_receive.zig` — scenario 53
- `examples/layer2/worker_loop.zig` — scenario 54
- `examples/layer2/oob_signal.zig` — scenario 55
- `examples/layer2/pipeline.zig` — scenario 56
- `examples/layer2/request_response.zig` — scenario 57
- `examples/layer2/fan_in.zig` — scenario 58
- `examples/layer2/shutdown_cleanup.zig` — scenario 59
- `examples/layer2/batch_processing.zig` — scenario 60
- `examples/layer2/fan_out.zig` — scenario 61
- `examples/layer2/shutdown_exit.zig` — scenario 62
- `examples/layer2/layer2.zig` — re-exports all 10
- `examples/examples.zig` — added layer2
- `tests/layer2_examples.zig` — 10 test wrappers
- `tests/matryoshka_tests.zig` — imports layer2_examples
- `design/task1-examples-001.md` — renumbered Layer2+Layer3 examples
- `design/task1-scenarios-001.md` — added 60-62; renumbered Layer3
- `design/matryoshka-zig-implementation-plan-007.md` — new plan version
- `design/context.md` — plan + example count updated
- `design/STATUS.md` — this entry

**Verification**

| Check | Result |
| :---- | :----- |
| `kitchen/build_and_test_debug.sh` | pass (59/59 tests) |
| `kitchen/build_and_test_all.sh` | pass (59/59 tests, all 4 modes) |
| `kitchen/build_cross_debug.sh` | pass (x86_64-macos, aarch64-macos, x86_64-windows) |
| Post-stage cleanup | mailbox.zig polynode.reset fix; helpers freeItem/freeList; layer2_mailbox alias |
| AI-sh + banned words scan | clean |

**Next**: Stage 3 — Pool. Show intent first.

### 2026-06-25 — Session 5
**Participants**: human + Claude

**Summary**
Stage 2.a (Mailbox impl + tests) completed with all 46 tests passing. Post-stage cleanup:
- `src/mailbox.zig`: removed `///` doc comments; replaced manual tag management with `MailboxPolyHelper = polynode.PolyHelper(_Mailbox)`; renamed `dll_node` → `node`.
- `helpers/helpers.zig`: added `pub fn clearList` (replaces banned "drain" pattern).
- `tests/layer2_mailbox.zig`: replaced local `drainList` with `helpers.clearList`; removed WHAT inline comments; added 3 multi-threaded scenarios (50 fan-in, 51 fan-out, 52 combined); added `Sensor`/`SensorPolyHelper` imports; added `freeItem` tag-dispatch helper.
- `design/task1-scenarios-001.md`: added multi-threaded test descriptions (50–52); renumbered Layer 2 examples 53–59 and Layer 3 60–89; corrected stale note about `popFirst` link clearing.
- Created `design/matryoshka-zig-implementation-plan-006.md`.
- Updated `design/context.md`.

**Changes**
- `src/mailbox.zig` — PolyHelper(_Mailbox) replaces manual tag; `node` replaces `dll_node`; no doc comments
- `helpers/helpers.zig` — added `clearList`
- `tests/layer2_mailbox.zig` — clearList, no WHAT comments, scenarios 50/51/52, freeItem helper
- `design/task1-scenarios-001.md` — scenarios 50–52 added; renumbered 53–89
- `design/matryoshka-zig-implementation-plan-006.md` — new plan version
- `design/context.md` — updated plan pointer
- `design/STATUS.md` — this entry

**Verification**

| Check | Result |
| :---- | :----- |
| `kitchen/build_and_test_debug.sh` | pass (49/49 tests) |
| `kitchen/build_and_test_all.sh` | pass (49/49 tests, all 4 modes) |
| `kitchen/build_cross_debug.sh` | pass (x86_64-macos, aarch64-macos, x86_64-windows) |
| Post-stage cleanup | done |
| AI-sh + banned words scan | clean |

**Next**: Stage 2.b — Mailbox examples. Show intent first.

### 2026-06-25 — Session 4
**Participants**: human + Claude

**Summary**
Stage 1.b: renamed NodeMixin → PolyHelper (bad name, not in API ref). Created API ref -007 with PolyHelper documentation and naming convention (XxxPoly = polynode.PolyHelper(Xxx)). Created 5 Layer 1 examples with test wrappers. Wired examples module in build.zig via createModule. Added SPDX preservation rule.

**Changes**
- `src/polynode.zig` — NodeMixin → PolyHelper, validateNodeType → validatePolyType
- `helpers/helpers.zig` — EventNode → EventPoly, SensorNode → SensorPoly
- `tests/layer1_polynode.zig` — updated all EventNode/SensorNode references
- `examples/examples.zig` — new file, example root
- `examples/block1/block1.zig` — new file, re-exports 5 examples
- `examples/block1/define_type.zig` — scenario 21
- `examples/block1/ownership_transfer.zig` — scenario 22
- `examples/block1/tag_dispatch.zig` — scenario 23
- `examples/block1/builder.zig` — scenario 24
- `examples/block1/produce_consume.zig` — scenario 25
- `tests/layer1_examples.zig` — new file, 5 test wrappers
- `tests/matryoshka_tests.zig` — imports layer1_examples
- `build.zig` — added emod (examples) via createModule, wired to tmod
- `design/matryoshka-api-reference-007.md` — new version, added PolyHelper section
- `design/context.md` — added API ref -007 pointer
- `design/matryoshka-zig-implementation-plan-003.md` — updated API ref references to -007

**Verification**

| Check | Result |
| :---- | :----- |
| `kitchen/build_and_test_debug.sh` | pass (22/22 tests) |
| `kitchen/build_and_test_all.sh` | pass (22/22 tests, all 4 modes) |
| `kitchen/build_cross_debug.sh` | pass (x86_64-macos, aarch64-macos, x86_64-windows) |
| Post-stage cleanup | no issues found |
| AI-sh scan | clean |

**Next**: Stage 2 — Mailbox. Show intent first.

### 2026-06-25 — Session 1
**Participants**: human + Claude

**Summary**
Created Stage 0 infrastructure. build.zig adapted from mailbox repo. Stub source files for polynode, mailbox, pool. condition_waitTimeout copied from legacy mailbox into src/internal/cond_timeout.zig with explicit types (LE import style). One test verifies module loads. Kitchen scripts for build/test/cross-compile.

**Changes**
- `build.zig` — module "matryoshka", test step, test module imports matryoshka
- `build.zig.zon` — name matryoshka, version 0.0.1, min zig 0.16.0
- `src/matryoshka.zig` — re-exports polynode, mailbox, pool
- `src/polynode.zig` — empty stub
- `src/mailbox.zig` — empty stub
- `src/pool.zig` — empty stub
- `src/internal/cond_timeout.zig` — condition_waitTimeout from legacy mailbox
- `tests/matryoshka_tests.zig` — one test: module loads
- `kitchen/build_and_test_debug.sh` — build + test Debug only
- `kitchen/build_and_test_all.sh` — build + test all 4 modes
- `kitchen/build_cross_debug.sh` — cross-compile Debug for mac + windows
- `design/STATUS.md` — this file

**Verification**

| Check | Result |
| :---- | :----- |
| `zig version` | 0.16.0 |
| `kitchen/build_and_test_debug.sh` | pass |
| `kitchen/build_and_test_all.sh` | pass |
| `kitchen/build_cross_debug.sh` | pass (x86_64-macos, aarch64-macos, x86_64-windows) |

**Next**: Stage 0.5 — Re-partition scenarios into test and example docs.

### 2026-06-25 — Session 3
**Participants**: human + Claude

**Summary**
Stage 1.a: implemented PolyNode ownership atom and Layer 1 tests. Types: PolyTag, PolyNode, NodeHandle, Slot, reset, is_linked, NodeMixin. Helper types (Event, Sensor) in new helpers/ module. Tests cover scenarios 1-14, 17. Discovered DoublyLinkedList does no safety checks — is_linked only detects multi-element membership. Added rules: tests before examples (N.a/N.b split), plan versioning, post-stage cleanup. Switched tmod to createModule (private, not exported).

**Changes**
- `src/polynode.zig` — PolyTag, PolyNode, NodeHandle, Slot, reset, is_linked, NodeMixin, validateNodeType
- `helpers/helpers.zig` — new file: Event, Sensor, EventNode, SensorNode
- `tests/layer1_polynode.zig` — new file: 16 tests (scenarios 1-14, 17)
- `tests/matryoshka_tests.zig` — imports layer1_polynode
- `build.zig` — helpers module via createModule, tmod switched from addModule to createModule
- `design/matryoshka-zig-implementation-plan-003.md` — added helpers/ to folder structure, tests-before-examples rule (N.a/N.b), plan versioning rule, post-stage cleanup rule
- `design/STATUS.md` — rules updated, session logged

**Verification**

| Check | Result |
| :---- | :----- |
| `kitchen/build_and_test_debug.sh` | pass (17/17 tests) |
| `kitchen/build_and_test_all.sh` | pass (17/17 tests, all 4 modes) |
| `kitchen/build_cross_debug.sh` | pass (x86_64-macos, aarch64-macos, x86_64-windows) |
| Post-stage cleanup | LE import order fixed in layer1_polynode.zig and matryoshka_tests.zig. Re-run: all pass |
| AI-sh scan | clean (only hits are the word list itself and literal "delivered") |

**Deferred**
- Scenarios 15-16: panic tests — no std.testing panic support in Zig 0.16 (Open Item 11)
- Scenarios 18-20: need mailbox/pool (Stage 2-3)

**Next**: Stage 1.b — PolyNode examples. Show intent first.

### 2026-06-25 — Session 2
**Participants**: human + Claude

**Summary**
Stage 0.5: re-partitioned scenarios from task1-scenarios-001.md (86) and task2-scenarios-001.md (61) into four docs. Tests and examples separated by job: tests check correctness, examples show stories. Scenario numbers preserved. Updated context.md with pointers to all four new docs.

**Changes**
- `design/task1-tests-001.md` — 62 test scenarios for Layers 1-3
- `design/task1-examples-001.md` — 12 example scenarios for Layers 1-3
- `design/task2-tests-001.md` — 23 test scenarios for Layer 4 + cross-layer
- `design/task2-examples-001.md` — 38 example scenarios for Layer 4 + cross-layer
- `design/context.md` — added pointers to all four new docs + historical sources

**Verification**
Docs-only stage. No code changes, no kitchen scripts needed.

**Next**: Stage 1 — PolyNode. Show intent first.
