# Roadmap

The implementation proceeds by proving one semantic layer at a time. Later
milestones do not weaken the conformance contract established earlier.

## 1. Contract and in-process transport

Status: In progress. The bounded opaque-payload lane and its initial ownership,
backpressure, FIFO, concurrent handoff, closure, and cleanup tests are present.

- Define endpoint references, payload lease ownership, normalized outcomes,
  and session identity without fixing a serialization format.
- Implement a bounded in-process transport.
- Build a reusable transport-conformance suite covering order, backpressure,
  deadlines, cancellation races, closure, and exact ownership release.
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

- Add a bounded registered task-kind catalogue.
- Implement start acceptance, control endpoint publication, cancellation, and
  completion observation under local supervision.
- Specify node incarnation and stale-handle behavior.
- Add request/reply facades and application receipts as messaging layers.

## Deferred

Durable queues, automatic replay, cross-session deduplication, exactly-once
task start, peer discovery, rolling executable deployment, and untrusted
shared-memory peers require separate designs and are not implied by this
roadmap.
