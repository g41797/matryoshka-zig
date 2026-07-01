# Matryoshka Storytelling Model (001)

It doesn't prescribe a format; it explains the philosophy.


How to think before writing a Matryoshka story.

> The stories are about **capturing the conversations that produce architectural patterns**.

Companion: matryoshka-model-001.md
Companion: rules-001.md
Companion: patterns-002.md

---

## The Mantra

Every Matryoshka story starts with one question.

> What problem are people trying to solve?

Not:

- Which APIs should be demonstrated.
- Which Matryoshka feature should be introduced.
- Which implementation should be written.

The implementation is the last step.

The story begins long before software exists.

---

## Stories teach architecture

A test proves correctness.

An example teaches one API or one pattern.

A story teaches architectural thinking.

The reader should finish the story thinking:

> "I would probably make the same decisions."

Only afterwards should they discover that Matryoshka already contains the required building blocks.

The story is not about Matryoshka.

The story is about solving a real problem.

---

## Start with people

Every story starts with people.

Sometimes users.

Sometimes operators.

Sometimes developers.

Sometimes architects.

Sometimes different teams.

The reader should first understand their work.

Only then should software appear.

Software exists because people need responsibilities to cooperate.

---

## Conversations come first

Architecture is rarely invented by one person.

It emerges from negotiation.

Capture those negotiations.

Remove the jokes.

Remove the side conversations.

Keep only the technical discussion.

The dialogue should sound like experienced engineers thinking aloud.

Example:

Developer A:
"I don't know who should own this."

Developer B:
"Then don't own it."

Developer A:
"So who does?"

Developer B:
"The next responsibility."

No Matryoshka terminology.

No implementation.

Only responsibilities.

---

## Responsibilities before software

Do not begin with components.

Do not begin with queues.

Do not begin with threads.

Begin with responsibilities.

Ask:

- Who performs this work?
- Who owns this information?
- What decisions belong here?
- What should happen if this part becomes slow?
- Can this responsibility change independently?

Architecture appears naturally.

---

## Negotiate boundaries

The most valuable part of a story is not the answer.

It is the discussion that removes bad answers.

Show alternatives.

Reject them.

Explain why.

Example:

"We could write directly into storage."

"No.

Then acquisition becomes responsible for persistence."

"Let's separate them."

Good boundaries are discovered.

Not declared.

---

## Delay Matryoshka

The first half of the story should contain almost no Matryoshka terminology.

Use domain language.

Use the language the participants would naturally use.

Only after the architecture becomes stable should the translation begin.

The reader should already agree with the architecture before seeing a Mailbox or a Master.

---

## Translation is mechanical

Once the architecture exists, translating it into Matryoshka should feel obvious.

Responsibilities become Masters.

Ownership movement becomes Mailboxes.

Resource lifetime becomes Pools.

Coordination becomes Io.Select loops.

The translation should feel inevitable.

Not clever.

---

## Implementation is N+1

The implementation is not the destination.

It is simply the next logical step.

The difficult work has already happened.

The architecture already exists.

The ownership model already exists.

The communication already exists.

The implementation simply makes those decisions executable.

---

## Real systems

Choose systems that programmers recognize.

Video transcoder.

Log collector.

Print server.

Image pipeline.

Package builder.

Sensor gateway.

The domain should feel familiar.

The reader should recognize the problem before reading the solution.

---

## Avoid artificial lessons

Never invent a problem to demonstrate Matryoshka.

Find a real problem.

Allow the architecture to emerge.

Allow Matryoshka to fit naturally.

The reader should never feel manipulated into learning a feature.

---

## The Reader Experience

The story should feel like sitting quietly in a design meeting.

First:

"I understand the problem."

Then:

"I agree with the decomposition."

Then:

"I would probably make the same decision."

Finally:

"Of course.

This maps directly onto Matryoshka."

That moment is the purpose of every story.


# Storytelling Rule

The story should have one voice.

Discussion.

Specification.

Translation.

Diagram.

Different artifacts.

Same rhythm.

Every section should feel as if it was written by the same engineer on the same day.

The reader should never notice a change of writing style.

Only a change of purpose.

## Discussion


Short sentences.

Questions.

Negotiation.

One idea at a time.

Engineering rhythm.

---

## SRS

The SRS is not a narrative.

It is a checklist.

Each requirement should describe one observable property.

Avoid explanations.

Avoid implementation hints.

Avoid multiple requirements inside one paragraph.

Good:

- Client receives an acknowledgment immediately.
- Submission never waits for printer availability.
- Jobs leave the spooler in submission order.
- Exactly one owner holds a job at any time.
- Clients receive one final result.
- Cancellation succeeds while the job is queued.
- Cancellation reaches the printer before queued work.
- Shutdown loses no jobs.

Each bullet is independently verifiable.

The discussion already explained *why*.

The SRS only records *what*.

---

## Translation

Translation should not become another discussion.

The architecture is already accepted.

Translation is bookkeeping.

Think of it as a table of mappings.

Example.

Requirement:
Non-blocking submission.

Matryoshka:

- Client Master.
- `PrintJob`.
- `mailbox.send()`.
- Ownership transferred.
- Client continues.

---

Requirement:
Ordered dispatch.

Matryoshka:

- Spool Master.
- `job_queue`.
- `mailbox.receive()`.
- FIFO preserved.

---

Requirement:
Result notification.

Matryoshka:

- Client mailbox.
- `reply_mbh`.
- Printer Master sends result directly.
- Spool Master not involved.

---

Requirement:
Exclusive ownership.

Matryoshka:

- Printer Master owns one job.
- Single slot.
- No shared access.
- No locks.

Notice the rhythm.

One mapping.

One responsibility.

One concept.

No paragraphs.

No tutorial prose.

---

## Central Insight

Keep it equally compact.

Instead of explaining.

State.

Then illustrate.

Example.

Central insight.

At any moment, whoever holds the job owns the problem.

Consequences.

- No shared status table.
- No polling.
- No ownership ambiguity.
- Responsibility follows location.

Illustration.

Job in `job_queue`.

- Spool Master owns it.

Job in `printer_inbox`.

- Moving between Masters.

Job in Printer slot.

- Printer Master owns it.

Job result.

- Client owns the outcome.

Readers already know the story.

They do not need another essay.
