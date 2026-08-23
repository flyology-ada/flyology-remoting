# 0008: Observe exact remote task generations without following restarts

Status: Accepted

## Context

A caller must be able to learn that a remote task ended, failed with its node,
or was restarted. A session disconnect proves none of those facts by itself,
and an Ada `Task_Id`, task-result monitor, or supervisor handle cannot cross an
IPC or network boundary.

Flyology already publishes exact task exit results and exposes generation-safe
supervisor waits. Remoting should preserve those semantics rather than create a
second task-lifecycle authority.

## Decision

A `Task_Reference` contains an exact node incarnation, a nonzero 64-bit logical
task identity, and a nonzero 64-bit generation. A supervised restart within the
same node incarnation retains the logical identity and advances the generation.
An observer always names one exact generation and never silently follows its
replacement.

The remoting node registry allocates each logical task identity from a
node-incarnation-wide nonwrapping space and retains the private mapping to its
exact local supervisor handle. A Flyology `Child_Id` is scoped to one
supervisor controller and must never be promoted directly into a remoting
`Task_ID`. The supervisor generation becomes the remoting generation for that
mapping.

The lifecycle results are distinct:

- `Task_Ended` carries a bounded portable completion summary copied from
  destination supervision;
- `Task_Replaced` carries the current replacement reference;
- `Node_Incarnation_Ended` requires an authoritative process-liveness source;
- `Peer_Unreachable` reports transport uncertainty only; and
- `Observation_Timed_Out` reports no lifecycle conclusion.

The portable completion summary omits process-local Ada task and exception
identities. `Flyology.Remoting.Tasks.From_Supervision` converts the copied
result of `Flyology.Supervision.Wait_Termination` while preserving the exact
node-global task identity supplied by the registry. The concrete task-kind
registry remains responsible for calling its static or family supervisor and
for mapping that identity to the local handle.
`Flyology.Task_Results` remains the underlying exact-task publication mechanism
used by supervision.

`Flyology.Remoting.Tasks.Local_Observers` binds that private handle through a
static generic. It rejects an invalid reference or handle/reference generation
mismatch before invoking the supplied exact-generation wait, then converts the
copied observation without retaining the supervisor or handle. The formal wait
must provide Flyology's atomic exact-handle check/registration semantics and
must not follow a replacement.

A node process restart changes the node incarnation. It ends every reference to
the old incarnation but is not represented as a task replacement. Rebinding a
logical service across process incarnations requires a separate discovery or
deployment protocol and is not implicit.

## Consequences

Remote callers can distinguish known completion, supervised replacement,
authoritative process loss, and temporary disconnection without treating
network reachability as task truth. Completion and replacement notifications
will be ordinary bounded protocol messages; the wire crate will encode their
schemas when it is pinned.

The current slice defines values, local conversion, and the checked generic
wait adapter. It does not yet register task kinds, start tasks remotely,
authenticate liveness authorities, or carry lifecycle observations over a
session.
