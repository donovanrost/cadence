---
title: "ADR-014: Shared CCSDS Library Boundary"
tags: [adr, architecture, ccsds, simulator, dependencies]
status: accepted
created: 2026-07-13
updated: 2026-08-21
---

# ADR-014: Shared CCSDS Library Boundary

## Status

Accepted

This ADR was originally recorded as ADR-013. It was renumbered without changing
the decision because the repository already had a different accepted ADR-013.

## Context

Cadence core and the external ground-network simulator both need CCSDS frame,
segmentation, reassembly, and COP-1 primitives. Keeping those modules inside
`cadence` forced the simulator to depend on the application it is intended to
exercise as an external peer.

## Decision

The dependency-leaf package `packages/ccsds` owns the `CCSDS.*` modules and
focused unit tests. Its OTP application is `:ccsds`.

Both `cadence` and `cadence_simulator` depend on `ccsds`. The package and module
names intentionally omit Cadence because the implementation is portable and
the protocols are standardized independently of the consuming products.

The package carries the metadata, documentation, changelog, and Apache-2.0
license required to build a standalone Hex artifact. Publication remains a
separate release decision.

`cadence_simulator` has no production dependency on `cadence`. Cadence remains a
test-only dependency for simulator integration tests that deliberately exercise a
real Cadence runtime.

The simulator also owns its configuration tree. A production simulator boot must
not load Cadence database, web, or background-job configuration.

## Consequences

- CCSDS behavior can be tested without starting Cadence or the simulator.
- Simulator releases can be built and started independently.
- Cadence and simulator protocol behavior still share one implementation.
- The package can be built, documented, and inspected as a standalone Hex
  artifact without publishing it.
- A future extraction into a separate repository can preserve the current
  package and module API.
