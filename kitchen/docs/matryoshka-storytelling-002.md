# Matryoshka Storytelling Model (002)

How to think before writing a Matryoshka story.

> The stories capture the conversations that produce architecture.

Companion:

* `matryoshka-model-001.md`
* `rules-001.md`
* `patterns-002.md`

---

# Why stories exist

A test proves correctness.

An example teaches one API.

A story explains how a real system is designed.

The reader should finish the story thinking:

> "I would probably make the same decisions."

Only afterwards should they discover that Matryoshka already contains the required building blocks.

The story is not about Matryoshka.

The story is about solving a real problem.

---

# The Mantra

Every story starts with one question.

> What problem are people trying to solve?

Never start with:

* APIs.
* Features.
* Masters.
* Mailboxes.
* Pools.
* Implementation.

Software appears later.

Architecture appears first.

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

# Conversations produce architecture

Architecture rarely appears fully formed.

People negotiate.

People disagree.

People reject ideas.

People discover better boundaries.

Capture those discussions.

Remove:

* jokes
* side conversations
* implementation details

Keep:

* questions
* alternatives
* decisions
* trade-offs

The discussion should sound like experienced engineers thinking aloud.

No Matryoshka terminology.

No implementation.

Only domain language.

---

# Responsibilities before software

Do not begin with software.

Begin with responsibilities.

Ask:

* Who performs this work?
* Who owns this information?
* Who should make this decision?
* What happens if this part becomes slow?
* Can this responsibility change independently?

Responsibilities create architecture.

Architecture creates software.

Not the other way around.

---

# Good boundaries are negotiated

The most valuable part of a story is rarely the final answer.

It is the discussion that removes bad answers.

Show alternatives.

Reject them.

Explain why.

Example.

"We could write directly into storage."

"No."

"Then acquisition becomes responsible for persistence."

"Let's separate them."

Good boundaries are discovered.

Not declared.

---

# Story artifacts

A story is not divided into chapters.

It is divided into engineering artifacts.

Each artifact exists because the previous one became stable.

Conversation.

↓

Domain whiteboard.

↓

SRS.

↓

Matryoshka whiteboard.

↓

Translation.

↓

Implementation.

Every artifact records the result of the previous step.

Nothing is skipped.

Nothing appears suddenly.

---

# The domain whiteboard

The first whiteboard belongs to the domain.

Not to Matryoshka.

Participants.

Responsibilities.

Information flow.

Ownership.

Questions.

No Masters.

No Mailboxes.

No Pools.

No implementation.

The whiteboard grows together with the discussion.

The discussion changes the drawing.

The drawing changes the discussion.

Eventually both become stable.

Only then should the SRS be written.

---

# The SRS

The SRS records the agreed whiteboard.

It does not continue the discussion.

It does not explain decisions.

It does not teach architecture.

It records observable behaviour.

One requirement.

One observable property.

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

# Delay Matryoshka

The reader should already agree with the architecture before seeing any Matryoshka terminology.

Use domain language.

Use the words the participants naturally use.

Only when the architecture becomes stable should Matryoshka appear.

---

# The Matryoshka whiteboard

The second whiteboard redraws the first one.

The topology should remain recognizable.

Only the vocabulary changes.

Responsibilities become Masters.

Queues become Mailboxes.

Resource lifetime becomes Pools.

Event waiting becomes `Io.Select`.

The architecture should not change.

Only its implementation language.

If the topology changes significantly, the translation probably started too early.

---

# Translation

Translation is not design.

The design already exists.

Translation identifies.

Not invents.

Think in mappings.

Requirement.

↓

Matryoshka.

Example.

Requirement.

Non-blocking submission.

Matryoshka.

* Client Master.
* `PrintJob`.
* `mailbox.send()`.
* Ownership transferred.

Example.

Requirement.

Ordered dispatch.

Matryoshka.

* Spool Master.
* `job_queue`.
* `mailbox.receive()`.
* FIFO preserved.

One mapping.

One responsibility.

One concept.

Avoid tutorial prose.

Avoid long paragraphs.

