# Cadence

Cadence is now structured as an umbrella project.

## Layout

- `apps/cadence` - new core application for the redesigned ground data system
- `apps/cadence_web` - new web/application boundary for Cadence
- `legacy/cadence_legacy` - preserved snapshot of the previous monolithic Cadence codebase

## Legacy Code

The legacy application is intentionally kept outside the umbrella `apps/` path so
its `Cadence` and `CadenceWeb` modules do not conflict with the new system.
