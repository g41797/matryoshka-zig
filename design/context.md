# Matryoshka Zig — Context Entry Point

## Writing rules
- Short intro, then bullets. Like staccato music.
- One fact per bullet.
- No prose paragraphs with comma-separated lists.

API reference: [matryoshka-api-reference-010.md](matryoshka-api-reference-010.md) — signatures, types, error sets, cancel contract, PolyHelper, tag identity (class vs instance), infra transport patterns, invariants, thread-safety, complexity, io.concurrent and Io.Group verified call syntax

Architecture: [matryoshka-architecture-001.md](matryoshka-architecture-001.md) — why matryoshka exists, concept progression, flows, layers

Latest context: [collected-context-002.md](collected-context-002.md)

Rules and plan: [matryoshka-zig-implementation-plan-010.md](matryoshka-zig-implementation-plan-010.md) — Section 0 (Sources), Section 1 (Process Rules + Build Order Rules), stages

Tests (Layers 1-3): [task1-tests-001.md](task1-tests-001.md) — 62 scenarios, correctness/edge cases/contract violations

Examples (Layers 1-4): [task1-examples-001.md](task1-examples-001.md) — 29 scenarios (Layer1: 21-25, Layer2: 53-62, Layer3: 89-92, Layer4: 17-24, 95-96), usage patterns/stories

Tests (Layer 4 + cross-layer): [task2-tests-001.md](task2-tests-001.md) — 23 scenarios, worker lifecycle/shutdown/cancellation/cross-layer

Examples (Layer 4 + cross-layer): [task2-examples-001.md](task2-examples-001.md) — 38 scenarios, Master patterns/Select/event sources/communication

Scenarios (historical): [task1-scenarios-001.md](task1-scenarios-001.md), [task2-scenarios-001.md](task2-scenarios-001.md) — original unsplit sources
