# Matryoshka Zig — Context Entry Point

## Writing rules
- Short intro, then bullets. Like staccato music.
- One fact per bullet.
- No prose paragraphs with comma-separated lists.

API reference: [matryoshka-api-reference-013.md](matryoshka-api-reference-013.md) — signatures, types, error sets, cancel contract, PolyHelper (+ create/destroy + no_create_destroy), slot-based programming, cooperative cleanup patterns, tag identity, infra transport patterns, invariants, thread-safety, complexity, Select internals, receiveResult/getWaitResult

Architecture: [matryoshka-architecture-001.md](matryoshka-architecture-001.md) — why matryoshka exists, concept progression, flows, layers

Latest context: [collected-context-003.md](collected-context-003.md)

Rules and plan: [matryoshka-zig-implementation-plan-013.md](matryoshka-zig-implementation-plan-013.md) — Section 0 (Sources), Section 1 (Process Rules + Build Order Rules), stages

Tests (Layers 1-3): [task1-tests-001.md](task1-tests-001.md) — 73 scenarios (Layer1: 1-20, Layer2: 26-52, Layer3: 63-88), correctness/edge cases/contract violations

Examples (Layers 1-4): [task1-examples-001.md](task1-examples-001.md) — 29 scenarios (Layer1: 21-25, Layer2: 53-62, Layer3: 89-92, Layer4: 17-24, 95-96), usage patterns/stories

Tests (Layer 4): [task2-tests-001.md](task2-tests-001.md) — 16 scenarios (1-16), worker lifecycle/shutdown/cancellation. All done.

Examples (Layer 4 + cross-layer): [task2-examples-001.md](task2-examples-001.md) — 45 scenarios (17-31, 32-41, 42-61), Master patterns/Select/event sources/cross-layer/mailbox-less

Scenarios (historical): [task1-scenarios-001.md](task1-scenarios-001.md), [task2-scenarios-001.md](task2-scenarios-001.md) — original unsplit sources
