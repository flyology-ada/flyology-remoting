# 0013: Deliver through an exact complementary session path

Status: Accepted

## Context

Decision 0010 fixes send acceptance at the first bounded session ingress.
Endpoint enqueue is later: it may fail after the sender has already transferred
ownership to remoting, and it must not change the completed send result.

The accepted in-process descriptor retains a sender-role `Sessions.Binding` and
two immutable leases. The existing `Nodes.In_Process` backend is payload-only
and fixes every mailbox to one buffer pool. It cannot retain the header or exact
session context, and a fixed mailbox must accept entries originating from
multiple live sessions with different payload and per-session header pools.

Delivery also crosses the directional view of one session. The sender binding's
local node becomes the receiver binding's peer, but decision 0009 prohibits
arbitrary rebinding and does not yet authorize this deterministic role change.

## Decision

### Complementary binding

`Sessions.Peer_View` is a public value operation on a valid binding. For every
valid `B`, it returns a valid binding with the same exact `Session_Reference`
and the opposite `Session_Role`; applying it twice returns `B`. Its local and
peer nodes are consequently reversed even when their node references compare
equal. This is a directional view of the same established session, not a
reconnect, replacement, or new authority.

This decision narrowly amends decision 0009's no-recontextualization rule:
validated receipt may replace a sender-role binding only with
`Peer_View (B)` for the same `Session_Reference`. Every other rebinding remains
forbidden.

One unidirectional `Delivery_Path` binds an accepted sender ingress, one
compound-aware destination node, and an explicitly established receiver
binding. Registration accepts the receiver binding once and validates that it
equals `Peer_View` of the sender binding, including for a session whose two node
references happen to be equal. Per-message delivery never accepts a
caller-supplied binding, never infers a role from node equality, and never
changes the `Session_Reference`.

Before registration succeeds, the destination node owner must equal the
receiver binding's exact local `Node_Reference`. Before endpoint enqueue, the
same complete source and destination references must validate outbound under
the sender view and inbound under the receiver view. A failure is a session
protocol violation, not an endpoint rejection and not evidence of node death.

### Contextual session admission

One configured process-local remoting `Context` is the storage and
linearization owner. It contains fixed session and compound-node tables, every
session ingress, path pending and outcome state, endpoint mailbox ring, and
resumable cleanup cursor. Its capacities are explicit construction
configuration. It retains no access to a shorter-lived public object.

`Session`, `Compound_Node`, `Delivery_Path`, and the decision 0012 liveness
authority are limited controlled handles with access discriminants for the same
context. They retain only complete slot-and-generation references and local
claim state; safe Ada code cannot finalize the context first. A delivery path
may additionally use access discriminants to keep its session and node handles
alive, but cleanup never depends on dereferencing those handles. The context
owns the provider state that a liveness cut must fence and drain.

Every operation that establishes one of these handles starts with a
caller-declared invalid handle and uses a limited controlled transition guard.
Only its final abort-deferred action installs the complete reference and
publishes the record state. This is the construction rule detailed below for
sessions and paths; compound-node and endpoint claims retain decision 0007's
equivalent rollback and generation discipline.

The context action that classifies liveness and reserves a session is the same
registry linearization required by decision 0012. An exact incarnation is
`Owned_Live`, terminal and retained, explicitly `Known_Unmanaged` by the
authenticated session-establishment authority, or unknown. Absence of a record
never implies an unmanaged peer. After terminal-record retirement, admission
therefore reports `Unknown_Node_Incarnation` exactly as decision 0012 requires.

Admission classifies both bound node references atomically before reserving a
session. If their retained states differ, the single result precedence is
`Node_Incarnation_Ended`, then `Liveness_Observation_Failed`, then
`Unknown_Node_Incarnation`; equal-node bindings classify that one reference
once. Only two live or explicitly known-unmanaged references proceed.

A caller first declares an invalid context-bound `Session` handle, then invokes
`Admit`. Admission validates the binding and pool configuration and reports
`Session_Admitted`, `Invalid_Binding`, `Node_Incarnation_Ended`,
`Liveness_Observation_Failed`, `Unknown_Node_Incarnation`, `Session_Exists`,
`Invalid_Configuration`, `Session_Table_Full`, `Session_Generation_Exhausted`,
`Header_Pool_In_Use`, or
`Header_Pool_Generation_Exhausted`. The handle is usable only after
`Session_Admitted`; every other result leaves it invalid.

Immutable admission precedence is `Invalid_Binding`, then
`Invalid_Configuration`, then the atomic liveness result in the precedence
above, then `Session_Exists`, then session-table capacity or generation
exhaustion, then header-pool reservation. The context reservation occurs before
the separate domain reservation and neither protected-object lock is nested;
the controlled admission guard rolls both back in reverse order.
Configuration validation includes buffer-domain identity, pool identities,
header geometry, and required bounded capacity and performs no allocation or
state change. The first matching classification is the sole result.

