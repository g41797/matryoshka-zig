# Matryoshka Storytelling Model (001)

How architecture becomes software.

How a story captures that process.

Companion:

* `matryoshka-model-001.md`
* `rules-001.md`
* `patterns-001.md`

---

# Why stories exist

Tests answer:

> Does it work?

Examples answer:

> How do I use this API?

Stories answer:

> Why does this architecture exist?

The implementation is never the story.

The architecture is.

---

# The Mantra

Every story starts with one question.

> What problem are people trying to solve?

Never start with:

* APIs
* Masters
* Mailboxes
* Pools
* Io
* implementation

Those appear naturally.

---

# Start with people

Every story begins with people.

Sometimes users.

Sometimes operators.

Sometimes developers.

Sometimes architects.

Sometimes different teams.

The reader should first understand their work.

Only afterwards should software appear.

Software exists because responsibilities need to cooperate.

---

# Architecture is negotiated

Architecture rarely comes from one person.

People discuss.

People disagree.

People draw.

People erase.

People redraw.

Eventually they agree.

That agreement becomes the architecture.

Capture that process.

Remove:

* jokes
* side conversations
* implementation details

Keep:

* questions
* alternatives
* rejected ideas
* accepted responsibilities

The discussion should sound like experienced engineers thinking aloud.

Use domain language.

Do not introduce Matryoshka terminology.

---

# Responsibilities before software

Do not search for components.

Search for responsibilities.

Ask:

* Who performs this work?
* Who owns this information?
* Who makes this decision?
* Who waits?
* Who should never wait?
* Who may disappear without affecting others?

Responsibilities define boundaries.

Boundaries define architecture.

Architecture defines software.

---

# Good boundaries are negotiated

The most valuable part of a story is rarely the final answer.

It is the discussion that removes bad answers.

Show alternatives.

Reject them.

Explain why.

Example.

```
"We could write directly into storage."

"No.

Then acquisition becomes responsible for persistence."

"Let's separate them."
```

Good boundaries are discovered.

Not declared.

---

# Story Artifacts

A story records the artifacts produced during system design.

Each artifact is a refinement of the previous one.

Nothing appears suddenly.

Nothing skips a step.

```text
People

        │

        ▼

Discussion

        ⇅

Domain Whiteboard

        │

        ▼

SRS

        │

        ▼

Whiteboard Evolution

        │

        ▼

Implementation
```

---

# Discussion

Purpose.

Discover the architecture.

Participants use domain language.

Not implementation language.

The discussion should contain:

* questions
* alternatives
* rejected ideas
* accepted responsibilities

The discussion and the whiteboard evolve together.

Neither is complete without the other.

---

# Domain Whiteboard

The whiteboard is the first architectural document.

It is not an illustration.

It is part of the design process.

Show:

* participants
* responsibilities
* ownership
* information flow

Do not show:

* Masters
* Mailboxes
* Pools
* Io

The drawing changes while people talk.

The discussion changes the drawing.

The drawing changes the discussion.

Eventually both become stable.

Only then should the SRS be written.

---

# SRS

The SRS freezes the agreed whiteboard.

It does not continue the discussion.

It records observable behaviour.

One requirement.

One observable property.

Avoid:

* explanations
* implementation
* architecture lessons

Example.

* Client receives an acknowledgment immediately.
* Submission never waits for printer availability.
* Jobs leave the spooler in submission order.
* Exactly one owner holds a job at any time.
* Every client receives one final result.
* Shutdown loses no jobs.

The discussion already explained why.

The SRS records what.

---

# Whiteboard Evolution

Do not throw the whiteboard away.

Evolve it.

Keep the topology.

Change the vocabulary.

Example.

```text
Client
```

becomes

```text
Client Master
```

```text
Queue
```

becomes

```text
Mailbox
```

```text
Reusable buffers
```

become

```text
Pool
```

```text
Waiting
```

becomes

```text
Io.Select
```

The architecture should remain recognizable.

If the topology changes significantly, the translation started too early.

---

# Translation Notes

The evolved whiteboard now receives implementation names.

Translation does not redesign.

Translation identifies.

One responsibility.

One Matryoshka construct.

Examples.

```
Client
    ↓
Client Master
```

```
Print queue
    ↓
Mailbox
```

```
Frame buffers
    ↓
Pool
```

```
Wait for work
    ↓
Io.Select
```

The architecture is already complete.

Translation only makes it executable.

Avoid tutorial prose.

Avoid long explanations.

Record mappings.

Nothing more.

---

# Flow Diagram

The final diagram validates the implementation view.

It follows ownership.

Not function calls.

Not execution order.

The reader should always be able to answer one question.

> Who owns this object now?

If ownership is always obvious, the diagram is complete.

---

# Implementation

Implementation is N+1.

Nothing fundamentally new should appear.

Every Master already exists on the evolved whiteboard.

Every Mailbox already exists as a communication path.

Every Pool already exists as a reusable resource.

Implementation makes the architecture executable.

It should never redefine it.

---

# One Voice

Every artifact belongs to the same story.

Only its purpose changes.

The writing style does not.

Use:

* short sentences
* one fact at a time
* engineering language
* domain vocabulary first

Avoid long explanatory prose.

The diagrams carry the structure.

The text records decisions.

---

# Real Systems

Choose systems programmers already recognize.

Examples.

* Print server
* Video transcoder
* Log collector
* Image pipeline
* Package builder
* Sensor gateway

Do not invent artificial scenarios to demonstrate Matryoshka.

Find real problems.

Allow the architecture to emerge naturally.

---

# The Acid Test

Hide everything after the SRS.

Read only:

* Discussion
* Domain Whiteboard
* SRS

Ask one question.

> Would this still be a good system?

The answer should be yes.

Now reveal the rest of the story.

The reader should think:

> Of course.

> The architecture did not change.

> It simply became executable.

If removing the Matryoshka sections breaks the story, the story was written backwards.

---

# The Reader Experience

The reader should feel like sitting quietly in a design meeting.

First.

I understand the problem.

Then.

I agree with the responsibilities.

Then.

I understand the architecture.

Then.

I understand the requirements.

Then.

I see the same architecture becoming executable.

Finally.

The implementation feels inevitable.

That feeling is the purpose of every Matryoshka story.
