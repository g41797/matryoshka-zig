# Matryoshka Thinking Model

Permanent doc. Not versioned.
The mental model behind every Matryoshka design decision.
Companion: [rules.md](rules.md) — the coding and process rules.

---

## The Mantra

Every Matryoshka design starts with one question.

> Who owns this item right now?

- Not "what data does this item hold."
- Not "which thread processes it."
- Just: who owns it.

Ownership is visible at the call site.
- If you must read the implementation to know who owns an item, the design is wrong.

---

## Core Principles

### Route state, not data

- Pass ownership pointers, not byte copies.
- The object that carries state moves between owners.
- Whoever holds it has exclusive ownership — and exclusive access.
- Wrong: put raw data into a queue, process it, produce results.
- Right: route the object that carries the state machine.

### Ownership moves, it never duplicates

- An item has exactly one owner at any moment.
- Owners: user code (IN_FLIGHT), mailbox (HELD), pool (HELD).
- When ownership transfers, the slot becomes null.
- `slot.* = null` is the ownership protocol, not a bookkeeping detail.
- The null is the proof of transfer.

### Ownership transfer = lock-free concurrency

- One owner at a time means no mutex during processing.
- Not a lock-free algorithm. Just: one owner at a time.
- The routing gives the lock-freedom.

### Pool availability = backpressure signal

- An empty pool is not just an error condition.
- It is a backpressure signal.
- `pool.getWaitResult` inside `Io.Select` makes availability a first-class event source.
- One loop handles data and buffer availability together.
- When a worker returns an item, the pool fires and the waiter resumes.
- No sleep. No poll. No explicit backpressure code.

### Layers compose

- Each layer adds exactly one capability.
- No custom locks needed. No custom thread managers needed.

```text
PolyNode           who owns this item?
  +
Mailbox            how does ownership move?
  +
Pool               should this item be reused or destroyed?
  +
Master             who coordinates startup, shutdown, cancellation, policy?
```

- Need ownership and movement only: use PolyNode + Mailbox. Stop there.
- Need backpressure and reuse: add Pool.
- Need coordination: add Master.
- The ownership model never changes. Only capabilities are added.

### Cancel is not close

- `error.Canceled` — the Io scheduler says stop now. External signal.
- `mailbox.close` / `pool.close` — the Master says this subsystem is shutting down.
- Cancel stops waiting.
- Close signals end-of-stream.
- Cancel does not trigger close.
- A worker that gets `error.Canceled` reports it. The Master decides what to do.

### Master is a concept, not a type

- Master is the coordination boundary.
- Any `Io.Select` loop is a Master.
- It is the place where startup order, shutdown order, cancellation policy, and resource ownership live.
- There is no required Master struct. No required interface.
- The responsibility matters. The structure does not.

---

## Three-Category Model

Tests, examples, and stories have different jobs.

### Test

- Checks correctness.
- One behavior at a time.
- Edge cases, error paths, state transitions, contract violations.
- Scope: one API call or one invariant.
- Internal artifact. Not user docs.

### Example

- Shows how to use one pattern.
- One API interaction. One layer.
- "How to seed a pool." "How to do fan-in."
- Reader learns what to call and in what order.
- Part of the docs.

### Story

- Shows how to think with Matryoshka.
- Multiple layers composing into a real flow.
- Starts from a real domain problem. Translates to Matryoshka patterns. Implements.
- Reader learns how to reason about a new problem using ownership thinking.
- Part of the docs.

A story is not a large example. It is a different kind of artifact.

### What qualifies as a story

- Must show at least two layers composing.
- Must have a real domain problem.

---

## Story Structure

Each story is a mini-project with two artifacts plus one shared test file.

### Narrative — `design/stories/name-001.md`

Four parts.

**Part 1 — Arch Design**
- Domain problem statement.
- Architect dialogue: constraints, tradeoffs, decisions.
- Result: bounded scope, defined boundaries.

**Part 2 — SRS (Software Requirements Specification)**
- Numbered requirements. One per bullet.
- Domain language, not Matryoshka language.
- Example: "The system must reuse video buffers to prevent fragmentation."

**Part 3 — Matryoshka Translation**
- Map each requirement to a Matryoshka concept.
- Programmer dialogue preferred — shows the reasoning, not just the result.
- Example: "Requirement 3 maps to pool.getWaitResult inside Io.Select."

**Part 4 — Flow Diagram**
- Full system ASCII diagram.
- Shows all layers, all ownership flows, all event sources.
- Diagram only. No prose.

### Code — `stories/name/name.zig`

- Signature: `pub fn run(allocator: std.mem.Allocator, io: std.Io) !void`.
- Full implementation of the story.
- All actors, all layers, graceful shutdown.
- ASCII ownership circuit diagram at the top of the file.

### Test wrapper — `tests/stories_test.zig`

- Single file. All story wrappers.
- Same pattern as `layer4_cross.zig` wrappers.
- Uses `std.Io.Threaded.init`.
