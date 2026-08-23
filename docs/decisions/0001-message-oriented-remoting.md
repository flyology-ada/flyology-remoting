# 0001: Use message-oriented remoting

Status: Accepted

## Context

Ada task identity, rendezvous, protected objects, masters, stacks, and live
state are process-local. Treating them as transparently remote would either
misrepresent their semantics or require a second distributed implementation of
Ada tasking.

## Decision

The remoting boundary consists of nodes, endpoints, and opaque encoded
messages. One-way messaging is primitive. Request/reply and remote task control
are protocols layered above correlated messages.

## Consequences

Application messaging code can remain independent of IPC or network transport.
Remote calls do not inherit local Ada call or rendezvous semantics. Delivery,
processing, cancellation, and completion acknowledgments must be explicit.