`Admit` uses a limited controlled guard. One context action reserves an
`Admitting` exact-session record, slot, and nonwrapping generation while holding
an admission transition claim. The guard then initializes the context-owned
ingress and provider state. Its final abort-deferred action installs the
complete reference in the caller's handle, changes `Admitting` to `Admitted`,
and disarms the guard. Abort, exception, or injected failure before that action
clears the invalid handle and rolls the record and every acquired capability
back; a liveness cut waits to linearize until the guard publishes or rolls back.
No unpublished object finalizer is required for correctness.

The remaining record states are `Initializing`, `Active`, `Closing`, `Failed`,
and `Cleanup_Retained`; every noninactive state occupies its slot and
exact-session key. `Session_Table_Full` means no reusable slot exists while at
least one slot is occupied. `Session_Generation_Exhausted` requires that no
record occupies a slot and every otherwise available inactive slot is
permanently exhausted. Distinct ingress objects therefore cannot admit the same
exact session, and a later path does not perform a second capacity allocation.

Every accepting send acquires a bounded context operation claim for its
admitted record before touching the context-owned ingress. The claim retains no
context lock across buffer work. A liveness cut that wins first fences new
claims and rejects the send. A send claim that wins first may publish its one
ownership transition, after which the liveness cut waits for the claim and
includes that entry in cleanup. Consequently, authoritative death or
`Observation_Failed` after admission but before path registration still closes
and drains the ingress, rejects later sends, and restores both pools exactly;
there is no untracked open session interval.

Contextual sessions expose no direct accepted-message dequeue. The earlier
public `Accepted_Message` and `Try_Take_Accepted` escape hatch are removed in
this pre-compatibility refactor; only the private claim-aware delivery operation
may extract the oldest carrier, and its controlled token remains
context-accounted until enqueue or release. Public forwarding is rehomed onto
an application-owned `Inbound_Message`: rejection preserves that message,
while acceptance installs a newly validated header and moves the unchanged
payload into the target session ingress.

Direct send and `Try_Forward` share `Invalid_Message_Context`,
`Invalid_Outbound_Route`, `Incompatible_Buffer_Domain`,
`Local_Resource_Exhausted`, `Backpressure`, `Session_Closed`,
`Node_Incarnation_Ended`, `Peer_Unreachable`, and `Message_Accepted`.
Immutable message, route, domain, extent, and policy checks precede the atomic
session claim; its retained liveness or close cause precedes header-pool and
queue capacity. Every result except `Message_Accepted` preserves the caller's
payload or complete inbound message. Acceptance atomically publishes the new
header and unchanged payload and vacates the caller value.

A direct close of an unclaimed session fences new session claims, waits for the
active claim, resumably drains the ingress, and retires the record only after
its cleanup token resolves. An aborting close leaves the record closing so
another close or finalization can resume. Once the driver claim exists, only
the path or liveness authority may perform that lifecycle transition.

Path registration reports one of `Path_Registered`, `Invalid_Binding`,
`Noncomplementary_Binding`, `Foreign_Node`, `Stale_Incarnation`,
`Ingress_Closed`, `Node_Incarnation_Ended`,
`Liveness_Observation_Failed`, `Unknown_Node_Incarnation`,
`Session_Path_Exists`, or `Session_Busy`. After immutable validation through
the exact destination incarnation, it acquires a bounded context registration
claim that changes the existing exact record from `Admitted` to `Initializing`.
The claim is granted only with no active session operation claim; otherwise
registration reports `Session_Busy` and changes nothing. A liveness or
conflicting-state cut that wins first determines the reported result. While the
registration claim is held, the decision 0012 authority waits to linearize, so
it cannot interleave an ownership decision with driver-claim publication.

An existing `Initializing` or `Active` record reports `Session_Path_Exists`;
normal closing reports `Ingress_Closed`; and an authoritative ended, failed, or
retired record reports its retained liveness or unknown-incarnation
classification. `Cleanup_Retained` keeps that classification until retirement.
These checks and the state transition are one context action.

Registration next publishes the record's one-use driver claim. Ordinary
failure rolls the context record back to `Admitted` and relinquishes that
claim. Final activation changes the same record to `Active` and publishes its
slot and generation as the path identity. If registration wins the context
claim, it is the earlier linearized action; a concurrent later liveness cut may
immediately fence the newly active path but does not retroactively change
`Path_Registered`. If the liveness cut wins first, registration reports its
retained classification and publishes no path.

The caller supplies an invalid context-bound `Delivery_Path` handle to
registration. Its controlled guard retains the transition and driver claims;
the final abort-deferred activation installs the complete path reference in the
handle and disarms the guard. Unwinding before that point leaves the handle
invalid and either restores `Admitted` or yields to an earlier liveness cut.

### Pool-independent ownership

