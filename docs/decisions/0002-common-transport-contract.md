# 0002: Share one bounded transport contract

Status: Accepted

## Context

In-process queues, shared-memory IPC, and network streams have different copy,
latency, security, and failure characteristics. A transport-opaque API is useful
only if it does not conceal semantic differences behind stronger promises than
some transports can keep.

## Decision

Every transport implements the same bounded, session-scoped contract:
at-most-once delivery, per-source/destination ordering within a live session,
explicit backpressure, no implicit replay, and normalized failure outcomes.
Transport construction and observability may expose route-specific details;
ordinary send and receive code does not.

## Consequences

One conformance suite can qualify every adapter. Durable delivery, global
ordering, and exactly-once execution cannot appear accidentally as properties
of a convenient local transport.
