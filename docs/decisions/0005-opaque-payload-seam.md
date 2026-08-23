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
contain one authoritative `Schema_Identity` plus an optional static maximum.
The identity contains a 16-byte family, 32-byte fingerprint, nonzero 32-bit
revision, and nonzero 32-bit profile. Its canonical envelope encoding is
exactly 56 bytes in that order, with revision and profile encoded unsigned
big-endian. Remoting envelopes add endpoint, session, message, correlation,
deadline, and tracing metadata.

The agreed minimum wire runtime supplies:

- Alire crate `flyology_wire` and Ada root `Flyology_Wire`, with no Flyology or
  remoting dependency;
- 16-byte family identities, 32-byte schema fingerprints, and nonzero 32-bit
  schema revision and profile identities;
- descriptors containing `Schema : Schema_Identity` and an optional static
  maximum encoded size;
- exact measurement plus transactional caller-buffer encode and decode status
  contracts, with decode receiving the validated writer schema identity; and
- no streaming or freely returnable borrowed view in version one.

Generated borrowed observation uses a statically bound visitor invoked inside
remoting's readable lease. It validates the complete payload first and then
makes a second bounded pass, so malformed or incompatible input invokes no
application callback. Visitor exceptions propagate while remoting retains the
lease through unwinding. A transport-independent codec descriptor and
formal-package contract belong only to wire.

## Consequences

The in-process reference transport and later IPC/network adapters can share
ownership conformance tests before typed message registration exists. A wire
codec can encode directly into transport-provided storage. Received payloads
offer only callback-scoped read access, leaving generated visitors tied to the
transport lease lifetime. A received payload may transfer directly to a
compatible outbound lane for forwarding without gaining writable access.

The first executable integration pins `flyology_wire` commit
`97dc25218a33a6dabfba9b726239d5daab676128`. The generic
`Flyology.Remoting.Codecs.In_Process` accepts the wire crate's formal-package
codec contract directly. It measures before borrowing mutable storage, writes
into the transport-owned block without an intermediate array, and invokes
decode only inside the received payload's readable callback. A successful
encode whose byte count differs from its exact measurement is a codec contract
violation and raises `Program_Error`; reported codec failures retain their wire
status and do not commit a new payload length.
