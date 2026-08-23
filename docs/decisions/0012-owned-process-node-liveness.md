# 0012: Recognize node death only from an exact owned-process authority

Status: Proposed

## Context

Decision 0008 distinguishes authoritative `Node_Incarnation_Ended` from
transport uncertainty but does not define an initial liveness authority.
Flyology can observe termination of an exact subprocess it owns. A socket
close, heartbeat timeout, or PID lookup does not prove that an arbitrary node
incarnation ended.

## Decision

Version one publishes `Node_Incarnation_Ended` only for a node process directly
owned through `Flyology.Subprocesses.Process`.

Each launch creates a dedicated one-shot aggregate that owns one limited
`Process`, its exact expected `Node_Reference`, a one-use launch capability,
and the monitor. The capability is delivered only through a direct inherited
framed control channel bound to that spawned process. It never uses
`Flyology.Subprocesses.Bootstrap`'s dedicated one-byte, one-`SCM_RIGHTS`
descriptor-handoff channel, which carries no second protocol. Death authority
is armed only after the child proves the capability while the session handshake
authenticates the same exact node incarnation.

Arming and successful Wait publication share one atomic aggregate-state
transition. Wait first while unarmed records `Pre_Arm_Exit`, reports launch or
admission failure, and permanently prevents arming. Arm first changes
`Unarmed` to `Armed`; a later or simultaneous Wait then publishes
`Node_Incarnation_Ended`. An arming attempt that observes `Pre_Arm_Exit` fails
and cannot convert the earlier exit into authoritative node death.

A Wait exception atomically records the terminal aggregate state
`Observation_Failed`. If it wins while unarmed, later arming is permanently
rejected and the launch or admission fails. If it wins while armed, it publishes
no death fact, rejects new session admission and rebinding, and fails current
sessions for that incarnation. Their remote observers may consequently receive
`Peer_Unreachable` from the forced transport closure, never
`Node_Incarnation_Ended`. The failure remains a local liveness-authority
diagnostic; current sessions use the same resumable out-of-lock cleanup protocol
without setting the incarnation-ended latch. Arm, successful Wait, and failed
Wait all linearize through this one aggregate state. Version one does not retry
or replace the one-shot monitor.

The aggregate is the exclusive authority for Wait, Send_Signal, Kill, Stop,
Close, and process finalization. Its bounded escalation policy requests
termination while Wait remains the reaping authority, escalates through the
aggregate's private signal or kill path when the graceful deadline expires,
lets Wait publish the result, joins the monitor, and only then calls Close or
finalizes. The policy does not bound total shutdown: process exit and reaping
may wait indefinitely for an uninterruptible kernel state. Wait is never
concurrent with Close. Version one never cancels Wait during shutdown; the
signal or kill path leaves Wait authoritative until it unwinds. Close and
finalization occur only after the monitor joins. Neither the aggregate nor its
`Process` object is reused for another launch. Replacement uses a new owner,
capability, `Incarnation_ID`, and monitor.

When the aggregate is armed, a successful return from
`Flyology.Subprocesses.Wait`, regardless of process exit code or termination
kind, atomically sets one persistent bounded incarnation-ended latch. The same
registry linearization marks every current session bound to that incarnation
failed, rejects further send and routing admission through those sessions,
claims exact once-only cleanup ownership for each session, and fences new
session admission, task-start dispatch, lifecycle publication, and rebinding
for that incarnation. It then wakes bounded observers. Each claimed session
owner drains and releases its accepted queue entries outside the registry lock
and exactly once. An aborting or raising closer leaves the session failed and
closing, relinquishes its cleanup claim, and permits another owner to resume at
the retained queue head. Removing an entry from that queue atomically moves
sole ownership into an abort-safe limited controlled cleanup token. Normal code
releases the token once; unwinding or finalization releases it once before the
session cleanup claim can be relinquished. The drain may advance or relinquish
its claim only after that token is resolved, so a resumed drain neither sees
nor releases the earlier entry twice and cannot leak it. Record retirement
waits for all such drains.
The transport may separately retain a `Peer_Unreachable` fact, but
authoritative death drives this session failure. A weaker reachability
observation that linearized earlier remains valid; after the latch commits,
later exact observations return `Node_Incarnation_Ended`. Duplicate publication
is inert.

The ended latch persists and is never cleared while its explicit bounded
node-registry monitor record is retained. Both an ended record and a terminal
`Observation_Failed` record follow the same bounded retirement cut. Retirement
requires no live observer registration, session, accepted queue entry, pending
task-start dispatch, or pending task or lifecycle publication for the
incarnation, and every failed-session drain must be complete. Under the registry
cut, retirement removes every retained incarnation-scoped task record together
with the terminal monitor record; it cannot leave a task mapping without its
death fence or failed-authority state. After retirement, a late registry lookup
or admission deterministically reports `Unknown_Node_Incarnation`; this is not
a `Task_Observation` result, and no task observation is constructed after the
lookup fails. Retirement cannot recreate or infer the retired terminal fact.
Registry capacity and retirement policy are fixed configuration, not unbounded
historical storage.

Exact task publication, node death, terminal `Observation_Failed`, and observer
registration share one registry linearization. A `Task_Ended` or
`Task_Replaced` fact committed first remains the result for that exact observer.
If the incarnation-ended latch commits first, it rejects later task publication
and the observer receives `Node_Incarnation_Ended`. If `Observation_Failed`
commits first, it rejects later lifecycle publication from the failed sessions,
wakes existing unresolved observers with `Peer_Unreachable`, and makes new
observation registration return `Peer_Unreachable` immediately without
subscribing. It never synthesizes `Node_Incarnation_Ended`. Registration checks
retained exact task state, the ended latch, and failed-authority state atomically
before subscribing.

A process observation failure follows the terminal `Observation_Failed` path
above and cannot leave an armable aggregate without a monitor.

The managed node must not daemonize, escape the owned process group, or
transfer its node identity to another process. Socket closure, TLS failure,
heartbeat loss, session timeout, PID lookup, and `kill (Pid, 0)` report only
reachability uncertainty.

Externally managed IPC and network peers have no authoritative death result in
version one; they may become only `Peer_Unreachable`. Supporting systemd,
Kubernetes, cluster membership, leases, or another external source requires a
later authority-specific decision with exact-incarnation binding and fencing.

## Consequences

Locally launched nodes receive crash-stop observation without PID-reuse
ambiguity. Arbitrary network peers cannot be declared dead. The persistent
latch avoids per-task fanout allocation. Death-before-arming,
admission-versus-death, send-versus-death ordering and ownership, live-session
failure and out-of-lock drain, task-publication ordering, termination
escalation, Wait/Close serialization, monitor join, interrupted cleanup and
resumption, including interruption after dequeue and before explicit release,
latch retirement and late lookup, duplicate publication, process replacement,
pre-arm and post-arm observation failure, and session-disconnect precedence
require focused tests before acceptance. The interrupted-drain fixture must
restore full pool capacity and prove that resumption does not double-release an
entry. Failed-monitor retirement must also restore registry capacity and permit
a new one-shot launch record without reusing the retired incarnation identity.
Fixtures must cover task-result-before-failure, failure-before-publication,
registration-after-failure, and registration-versus-failure, and prove that no
stranded subscription prevents failed-record retirement.

## Alternatives

- Treat connection loss as node death.
- Poll a PID.
- Treat heartbeats or leases as definitive without a fenced authority.
- Accept an unconstrained application callback asserting death.
