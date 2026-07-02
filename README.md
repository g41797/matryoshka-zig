# matryoshka-io

## Intent

We know how to write Zig libraries.

We are still learning how to build Zig systems.

Zig **Io** makes developers' lives even more _interesting_.

**Matryoshka** is my attempt to make them a little more _boring_.

## Three small building blocks

Matryoshka-io is built on only three small source files.

### PolyNode

`PolyNode` is the bigger brother of Zig's intrusive `Node`.

It adds one capability:

* simple run-time type identification.

It remains suitable for:

* intrusive lists;
* intrusive queues;
* other intrusive containers.

A `PolyNode` knows its concrete type without requiring:

* inheritance;
* interfaces;
* virtual functions.

### Mailbox

`Mailbox` transfers `PolyNode` objects between _Masters_.

It is type-erased.

It does not know or care about the concrete object type.

It transfers ownership together with the object.

### Pool

`Pool` reuses `PolyNode`-based objects.

It is type-erased.

It does not know or care about the concrete object type.

It returns objects for reuse instead of destroying them.

### Intrusive containers on steroids

If

- `PolyNode` is the bigger brother of Zig's intrusive `Node`

then

- `Mailbox` and `Pool` are intrusive containers on steroids.

The steroids are simple:

* ownership transfer;
* object reuse.

Nothing more.

* No interfaces.
* No inheritance.
* No framework.

Just three small source files.

> Together, these three building blocks provide only two capabilities:
>
> * move objects;
> * reuse objects.

## One architectural concept

Matryoshka also introduces one architectural concept.

**Master**.

Master is a role.

Master is **not**:

* a type;
* an interface;
* a base class;
* a runtime.

A Master:

* has a relatively long lifetime;
* owns Matryoshka building blocks;
* owns internal state;
* performs a dedicated responsibility.

Some Masters also:

* coordinate other Masters;
* own shared resources.

A worker is simply a Master with a single dedicated responsibility.

## Matryoshka-based system

A Matryoshka-based system is built from Masters.

Masters:

* own state;
* communicate through Mailboxes;
* share reusable objects through Pool(s).

Matryoshka doesn't dictate the implementation.

## The role of Zig Io

Matryoshka-io uses Zig Io in two situations.

### Required by Zig

Some operations must use Zig Io because Zig provides them only through the Io API.

Matryoshka uses Io where it is required, but the architectural concepts remain unchanged.

### Useful Io features

Some Io features make Matryoshka better integrated with the Zig Io ecosystem.

Examples include:

* waiting for multiple event sources;
* timers;
* cancellation;
* integration with other Io-based libraries.

These capabilities extend Matryoshka.

They do not define it.

## Why use Matryoshka with Zig Io?

Think about cars.

* A traditional threaded application is a _conventional_ car.
* A pure Io-based application is an _electric_ car.
* Matryoshka-io is a _**hybrid**_.

Matryoshka:

* keeps the architecture simple;
* uses Zig Io where Zig requires it;
* uses Zig Io where it provides additional functionality.

Build Zig systems today.

If Zig Io changes tomorrow—and it will—your architecture stays the same.
