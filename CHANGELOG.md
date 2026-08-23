# Changelog

## Unreleased

- Establish the message-oriented architecture, transport contract, IPC data
  plane, and registered-task-kind boundary.
- Add a bounded in-process opaque-payload lane with ownership-preserving
  backpressure, FIFO transfer, closure, and cleanup tests.
- Add transport-neutral node, incarnation, session, and endpoint references
  with a bounded task-safe generation-stamped endpoint directory.