Flyology must first supply a definite, limited, pool-independent owned-buffer
capability and a limited `Buffer_Domain`. A domain owns a fixed, explicitly
configured catalogue of heterogeneous buffer pools and all their storage. It
is constructed before the remoting context. `Context` has an access
discriminant for its one domain, so ordinary Ada accessibility requires the
domain and every owned pool to outlive the context and all context-bound
handles. Session admission selects header and payload pool references only from
that domain; it never retains a raw caller-owned pool access.

The selected payload pool is the session's acquisition source for newly
encoded application messages, not a stored-carrier type constraint. A forwarded
payload capability from any pool in the same domain may enter the target
session without copying; a different domain reports
`Incompatible_Buffer_Domain` before acquiring a new header or moving ownership.
Every session-specific payload size and policy check still runs before commit.

The selected header pool is reserved exclusively for that exact session with a
nonwrapping reservation generation. `Reserved` or `Released_Pending_Ack`
reports `Header_Pool_In_Use`. `Available` with a usable generation, including
the final generation, permits reservation. Only `Permanently_Exhausted` after
acknowledgment of the final-generation release reports
`Header_Pool_Generation_Exhausted`. The reservation remains held through
`Cleanup_Retained` until every ingress, pending, endpoint-mailbox, operation,
and cleanup-token header capability for the session has returned. Only then may
record retirement release and, unless it was final, advance the reservation
generation for another session.

Reservation retirement is a resumable two-protected-object protocol. One
context action changes its header substate from `Header_Held` to
`Header_Release_Claimed` and copies the complete pool reservation reference.
With no context lock held, cleanup asks the domain to prepare release of that
exact generation. The domain changes it to `Released_Pending_Ack`; repeated
prepare for the same generation is inert, and no later session may reserve the
pool yet.

A limited controlled release token carries that complete reference and an
access discriminant for the context's `Buffer_Domain`. The token is local to
the cleanup operation, so the domain is necessarily live when its finalizer
acknowledges after context-record retirement. One final context action writes
`Ack_Authorized` into the necessarily by-reference token, changes the matching
substate to `Header_Released`, and retires the session record. Protected-action
abort deferral leaves no gap between authorization and retirement. Normal code
then acknowledges the domain; token finalization is the nonraising fallback.
Acknowledgment clears the token and makes the pool available for another
reservation if its generation can advance; at the final generation it instead
marks the pool permanently exhausted. An acknowledgment is harmless for an
older generation after later reuse and never releases a newer reservation. An
unknown or future generation is an internal protocol failure.

Abort before the final context action leaves `Header_Release_Claimed` and the
domain pending, so cleanup repeats prepare and no other session can intervene.
Abort afterward finalizes the authorized token and acknowledges the domain
after the context record is already retired. No context and domain lock is
nested, and the domain never has to remember more than its one pending
reservation.

The capability retains one domain pool token dynamically and provides only
move, release, length, capacity, and callback-scoped readable observation. It
exposes no pool access, native address, token, or writable address overlay. A
complete pool slot and nonwrapping generation prevent a stale pool reference
from selecting replacement storage. Domain construction may allocate the
configured pool storage once; message admission, movement, observation, and
cleanup allocate nothing. Domain finalization occurs only after context
finalization has resolved every capability and cleanup claim.

The definite stored capability contains no access value; its operations take
the owning domain explicitly and validate its complete pool reference. Public
`Writable_Payload` and `Inbound_Message` owners instead have access
discriminants for that domain, so they may outlive a session or context but
cannot outlive the storage needed by finalization. Context-owned carriers use
the context's discriminated domain. Moving between those wrappers transfers
only the definite capability and never weakens accessibility.

Remoting builds a private definite compound carrier from two such capabilities,
the validated semantic header, and one exact binding. The carrier exposes no
raw header or writable payload API. Moving and releasing it always treats the
two leases, semantic header, and binding as one ownership unit. This carrier is
an internal provider seam. The in-process path creates a receiver-bound carrier
through `Peer_View`; a future IPC or RPC adapter creates the same semantic
input only after its own session-bound header validation. The compound-aware
endpoint node consumes that receiver-bound carrier and does not depend on
`Sessions.In_Process`. A formal package tied to the reference adapter may help
its construction but must not become the transport-neutral application API.

A successful endpoint enqueue creates an inbound carrier under the already
validated complementary binding. The immutable canonical header lease and
opaque payload lease transfer unchanged. This operation is receipt on the same
exact session, not forwarding: it takes no writable borrow and allocates no
replacement header. Forwarding to another `Session_Reference` continues to
require a newly validated header under decision 0009.

### Bounded delivery path

`Delivery_Path` is limited, controlled, and the sole consumer and close
authority for its registered ingress. The session already owns an `Admitted`
context record. Registration holds that record's transition claim while it
publishes an atomic one-use driver claim and activates the same record; later
ordinary rejection rolls both changes back. A claimed session rejects direct
close, a second driver claim, and any competing delivery path.
The path has access discriminants for the session and node, so safe Ada code
cannot finalize either owner before the path. Path finalization closes and
drains before relinquishing the session claim; session finalization therefore
never competes with a live path.

