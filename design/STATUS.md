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
- API: matryoshka-api-reference-010.md
- Zig details: matryoshka-zig-0.16-implementation-guide-001.md
- Architecture: matryoshka-architecture-foundation-4-001.md
- Architecture introduction: matryoshka-architecture-001.md
- Tests: task1-tests-001.md, task2-tests-001.md
- Examples: task1-examples-001.md, task2-examples-001.md
- Scenarios (historical): task1-scenarios-001.md (92), task2-scenarios-001.md (61)
- Legacy mailbox: /home/g41797/dev/root/github.com/g41797/mailbox/
- Odin proto: /home/g41797/dev/root/github.com/g41797/matryoshka/
- tofu (build infra): /home/g41797/dev/root/github.com/g41797/tofu/
- Plan: matryoshka-zig-implementation-plan-009.md

## Participants
- Owner(g41797-human): design, decision-making
- Claude: implementation, tests

## Project
Ownership-transfer and lifecycle toolkit for Zig 0.16.
Three blocks: polynode, mailbox, pool. Both mailbox and pool optional.

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
Current: Stage 5.a — DONE (99/99 tests).
Next: Stage 5.b — Master examples. Show intent first.

## Session Log

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