---

# Flow diagram

The flow diagram validates the translation.

It follows ownership.

Not control flow.

Not function calls.

The reader should be able to answer one question everywhere in the diagram.

"Who owns this object now?"

If ownership is always obvious, the diagram is complete.

---

# Implementation is N+1

Implementation is not the destination.

It is simply the next logical artifact.

The difficult work already happened.

The responsibilities already exist.

The architecture already exists.

The ownership model already exists.

The implementation makes those decisions executable.

---

# One voice

The story has one voice.

Discussion.

Whiteboard.

SRS.

Translation.

Diagram.

Implementation.

Different artifacts.

Same rhythm.

Short sentences.

One fact at a time.

Engineering language.

The reader should notice a change of purpose.

Not a change of writing style.

---

# Real systems

Choose systems programmers recognize.

Print server.

Video transcoder.

Log collector.

Image pipeline.

Package builder.

Sensor gateway.

The reader should recognize the problem immediately.

Do not invent artificial scenarios to demonstrate Matryoshka.

Find real problems.

Allow the architecture to emerge naturally.

---

# The Acid Test

Hide everything after the SRS.

Read only:

* Discussion.
* Domain whiteboard.
* SRS.

Ask one question.

"Would this still be a good system?"

The answer should be yes.

Now reveal the Matryoshka sections.

The reader should think:

"Of course."

"This maps naturally onto Matryoshka."

If the architecture depends on Matryoshka before the translation begins, the story was written backwards.

---

# The Reader Experience

The reader should feel like sitting quietly in a design meeting.

First.

"I understand the problem."

Then.

"I agree with the responsibilities."

Then.

"I agree with the architecture."

Then.

"I understand the requirements."

Then.

"Of course these become Masters."

Finally.

"The implementation is almost obvious."

That feeling is the purpose of every Matryoshka story.

---------

# Last conversation

Before investing time in rewriting the whole document, I want to challenge one assumption.

I no longer think a **Matryoshka Whiteboard** and a **Flow Diagram** are different artifacts.

I think they are the **same artifact**, viewed from different abstraction levels.

Real design usually goes like this:

```text
People

↓

Discussion

⇅

Whiteboard

↓

SRS

↓

Whiteboard evolves

↓

Implementation
```

Nobody erases the board and starts over.

They keep modifying it.

The labels evolve.

The topology almost never does.

So I would actually reduce the number of artifacts, not increase them.

The story becomes:

1. Discussion
2. Domain Whiteboard
3. SRS
4. Whiteboard Evolution (Matryoshka)
5. Implementation

Notice what happened.

The "translation" is no longer prose.

The translation is the **evolution of the whiteboard**.

That feels much closer to how experienced engineers work.

For example:

```text
Stage 1 (domain)

+--------+      +---------+      +---------+
| Client | ---> | Spooler | ---> | Printer |
+--------+      +---------+      +---------+

           reply
<------------------------------------------
```

After the discussion and SRS, the **same drawing** evolves:

```text
Stage 2 (Matryoshka)

+---------------+      +----------------+      +-----------------+
| Client Master | ---> | Spool Master   | ---> | Printer Master  |
+---------------+      +----------------+      +-----------------+
        │                     │                        │
        │               job_queue                 printer_inbox
        │                     │                        │
        └────────────── reply_mbh ─────────────────────┘
```

Nothing fundamental changed.

Only the vocabulary became executable.

Then the implementation follows.

I think this is actually a stronger model than introducing another standalone "Translation" artifact.

---

So if I rewrite the document now, I would **not** produce the version I showed earlier. I'd produce a substantially different one centered around this idea:

> **A story follows the evolution of one architecture.**

Not:

> discussion → prose → prose → diagram.

But:

> discussion ⇄ whiteboard → SRS → evolved whiteboard → implementation.

I think that's the model you've been reaching for throughout this conversation. It's simpler, closer to real engineering practice, and it naturally explains why the SRS and translation shouldn't become long prose sections—they're snapshots of an architecture that is gradually becoming more concrete, not new acts in the story.

