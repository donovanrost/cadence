# Cadence

Cadence is now structured as an umbrella project.

## Layout

- `apps/cadence` - new core application for the redesigned ground data system
- `apps/cadence_web` - new web/application boundary for Cadence
- `apps/cadence_ccsds` - shared CCSDS protocol library
- `apps/cadence_simulator` - independently runnable external provider simulator
- `legacy/cadence_legacy` - preserved snapshot of the previous monolithic Cadence codebase

## Documentation

- [Developer Architecture Guide](docs/developer-architecture-guide.md) - current implementation shape, storage tiers, runtime boundaries, and local development workflow
- [How-To Guides](docs/how-to/_index.md) - practical workflows for local development, profiling, and benchmarking
- [Architecture Decision Records](docs/decisions/_index.md) - accepted architectural decisions for the redesigned system
- [Contact Scheduling and Ground Network Simulation Design](docs/superpowers/specs/2026-07-12-contact-scheduling-and-ground-network-simulation-design.md) - idealized provider-neutral scheduling and simulator end state
- [Simulator Provider Integration Flow](docs/simulator_provider_integration_flow.md) - configure the simulator through Cadence's ordinary provider boundary

## Legacy Code

The legacy application is intentionally kept outside the umbrella `apps/` path so
its `Cadence` and `CadenceWeb` modules do not conflict with the new system.
