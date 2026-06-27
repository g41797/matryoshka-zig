# Slot vs Reference Counting

This is the next concept after understanding `Slot`.

---

## Slot answers a different question

A Slot does **not** answer:

> "When should this object be deleted?"

A Slot answers:

> "Who owns this object right now?"

These are completely different problems.

---

## Slot model

```
      Slot
        |
        v

  ---------------------
  |                   |
  |      ITEM         |
  |                   |
  ---------------------
```

A Slot either contains an Item or it doesn't.

```zig
const Item = *PolyNode;
const Slot = ?Item;
```

Ownership moves by moving the Item between Slots.

```
Slot A          Slot B

+------+        +------+
| ITEM | -----> |      |
+------+        +------+

becomes

+------+        +------+
|      |        | ITEM |
+------+        +------+
```

After the move:

* Slot A is empty
* Slot B owns the Item
* exactly one owner exists

No counting.
No sharing.
No ambiguity.

---

## Reference counting model

Reference counting answers:

> "How many owners currently exist?"

```
refcount = 3

 Owner A
      \
       \
        ITEM
       /
      /
 Owner B

 Owner C
```

Multiple owners exist simultaneously.

Object is deleted when count reaches zero.

---

## What reference counting tracks

Reference counting tracks:

```
who still uses this object?
```

Slot tracks:

```
who owns this object?
```

Different questions.

---

## Slot world

There is always one owner.

```
Mailbox
    |
    v
  ITEM
```

Later:

```
Worker
    |
    v
  ITEM
```

Later:

```
Pool
   |
   v
 ITEM
```

The Item moves.

Ownership changes.

The Item itself stays the same.

---

## Refcount world

Ownership is replaced by sharing.

```
Mailbox ----\
             \
              ITEM
             /
Worker  -----/
```

Now both can use it.

The object cannot be deleted until both release it.

---

## Why Matryoshka prefers Slots

Matryoshka is fundamentally about movement.

```
Producer
    |
Mailbox
    |
Worker
    |
Pool
```

Every step transfers ownership.

Nobody shares ownership.

Because of that:

* no refcount field
* no atomic increments
* no atomic decrements
* no cycle problems
* no ownership ambiguity

The Item always has exactly one owner.

---

## Slot and Pool

Pool does not ask:

> "Is somebody still using this Item?"

Pool already knows.

If the Item is inside the Pool:

```
Pool owns it.
```

If the Item was returned by `pool.get()`:

```
Caller owns it.
```

No counting required.

---

## Slot and Mailbox

Mailbox does not ask:

> "How many threads reference this Item?"

Mailbox already knows.

```
send()
```

moves ownership into the mailbox.

```
receive()
```

moves ownership out of the mailbox.

Exactly one owner at every moment.

---

## Physical intuition

Reference counting:

```
How many people hold the box?
```

Slot:

```
Where is the box?
```

Matryoshka is much closer to:

```
Where is the box?
```

than to:

```
How many people touch the box?
```

---

## The core idea

A Slot is not a memory-management mechanism.

A Slot is an ownership location.

```
Slot = place where an Item may exist
```

Reference counting is a lifetime-management mechanism.

```
RefCount = number of active owners
```

Matryoshka is built around ownership movement.

Therefore the primary abstraction is:

```
Slot
```

not

```
RefCount
```


Another version

Yes. That is one of the fundamental limitations of reference counting.

Reference counting can answer:

```
How many references exist?
```

It cannot answer:

```
Who owns them?
Who is using them?
Which thread has them?
Which subsystem has them?
Why are they still alive?
```

Example:

```
ref_count = 3
```

What does that mean?

```
Thread A ?
Thread B ?
Mailbox ?
Pool ?
Cache ?
Forgotten global variable ?
Reference cycle ?
```

Reference counting does not know.

It only knows:

```
3 references exist
```

Nothing more.

---

Slot ownership answers a different question.

Instead of:

```
How many references exist?
```

it asks:

```
Who owns the object right now?
```

Example:

```
Mailbox ---> Item
```

or

```
Worker ---> Item
```

or

```
Pool ---> Item
```

There is exactly one owner.

Ownership is visible.

---

Reference counting:

```
Object
  ^
  |
ref_count = 7
```

Who owns it?

```
unknown
```

---

Slot ownership:

```
+--------+
|  Item  |
+--------+
    ^
    |
  Slot
```

Move:

```
Worker Slot ----> null

Mailbox Slot ---> Item
```

After move:

```
Worker Slot  = null
Mailbox Slot = Item
```

Ownership is obvious.

---

This is why Matryoshka's model is closer to:

```
parcel passing
```

than to:

```
shared object graphs
```

A mailbox receives a parcel.

A worker receives a parcel.

A pool receives a parcel.

At every step you can point to the current owner.

---

Another way to say it:

Reference counting is a lifetime mechanism.

```
Can I delete this object yet?
```

Ownership slots are a movement mechanism.

```
Where is this object now?
Who owns it now?
```

These are different problems.

---

A useful slogan for Matryoshka documentation might be:

```
Reference counting answers:

    "Can I free it?"

Slot ownership answers:

    "Who has it?"
```

That distinction is immediately understandable even for developers who have never seen intrusive ownership systems before.