The driver claim is private context state, not a caller-retainable access or
detached dequeue capability. Claim-aware take and close operations require the
complete active path reference. Direct session close remains available only
while a session is unclaimed; after attachment it raises the public
`Driver_Claimed` exception without changing ingress state. Registration maps a
failed claim to `Ingress_Closed` rather than propagating that exception.

Registration holds the provisional ingress claim and context transition in one
limited controlled guard. Abort, exception, or any reported ordinary failure
rolls them back in reverse order. A liveness cut that linearized before the
transition owns cleanup; one that arrived after it waits for the transition
claim and observes either the restored `Admitted` record or the published
`Active` record. Only final publication changes the sole record from
`Initializing` to `Active` and disarms the guard. Delivery, receive, close, and
lookup cannot observe an initializing record as active; there is no interval
in which an unowned path record or driver claim can survive unwinding.

The active context record owns at most one dequeued pending carrier. Its
registry identity is the admitted record's exact `Path_Reference`, containing
the record slot and its nonwrapping generation. Every endpoint mailbox entry is
tagged with that complete value and receiver binding; a generation without its
slot is never an identity.

Before touching the ingress, `Try_Deliver_One` atomically acquires the context
record's single bounded path-operation claim. A competing call reports
`Path_Busy`. Close fences new claims and waits for the held claim. The claim is
abort-safe and remains held while a dequeued carrier is in the operation's
controlled cleanup token, closing the gap between ingress removal and
publication as the record's pending head.

`Try_Deliver_One` performs take, validation, endpoint pinning, and enqueue as
one bounded state-machine step:

1. When idle, take only the oldest ingress entry.
2. When pending, attempt only that entry; do not take a later entry.
3. On endpoint enqueue, transfer the complete carrier and become idle.
4. On mailbox backpressure or bounded pin exhaustion, retain the complete
   pending carrier for an explicit later call.
5. On a permanent endpoint rejection, copy the exact binding, message,
   correlation, complete source, complete destination, and typed delivery
   status into the context record's one fixed `Outcome_Pending` slot, release
   both leases exactly once, and retain that state until `Take_Outcome` returns
   it through the caller's limited outcome target and clears it.
6. While an outcome is pending, do not dequeue a later entry; there is no
   outcome-capacity exhaustion or silent overwrite.
7. On a session protocol violation, fail the exact session, release its
   pending carrier, and start its resumable drain.

`Try_Deliver_One` reports exactly one of `Endpoint_Queued`, `Ingress_Empty`,
`Mailbox_Backpressure`, `Endpoint_Pin_Exhausted`,
`Outcome_Awaiting_Take`, `Path_Busy`, `Path_Closing`, `Stale_Path`,
`Session_Failed`, `Session_Protocol_Failed`, `Node_Incarnation_Ended`,
`Peer_Unreachable`, `Foreign_Node`, `Stale_Incarnation`, `Stale_Endpoint`, or
`Endpoint_Closing`.

Classification first acquires the exact path claim, with stale, busy, terminal
liveness, failed, and closing states resolved in that order; terminal liveness
uses `Node_Incarnation_Ended` before `Peer_Unreachable`. It next reports an
existing `Outcome_Awaiting_Take`; otherwise it uses the retained pending head
or takes the oldest ingress entry, reporting `Ingress_Empty` when no carrier is
available. An internally drained ingress while the record is active is a
session protocol failure, not a public empty variant. Semantic validation precedes
endpoint pinning and reports `Session_Protocol_Failed`. Pin exhaustion and
mailbox backpressure retain the same pending carrier and report their retryable
results. `Foreign_Node`, `Stale_Incarnation`, `Stale_Endpoint`, and
`Endpoint_Closing` are permanent endpoint results: each copies that status into
`Outcome_Pending` and resolves the carrier before the operation claim is
released. `Endpoint_Queued` is the only result that transfers the head to the
mailbox. Every other result either leaves state unchanged, retains the one
pending head or outcome as specified, or enters the named terminal cleanup.

The operation never spins, waits for capacity, retries implicitly, or skips a
pending head. Retaining one retryable head preserves decision 0010's
per-source/destination acceptance order. A later deadline or cancellation
layer may terminate that head through the same permanent-outcome path without
moving the acceptance point.

Terminal rejection stores `Outcome_Pending` while the delivery operation claim
still excludes every observer, then releases the carrier through its controlled
cleanup token outside the context action. The operation claim is relinquished
only after that token resolves, including during unwinding. `Take_Outcome`
acquires the same single operation claim or reports `Path_Busy`, and publishes
and clears the fixed record in one protected context action. An abort or
exception before carrier release completes leaves the outcome retained; an
abort cannot create an idle path with a lost terminal outcome.

