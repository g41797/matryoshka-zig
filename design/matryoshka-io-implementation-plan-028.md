# Matryoshka Zig — Implementation Plan (028)

Replaces [matryoshka-io-implementation-plan-027.md](matryoshka-io-implementation-plan-027.md).

## Status

EXMPL 3e — IN PROGRESS.

---

## Completed stages (summary)

- Stage 0–8: API, tests, examples layers 1–3 done.
- Stage 9 (Layer 4 infrastructure): pool, mailbox, select, group done.
- EXMPL 3a: 45 layer4 examples written (layer4.zig registration, test wrappers).
- EXMPL 3b: renamed all layer4 examples; Master pattern applied to 6 complex files.
- EXMPL 3c: Observable by human rule (rules-005 → rules-006); fixed 3 Master violations (020, 031, 048).
- EXMPL 3d: extracted step functions from 31 flat layer4 files with section comments.

---

## EXMPL 3e — Observable: structural signals + fix 24 violating examples

### Goal

Full audit after EXMPL 3d revealed 24 Observable violations in files with no section comments.
Root cause: the rule relied on a subjective heuristic. EXMPL 3e adds objective structural extraction signals and fixes all 24 violations.

### Rule change — `rules-007.md`

New subsection **Structural extraction signals** added to `## Observable by human — MUST`:

1. Any `while` loop with a `switch` body → `runEventLoop` or equivalent.
2. Any `Io.Select` setup block (`buf` + `sel.init` + `sel.concurrent`) → `setupSelect`.
3. Any cluster of `io.concurrent` / `group.concurrent` / `Thread.spawn` calls → `spawnWorkers` or equivalent.
4. Any for-loop or sequential send/fill/seed block → `sendItems`, `fillMailbox`, etc.

Also adds item 10 to the per-stage finish checklist:
> Rules audit: after any stage that changes `*.zig` or `*.md`, audit all changed files against all rules. Report violations before closing the stage.

### Pattern change — `patterns-006.md`

Two new coordinator-level templates added to `## Observable function shapes`:
- Coordinator with Select event loop (flat file): `setupSelect` + `runEventLoop` pattern.
- Coordinator with spawn + await (flat file): `spawnAndAwaitWorkers` pattern.

### Files fixed (24)

**Group A — event loop inline (10):**
025, 026, 028, 042, 044, 045, 046, 058, 060, 061

**Group B — spawn/await inline (5):**
017, 019, 021, 022, 054

**Group C — mixed (4):**
024, 056, 059, 095

**Group D — minor (4):**
029, 043, 049, 050

### Verification

- 161/161 × 4 build modes.
- Cross-compile PASS (x86_64-macos, aarch64-macos, x86_64-windows).
- AI-sh + banned words scan CLEAN.
- Full layer4 audit: 0 Observable violations.

---

## Next

Stage 9 — Docs + README + autodocs. PLANNED.
