# Matryoshka Zig — Context Entry Point

## Writing rules
- Short intro, then bullets. Like staccato music.
- One fact per bullet.
- No prose paragraphs with comma-separated lists.

API reference: [matryoshka-api-reference-015.md](matryoshka-api-reference-015.md) — signatures, types, error sets, cancel contract, PolyHelper (+ create/destroy + no_create_destroy), slot-based programming, cooperative cleanup patterns, tag identity, infra transport patterns, invariants, thread-safety, complexity, Select internals, receiveResult/getWaitResult

Architecture: [matryoshka-architecture-001.md](matryoshka-architecture-001.md) — why matryoshka exists, concept progression, flows, layers

Latest context: [collected-context-004.md](collected-context-004.md) — project state only

Thinking model: [matryoshka-model-003.md](matryoshka-model-003.md) — ownership mantra, three-category model, story structure, pool items are empty containers, when to allocate a Master

Rules: [rules-003.md](rules-003.md) — coding, doc, and process rules (+ example completeness rule + Master pattern rule)

Patterns: [patterns-001.md](patterns-001.md) — reusable coding patterns (pool, Select, Group, shutdown, dispatch, Master composition)

Plan: [matryoshka-io-implementation-plan-023.md](matryoshka-io-implementation-plan-023.md) — slim state-only plan; rules live in rules-003.md

Storytelling: [../kitchen/docs/matryoshka-storytelling-001.md](../kitchen/docs/matryoshka-storytelling-001.md) — storytelling philosophy and rhythm rules (Discussion, SRS, Translation, Central Insight)

Docs plan: [matryoshka-io-docs-plan-001.md](matryoshka-io-docs-plan-001.md) — documentation work plan (stories, examples-as-docs, README, autodocs)

Tests (Layers 1-3): [task1-tests-001.md](task1-tests-001.md) — 73 scenarios (Layer1: 1-20, Layer2: 26-52, Layer3: 63-88), correctness/edge cases/contract violations

Examples (Layers 1-4): [task1-examples-002.md](task1-examples-002.md) — 29 scenarios (Layer1: 21-25, Layer2: 53-62, Layer3: 89-92, Layer4: 17-24, 95-96), usage patterns/stories

Tests (Layer 4): [task2-tests-001.md](task2-tests-001.md) — 16 scenarios (1-16), worker lifecycle/shutdown/cancellation. All done.

Examples (Layer 4 + cross-layer): [task2-examples-002.md](task2-examples-002.md) — 45 scenarios (17-31, 32-41, 42-61), Master patterns/Select/event sources/cross-layer/mailbox-less

Scenarios (historical): [task1-scenarios-001.md](task1-scenarios-001.md), [task2-scenarios-001.md](task2-scenarios-001.md) — original unsplit sources
