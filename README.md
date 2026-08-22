# Cadence

Cadence is a monorepo poncho coordinated by a code-free Elixir Workspace root.
Each application and package owns its Mix build, dependencies, lockfile, and
configuration boundary.

## Layout

- `apps/cadence` - core domain, persistence, and runtime application
- `apps/cadence_web` - Phoenix boundary and Cadence server composition root
- `apps/cadence_simulator` - independently runnable external provider simulator
- `packages/cadence_catalog` - catalog and Mission Model compiler package
- `packages/ccsds` - standalone-ready CCSDS protocol package
- `legacy/cadence_legacy` - preserved snapshot of the previous monolithic Cadence codebase

## Documentation

- [Developer Architecture Guide](docs/developer-architecture-guide.md) - current implementation shape, storage tiers, runtime boundaries, and local development workflow
- [CCSDS Library Gap Assessment](docs/ccsds-library-gap-assessment.md) - implemented protocol subset, remaining standards gaps, and recommended sequencing
- [How-To Guides](docs/how-to/_index.md) - practical workflows for local development, profiling, and benchmarking
- [Architecture Decision Records](docs/decisions/_index.md) - accepted architectural decisions for the redesigned system
- [Contact Scheduling and Ground Network Simulation Design](docs/superpowers/specs/2026-07-12-contact-scheduling-and-ground-network-simulation-design.md) - idealized provider-neutral scheduling and simulator end state
- [Simulator Provider Integration Flow](docs/simulator_provider_integration_flow.md) - configure the simulator through Cadence's ordinary provider boundary

## Legacy Code

The legacy application is intentionally kept outside the active Workspace
project paths so its `Cadence` and `CadenceWeb` modules do not conflict with the
new system.
