# 0009: Bind the version-one envelope to an established session

Status: Proposed

## Context

Messages need one canonical representation across in-process, IPC, and network
transports. Complete endpoint references contain node incarnations, but a live
session already binds exact initiator and acceptor nodes plus a nonreused
session identity. Repeating those values in every message increases the fixed
header without strengthening authentication.

Accepted decision 0005 describes endpoint, session, message, correlation,
deadline, and tracing metadata semantically. If accepted, this decision amends
0005 by distinguishing semantic message context from fields encoded in the
version-one envelope: session, deadline, and tracing values are not present in
the version 1.0 header.

## Decision

An established session supplies complete initiator and acceptor
`Node_Reference` values and its `Session_ID`. Every admitted descriptor and
queue item is inseparably associated with that exact
`Flyology.Remoting.Sessions.Binding`; an admitted entry cannot be
recontextualized under another binding. Per-message bytes carry endpoint slots
and generations. A decoder reconstructs complete endpoint references from the
session role and message direction, then validates them through the session
binding before delivery.

The logical encoded message is a compound descriptor with two ordered segments:
an owned mutable header lease and an opaque payload lease. Its canonical byte
sequence is the concatenation of those segments. An IPC queue publishes both
relocatable segment extents. A network transport uses a bounded two-segment send
state machine: it retains both leases in one serialization slot and sends the
header followed by the payload under one shared deadline and cancellation
budget. A provider gather write is an optional optimization, not a version-one
dependency. A received contiguous frame remains owned by its transport lease
and may expose immutable header and payload slice tokens tied to that owner; no
retained Ada access value is created.

After receipt, the immutable payload lease may transfer without copying into a
new compound descriptor on another session. Forwarding allocates and constructs
a new owned header, validates the new envelope and route, and leaves the payload
bytes unchanged. It never requests writable access to the received payload or
reuses the earlier contextual header.

The new header is writable only during construction. Complete local validation
then seals it into an immutable, non-writably-borrowable lease before send
acceptance or queue publication. This is a protocol ownership seal even when
IPC mappings remain physically writable. Header storage comes from a configured
fixed-capacity per-session pool. A bounded precommit builder slot reserves one
header token before any payload ownership change; pool or builder-slot
exhaustion reports precommit `Local_Resource_Exhausted`, not acceptance. Before
send commit, the builder owns the header token while the caller or forwarder
retains the payload. A rejected or interrupted construction releases the token
exactly once and leaves or restores the payload owner; no transport may observe
a partially constructed or subsequently mutable header.

An in-process high-level session owns a bounded ingress queue ahead of endpoint
delivery. Its entries retain the exact session binding with the encoded lease.
IPC and network queues are themselves owned by one exact session binding. A
session close drains and releases its accepted entries exactly once. Entries
from a closed or replaced session are never decoded or delivered under a new
session, even when the endpoint slot and generation remain current.

Version 1.0 uses this fixed 144-byte base header. Every offset is measured in
octets relative to the header array's `First` bound:

| Offset | Size | Field |
| ---: | ---: | --- |
| 0 | 4 | ASCII magic `FLYR` |
| 4 | 2 | Major version, `1` |
| 6 | 2 | Minor version, `0` |
| 8 | 4 | Header length, `144` |
| 12 | 8 | Payload length |
| 20 | 4 | Reserved flags, zero |
| 24 | 16 | Nonzero message identity |
| 40 | 16 | Correlated request message identity; all-zero means absent |
| 56 | 8 | Source endpoint slot |
| 64 | 8 | Source endpoint generation |
| 72 | 8 | Destination endpoint slot |
| 80 | 8 | Destination endpoint generation |
| 88 | 56 | Canonical `flyology_wire` schema identity |

Scalar integers use unsigned big-endian encoding. `Message_ID` is an ordered
sequence of exactly 16 octets in transmitted index order; the all-zero sequence
is invalid and every nonzero sequence is structurally valid. The correlation
field is either all zero for no correlation or an exact copy of the
`Message_ID` of the request being correlated. Correlation matching and pending
request retention belong to the later request/reply layer.

A version 1.0 encoder emits exactly 144 header bytes, and a version 1.0 decoder
accepts only a header length of 144. A future negotiated minor version may
assign extension bytes after the base header.

The payload segment has exactly `Payload_Length` bytes. The compound
descriptor's logical extent must equal the checked sum of `Header_Length` and
`Payload_Length`; an IPC or message descriptor permits no trailing bytes in
either segment or their logical concatenation. A contiguous received frame
places the payload at the checked offset `Input'First + Header_Length`.
Configuration supplies bounded maximum header, payload, and complete-message
sizes. Every addition and conversion is checked before slicing, publishing
semantic header fields, or borrowing storage.

The writer `Schema_Identity` is decoded and validated once, then passed
unchanged to the selected codec. A codec may write directly into the payload
slice.

Unknown major versions, unnegotiated minor versions, nonzero flags, invalid
identities, invalid directional routes, arithmetic overflow, configured-limit
excess, and inconsistent complete extents fail the session closed.

Message identities are caller-supplied, nonzero, and not reused by one sender
within a live session. Nonreuse is a trusted-sender invariant, not an implicit
receiver deduplication table. Message identities do not provide durable or
cross-session deduplication. Deadlines and tracing are not encoded in version
1.0.

The session-establishment protocol must authenticate and authorize the bound
node incarnations and session identity. This envelope supplies no
authentication. Its acceptance does not define that handshake or its
capability negotiation.

## Consequences

IPC can publish a compound message lease without copying payload bytes, while a
network transport can frame the identical logical byte sequence. Re-enveloping
copies or rewrites only the fixed header. Captured bytes require their session
binding to reconstruct complete endpoints. The in-process node's current
payload-only mailbox remains a lower-level primitive; high-level session
delivery extends its bounded entry with exact session context. Reconnect
establishes a new contextual boundary and performs no implicit replay.

Fixed byte fixtures, arbitrary-bound array tests, complete-extent overflow
tests, and fragmented network-input tests are required before acceptance.
Compound-ownership tests must cover two-segment allocation rollback, rejected
and aborted forwarding with payload restoration and header release, accepted
transfer vacating both source handles, exact release of both extents after close
or partial network failure, and prohibition of a retained slice after its
backing owner releases. Fault injection immediately after header allocation and
after sealing but before payload commit, plus after compound commit and before
drain, must restore full pool capacity and detect both leaks and double release.
Capacity tests must fill every builder and header-pool slot concurrently, prove
the next attempt reports `Local_Resource_Exhausted` without moving its payload,
and prove capacity is reusable after rejection, abort, and accepted drain.

## Alternatives

- Repeat complete node references and the session identity in every message.
- Use transport-specific envelopes.
- Copy Ada descriptor values as bytes despite their lack of a stable ABI.
