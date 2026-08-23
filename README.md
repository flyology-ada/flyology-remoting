# Flyology Remoting

Flyology Remoting is an experimental, message-oriented remoting library for
[Flyology](https://flyology.org/) tasks. It is intended to give applications
one endpoint and messaging model across an in-process transport, local
interprocess communication, and network connections.

The project is currently establishing its contracts. It provides runtime node,
session, generation-stamped endpoint and remote-task identities, a bounded
in-process reference lane, and an endpoint-aware in-process node for opaque
payload ownership and conformance work. A pinned `flyology_wire` codec can
encode directly into and decode directly from those payload leases. The
project does not yet provide cross-node routing, IPC, network transport,
registered task start, or remote lifecycle delivery.

`Flyology.Remoting.Sessions` binds an existing live-session reference to the
local initiator or acceptor role and validates exact-incarnation endpoint
direction before transport framing. This semantic binding allocates nothing
and implies no authentication, authorization, reachability, or process
liveness. Callers remain responsible for supplying a session identity that is
not reused and the local role established by the session owner or handshake;
the binding does not decide which identities an eventual envelope repeats or
derives from its handshake.

## Scope

The remoting boundary consists of nodes, endpoints, opaque encoded messages,
and registered task kinds:

- An endpoint is a generation-stamped destination for messages. It is not an
  Ada task identity or an access value.
- A destination node starts only task kinds registered by the executable
  already deployed there. Remoting does not move code, stacks, or live task
  state.
- The destination creates an ordinary Flyology native or lightweight task.
  Remoting does not introduce a third task lane.
- Request/reply is built from messages and correlation metadata. The base
  transport does not expose remote procedure calls.
- Deployment configuration resolves an endpoint to an in-process, IPC, or
  network transport without changing the application messaging API.

See [Architecture](docs/architecture.md) for the accepted foundations and
[Roadmap](docs/roadmap.md) for the implementation sequence. Every architecture
decision and change follows the repository's [review policy](docs/review-policy.md).

## Reference transport

`Flyology.Remoting.Transports.In_Process` is a generic, fixed-capacity FIFO
lane over a caller-owned `Flyology.Buffers.Pool`. A writable payload transfers
to the lane only on `Message_Accepted`; backpressure and closure preserve its
ownership. A received payload exposes only a callback-scoped readable borrow.
Closing a lane rejects new sends and drains already accepted payloads.
Received payloads can be forwarded to another compatible lane without copying
or acquiring mutable access.

A reusable test-only payload-lane contract qualifies immediate ownership,
FIFO, backpressure, forwarding, empty-payload, close/drain, and exact-release
semantics. It is intentionally not called full session conformance yet because
the current lane has no handshake, deadline, cancellation, or disconnect API.

This is the executable semantic reference for later IPC and network adapters,
not a separate application messaging API. It deliberately carries opaque bytes
and defines no type IDs, schema values, framing, endpoints, or codec contract.

`Flyology.Remoting.Nodes.In_Process` adds fixed-capacity endpoint mailboxes over
the lane. It rejects foreign, stale-incarnation, stale-generation, and closing
destinations before queue access. Closing drains accepted payloads and advances
the slot generation before reuse. A limited controlled handle owns each local
claim and closes it during finalization.

A reusable test-only local-node contract qualifies deterministic owner, bounded
claim, routing classification, FIFO, ownership, close/drain, and generation
reuse behavior. In-process abort cleanup and concurrent close remain separate
implementation tests. This is destination-router conformance, not session or
cross-node transport conformance.

## Remote task observation

Remote task references identify one logical task generation in one exact node
incarnation. The local adapter converts Flyology supervision observations into
bounded portable outcomes: ended, replaced, timed out, node incarnation ended,
or peer unreachable. A disconnect is deliberately not called task death, and
an exact-generation observation never follows a restarted task automatically.
The generic local observer verifies the registry-retained supervisor handle's
generation before entering Flyology's atomic exact-generation wait. A focused
integration fixture instantiates that seam directly against a real
`Flyology.Supervision.Families` exact wait.

## Initial delivery contract

The first transport contract will be bounded and session-scoped:

- accepted messages are delivered at most once;
- order is preserved from one sending endpoint to one receiving endpoint
  within one live session;
- reconnect does not replay messages or preserve the earlier session's order;
- accepting a send transfers payload ownership to remoting but does not mean
  that the receiver processed it;
- overload, deadline expiry, incompatibility, disconnection, and authorization
  failure remain distinct outcomes; and
- cancellation may stop pending local work but cannot retract a message that
  has already been delivered.

Durable delivery, transparent retry, global ordering, exactly-once execution,
peer discovery, and code deployment are not initial promises.

## IPC direction

The planned local transport uses shared memory as a data plane and Unix-domain
sockets as control planes. A codec may write an encoded message directly into
shareable storage. The data queue then transfers a bounded descriptor or lease
rather than copying payload bytes into the receiving process.

This is zero-copy payload transfer after encoding, not zero serialization.
Network transports may send the same sealed bytes, but normal kernel and TLS
copies still apply. Shared-memory peers must be mutually trusted because a
process able to map writable pages can violate protocol-level immutability.

Flyology's descriptor handoff channel remains dedicated to its one-descriptor
protocol. Remoting will use a separate control/wake connection rather than
mixing ordinary frames with that channel.

## Serialization boundary

Remoting consumes opaque encoded bytes plus the writer schema identity. Its
`Family` component is the message family/type identity; remoting does not define
a parallel message-type namespace. The sibling `flyology_wire` crate owns which
Ada values can cross the boundary, codec generation, schema evolution, and
whether a payload supports a validated borrowed view. Remoting does not use Ada
object layout, native addresses, access values, or runtime tags as a wire
format.

The current integration pins `flyology_wire` at a reviewed commit and accepts
its static codec contract directly. A transport-independent payload-lease
adapter measures a value before remoting lends writable storage, encodes into
that storage without an intermediate copy, and decodes a received lease under
the validated writer schema identity while remoting retains ownership. The
in-process codec package is a thin facade over this common adapter.

## Build and test

Add the Flyology organization index before building development versions:

```sh
alr index --reset-community
alr index --add=git+https://github.com/flyology-ada/alire-index.git \
  --name=flyology --before=community
alr build
./scripts/test.sh
```

The test harness builds the crate and exercises reference-lane
and endpoint-node ownership, backpressure, FIFO order, concurrent lightweight
task handoff and close, closure, and undelivered-payload cleanup. They also
exercise invalid identity sentinels, restart and reconnect freshness, bounded
endpoint allocation, stale reference rejection, slot reuse, concurrent claims,
portable exact-generation lifecycle conversion, and a canonical Profile 1
value encoded through an endpoint mailbox without replacing its payload
storage. Codec failures cover short output, invalid values, incompatible writer
schemas, malformed bytes, and noncanonical bytes.

Continuous integration runs the same suite on Linux and macOS with a pinned
Alire and GNAT toolchain. It also compiles the library separately in release
mode, so the checked test build is not the only consumer configuration covered.

## Agent setup

This repository uses APM 0.28.0 to provision one locked graph of shared and
repository-specific instructions and skills for Codex and Claude. In a new
clone or worktree, run:

```sh
curl -sSL https://aka.ms/apm-unix | sh -s -- @v0.28.0
apm --version

apm install --frozen
apm compile --target codex
```

The compiled `AGENTS.md` is committed so Codex receives the instructions
without setup. APM generates Claude's native rules and the Codex and Claude
skill trees locally from the same `apm.lock.yaml` graph; those deployment
outputs are ignored. Start a fresh client session after installation so it
discovers the generated skills. Repository-specific instructions live under
`agent-packages/`, and shared Ada and workflow resources come from the
`flyology-ada/agents` `main` update channel at the exact revision recorded in
`apm.lock.yaml`.

To review an intentional shared-resource upgrade, run:

```sh
apm outdated
apm update flyology-ada/agents
apm compile --target codex
apm audit --ci
git diff --check
```

Review the resulting lockfile, generated `AGENTS.md`, and behavior before
committing them. Frozen installation and CI never update the selected shared
revision.

## License

Flyology Remoting is available under either the MIT License or the Apache
License 2.0, at your option.