`Take_Outcome` reports `Outcome_Taken`, `No_Outcome`, `Path_Busy`,
`Path_Closing`, `Stale_Path`, `Session_Failed`,
`Node_Incarnation_Ended`, or `Peer_Unreachable`. Precedence is stale reference,
busy claim, terminal liveness, failed session, closing path, then
outcome-present versus no outcome. `Delivery_Outcome` is a limited,
validity-bearing, necessarily by-reference target. It must be vacant on entry;
the protected action writes all scalar fields into that object before clearing
`Outcome_Pending`. It remains vacant for every result except `Outcome_Taken`.
Protected-action abort deferral therefore covers both publication and clear,
with no Ada copy-out gap. Close or liveness cleanup that wins first may consume
the local outcome; a result already taken remains an application-owned value.

Endpoint enqueue is reported as `Endpoint_Queued`, not `Message_Accepted`. It
means that the destination application mailbox owns the descriptor; it does
not mean that the peer processed, decoded, or even dequeued it. Every failure
is post-acceptance and therefore cannot restore ownership to the sending
application or revise its earlier `Message_Accepted` result.

Until the reviewed Wire control-message schema and schema lock exist,
delivery outcomes remain local typed values. The reference adapter does not
invent remoting-specific payload serialization or silently claim that a remote
peer observed an outcome.

### Compound-aware endpoint node

The caller claims a compound node through the shared context into an invalid
`Compound_Node` handle. Claim validates one exact nonzero owner and the retained
liveness provenance in the same registry linearization as session admission.
It reports `Node_Claimed`, `Invalid_Node_Owner`,
`Node_Incarnation_Ended`, `Liveness_Observation_Failed`,
`Unknown_Node_Incarnation`, `Node_Exists`, `Node_Table_Full`, or
`Node_Generation_Exhausted`.

Claim precedence is `Invalid_Node_Owner`, then the session-admission liveness
precedence, then `Node_Exists`, then exact same-owner generation exhaustion,
then table capacity or global generation exhaustion. The claim action and
liveness lookup are one context registry action.

Node record states are `Node_Admitting`, `Node_Active`, `Node_Closing`,
`Node_Closed`, `Node_Failed`, and `Node_Cleanup_Retained`. The exact owner index
permits only one record in any of those states for a `Node_Reference`; it never
allocates a second record for a closed owner. A second claim while that record
is not `Node_Closed` reports `Node_Exists`. A guarded final action publishes
`Node_Active` and a complete context node slot and nonwrapping node generation.
Failure before publication rolls the claim back and leaves the handle invalid.

Normal node close fences node and endpoint claims and pins, waits for earlier
claims, and closes every path bound to the complete node-record reference
without assigning a death cause. After those path records retire, it drains any
remaining endpoint mailbox, advances or exhausts every endpoint generation,
and changes the record to `Node_Closed`. It reports
`Node_Close_Completed`, `Node_Close_Already_In_Progress`, `Stale_Node`,
`Node_Incarnation_Ended`, or `Peer_Unreachable`. It never publishes node death.
An interrupted close retains its cleanup cursor and may be resumed by another
close or handle finalization.

A normally closed record remains bound to its exact owner and preserves all
endpoint-generation history. A later claim for that same still-live owner may
reactivate only that record, after every earlier bound path retired, with a new
node-handle generation; every earlier node handle is stale and every earlier
endpoint remains stale. The record is
not reusable for another owner until the associated incarnation provenance can
retire. A different `Node_Reference` may reuse the slot only if that joint
retirement advances the node generation; a slot already at its final generation
is permanently exhausted. The earlier exact owner is then unknown and cannot
be readmitted. Replacement of a running node always uses a new
`Incarnation_ID`.

An exact same-owner closed record at its final node generation reports
`Node_Generation_Exhausted`. Otherwise `Node_Table_Full` means no inactive or
same-owner closed record is reusable while at least one record is retained.
With no retained record, `Node_Generation_Exhausted` means every inactive slot
is at its final generation. An exhausted same-owner record remains unavailable
until its incarnation provenance retires; endpoint generations never reset
merely because a public node handle finalized.

Node and incarnation provenance retirement is one noncyclic context action.
Normal close may leave `Node_Closed` available for same-owner reactivation while
its live provenance remains. Once provenance is otherwise eligible for
retirement, the action requires the node record to be closed or
cleanup-retained, with no path, endpoint, pin, carrier, provider, observer, or
cleanup token remaining; it then removes both exact indices atomically and
marks the node slot inactive at its advanced or exhausted generation. Neither
side waits for the other to retire first.

The reference compound-aware node is a sibling of the payload-only
`Nodes.In_Process`, not an extension of its pool-specific mailbox. The context
owns each node record and its storage:

- one exact node owner;
- a fixed endpoint table and complete session-record references;
- nonwrapping endpoint generations and complete context path references;
- bounded operation pins;
- fixed-capacity mailbox rings of private definite carriers; and
- no heap-allocated holder or retained access to a caller's message object.

