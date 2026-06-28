# Matryoshka Zig — Rules

Permanent doc. Not versioned.
All coding, doc, and process rules for the project.
Companion: [matryoshka-model.md](matryoshka-model.md) — the thinking model.

---

## Coding Rules — Tests

What a test must do.
- Check correctness of the implementation.
- Cover one behavior at a time.
- Cover edge cases, error paths, state transitions, contract violations.
- Be structured, reusable, well-named. Same quality as production code.

What a test must not do.
- No throwaway code.
- No story flows. That is the job of examples.

Allocator and io source.
- Tests supply `std.testing.allocator`.
- Tests supply `std.Io`, usually via `std.Io.Threaded.init`.
- Tests set `std.testing.log_level = .debug`.
- Tests use `testing.expect` for verification.

---

## Coding Rules — Examples

Checks.
- Use `helpers.expect(error.XxxFailed, condition, "description")` for invariant checks.
- Works in all build modes, unlike `std.debug.assert` which is removed in ReleaseFast and ReleaseSmall.
- Each example uses its own error name, e.g. `error.BuilderFailed`.

No testing APIs.
- No `std.testing` anything inside example code.
- No `testing.allocator`, no `testing.expect*`, no `testing.log_level`.
- No `std.debug.assert`.
- Use `std.log` for diagnostic output.

Test wrappers live in `tests/`.
- Every example is runnable code.
- A test wrapper calls the example and verifies it.
- Test wrappers supply `std.testing.allocator` and `std.Io`.
- Test wrappers set `std.testing.log_level = .debug`.
- Test wrappers catch errors with `@errorName(err)` for diagnostics.

Scope and shape.
- One pattern. One layer.
- Signature: `pub fn run(allocator: std.mem.Allocator, io: std.Io) !void`.
- ASCII ownership circuit diagram at the top of every example. No diagram = not done.
- Show correct resource cleanup. `errdefer` on error paths, `defer` on all-path cleanup.
- Examples become docs. Leaky examples teach leaky habits.
- Reference model: tofu `recipes/cookbook.zig`.

---

## Coding Rules — Stories

- Signature: `pub fn run(allocator: std.mem.Allocator, io: std.Io) !void`.
- Must show multiple layers composing into a real flow.
- ASCII ownership circuit diagram at the top of the file.
- Test wrapper in single `tests/stories_test.zig`, using `std.Io.Threaded.init`.
- SPDX header required if placed under `src/`-style ownership; owner adds SPDX headers.

---

## Coding Standards

Import order (LE style).
- Package and local imports first.
- `const std = @import("std")` always last.
- "LE" means Local-first, External last.
- Do NOT flag std-last as a violation.

```zig
const polynode = @import("polynode.zig");
const cond_timeout = @import("internal/cond_timeout.zig");
const std = @import("std");
```

SPDX headers.
- Required in all `src/` files.
- Owner-added. Never remove them during edits.
- Do not add SPDX headers to new `src/` files. Owner will add them.

Layer terminology.
- Use "layer" not "block" everywhere — docs, tests, examples, directories.
- Exception: Odin reference paths (`block1/`, `block2/`) are quoted literals naming Odin's own directories.

General Zig style.
- Explicit typing: `const x: T = ...` where the type is known.
- Explicit dereference: `ptr.*.field`.
- Check the standard library before adding custom definitions.
- `errdefer` after every `alloc.create` or resource-acquiring `try`.
- `defer` for cleanup that must run on all exit paths.

The Slot Rule.
- Never overwrite a non-null slot.
- Always start with `var slot: Slot = null`.
- All acquisition APIs assert `slot.* == null` on entry.
- Transfer clears the slot: `slot.* = null`.
- Cleanup ops (`pool.put`, `PolyHelper.destroy`, `helpers.freeSlot`) are no-ops on null slots.
- Use defer-before-acquisition — safe because cleanup is null-safe.
- Never use `allocator.create` / `allocator.destroy` directly on PolyNode-based user types in examples or tests. Use `PolyHelper.create`, `PolyHelper.destroy`, or `helpers.freeSlot`.

Banned words.
- `drain` — use `clear`, `reset`, `empty`, or a domain verb. Example: `clearList` not `drainList`.
- `dll` / `DLL` — clashes with Windows DLL. Use `List.Node`, `list_node_ptr`, or spell out `DoublyLinkedList`.
- "commit" when meaning save/update/write — implies git, which is owner-only. Say "save", "update", or "write".
- AI-sh word list: robust, seamlessly, comprehensive, leverage, efficient, powerful, facilitate, utilize, ensure, performant, ergonomic, idiomatic, streamline, orchestrate, sophisticated, intuitive, scalable, unlock, empower, harness, deliver, fed, arm, leg, idempotent, fires, faces.
- Scan `.zig` and `.md` after any stage that changes them. Report hits to owner. Do not fix without approval.

