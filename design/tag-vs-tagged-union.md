This is actually one of the most important architectural questions in Matryoshka.

The short answer:

**Because tagged unions and PolyNode tags solve completely different problems.**

---

## Tagged union solves compile-time type selection

```zig
const Message = union(enum) {
    event: Event,
    sensor: Sensor,
    mailbox: MailboxHandle,
};
```

Receiver gets:

```zig
switch (msg) {
    .event => ...
    .sensor => ...
    .mailbox => ...
}
```

Type is known by the union.

Excellent Zig solution.

---

## PolyNode solves runtime identity after type erasure

Matryoshka intentionally does this:

```zig
pub const Item = *PolyNode;
```

Mailbox stores:

```zig
std.DoublyLinkedList
```

Pool stores:

```zig
std.DoublyLinkedList
```

Neither knows:

```text
Event
Sensor
Job
MailboxHandle
PoolHandle
```

Everything becomes:

```zig
*PolyNode
```

At that point the type information is gone.

---

Without a tag:

```zig
const item: *PolyNode = ...;
```

Question:

```text
What is this?
```

Impossible to answer.

---

With a tag:

```zig
if (item.tag == EVENT_TAG) { ... }

if (item.tag == SENSOR_TAG) { ... }

if (item.tag == MAILBOX_TAG) { ... }
```

Now runtime identity survives type erasure.

---

## Why not use a tagged union instead?

Imagine mailbox queue:

```zig
std.ArrayList(Message)
```

or

```zig
std.DoublyLinkedList(Message)
```

where Message is a tagged union.

That works.

But now:

```zig
Mailbox stores Message
Pool stores Message
Everything stores Message
```

Matryoshka intentionally chose:

```zig
Mailbox stores *PolyNode
Pool stores *PolyNode
```

because it wants:

### Intrusive ownership

```zig
Event
Sensor
Job
MailboxHandle
PoolHandle
```

all embedded directly.

No wrapper allocation.

No copying.

No giant union.

No central registry.

---

## Another way to see it

Tagged union:

```text
Type erased?      No
Compile-time?     Yes
Known variants?   Yes
Closed world?     Yes
```

PolyNode tag:

```text
Type erased?      Yes
Compile-time?     No
Known variants?   No
Open world?       Yes
```

---

Example.

Today:

```zig
Event
Sensor
```

Tomorrow:

```zig
DatabaseConnection
```

Next year:

```zig
WebSocket
```

Mailbox code never changes.

Pool code never changes.

Only:

```zig
DATABASE_TAG
```

gets added.

This is an **open-world runtime extension mechanism**.

Tagged unions are usually a **closed-world compile-time mechanism**.

---

## The deeper question

If Zig has:

```zig
Io.Select
Future
Group
Queue
```

and Matryoshka is becoming more Io-oriented, then the natural question becomes:

```text
Do we still need runtime tags at all?
```

For pure application events:

```zig
union(enum) {
    timer,
    network,
    shutdown,
}
```

probably not.

For Matryoshka's intrusive infrastructure:

```zig
Mailbox
Pool
Ownership transfer
Infrastructure-as-items
```

you still need some runtime identity after everything becomes:

```zig
*PolyNode
```

Otherwise there is no safe way to recover:

```zig
*Event
*Sensor
*MailboxHandle
*PoolHandle
```

from the same intrusive queue.

So the real answer is:

```text
Tagged unions answer:
    "Which variant is this value?"

PolyNode tags answer:
    "Which concrete object is behind this type-erased pointer?"
```

Those are different problems.

If Matryoshka eventually evolves toward a more Io.Select-centric architecture, the amount of code using tags may decrease, but as long as the core transport type remains:

```zig
*PolyNode
```

some form of runtime identity is still required.
