# Flyology Remoting agent guide

## Project identity and boundaries

- The project is Flyology Remoting. Its Alire crate is `flyology_remoting` and
  its public Ada namespace begins at `Flyology.Remoting`.
- Use **native task** and **lightweight task** only for Flyology execution
  lanes. A remotely controlled task is still one of those ordinary local Ada
  tasks at its destination.
- Use **node**, **endpoint**, **message**, **session**, and **registered task
  kind** for remoting concepts. An endpoint is not an Ada task identity.
- Keep one message API across in-process, shared-memory IPC, and network
  transports. Transport opacity does not hide security, failure, or performance
  facts from configuration and observability.
- Keep serialization, type eligibility, schema evolution, and codec generation
  in the sibling codec project. Remoting owns opaque payload leases, semantic
  envelopes, framing, routing, backpressure, and remote lifecycle protocols.

## Semantic invariants

- One-way messaging is primitive. Build request/reply and remote task control
  from correlated messages.
- Version one is bounded, session-scoped, at-most-once, and does not replay
  after reconnect. Do not imply durable or exactly-once delivery.
- A send acceptance transfers payload ownership to remoting; it does not prove
  remote receipt or application processing.
- A rejected send restores caller ownership. Cancellation, abandonment, and
  failure release every transport-owned payload exactly once.
- Preserve order from one source endpoint to one destination endpoint within
  one live session. Do not imply global or cross-session order.
- A destination starts only registered task kinds already present in its
  executable. Do not add closure, stack, live-state, or code mobility.
- A remote cancellation is a request to destination supervision. It cannot
  retract an already delivered message or prove immediate task termination.
- Shared-memory descriptors contain validated offsets, extents, generations,
  and scalar metadata, never native addresses or Ada access values.
- Describe IPC as avoiding a payload copy after encoding only when the codec
  writes directly into shared storage. Do not call serialization, TLS, socket,
  or kernel paths universally zero-copy.
- Keep Flyology's descriptor handoff channel dedicated. Use another connection
  for control frames and wakes.
- Treat writable shared-memory peers as mutually trusted until a separate
  hostile-peer design exists.

## Repository workflow

- Run `git status --short --branch` before changing anything. Preserve
  unrelated user changes.
- Read `docs/architecture.md`, the relevant decision records, and the Flyology
  public implementation before changing a boundary.
- Use `rg` for discovery and `apply_patch` for hand edits.
- Keep handwritten Ada source to 110 columns. Run
  `gnatformat -P flyology_remoting.gpr <source-files>` after editing Ada.
- Add `-gnatyM110` after generated Ada compiler switches in every owning GPR
  project.
- Prefer Ada. A native C boundary requires a repository-grounded reason that
  direct Ada imports cannot express the mechanism safely.
- Run `./scripts/test.sh` and `git diff --check` before presenting a change.
- Run `gh` outside the sandbox. Repository:
  `flyology-ada/flyology-remoting`.

## Review cycle

- Run an explicit review cycle for every architecture decision and every code,
  test, build, or documentation change before committing it.
- Review architecture changes against dependency direction, ownership,
  boundedness, ordering, delivery, failure, trust, compatibility, and stated
  non-goals. Review implementation changes against the accepted decisions,
  Ada lifetime rules, cleanup on every exit, and executable test evidence.
- Classify actionable findings as P0, P1, P2, or P3 using
  `docs/review-policy.md`.
- Fix every P0 and P1 before commit. Fix P2 findings when they are reasonably
  within the change's scope; otherwise record a concrete deferral rationale and
  follow-up location. P3 findings may remain as suggestions.
- After fixes, rerun the relevant checks and repeat the review. Do not commit
  until the final pass has no open P0 or P1 finding and every P2 has been fixed
  or explicitly dispositioned.

## Commits

Use focused Problem/Solution commit messages:

```text
Problem: <one-line problem statement in the present tense>

<Context and impact.>

Solution: <one-line solution statement>

<What changed and why.>
```

Write modest, factual prose. The project is experimental; do not imply
production qualification or behavior not established by tests.