A `Compound_Node` is only a context-bound slot-and-generation handle. Its node
record, endpoint state, and mailboxes remain valid while a liveness or close
cleanup proceeds even if the public handle is finalizing. Endpoint handles are
likewise context-bound and contain no access back to a compound-node object.

The endpoint lifecycle remains decision 0007's active, closing, drain, and
generation-reuse protocol. The context path registry and node endpoint registry
provide the two bounded classifications for enqueue, receive, and close. A
delivery holds its context operation claim across the node action, so a
liveness or path-close fence that loses to that claim waits for its one
ownership transition and includes any newly queued entry in cleanup. Each
mailbox slot is atomically `Vacant`, `Occupied`, or `Cleanup_Claimed`. A claimed slot
cannot be received, reused, compacted, or skipped until its controlled cleanup
token resolves; when it reaches the queue head it blocks later entries, which
preserves FIFO. A closer claims at most one complete entry per registry action,
releases it outside the lock, marks that exact slot vacant in a later action,
and resumes its bounded scan.

No session operation, wait, callback, or buffer release occurs while the node
registry lock is held. Only fixed metadata checks and complete-carrier moves
occur in its protected actions.

Close, failure, and liveness cleanup are driven through a context operation,
not through a callback into a public handle. One protected action claims and
moves at most one ingress, pending, or mailbox carrier into a local limited
cleanup token. The token releases outside every registry lock and its
abort-safe completion advances the retained context cursor. An interrupted
driver leaves `Cleanup_Claimed` state and a resumable cursor; another caller or
context finalization resumes only after the earlier token resolves. This seam
uses neither `Unchecked_Access`, a heap holder, nor a callback under a lock.

`Try_Receive` transfers one complete entry into a limited
`Inbound_Message`. That value exposes the exact receiver binding, message,
correlation, unchanged writer identity, reconstructed source and destination,
payload length, and callback-scoped readable payload observation. It exposes
neither the V1 header type nor a raw-header send operation.

Before publishing `Inbound_Message`, receive copies those semantic fields,
moves the carrier from the head into its operation token, marks that mailbox
slot `Cleanup_Claimed`, and releases the encoded header capability. The endpoint
pin and context receive claim remain held until the token resolves. One final
abort-deferred action moves the remaining payload capability into the vacant
target and marks the exact mailbox slot vacant. Unwinding beforehand releases
each capability the token still owns—only the payload after header release—and
its abort-safe completion vacates the same claimed slot before relinquishing
the pin and claim. It publishes no message. Application-owned inbound messages
therefore retain no session header lease, and a header-pool reservation depends
only on context-accounted state.

Receive uses a bounded peek/claim/recheck protocol. It first acquires an
endpoint operation pin and copies the head's complete `Path_Reference` and slot
identity under the node action. With no node lock held, it acquires the
context's receive claim for that exact path. It then rechecks the same endpoint
generation, head slot, and path reference under the node action before moving
the carrier. A changed head reports `Receive_State_Changed`; the call does not
loop or skip an entry.

If authoritative death, observation failure, or path close fences the context
record before the receive claim, the claim is rejected and no message is
published. Cleanup proceeds after the endpoint pin is released. If the receive
claim wins, the later fence waits while the recheck either transfers
application ownership or reports no transfer. No wait, buffer release, or
context call occurs while the node registry lock is held.

The compound node's receive results are `Message_Received`, `No_Message`,
`Foreign_Node`, `Stale_Incarnation`, `Stale_Endpoint`, `Endpoint_Closing`,
`Path_Closing`, `Session_Failed`, `Node_Incarnation_Ended`,
`Peer_Unreachable`, `Receive_State_Changed`, and
`Local_Resource_Exhausted`. Classification first validates and pins the exact
endpoint, then observes empty-versus-head, then claims the head's exact path,
and finally performs the head recheck. Thus endpoint identity and closing
results precede `No_Message`; `No_Message` precedes a path classification;
bounded endpoint-pin or context-claim exhaustion reports
`Local_Resource_Exhausted`; and a successful path claim followed by a changed
head reports `Receive_State_Changed`. Normal path close reports
`Path_Closing`, a protocol failure reports `Session_Failed`, authoritative
death reports `Node_Incarnation_Ended`, and terminal observation failure
reports `Peer_Unreachable`.

The context retains the first lifecycle cause separately from its terminal
liveness overlay. For calls after multiple facts have committed, receive
precedence is `Node_Incarnation_Ended`, then `Peer_Unreachable`, then
`Session_Failed`, then `Path_Closing`. A later authoritative liveness fact may
therefore strengthen a future diagnostic, but it never changes the earlier
ownership winner or a result already returned. Normal close and protocol
failure cannot overwrite a retained liveness fact.

