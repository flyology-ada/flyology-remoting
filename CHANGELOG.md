# Changelog

## Unreleased

- Establish the message-oriented architecture, transport contract, IPC data
  plane, and registered-task-kind boundary.
- Add a bounded in-process opaque-payload lane with ownership-preserving
  backpressure, FIFO transfer, closure, and cleanup tests.
- Add transport-neutral node, incarnation, session, and endpoint references
  with a bounded task-safe generation-stamped endpoint directory.
- Add a bounded endpoint-aware in-process node with generation-safe routing,
  close/drain reclamation, and concurrent-close ownership tests.
- Add exact-generation remote task references, portable lifecycle outcomes,
  and conversion from Flyology supervision observations while preserving
  node-global task identities across supervisor-local restarts.
- Pin `flyology_wire` and add a static codec adapter that measures and encodes
  directly into writable payload leases and decodes inside received leases.
- Add pinned Linux and macOS continuous integration for the full test suite,
  plus an independent Linux release build.
- Clarify that wire schema incompatibility is a message-level outcome, while
  malformed protocol or handshake input is session-fatal.
- Add a checked generic adapter from registry-retained supervisor handles to
  Flyology's exact-generation lifecycle wait.
- Add a reusable payload-lane conformance harness for immediate bounded
  ownership, FIFO, backpressure, forwarding, closure, and exact release.
- Factor direct wire encoding and decode-under-lease into a transport-generic
  codec adapter while retaining the in-process facade.
- Add reusable immediate local-node conformance for bounded claims, routing,
  ownership, close/drain, and generation-safe endpoint reuse.
