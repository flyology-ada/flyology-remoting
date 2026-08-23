# Architecture

This document records the initial architecture of Flyology Remoting. The
decisions establish semantic boundaries; concrete public Ada declarations and
wire values remain subject to executable transport and codec tests.

## Model

One process normally hosts one remoting node. A node incarnation identifies a
particular running instance so references from an earlier process lifetime fail
closed. An endpoint is a node-scoped, generation-stamped mailbox or control
destination. Reusing endpoint storage must advance its generation.

A local Ada task may own one or more endpoints. A remote endpoint reference is
a value; it cannot contain an Ada access value, native descriptor, mapped
address, or transport object. A resolver owned by deployment configuration
selects the route to the referenced node.

The transport moves messages between endpoints. A message has semantic
metadata and one opaque encoded payload:

- source and destination endpoint references;
- message type and schema identity supplied by the codec layer;
- a message identity scoped for diagnostics and deduplication mechanisms;
- optional correlation metadata for request/reply;
- optional deadline and tracing metadata; and
- a sealed payload lease.

The protocol will define an exact bounded envelope only together with its
validation and compatibility tests. This document deliberately assigns no
wire widths, byte order, magic values, maximum sizes, or default timeouts.

## Send ownership and acknowledgment

Before submission, the caller owns a writable payload. Submission seals it.
A rejected send leaves or restores caller ownership; an accepted send transfers
ownership to remoting. Acceptance means that the selected transport owns the
message, not that a peer received or processed it.

Remote receipt, task start, and application processing are separate protocol
milestones. A caller needing confirmation requests an explicit receipt or
application response. A transport must not infer success from local socket
acceptance, descriptor handoff, or shared-queue publication alone.

The intended payload lifecycle is:

```text
vacant -> writable -> sealed -> transport-owned -> receiver-owned -> released
                     |              |
                     +-- rejected --+--> caller-owned
```

Every state transition has one owner. Abandonment, cancellation, timeout, and
peer failure must either restore caller ownership before rejection or release
transport-owned storage exactly once.

## Common transport contract

All transports implement the same conformance contract:

1. Capacity is bounded and backpressure is explicit.
2. Accepted messages are delivered at most once within a live session.
3. Messages accepted from one source endpoint to one destination endpoint are
   observed in acceptance order within that session.
4. A reconnect creates a new session. Version one performs no implicit replay.
5. Deadline expiry bounds local waiting; it does not prove that a previously
   delivered message was ignored remotely.
6. Cancellation can stop pending transport work but cannot retract delivery.
7. Overload, incompatibility, authorization failure, disconnection, deadline
   expiry, and local resource exhaustion remain distinguishable.
8. Resource bounds and allocation points are visible in construction or
   configuration. A transport does not hide an unbounded queue or retry loop.

Transport selection is opaque to ordinary messaging code, not to deployment,
security configuration, diagnostics, or performance observation. The common
contract is intentionally no stronger than every transport can implement.

## Transport layers

### In-process reference transport

The first transport is an executable reference model. It uses bounded
single-owner payload transfer and establishes the conformance suite without
IPC framing or network failure injection. It is not a special fast-path API.

The implemented first slice is a generic unidirectional lane over a
caller-owned Flyology buffer pool. Its writable and received payload handles
are different limited types: only the sender can borrow mutable storage, while
the receiver gets callback-scoped read access. Nonblocking send and receive
make ownership-preserving backpressure, closure, FIFO order, and drainage
directly testable without a codec dependency.

The lane's immediate accepted, backpressure, empty, and closed results describe
only the local bounded queue. IPC and network sessions wrap that primitive and
retain the common contract's distinct disconnection, deadline, compatibility,
authorization, and resource failures.

### Shared-memory IPC transport

The IPC transport separates setup and signaling from bulk data:

- A dedicated Flyology shared-memory handoff channel transfers one backing
  descriptor during session setup or segment replacement.
- A different Unix-domain connection authenticates the peer, negotiates the
  protocol, carries lifecycle control frames, and provides readiness wakes.
- A Flyology shared-memory segment contains validated relocatable allocation
  state and bounded queues of message descriptors.
- Published descriptors contain offsets, lengths, generations, and semantic
  metadata rather than process-local addresses.

The descriptor handoff channel cannot carry ordinary remoting frames because
Flyology requires that channel to remain dedicated to its one-byte,
one-descriptor protocol. Successful handoff is only a local kernel milestone;
the receiver must acknowledge completed mapping, segment attachment, and
protocol validation before cutover.

The sender may encode directly into a shared allocation and publish only its
descriptor. The receiver validates the complete extent before creating a
borrowed read-only view. Protocol-level sealing does not make writable shared
pages physically immutable. Version one therefore treats IPC participants as
mutually trusted members of one security boundary.

Segment replacement follows Flyology's quiescent replacement model. Remoting
must stop producers and consumers, hand off the replacement, await attachment,
and select one snapshot before resuming. It must not mutate both snapshots.

### Network transport

The initial network transport is a framed, ordered byte stream over a managed
Flyology connection, with TLS selected by deployment policy. It uses the same
semantic envelope and encoded payload as IPC, but it need not share the IPC
queue representation. Framing, handshake, flow control, and protocol errors
belong to remoting; descriptor readiness, connection ownership, TLS progress,
and cancellation remain in Flyology.

TLS authenticates transport peers only according to its configured trust
policy. Authorization of nodes, task kinds, and endpoints remains a remoting
or application policy.

## Registered task kinds

Remote execution is a protocol above messaging. Each destination executable
registers a bounded catalogue of task kinds. A start request names a task kind
and version and carries one encoded initialization message. The destination
either rejects it explicitly or creates an ordinary supervised Ada task and
returns a control endpoint.

The destination selects `Flyology.Native_Task` or
`Flyology.Lightweight_Task` according to its local registration and policy.
The caller does not transfer an Ada task identity, stack, closure, master,
protected object, rendezvous, or execution-group assignment.

Cancellation is a request delivered to the destination supervisor. It should
normally drive a Flyology cancellation token and structured cleanup; it is not
a claim that distributed abort is instantaneous. Waiting observes a published
completion outcome. A lost connection does not by itself prove that the task
stopped.

Exactly-once task start is not an initial guarantee. If retryable start is
later required, the start protocol must define an idempotency identity,
deduplication lifetime, retained outcome, and bounded storage policy.

## Package boundaries

The planned public surface is layered rather than transport-specific:

- `Flyology.Remoting` owns common vocabulary and high-level operations.
- Endpoint and message packages own references, payload leases, send/receive,
  and request/reply correlation.
- A transport SPI owns bounded session progress and normalized outcomes.
- Concrete in-process, shared-memory, and network adapters remain below that
  SPI.
- A task-kind registry and supervisor own start, cancellation, and completion.
- The sibling codec crate owns type eligibility, schema identity, encoded
  representation, validation, and schema evolution.

Applications do not receive a transport class-wide object with which to branch
on local versus network operation. Construction and deployment code installs
routes and security policy; application code uses endpoint references.

## Failure and trust boundaries

The design assumes crash-stop peers initially. It does not yet provide durable
queues, process-death recovery for abandoned shared-memory guards, Byzantine
shared-memory protection, namespace discovery, executable deployment, or
cross-node consensus.

Every external envelope, frame, shared-memory descriptor, extent, length,
generation, type identity, and state transition is validated before use.
Malformed or incompatible peer input fails the affected session closed. A
transport must drain or release every kernel-owned or shared payload before
reclaiming its storage.
