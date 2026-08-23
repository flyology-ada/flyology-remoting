# 0010: Commit send acceptance at bounded remoting admission

Status: Accepted

## Context

Accepted decisions establish that a rejected send preserves caller ownership
and an accepted send transfers ownership to remoting, but they do not yet name
the cross-transport linearization point. Socket writes, descriptor handoff,
peer receipt, and application processing occur at different times and prove
different facts.

## Decision

Send acceptance linearizes when remoting atomically publishes the sealed
compound descriptor into the sending session's first bounded outbound queue,
after all locally decidable validation. That commit takes sole ownership of the
payload and binds it inseparably to the already remoting-owned sealed header.
Every admitted entry retains the exact session binding described by decision
0009. This decision depends on 0009 and can be accepted only with or after it.

Before that point, rejection, timeout, cancellation, disconnection,
backpressure, or builder/header-pool exhaustion releases the builder-owned
header exactly once and leaves or restores caller payload ownership. Exhaustion
is the distinct precommit `Local_Resource_Exhausted` result. After that point,
the result is `Message_Accepted`; remoting owns both segments, and later peer
rejection, payload incompatibility, partial write, or disconnection cannot
revoke acceptance or restore caller ownership.

The concrete commit points are:

- in-process: enqueue into the bounded high-level session ingress queue, before
  later destination-mailbox delivery;
- IPC: publication in the bounded remoting-owned shared queue; and
- network: transfer into the bounded session outbound queue, not socket write
  completion.

Cancellation and deadline races linearize against the same commit. If
acceptance wins, cancellation cannot retract the message. Post-acceptance
delivery failure releases transport-owned storage exactly once, fails the
affected session when appropriate, and performs no implicit replay. Session
close drains both segments of every accepted entry exactly once; no entry is
recontextualized for a reconnect.

Per-source/destination ordering is acceptance order within one live session.
Peer receipt, task start, and application processing require explicit protocol
acknowledgments and are not implied by `Message_Accepted`. A valid message whose
payload codec reports `Incompatible` produces a mandatory explicit
message-scoped outcome and leaves the session live, as required by decision
0005. Authorization rejection is likewise message-scoped unless the peer has
violated the session protocol. Malformed framing, protocol violations, and
transport delivery failures may fail the session. No asynchronous outcome
changes the completed send result.

Carrying the explicit message outcome across IPC or network requires a
separately reviewed `flyology_wire` control-message schema and accepted schema
lock. Remoting does not define a parallel payload codec or type identity for
that outcome.

## Consequences

Ownership has one transport-independent boundary. Network sessions require
bounded outbound storage, and an accepted message may still be delivered zero
times. Partial network writes do not create ambiguous caller ownership.

Conformance must inject cancellation, deadline, backpressure, close, session
drain, Ada abort, exception, abandonment, and post-acceptance failure races
around the commit point. Injection after header allocation or sealing but before
payload commit must release the header and restore payload ownership; injection
after commit must make compound drain release both segments. When an
authoritative-death source from decision 0012 is implemented, conformance must
also cover its send race: acceptance first returns `Message_Accepted` before the
failed session drains the entry; the death fence first rejects admission and
leaves or restores caller ownership.

## Alternatives

- Accept at kernel write completion.
- Accept only after peer receipt or application processing.
- Restore caller ownership after a post-acceptance failure.
