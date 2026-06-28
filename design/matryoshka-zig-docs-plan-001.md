# Matryoshka Zig — Documentation Plan (001)

Documentation work plan. Separate from the implementation plan.
Tracks docs-facing work: stories, examples-as-docs, README, autodocs.

---

## Goal

Document matryoshka-zig for users.
- Target reader: knows Zig, does not know Matryoshka.
- Teach the ownership thinking model, then the API, then real flows.

---

## Status Snapshot (as of INTR 5)

Stories.
- `video-transcoder-001` — narrative written, code complete.
- Code compiles. Runtime not yet confirmed green.

Examples.
- Layer 1: 5 examples (`examples/layer1/`).
- Layer 2: 10 examples (`examples/layer2/`).
- Layer 3: 4 examples (`examples/layer3/`).
- Layer 4: 37 examples (`examples/layer4/`).
- Total: 56 example files. Each carries an ASCII ownership diagram.

README.
- Not started for Stage 9.

---

## Planned Work

Stage 9 — README + autodocs.
- `zig build docs` via `getEmittedDocs()` → `docs/`.
- Root `README.md` as a library index: polynode, mailbox, pool.
- One copy-pasteable snippet per layer.
- Final AI-sh scan across all `*.md` and `*.zig`.

Stories to add (future).
- Source ideas from `design/matryoshka-real-world-scenario-001.md`.
- Source ideas from other domains that show two or more layers composing.

Examples to review.
- Check which Layer 4 files are genuine how-to versus micro-tests.
- Promote or merge micro-tests where a clearer single-pattern example helps.

Doc review.
- Check all existing narratives for human-readability per `rules.md`.
- Confirm diagrams are ASCII, human-readable, not space-optimized.

---

## References

- [matryoshka-model.md](matryoshka-model.md) — thinking model, three-category model, story structure.
- [rules.md](rules.md) — coding, doc, and process rules.
