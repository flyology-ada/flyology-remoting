# 0003: Separate the IPC data and control planes

Status: Accepted

## Context

Flyology can transfer shared-memory backing descriptors and operate on
relocatable shared layouts. Its owned descriptor handoff channel is deliberately
restricted to one byte and one descriptor and cannot share ordinary traffic.

## Decision

The IPC data plane stores sealed encoded payloads and bounded queues of
relocatable descriptors in shared memory. A dedicated handoff channel transfers
backing descriptors. A separate Unix-domain control connection handles peer
authentication, negotiation, wakes, acknowledgments, and lifecycle frames.

## Consequences

The payload need not be copied between processes after encoding. Setup and wake
traffic does not violate the handoff channel contract. Writable shared mappings
mean IPC participants belong to one trust boundary in the first design.
