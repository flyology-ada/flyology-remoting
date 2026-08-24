# Architecture

This document records the initial architecture of Flyology Remoting. The
decisions establish semantic boundaries; concrete public Ada declarations and
wire values remain subject to executable transport and codec tests.

## Model

One process normally hosts one remoting node. A caller-supplied stable node ID
identifies the logical node across restarts, while a caller-supplied incarnation
identifies one running instance so references from an earlier process lifetime
fail closed. An endpoint is a node-scoped, generation-stamped mailbox or
control destination. Reusing endpoint storage advances a nonwrapping
generation.

A local Ada task may own one or more endpoints. A remote endpoint reference is
a value; it cannot contain an Ada access value, native descriptor, mapped
address, or transport object. A resolver owned by deployment configuration
selects the route to the referenced node.

The transport moves messages between endpoints. A message has semantic
metadata and one opaque encoded payload:

- source and destination endpoint references;
- the writer schema identity supplied by the codec layer, whose family is the
  message family/type identity;
- a message identity scoped for diagnostics and deduplication mechanisms;
- optional correlation metadata for request/reply;
- optional deadline and tracing metadata; and
- a sealed payload lease.

Version one has an exact 144-byte big-endian header defined by decision 0009.
It carries magic and version fields, checked header and payload lengths,
reserved flags, message and optional correlation identities, source and
destination endpoint slots and generations, and the canonical 56-byte
`flyology_wire` writer schema identity. Complete node references and the
session identity come from the exact role-bound session rather than repeating
in each message. Header, payload, and complete-message limits remain explicit
construction or session configuration; no default timeout is assigned.

The logical encoded message is a compound sealed header lease plus an opaque
payload lease. IPC publishes their relocatable extents. A network adapter sends
the same logical byte sequence with a bounded two-segment state machine;
provider gather I/O is optional. Re-enveloping may retain the immutable payload
bytes while constructing and validating a new session-bound header.

A live session value names its initiator node incarnation, acceptor node
incarnation, and a nonreused session ID. Reconnect creates a new value. The
identity constructors generate no entropy and perform no authentication;
deployment and session establishment supply and authorize their values.

## Send ownership and acknowledgment

Before submission, the caller owns a writable payload while remoting's bounded
builder owns its fixed-capacity header token. Submission seals the header. A
rejected send releases the header and leaves or restores payload ownership; an
accepted send transfers payload ownership and atomically publishes it with the
already remoting-owned sealed header at the sending session's first bounded
outbound queue. Acceptance means that the selected transport owns both
segments, not that a peer received or processed the message.

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

The compound in-process lane implements the two-segment ownership mechanism
required by decisions 0009 and 0010 with separate caller-owned payload and
canonical-header pools. It remains binding-agnostic and therefore is not yet
decision 0010's high-level session acceptance queue. A limited builder holds a
noncopyable reservation and one sealed 144-byte header lease. Every access to
the private payload channel occurs under one outer protected gate, which moves
the header into a fixed registry slot and the payload into the channel within
one abort-deferred action. Private channel metadata associates the queued
payload with that occupied header slot and never escapes, so the slot needs no
generation. Receive atomically moves both leases into one limited immutable
message before reusing the slot.

Every rejected commit releases its sealed header and retains the payload; the
limited builder object may then be prepared again. Accepted forwarding moves
the original payload without copying, publishes a newly sealed contextual
header, and releases the old header within
the same protected action. Close fences new builders; callers may drain
accepted pairs, and lane finalization performs a nonraising pair drain. Header
pool capacity must cover at least the queue plus active builders. Additional
leases retained by receivers can cause shared-pool contention, which remains an
explicit local resource outcome rather than hidden allocation.

The compound lane currently uses the narrow `Flyology.Buffers.Drivers`
detached-token SPI because each lane selects its header pool at run time while
the fixed registry requires a definite stored type. This is a reviewed
provider coupling, not an application API. It must be promoted to a stable
Flyology buffer capability or replaced before a compatibility release of
remoting.

