# Matryoshka Zig 0.16 — Staged Implementation Plan (022)

Slim plan. State only.
All process and coding rules live in [rules-002.md](rules-002.md). Not repeated here.

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
Stage 9     Docs + README + autodocs                        NEXT
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

Revised scenarios.
- 46, 47, 56: Master's own pre-loaded state or queue drives work; pool provides container.
- 53: Master distributes pre-loaded job descriptors via mailbox; workers return results to pool.
- 57: Spawn-time args + worker's own counter state drive work; pool provides buffer.
- 58: Master's own cycle counter drives work; pool availability controls concurrency.
- 59: Spawn-time task index drives work; pool provides result container per worker.

New doc versions created.
- `design/matryoshka-model-002.md` — new Core Principle added.
- `design/rules-002.md` — Completeness block added to example rules.
- `design/task1-examples-002.md` — re-issued, compliance header added.
- `design/task2-examples-002.md` — 7 scenarios revised.

EXMPL 2 (future).
- Write corrected `.zig` files for revised scenarios (57, 58, 59 at minimum).
- Plan separately after Stage 9.

---

## 3. Open Items / Next Up

- Stage 9 (README + autodocs) is next. See `matryoshka-io-docs-plan-001.md`.
- EXMPL 2 (corrected example Zig files) follows Stage 9 or runs in parallel.

Carried open items.
- 5 — `condition_waitTimeout` workaround (codeberg/zig#31278).
- 6 — `Io.Evented` backend not tested.
- 10 — Which Layer 2-3 examples need real threads.
- 11 — Panic test style in Zig 0.16 (scenarios 15-16 deferred).
- 12 — Real-Io examples are integration tests, gate by platform.

---

## 4. References

- [rules-002.md](rules-002.md) — all process and coding rules. Source of truth for process.
- [matryoshka-model-002.md](matryoshka-model-002.md) — thinking model and story structure.
- [matryoshka-storytelling-001.md](../kitchen/docs/matryoshka-storytelling-001.md) — storytelling philosophy and rhythm rules.
- [patterns-002.md](patterns-002.md) — reusable coding patterns.
- [matryoshka-io-docs-plan-001.md](matryoshka-io-docs-plan-001.md) — documentation work plan.
- `matryoshka-api-reference-015.md` — primary source of truth for signatures, types, errors.
- `collected-context-004.md` — project state, idiom patterns, Io primitives, bug fixes.
