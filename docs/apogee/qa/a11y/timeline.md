# timeline: accessibility (§6)

Owner: fe-ops. Run 2, 2026-11-13 07:55-08:47Z (method: [README](README.md)).

## Findings

- Clean. The probe flagged a "trap" on the last tab stop at 390. It was the live data-source status link ("Flight telemetry source is Unavailable/Degraded") re-rendering as the source breaker flapped, not a real trap.

## Runs

| Route | Role | Width | Load | h1 | Tab stops | axe |
| --- | --- | ---: | --- | ---: | ---: | --- |
| `M/timeline` | member | 1440 | ok | 1 | 46 | none |
| `M/timeline` | member | 390 | ok | 1 | 17 | none |
| `M/timeline` | admin | 1440 | ok | 1 | 47 | none |
| `M/timeline` | admin | 390 | ok | 1 | 17 | none |
