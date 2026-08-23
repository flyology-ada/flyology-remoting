# 0007: Route in-process messages through bounded endpoint mailboxes

Status: Accepted

## Context

The reference lane proves single-queue ownership but does not exercise an
endpoint reference, stale-generation rejection, endpoint reclamation, or the
race between routing and endpoint close. Later IPC and network transports need
those semantics independently of their framing and failure injection.

## Decision

`Flyology.Remoting.Nodes.In_Process` fixes its buffer pool, endpoint capacity,
mailbox capacity, and per-endpoint concurrent-operation bound at generic
instantiation. Each slot owns one permanent in-process lane. Claiming a free
slot advances its nonwrapping endpoint generation and returns a reference for
the node's exact incarnation. A limited controlled endpoint handle owns that
claim. Construction is abort-deferred and finalization closes the endpoint, so
an aborted owner cannot lose the only reference and permanently consume a
bounded slot.

Send and receive first validate the logical node, incarnation, slot, and
generation. A protected gate then takes a bounded operation pin before touching
the mailbox. Close marks the exact generation as closing before waiting for
existing pins to leave. It drains and releases the bounded mailbox, retires the
generation, and only then permits slot reuse. An interrupted closer leaves the
endpoint closing; a later caller may resume cleanup. At most one closer drains
a generation at a time.

The permanent internal lanes are not individually closed and reopened. Their
queue state is empty before a slot becomes available again, avoiding an
unclose operation or a second queue allocation. Payload handles retain the
reference transport's single-owner move semantics.

## Consequences

The reference node has fixed storage and no hidden retry queue. It distinguishes
foreign logical nodes, stale process incarnations, stale endpoint generations,
closing endpoints, backpressure, and local pin exhaustion. Closing an endpoint
discards accepted but unreceived payloads by releasing them exactly once; send
acceptance still does not mean application processing.

This is an executable in-process adapter, not the final transport-selection or
wire-envelope API. IPC and network sessions must implement the same lifecycle
and failure distinctions with their own bounded state.
