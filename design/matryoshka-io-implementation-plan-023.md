# Matryoshka Zig 0.16 — Staged Implementation Plan (023)

Slim plan. State only.
All process and coding rules live in [rules-003.md](rules-003.md). Not repeated here.

- Repo: `matryoshka-io`. Module name: `matryoshka`.
- Zig 0.16.0. Target backend: `Io.Threaded`.
- Both Mailbox and Pool are optional.

---

## 1. Project State

Test count.
- 161/161 passing across 4 optimization modes and 3 cross-compile targets.

Stages.
- Stages 0–8: complete.

INTR.
- INTR 1–5: complete.

Build order (reference).

```text
Stage 0     infrastructure                                  DONE
Stage 0.5   re-partition scenarios                          DONE
Stage 1     Layer 1  PolyNode                               DONE
Stage 2     Layer 2  Mailbox                                DONE
Stage 3     Layer 3  Pool                                   DONE
Stage 4     Layer 2+3  Infra as items                       DONE
Stage 5     Layer 4  Master (concurrency)                   DONE
INTR 1      Slot-based programming retrofit                 DONE
Stage 6     Cancellation + shutdown                         DONE
INTR 2      Thread-safe hooks + multi-thread example        DONE
Stage 7.a   Event sources — implementation                  DONE
INTR 3      ASCII ownership diagrams retrofit               DONE
Stage 7.b   Event sources — examples                        DONE
INTR 4      Bug fixes + doc corrections                     DONE
Stage 8     Mailbox-less patterns + cross-layer             DONE
INTR 5      Stories + doc infrastructure                    DONE
STORY 2     Print Server narrative                          DONE
STORY 1     Video Transcoder narrative rewrite              DONE
Story Rhythm  Both stories SRS+Translation+Insight          DONE
EXMPL 1     Example completeness audit + rule addition      DONE
EXMPL 2     Master pattern: pilot + doc update              DONE
EXMPL 3     Master pattern: full task2 conversion           NEXT
Stage 9     Docs + README + autodocs                        FUTURE
```

---

## 2. EXMPL 1 — Example Completeness Audit + Rule Addition

Doc-only stage. No Zig code written. No kitchen scripts needed.

New rule added.
- "Pool items are empty containers" added to `matryoshka-model-002.md` as a Core Principle.
- "Completeness" block added to `rules-002.md` Coding Rules — Examples section.
- Rule: an example must show origin of work input, what the worker does, where results go.
- Pool items are empty containers on acquisition. Work intent comes from outside the pool item.

Audit results.
- `task1-examples-002.md`: all 29 scenarios OK. Re-issued with compliance header note only.
- `task2-examples-002.md`: 7 scenarios revised (46, 47, 53, 56, 57, 58, 59). All others unchanged.

---

## 3. EXMPL 2 — Master Pattern: Pilot + Doc Update

New rule: flat function vs. allocate-a-Master. Pilot example implemented. 161/161 tests pass.

New coding rule.
- When to stay flat: minimal functionality, all state in locals, short lifecycle.
- When to allocate a Master: multiple steps, shared state, complex lifecycle.
- Same two-tier rule applies to worker functions.
- Canonical reference: `examples/layer4/master_with_pool.zig`.

New doc versions.
- `design/rules-003.md` — Master pattern rule added to Coding Rules — Examples and Stories.
- `design/matryoshka-model-003.md` — "When to allocate a Master" Core Principle added.

Pilot implementation.
- `examples/layer4/master_with_pool.zig` rewritten with `MasterWithPool` struct.
- `MasterWithPool`: `init` / `destroy` / `run` / `sendItems` (private step).
- `workerFn` stays flat — simple worker, no Master allocation needed.
- Test wrapper unchanged. All kitchen scripts pass.

---

## 4. Open Items / Next Up

- EXMPL 3 (full task2 conversion) is next. Convert all task2 examples to Master pattern.
- Stage 9 (README + autodocs) follows EXMPL 3. See `matryoshka-io-docs-plan-001.md`.

Carried open items.
- 5 — `condition_waitTimeout` workaround (codeberg/zig#31278).
- 6 — `Io.Evented` backend not tested.
- 10 — Which Layer 2-3 examples need real threads.
- 11 — Panic test style in Zig 0.16 (scenarios 15-16 deferred).
- 12 — Real-Io examples are integration tests, gate by platform.

---

## 5. References

- [rules-003.md](rules-003.md) — all process and coding rules. Source of truth for process.
- [matryoshka-model-003.md](matryoshka-model-003.md) — thinking model and story structure.
- [matryoshka-storytelling-001.md](../kitchen/docs/matryoshka-storytelling-001.md) — storytelling philosophy and rhythm rules.
- [patterns-001.md](patterns-001.md) — reusable coding patterns.
- [matryoshka-io-docs-plan-001.md](matryoshka-io-docs-plan-001.md) — documentation work plan.
- `matryoshka-api-reference-015.md` — primary source of truth for signatures, types, errors.
- `collected-context-004.md` — project state, idiom patterns, Io primitives, bug fixes.