The exact-binding in-process session ingress wraps that primitive without
exposing its lane, builders, or raw-header path. One limited session retains an
immutable `Sessions.Binding`; complete source and destination endpoint
references are validated against that binding before header reservation. The
wrapper derives payload length from the owned lease and constructs the relative
V1 header privately. Atomic compound enqueue is therefore the immediate
decision-0010 acceptance point.

Transport-facing dequeue publishes both leases and a by-value copy of the
exact binding in one abort-deferred action. Complete endpoint references are
reconstructed only from that retained binding plus the sealed header's slots
and generations. Forwarding validates a new outbound binding and replaces only
the contextual header. A dedicated header pool is required for every live
session and must outlive its dequeued messages. Session close fences admission
and synchronously drains queued descriptors; it does not classify the peer or
node as dead.

This immediate ingress is not destination delivery or full session
conformance. The existing endpoint-aware node is payload-only and cannot be
the next hop without losing header and binding context. Deadlines,
cancellation, authoritative-death fencing, and post-acceptance delivery
outcomes remain separate reviewed layers.

The endpoint-aware reference node builds a fixed mailbox array over those
lanes. A protected gate validates and pins exact endpoint generations around
each nonblocking queue operation. Closing prevents new pins, waits for existing
operations, drains and releases accepted payloads, and retires the generation
before its slot can be reused. Endpoint and mailbox capacity are explicit
generic parameters. A limited controlled endpoint handle owns each claim and
closes it during finalization, including owner abort and exceptional exit.

The lanes' immediate accepted, backpressure, local-resource, empty, and closed
results describe only the local bounded queue. IPC and network sessions wrap that primitive and
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

Decision 0011 fixes each task kind as an exact nonzero opaque 16-octet identity
plus a nonzero 32-bit version. Registration and sealing share one task-safe
bounded catalogue linearization, while authenticated prelookup policy controls
unknown-versus-unsupported disclosure. The catalogue and its future reviewed
Wire control-message schema are not implemented yet.

The destination selects `Flyology.Native_Task` or
`Flyology.Lightweight_Task` according to its local registration and policy.
The caller does not transfer an Ada task identity, stack, closure, master,
protected object, rendezvous, or execution-group assignment.

Cancellation is a request delivered to the destination supervisor. It should
normally drive a Flyology cancellation token and structured cleanup; it is not
a claim that distributed abort is instantaneous. Waiting observes one exact
generation and never follows a replacement. A portable task reference contains
the exact node incarnation, logical task ID, and nonwrapping generation. The
node registry allocates logical task IDs from one nonwrapping space for the
whole node incarnation and maps them to exact local supervisor handles;
supervisor-local child IDs never cross that boundary.
Destination adapters convert `Flyology.Supervision.Wait_Termination` into
bounded `Task_Ended` or `Task_Replaced` observations. An authoritative node
incarnation monitor may report `Node_Incarnation_Ended`; a lost connection
alone reports only `Peer_Unreachable` and does not prove that the task stopped.

Decision 0012 permits that authoritative result only from an exact directly
owned `Flyology.Subprocesses.Process` after capability proof and a session
handshake that authenticates the same exact bound node incarnation. Its
one-shot monitor, arm-versus-exit state, session fencing, resumable cleanup,
and bounded retirement are accepted but not implemented.

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
generation, schema identity, and state transition is validated before use.
Malformed protocol input, handshake incompatibility, invalid framing, and the
payload statuses `Malformed`, `Noncanonical`, `Limit_Exceeded`, or
`Invalid_Value` fail the affected session closed. `Incompatible` for an
otherwise valid message is a directional schema result at message scope and
does not by itself close the session. A transport must drain or release every
kernel-owned or shared payload before reclaiming its storage.

Wire codec descriptors are Ada values rather than stable memory ABIs. An
envelope encodes each family, fingerprint, revision, and profile field using
`flyology_wire`'s canonical representation and validates its zero sentinels; it
never copies a descriptor object's memory representation into a frame.
