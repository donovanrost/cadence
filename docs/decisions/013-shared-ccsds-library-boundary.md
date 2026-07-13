---
title: "ADR-013: Shared CCSDS Library Boundary"
tags: [adr, architecture, ccsds, simulator, dependencies]
status: accepted
created: 2026-07-13
updated: 2026-07-13
---

# ADR-013: Shared CCSDS Library Boundary

## Context

Cadence core and the external ground-network simulator both need CCSDS frame,
segmentation, reassembly, and COP-1 primitives. Keeping those modules inside
`cadence` forced the simulator to depend on the application it is intended to
exercise as an external peer.

## Decision

The dependency-leaf umbrella application `cadence_ccsds` owns the existing
`Cadence.CCSDS.*` modules and focused unit tests.

Both `cadence` and `cadence_simulator` depend on `cadence_ccsds`. The namespace is
preserved to avoid combining the architectural extraction with an unrelated API
rename.

`cadence_simulator` has no production dependency on `cadence`. Cadence remains a
test-only dependency for simulator integration tests that deliberately exercise a
real Cadence runtime.

The simulator also owns its configuration tree. A production simulator boot must
not load Cadence database, web, or background-job configuration.

## Consequences

- CCSDS behavior can be tested without starting Cadence or the simulator.
- Simulator releases can be built and started independently.
- Cadence and simulator protocol behavior still share one implementation.
- A future extraction into a standalone package or repository can occur without
  changing the current module API.
