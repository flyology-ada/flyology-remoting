# Roadmap

The implementation proceeds by proving one semantic layer at a time. Later
milestones do not weaken the conformance contract established earlier.

## 1. Contract and in-process transport

Status: In progress. Runtime node/session identities, a bounded
generation-stamped endpoint directory, the opaque-payload reference lane, and
an endpoint-aware in-process node are present with stale-reference, capacity,
ownership, FIFO, concurrent handoff/close, reclamation, and cleanup tests. The
published `flyology_wire` static codec contract is pinned and exercised
directly over node payload leases without an intermediate array.

- Define endpoint references, payload lease ownership, normalized outcomes,
  and session identity without fixing an envelope format. Runtime identity
  values and local endpoint allocation are complete.
- Implement a bounded in-process transport.
- Route opaque payloads through bounded endpoint mailboxes and close/drain
  exact generations before slot reuse.
- Apply statically bound wire codecs directly to writable and received payload
  leases while passing the validated writer schema unchanged. The common
  codec-over-lease adapter is transport-independent; the in-process package is
  now a thin facade over it.
- Build a reusable transport-conformance suite covering order, backpressure,
  deadlines, cancellation races, closure, and exact ownership release.
  The reusable payload-lane subset now covers FIFO order, bounded
  backpressure, ownership restoration, forwarding, empty payloads,
  close/drain, and exact release. Session deadline, cancellation, disconnect,
  and acceptance-commit cases remain pending the session SPI.
- Keep the first API one-way; add request/reply only after message correlation
  can reuse the same ownership rules.

## 2. Shared-memory IPC

- Establish a local session over authenticated Unix-domain control channels.
- Hand off and attach a Flyology shared-memory segment through a dedicated
  descriptor channel.
- Define bounded relocatable payload allocation and descriptor queues.
- Add cross-process wake, shutdown, peer-death, malformed-descriptor, and
  segment-replacement tests.
- Demonstrate direct codec output into shared storage and measure copies
  without claiming that every caller or kernel path is zero-copy.

## 3. Network sessions

- Define a versioned handshake and bounded frame parser.
- Add plain test transport and deployment-selected TLS over Flyology managed
  connections.
- Run the same conformance suite with injected fragmentation, disconnects,
  deadlines, and backpressure.
- Add interoperability fixtures only after the wire protocol is specified.

## 4. Remote task lifecycle

- Use exact node/logical-task/generation references and preserve Flyology
  supervision's ended-versus-replaced observation semantics. The value model,
  local supervision conversion, and checked exact-generation wait adapter are
  complete.
- Add a bounded registered task-kind catalogue.
- Implement start acceptance, control endpoint publication, cancellation, and
  transport delivery of completion observations under local supervision.
- Add authoritative node-incarnation death input without treating session
  disconnection as task death.
- Add request/reply facades and application receipts as messaging layers.

## Deferred

Durable queues, automatic replay, cross-session deduplication, exactly-once
task start, peer discovery, rolling executable deployment, and untrusted
shared-memory peers require separate designs and are not implied by this
roadmap.
