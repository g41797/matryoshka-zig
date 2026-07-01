I think the current organization is mixing **language idioms**, **ownership**, **containers**, and **Io architecture**. That forces the reader to jump between abstraction levels.

For a reference manual, I'd organize it like this:

```text
patterns-001.md
================
Part I. Core Language Patterns
------------------------------
1. Slot ownership
   - Empty slot
   - Slot overwrite prevention
   - Transfer clears ownership
   - Null-safe cleanup
   - Acquire-after-defer
   - Fallback destroy

2. PolyNode
   - PolyHelper
   - Safe cast
   - Tag identifies class
   - Wrapper types
   - Mailbox as message
   - Pool as message

3. Error handling
   - Close vs Cancel
   - Cancellation boundary
   - Cancellation preserves ownership


patterns-002.md
================
Part II. Container Patterns
---------------------------

4. Mailbox
   - send/receive ownership
   - try_receive
   - batch receive
   - OOB messages
   - close recovery

5. Pool
   - Pool lifecycle policy
   - available_or_new
   - available_only
   - new_only
   - on_get
   - on_put
   - on_close
   - hook synchronization
   - multi-tag pools
   - seeding
   - fixed-size pools

6. Future
   - direct future
   - cancellation
   - timeout


patterns-003.md
================
Part III. Io Runtime Patterns
-----------------------------

7. Io.Group
   - spawn
   - await
   - reusable group
   - shutdown by close
   - shutdown by cancel

8. Io.Select
   - mailbox event source
   - pool event source
   - timer source
   - external push
   - one-shot registration
   - register-await-reregister
   - cancel walk
   - cancelDiscard

9. Backpressure
   - pool wait
   - producer throttling
   - Select + Pool

10. Integration
    - Mailbox + Pool
    - Master + Workers
    - Thin run()
    - Layer-4 architecture
    - Graceful shutdown sequence
```

I would also move a few patterns:

| Pattern                          | Current      | Better place               |
| -------------------------------- | ------------ | -------------------------- |
| Close vs Cancel                  | Cancellation | Core Language              |
| Cancellation boundary            | Cancellation | Core Language              |
| Cancellation preserves ownership | Cancellation | Core Language              |
| Mailbox as message               | PolyNode     | PolyNode (keep)            |
| Pool as message                  | PolyNode     | PolyNode (keep)            |
| Acquire-after-defer              | Ownership    | Ownership (first section)  |
| Backpressure                     | Pool         | Io Runtime                 |
| Graceful shutdown                | standalone   | Integration (last chapter) |
| Master composition               | standalone   | Integration (last chapter) |

I would also remove several patterns because they are not really independent patterns:

* Hook decision pattern (it's just `on_get` behavior)
* One-shot event registration (already implied by register→await→reregister)
* Reusable Group (property, not a pattern)
* Multi-tag pool (just a capability unless accompanied by an architecture example)

So the catalog becomes progressively more complex:

1. **Ownership** (everything builds on this)
2. **PolyNode** (runtime typing)
3. **Mailbox** (communication)
4. **Pool** (resource management)
5. **Future** (single async operation)
6. **Io.Group** (parallel execution)
7. **Io.Select** (event multiplexing)
8. **Backpressure**
9. **Complete architectures**
