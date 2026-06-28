# Matryoshka Zig 0.16 — Staged Implementation Plan (018)

Slim plan. State only.
All process and coding rules live in [rules.md](rules.md). Not repeated here.

- Repo: `matryoshka-zig`. Module name: `matryoshka`.
- Zig 0.16.0. Target backend: `Io.Threaded`.
- Both Mailbox and Pool are optional.

---

## 1. Project State

Test count.
- 160/160 passing across 4 optimization modes and 3 cross-compile targets.
- Story test (`tests/stories_test.zig`) compiles. Runtime not yet confirmed.

Stages.
- Stages 0–8: complete.

INTR.
- INTR 1–4: complete.
- INTR 5: pilot code complete (compiles, story test not yet verified green); doc infrastructure complete.

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
INTR 5      Stories + doc infrastructure                    IN PROGRESS
Stage 9     Docs + README + autodocs                        NEXT
```

---

## 2. INTR 5 — Stories + Doc Infrastructure

Pilot.
- Stories module wired into the build (`stories/stories.zig`).
- Pilot story: video transcoder.
  - Narrative: `design/stories/video-transcoder-001.md` (4 parts present).
  - Code: `stories/video_transcoder/video_transcoder.zig` — `pub fn run(allocator, io) !void`.
  - Test wrapper: `tests/stories_test.zig`.
- Pilot code compiles. Story test runtime not yet verified.

Doc infrastructure (this task).
- `design/matryoshka-model.md` — thinking model, three-category model, story structure.
- `design/rules.md` — all coding, doc, and process rules.
- `design/matryoshka-zig-docs-plan-001.md` — documentation work plan.
- `design/matryoshka-zig-implementation-plan-018.md` — this slim plan.
- `design/collected-context-004.md` — trimmed to project state; model/rules content moved out.

---

## 3. Open Items / Next Up

- Verify story test runs green across all kitchen scripts (160 + story).
- Then Stage 9 — README rewrite + autodocs. See `matryoshka-zig-docs-plan-001.md`.

Carried open items.
- 5 — `condition_waitTimeout` workaround (codeberg/zig#31278).
- 6 — `Io.Evented` backend not tested.
- 10 — Which Layer 2-3 examples need real threads.
- 11 — Panic test style in Zig 0.16 (scenarios 15-16 deferred).
- 12 — Real-Io examples are integration tests, gate by platform.

---

## 4. References

- [rules.md](rules.md) — all process and coding rules. Source of truth for process.
- [matryoshka-model.md](matryoshka-model.md) — thinking model and story structure.
- [matryoshka-zig-docs-plan-001.md](matryoshka-zig-docs-plan-001.md) — documentation work plan.
- `matryoshka-api-reference-015.md` — primary source of truth for signatures, types, errors.
- `collected-context-004.md` — project state, idiom patterns, Io primitives, bug fixes.
