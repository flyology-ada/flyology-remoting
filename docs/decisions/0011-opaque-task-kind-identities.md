# 0011: Use opaque task-kind identities with exact versions

Status: Accepted

## Context

Decision 0004 requires a bounded catalogue of registered task kinds but does
not define their public identity or version selection. Reusing a payload schema
identity would couple executable behavior to initialization representation.

## Decision

`Task_Kind_ID` is an ordered sequence of exactly 16 octets whose all-zero value
is invalid. `Task_Kind_Version` is a semantic nonzero unsigned 32-bit value.
This decision assigns no independent remoting byte encoding to either value. A
separately reviewed future task-start `flyology_wire` control-message schema
will encode both fields under its selected profile. Its accepted schema lock,
family identity, and fingerprint are prerequisites for task-start protocol
implementation.

A start request selects one exact `(Task_Kind_ID, Task_Kind_Version)` pair.
Version one performs no range negotiation, implicit fallback, or selection of
the latest registered version. Unknown identity and known identity with an
unsupported version remain distinct rejection outcomes.

Task-kind identity is separate from the complete wire `Schema_Identity`, its
`Family_ID`, the initialization schema revision, node-global `Task_ID`,
executable identity, and Ada type identity. Assignment and persistence of
task-kind identities belong to the application or deployment.

The destination catalogue has fixed capacity. Registration and sealing share
one task-safe linearization in the catalogue's protected state. They report
distinct deterministic local results for duplicate pair, capacity exhaustion,
and registration after sealing. The catalogue is sealed before any remote
task-start dispatch or admission. Each entry binds statically deployed code,
local supervision and control capability, initialization-codec expectations,
and launch authorization policy. No code, access value, callback address, or
Ada runtime tag crosses the transport boundary.

A single catalogue-level pre-lookup disclosure policy, evaluated from the
authenticated session before inspecting entries, decides whether that caller
may distinguish unknown identity from unsupported version. The default policy
returns one common remote rejection; local diagnostics preserve the exact
cause. Entry launch authorization is evaluated only after exact lookup and
cannot alter the unknown-identity versus unsupported-version disclosure. A
supported exact pair may subsequently return the distinct
`Authorization_Rejected` outcome required by the accepted failure contract.

Retrying a start request has no exactly-once guarantee. Any later retryable
start protocol must separately define an idempotency identity, retention
lifetime, and bounded deduplication policy.

## Consequences

Task behavior can evolve independently of its initialization payload schema.
Catalogue lookup is bounded and deterministic. Rolling deployments explicitly
register every supported version.

Catalogue duplicate, exhaustion, unknown-identity, unsupported-version,
authorization-disclosure, and sealed-state tests are required before
acceptance. Control-message family identities, fingerprints, and schema locks
remain separate reviewed interoperability assignments.

## Alternatives

- Use human-readable names.
- Reuse wire family identities or schema fingerprints.
- Select an implicitly compatible or latest version.
