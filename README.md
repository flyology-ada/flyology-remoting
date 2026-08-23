# Flyology Remoting

Flyology Remoting is an experimental, message-oriented remoting library for
[Flyology](https://flyology.org/) tasks. It is intended to give applications
one endpoint and messaging model across an in-process transport, local
interprocess communication, and network connections.

The project is currently establishing its contracts. It does not yet provide
a working transport or remote task API.

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
[Roadmap](docs/roadmap.md) for the implementation sequence.

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

Remoting consumes opaque encoded bytes plus message type and schema identity.
The sibling serialization project will define which Ada values can cross the
boundary, codec generation, schema evolution, and whether a payload supports a
validated borrowed view. Remoting will not use Ada object layout, native
addresses, access values, or runtime tags as a wire format.

## Build and test

Add the Flyology organization index before building development versions:

```sh
alr index --reset-community
alr index --add=git+https://github.com/flyology-ada/alire-index.git \
  --name=flyology --before=community
alr build
./scripts/test.sh
```

The current smoke test verifies that the companion crate and its
`Flyology.Remoting` namespace compile against the selected Flyology version.

## License

Flyology Remoting is available under either the MIT License or the Apache
License 2.0, at your option.
