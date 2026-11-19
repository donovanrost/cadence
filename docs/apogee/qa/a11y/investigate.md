# investigate: accessibility (§6)

Owner: fe-ops. Run 2, 2026-11-13 07:55-08:47Z (method: [README](README.md)).

## Findings

- No findings: axe clean at both widths for both roles, one h1, every tab stop visible with a focus indicator, no sideways scroll.

## Runs

| Route | Role | Width | Load | h1 | Tab stops | axe |
| --- | --- | ---: | --- | ---: | ---: | --- |
| `M/fleet/1` | member | 1440 | ok | 1 | 26 | none |
| `M/fleet/1` | member | 390 | ok | 1 | 4 | none |
| `M/fleet/1` | admin | 1440 | ok | 1 | 27 | none |
| `M/fleet/1` | admin | 390 | ok | 1 | 9 | none |
| `M/fleet/1/configuration` | member | 1440 | ok | 1 | 31 | none |
| `M/fleet/1/configuration` | member | 390 | ok | 1 | 9 | none |
| `M/fleet/1/configuration` | admin | 1440 | ok | 1 | 33 | none |
| `M/fleet/1/configuration` | admin | 390 | ok | 1 | 4 | none |
| `M/fleet/1/history` | member | 1440 | ok | 1 | 25 | none |
| `M/fleet/1/history` | member | 390 | ok | 1 | 9 | none |
| `M/fleet/1/history` | admin | 1440 | ok | 1 | 26 | none |
| `M/fleet/1/history` | admin | 390 | ok | 1 | 4 | none |
| `M/fleet/1/passes` | member | 1440 | ok | 1 | 31 | none |
| `M/fleet/1/passes` | member | 390 | ok | 1 | 9 | none |
| `M/fleet/1/passes` | admin | 1440 | ok | 1 | 32 | none |
| `M/fleet/1/passes` | admin | 390 | ok | 1 | 9 | none |
| `M/fleet/1/telemetry` | member | 1440 | ok | 1 | 120+ | none |
| `M/fleet/1/telemetry` | member | 390 | ok | 1 | 9 | none |
| `M/fleet/1/telemetry` | admin | 1440 | ok | 1 | 120+ | none |
| `M/fleet/1/telemetry` | admin | 390 | ok | 1 | 9 | none |
| `M/fleet/1/uplink` | member | 1440 | ok | 1 | 26 | none |
| `M/fleet/1/uplink` | member | 390 | ok | 1 | 9 | none |
| `M/fleet/1/uplink` | admin | 1440 | ok | 1 | 27 | none |
| `M/fleet/1/uplink` | admin | 390 | ok | 1 | 9 | none |