---

## Comment and Doc Comment Rules

- Short intro line, then bullets. Staccato rhythm.
- One fact per bullet.
- No prose paragraphs with comma-separated lists.
- No dense multi-fact sentences.
- Do not explain WHAT — names do that.
- Explain WHY only if non-obvious.
- No multi-paragraph docstrings.
- No "used by X" / "added for Y flow" comments.
- No `///` doc comments in `src/`.

---

## Documentation Rules

- Simple English. Short sentences. Bullets over long sentences.
- Story narrative uses the 4-part structure: arch dialogue → SRS → matryoshka translation → flow diagram.
- Diagrams are ASCII, human-readable, not space-optimized.
- Do not save space in files. Clarity over brevity.
- Cross-reference instead of duplicating. Link to `matryoshka-model.md` and `rules.md`.
- When appending to a doc, match the heading levels already in use.

---

## Process / Workflow Rules

Auto-mode.
- No git. All git operations go through the owner.
- No file deletions - ask owner.

Per-stage finish checklist.
1. `kitchen/build_and_test_debug.sh` — quick build + Debug test.
2. `kitchen/build_and_test_all.sh` — full build + all 4 optimization modes.
3. `kitchen/build_cross_debug.sh` — cross-compile Debug for mac + windows.
4. Post-stage cleanup: revise code for obsolete parts, wrong comments, repeated code that can be extracted.
5. Re-run all three kitchen scripts after cleanup.
6. AI-sh + banned words scan over changed `*.md` and `*.zig`. Report to owner.
7. Update `design/STATUS.md` Session Log. Include a "Post-stage cleanup" row. Absence of that row means the rule was skipped.
8. Sync `README.md` and any touched per-module README.

Kitchen script order.
- `build_and_test_debug.sh` → `build_and_test_all.sh` → `build_cross_debug.sh`.
- Build before test. `zig build` must pass before `zig build test`.
- Full verification = all 4 optimization modes: Debug, ReleaseSafe, ReleaseFast, ReleaseSmall.
- A stage is complete only when all 4 modes pass.
- Redirect build/test output to `zig-out/` log files. Analyze via files, not shell stdout.

New plan version vs update.
- Create a new plan version after each completed stage or INTR.
- Plans are new versions of `design/matryoshka-zig-implementation-plan-NNN.md`, not separate files.
- Collapse done stages to one-line summaries. Keep active and future stages in full detail.
- Old plan versions stay as historical record. Do not delete them.

Document versioning.
- Never overwrite an important design doc. New file with incremented suffix.
- Doc link rule: after creating any new doc version, update all cross-references to the old version in every other doc. No exception. Owner never does this manually.
- `design/context.md` is the stable entry point.

Stage discipline.
- Read `design/STATUS.md` Session Log first.
- Show intent before code. Owner approves before code is written.
- Plan approval is NOT code change approval. Each fix needs its own approval.
- One stage at a time. No skipping. Each stage passes before the next.
- No real code before infrastructure (Stage 0) is verified.
- Tests before examples. Stage N.a = impl + tests. Stage N.b = examples. No mixing.
- Architectural changes need explicit owner approval.

Implementation invariants.
- Source of truth for signatures, types, errors: the current API reference. Wins over all other sources.
- Never send a stack-allocated item. Use `alloc.create` or `pool.get`.
- After transfer (`send`, `put`), `slot.* = null`.
- After `close`, walk the returned list. Free heap items or return pool items.
- `mailbox.close`, `pool.close`, `pool.put`, `pool.put_all` use `lockUncancelable`.
- Never use `std.Thread.Mutex` / `std.Thread.Condition` in `_Mailbox` or `_Pool`.
- `error.Canceled` is never remapped to `error.Closed`.
- `condition_waitTimeout` is a private helper copied from the legacy mailbox (codeberg/zig#31278).

`std.DoublyLinkedList` and `polynode.reset`.
- `std.DoublyLinkedList` does nothing for node safety. Any removal (`remove`, `pop`, `popFirst`, or any variant) does NOT zero `prev`/`next` on the removed node.
- After any list removal, the node's `prev`/`next` still point into the old list. `polynode.is_linked` returns true. `polynode.destroy` will assert-fail.
- Rule: call `polynode.reset(poly)` immediately after any list removal, before any `PolyHelper.destroy` call.
- This applies everywhere: `on_close` hooks, mailbox close walks, pool close walks, any custom list traversal.
- The list provides no safety net. The developer is solely responsible.
