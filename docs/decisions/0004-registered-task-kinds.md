# 0004: Start only registered task kinds

Status: Accepted

## Context

Moving arbitrary task bodies would also require code distribution, ABI and
dependency agreement, captured-state serialization, stack migration, and
security policy. Those problems are separate from message transport.

## Decision

A destination executable registers a bounded catalogue of task kinds. A start
message selects a registered kind and supplies encoded initialization data. The
destination creates and supervises an ordinary native or lightweight Flyology
task and publishes a control endpoint.

## Consequences

Deployment remains explicit and auditable. Remote task handles represent
control protocol state, not Ada task identities. Cancellation and completion
are messages observed through the destination supervisor.