The caller supplies a vacant `Inbound_Message`. It becomes nonvacant exactly
for `Message_Received` and remains vacant for every other result, exception,
or abort. The implementation may collapse no named result into another and
never reports authoritative death for ordinary path or transport closure.
The formal target subtype is discriminant-constrained to the compound node's
exact `Buffer_Domain`, independently of assertion policy. Parameter binding for
a wrong-domain target raises `Constraint_Error` before the operation body, so it
cannot pin an endpoint or change the vacant target.

### Close, reconnect, and death

Path close first fences new delivery claims, waits for the active claim, closes and
drains its ingress and pending head, and selectively drains every endpoint
entry tagged with the exact `Path_Reference`. Endpoint close first fences its
pins, waits for active pins, and drains every entry in that endpoint generation
before reuse. Concurrent path close, endpoint close, and receive share one
ownership decision:

- receive first transfers application ownership and close cannot retract it;
- either close first detaches and releases the entry, and receive cannot
  publish it; and
- enqueue first reports `Endpoint_Queued`, but a later close may still drain
  the entry before application receipt.

An interrupted drain leaves the record closing and relinquishes its cleanup
claim only after its detached cleanup token resolves. Another caller may resume
without leaking or releasing the same carrier twice. Path finalization is the
close fallback. Once a path is registered, callers close through the path; the
session's one-use driver claim makes the lower-level ingress close and dequeue
operations unavailable as competing lifecycle authorities.

Path retirement occurs only after the ingress, pending carrier, active
operation claim, every `Cleanup_Claimed` slot, and every queued entry tagged
with the complete path reference are resolved. Close explicitly consumes any
unclaimed `Outcome_Pending` value before retirement. After node selective
cleanup is complete, the context keeps its record `Cleanup_Retained`. The path
relinquishes its session driver claim before one
final context action removes the exact-session key, marks the record slot
inactive, and makes the complete path reference stale. The local handle then
becomes invalid. A later session admission advances the inactive context slot's
nonwrapping generation and rejects every earlier complete path reference. A
slot at its final generation is permanently exhausted.

A reconnect uses a new `Session_ID`, sender binding, receiver binding, and path
reference. It cannot receive, purge, or reinterpret an earlier path's entry. An
application-owned `Inbound_Message` retains its earlier exact binding until
release.

Version one permits only one active unidirectional path for an exact
`Session_Reference`; that path is the complete local session state. A protocol
violation therefore latches that exact session failed, fences its path before
another take or enqueue, and performs the same resumable drain. A later
bidirectional request/reply decision must make the latch cover every path of
the same `Session_Reference` rather than weakening this rule.

Normal path close, endpoint close, transport disconnect, backpressure, stale
endpoint state, and stale incarnation classification never publish
`Node_Incarnation_Ended`. Decision 0012's exact owned-process authority remains
the only version-one death authority. Its already accepted registry cut is
extended to every contextual session state defined here. For an `Admitted`
session with no path, the cut fences session operation claims, closes and
drains the ingress, and retires its context record. For an initializing or
active path, the cut also fences its registration or delivery claim before
another ingress take or endpoint enqueue and marks the record failed and
closing. It applies to every record whose exact binding contains the affected
node incarnation.

The same registry cut marks the exact matching compound-node record failed,
fences new node and endpoint claims and pins, and makes its complete node and
endpoint handles noncurrent. While the failed record is retained, operations
on those handles report the retained liveness cause rather than an ordinary
stale result. Claims that linearized earlier finish their one ownership
transition before cleanup. After path claims and selective drains resolve, the
context drains any remaining endpoint entries, preserves exhausted generations,
and leaves the quiescent node record `Node_Cleanup_Retained` for the atomic
node/provenance retirement action; only that retirement makes the handles
stale. Ordinary node close follows the normal `Node_Closed` path above and
cannot set or imitate this liveness cause.

A claim that linearized first completes its one ownership transition before
the cut proceeds; it cannot publish after the cut. Each path then completes the
same retirement cut: resolve the active operation and every cleanup claim,
drain ingress, pending, and exact-path mailbox carriers, consume the local
outcome slot, retire the path record, and relinquish the session driver claim.
Incarnation-record retirement waits for every session and path to retire and
for every compound-node, endpoint, provider, and cleanup-token state to become
quiescent; its final context action jointly retires each eligible node record
and the provenance record as defined above. Terminal observation failure
performs the same ownership cleanup without publishing death. This composition
may be implemented in a later slice, but it is required and needs no further
semantic decision. Delivery failure itself never invokes the authority.

## Consequences

The in-process reference path can move a canonical header and payload from
session acceptance into an endpoint shared by heterogeneous session pools
without copying bytes or exposing transport details to application code.
Acceptance, endpoint queueing, application receipt, decode, and processing are
distinct milestones.

The implementation proceeds in three separately reviewed changes:

1. add and qualify Flyology's bounded buffer domain and definite owned-buffer
   capability;
2. add the context-owned provider tables and refactor sessions and compound
   nodes into guarded handles over the private definite carrier; and
3. add complementary binding, path activation, the delivery pump, outcomes,
   and the inbound message API.

