# matryoshka-io

## The problem

> There is no **coherent "Zig + Io system architecture layer"**. There are only isolated implementations of individual patterns.

**This is the message. Don't shoot the messenger.**

Matryoshka is the first, maybe naive, attempt to solve this problem.

Matryoshka-io is about **building systems**, not about showcasing Zig Io.

## Three building blocks

Matryoshka-io is built around only three small sources:

* **PolyNode** — everything exchanged.
* **Mailbox** — everything communicates.
* **Pool** — everything reusable.

That's it.


## One architectural role

Matryoshka introduces one architectural concept:

**Master**.

Master is:

* not a class
* not a base type
* not a runtime
* not an interface

Master is a **role**.

Every _independently executing part_ of the system is a **Master**.

A Master may:

* own private state;
* own shared resources;
* coordinate other Masters;
* perform all of these responsibilities.

A _worker_ is simply a Master with one dedicated responsibility.

There is no fundamental distinction between a "master" and a "worker". 

The difference is only the role they perform.

## Zig Io is an implementation detail

Future, Group and Select are **not** fundamental Matryoshka concepts.

They are integration layers that allow Matryoshka to use Zig Io where it provides practical benefits.

The architecture does not depend on Zig Io.

If Zig Io evolves, only the implementation should change. 

The architectural concepts remain the same.

## Matryoshka Manifest

**Matryoshka-io is:**

* a toolkit for building concurrent systems;
* based on three building blocks:

    * **PolyNode**
    * **Mailbox**
    * **Pool**
* organized around one architectural role:

    * **Master**

Zig Io is used internally where it helps.

It is an implementation detail, **not the architecture**.
