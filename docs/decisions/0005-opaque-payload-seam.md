# 0005: Keep transport progress independent of codecs

Status: Accepted

## Context

The sibling `flyology_wire` crate owns schema identity and conversion between
Ada values and canonical payload bytes. Remoting must make progress and qualify
ownership, ordering, backpressure, closure, and cleanup before every generated
codec and profile is available.

## Decision

Transport adapters operate on bounded opaque payload leases. A codec receives a
callback-scoped writable or readable contiguous byte array while remoting keeps
the lease alive. The transport does not interpret schema fields or define a
parallel codec interface.

`flyology_wire` defines its octet, offset, count, and array names as subtypes of
the corresponding `Ada.Streams` types. Flyology buffer borrows therefore pass
directly to codecs without an array conversion or address overlay. Codecs must
accept arbitrary borrowed array bounds and index relative to the actual first
element.

The dependency remains `flyology_remoting -> flyology_wire`. Wire descriptors
supply family, schema, revision, and profile identity. Remoting envelopes add
endpoint, session, message, correlation, deadline, and tracing metadata.

The agreed minimum wire runtime supplies:

- Alire crate `flyology_wire` and Ada root `Flyology_Wire`, with no Flyology or
  remoting dependency;
- 16-byte family identities, 32-byte schema fingerprints, and nonzero 32-bit
  schema revision and profile identities;
- descriptors containing those four identities and an optional static maximum
  encoded size;
- exact measurement plus transactional caller-buffer encode and decode status
  contracts; and
- no streaming or freely returnable borrowed view in version one.

Later generated borrowed decoding will use a callback-scoped limited view while
remoting retains the readable lease. A transport-independent codec descriptor
and formal-package contract belong only to wire.

## Consequences

The in-process reference transport and later IPC/network adapters can share
ownership conformance tests before typed message registration exists. A wire
codec can encode directly into transport-provided storage. Received payloads
offer only callback-scoped read access, leaving later borrowed decoding tied to
the transport lease lifetime. A received payload may transfer directly to a
compatible outbound lane for forwarding without gaining writable access.