Conformance must cover both role directions, equal-node opposite roles,
heterogeneous payload and header pools, exact writer pass-through, reconnect
isolation, duplicate session admission, session-table capacity and generation
exhaustion, known-unmanaged provenance, retired-owned unknown classification,
and the precedence of simultaneous ended, observation-failed, and unknown node
states in equal-node and two-node bindings. Admission fault fixtures cover
invalid configuration, after `Admitting` reservation, during provider-state
initialization, and immediately before publication; every failure leaves the
handle invalid and restores table and pool capacity without relying on an
unpublished object's finalizer.

Buffer-domain fixtures declare domain, context, and handles in their required
order, exercise heterogeneous header and payload pools, and prove every pool is
fully restored before context and then domain finalization. Compile-time
negative fixtures reject a context, `Writable_Payload`, or `Inbound_Message`
that can outlive its domain; no test relies on a raising pool finalizer to
detect a dangling capability. Header fixtures cover concurrent selection,
exclusive reservation, admission rollback, generation exhaustion, and release
only after the final context-accounted header returns. A session may retire and
its header pool may be reassigned while an application-owned payload-only
`Inbound_Message` remains live. Header retirement injects abort after
`Header_Release_Claimed` but before domain prepare, after domain prepare but
before context retirement, after context retirement but before acknowledgment,
and after acknowledgment but before token clear. The first two keep the pool
unavailable and resume the same generation; the latter two use the authorized
token to acknowledge exactly once or harmlessly repeat acknowledgment. A newer
reservation and release between repeated old acknowledgments must remain
untouched. A final-generation prepare and acknowledgment must leave the pool
permanently exhausted and reject another reservation.

Lifecycle conformance covers context-before-handle declaration order, session,
node, endpoint, and path handle finalization racing close and liveness cleanup,
duplicate path registration and registration rollback, operation-busy
classification, and registration racing `Initializing`, closing, failed, and
cleanup-retained records. The contextual public API has no direct accepted
dequeue; compile-time surface checks and runtime fault seams must show that no
carrier can escape the record's driver and cleanup accounting. Admission
fixtures race both authoritative death and terminal observation failure before
admission and after admission but before path registration, including accepted
ingress entries; later sends must be rejected and every pool restored exactly.

Node fixtures cover invalid and unknown owners, duplicate exact-owner handles,
node-table and generation exhaustion, interrupted normal close, same-owner
reactivation with preserved endpoint generations, different-incarnation slot
reuse, final-generation rejection, rejection of a retired exact owner, and the
atomic node/provenance co-retirement cut. They force both orderings between
authoritative death or observation failure and node claim, endpoint claim,
active pin, normal close, handle finalization, and record retirement. No old
node or endpoint reference may select a reactivated or replacement mailbox.

Delivery conformance covers FIFO across retryable backpressure,
terminal-outcome retention through abort, exact source and destination
retention after terminal rejection, every endpoint and complete path-reference
classification, repeated record-slot reuse and stale-reference rejection,
path/endpoint/receive/close races, and abort and fault injection before and
after carrier publication. Registration fixtures race both liveness outcomes
before the context transition, while the transition claim is held, and after
activation; they must leave no active or initializing residue and must restore
driver and table capacity. Delivery fixtures cover every named result and its
pending, outcome, or terminal state; `Take_Outcome` fixtures cover every named
result, precedence, target validity, close or liveness consumption, and abort
at the former post-clear/pre-return copy-out seam. Receive fixtures force both
orderings
between the queued-head context claim and authoritative death or observation
failure, and must either transfer application ownership or clean the exact
carrier, never both. They also cover every named result, endpoint and empty
precedence, close-before-death, failure-before-death, death-before-close or
failure, `Receive_State_Changed`, and the vacant target postcondition.
They also exercise the same-domain target constraint and prove wrong-domain
parameter binding cannot pin an endpoint or mutate its vacant target.

Forwarding fixtures reject and abort before commit while preserving the payload
lease, content, semantic metadata, and binding. Acceptance must install a newly
validated target header, move the unchanged payload across heterogeneous domain
pools, and vacate the `Inbound_Message`. Both orderings of target-session death
and commit restore exact payload and newly acquired header capacity. Drain
fixtures cover authoritative death racing the
after-dequeue/before-pending-publication claim and exact restoration of every
pool, including interruption and public-handle finalization while context-owned
cleanup is retained. No test may equate an endpoint or transport failure with
authoritative node death.

## Alternatives

- Put accepted descriptors into the existing payload-only node.
- Fix every destination mailbox to one session's payload and header pools.
- Supply or infer a replacement binding for each message.
- Copy payload bytes into homogeneous mailbox storage.
- Treat endpoint enqueue or application dequeue as send acceptance.
- Retry backpressure implicitly while allowing later accepted entries to pass.
- Let path close leave its endpoint-queued entries for a reconnect.
- Treat close, disconnect, timeout, or stale endpoint state as node death.
