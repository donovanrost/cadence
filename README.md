# Cadence

Cadence is now structured as an umbrella project.

## Layout

- `apps/cadence` - new core application for the redesigned ground data system
- `apps/cadence_web` - new web/application boundary for Cadence
- `apps/cadence_simulator` - external simulator and local performance tooling
- `legacy/cadence_legacy` - preserved snapshot of the previous monolithic Cadence codebase

## Documentation

- [Developer Architecture Guide](docs/developer-architecture-guide.md) - current implementation shape, storage tiers, runtime boundaries, and local development workflow
- [How-To Guides](docs/how-to/_index.md) - practical workflows for local development, profiling, and benchmarking
- [Architecture Decision Records](docs/decisions/_index.md) - accepted architectural decisions for the redesigned system
- [Simulator Contact Bootstrap Flow](docs/simulator_contact_bootstrap_flow.md) - lower-level control-plane bootstrap flow for simulator-backed contacts

## Legacy Code

The legacy application is intentionally kept outside the umbrella `apps/` path so
its `Cadence` and `CadenceWeb` modules do not conflict with the new system.
