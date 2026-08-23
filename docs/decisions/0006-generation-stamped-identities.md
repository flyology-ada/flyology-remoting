# 0006: Make node, session, and endpoint identity explicit values

Status: Accepted

## Context

An endpoint reference must cross process and network boundaries without
containing an Ada task identity, address, access value, descriptor, or
transport object. References from a prior process incarnation or a reused
endpoint slot must fail closed. A reconnect must also be distinguishable from
the session it replaces.

## Decision

A logical node has a caller-supplied 128-bit `Node_ID` that remains stable
across restarts. Each running process has a caller-supplied, nonreused 128-bit
`Incarnation_ID`. Their pair is a `Node_Reference`.

A live session is identified by its initiator node reference, acceptor node
reference, and a caller-supplied, nonreused 128-bit `Session_ID`. Reconnect
creates a different session identity and carries no implicit replay or ordering
from the earlier session.

An endpoint reference contains its complete node reference, a nonzero 64-bit
slot, and a nonzero 64-bit generation. A bounded local directory advances the
generation whenever it reuses a slot. Generations never wrap; a slot at the
last generation becomes permanently unavailable after release. Claiming
distinguishes a temporarily full directory from permanently exhausted
generation space.

All-zero node, incarnation, session, slot, and generation values are invalid
sentinels. Constructors import scalar words and preserve invalid inputs as
invalid values so untrusted parsing can validate without relying on enabled
Ada precondition checks.

The library does not generate entropy, persist stable identities, or assert
that a supplied value is unique. Session establishment and deployment own
those responsibilities. An identity is a routing and freshness value, not
proof of authentication or authorization.

The public high/low words define semantic value spaces, not an envelope memory
layout or native ABI. Canonical byte encoding, frame layout, and negotiation
remain later remoting decisions. A future envelope must encode
`flyology_wire` descriptor fields individually in their canonical forms; it
must never copy a `Codec_Descriptor` Ada object as bytes.

## Consequences

Endpoint equality is transport-independent. A directory can distinguish a
foreign logical node, a stale process incarnation, and a stale endpoint
generation without consulting an Ada task object. Directory capacity and slot
reuse are bounded and task-safe. Callers must obtain identity material from an
appropriate configuration, random, or monotonic persistence authority before
constructing live nodes and sessions.
