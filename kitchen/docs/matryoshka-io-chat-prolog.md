# Matryoshka-io Working Context (Prolog v4)

## Purpose of this project

Matryoshka-io is an architecture model for building software systems.

It defines how systems are structured and how they behave at runtime.

It is independent of implementation language.

It is not defined by Zig.

It is not defined by any specific runtime library.

---

## Core principle

Architecture is primary.

Implementation is secondary.

- Architecture defines structure and behavior.
- Implementation uses available platform features.
- Architecture must remain valid across implementations.

---

## IO (IMPORTANT CLARIFICATION)

IO is NOT the architecture.

IO is an implementation capability layer.

IO is used in two ways:

- Required by the operating system environment.
  - sockets
  - file descriptors
  - polling mechanisms
  - async wakeups

- Optional capability provider.
  - event sources
  - timers
  - scheduling hooks
  - cancellation signals
  - synchronization primitives

IO does not define system structure.

IO does not define Matryoshka concepts.

IO is used when it improves implementation.

---

## Architecture vs Implementation rule

Strict separation must always be maintained.

### Architecture layer

- Defines system structure
- Defines runtime behavior
- Defines composition rules
- Must remain independent of Zig
- Must remain independent of IO APIs

### Implementation layer

- Uses Zig features
- Uses IO when available
- Implements architectural rules
- Provides runtime execution

---

## Working rule (VERY IMPORTANT)

Before introducing any concept:

- If concept exists without Zig → it may be architecture
- If concept exists only because of Zig IO → it is implementation
- If concept depends on OS API details → it is implementation

Do NOT elevate implementation details into architecture.

---

## Documentation style rules

- Simple English
- Short sentences
- Bullets over prose
- One fact per bullet

---

## Staccato rhythm rule

Each section should follow:

- One short introduction sentence
- Bullet list of facts
- One fact per bullet
- No multi-idea sentences inside bullets

---

## Story documentation structure (MANDATORY)

All Story documents must use:

1. Architecture dialogue
2. SRS (system requirements)
3. Matryoshka mapping
4. ASCII flow diagram

---

## Cross-reference rule

Repository: https://github.com/g41797/matryoshka-io

Most md documants are under design folder

Do not duplicate definitions.

Reference instead:

- matryoshka-model-001.md
- matryoshka-api-reference-015.md
- rules-001.md
- patterns-002.md

---

## Writing principle

This is engineering documentation.

Not a narrative.

Not marketing.

Not conceptual philosophy.

Focus on clarity and correctness.

Prefer explicit structure over abstraction.

---

## Working protocol for chats using this prolog

- Start from existing verified documents
- Detect inconsistencies early
- Ask before inventing new terms, require additional documantation
- Prefer correction over expansion
- Keep architecture stable across iterations

