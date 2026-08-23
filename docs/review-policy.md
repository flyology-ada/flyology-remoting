# Review policy

Every architecture decision and repository change receives an explicit review
before commit. The review is repeated after corrections so the final result,
not only the first draft, is assessed.

## Priorities

- **P0**: The change can cause catastrophic data loss, security compromise,
  undefined ownership, or a fundamentally unusable protocol. It blocks commit.
- **P1**: The change violates an accepted invariant, introduces a likely
  correctness or lifetime failure, or makes the documented contract materially
  false. It blocks commit.
- **P2**: The change has a bounded correctness, compatibility, operability,
  maintainability, or test gap that should normally be corrected in scope. It
  may be deferred only with a concrete rationale and follow-up location.
- **P3**: A nonblocking improvement, clarification, or simplification.

## Architecture review

Check every new or changed decision for:

1. Dependency direction and separation from `flyology_wire` and Flyology.
2. Payload, descriptor, task, operation, and connection ownership.
3. Bounds, allocation points, backpressure, and cleanup.
4. Ordering, delivery, acknowledgment, reconnect, retry, and cancellation
   semantics.
5. Failure classification and what each success milestone proves.
6. Trust, authentication, authorization, and malformed-peer behavior.
7. Versioning, negotiation, compatibility, and stale-reference behavior.
8. Public values or policy choices that have not yet been authorized.
9. Consistency between decision records, architecture, roadmap, and code.

## Change review

Check every implementation change for:

1. Conformance with accepted decisions and public Ada contracts.
2. Single ownership before, during, and after success, rejection, cancellation,
   exception, closure, abandonment, and finalization.
3. Correct Ada accessibility, discriminant, limited-type, controlled-type, and
   task-lifetime behavior.
4. Bounded queues, loops, retries, memory, parsing, and peer-controlled work.
5. Native/lightweight task behavior and absence of hidden blocking on an event
   loop.
6. Tests for normal behavior, limits, negative outcomes, races, and cleanup.
7. Documentation and changelog accuracy.
8. Build, formatting, line-length, and diff checks.

## Completion record

The change handoff or commit preparation should state:

- checks executed and their results;
- review findings by priority;
- fixes made;
- any dispositioned P2 with its rationale and follow-up location; and
- confirmation that the final review has no open P0 or P1 finding.
