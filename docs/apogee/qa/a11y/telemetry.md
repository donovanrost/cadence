# telemetry: accessibility (§6)

Owner: fe-ops (Explore) / dashboards (Dashboards). Run 2, 2026-11-13 07:55-08:47Z (method: [README](README.md)).

## Findings

- **dashboards:** at 390 the Dashboards directory table is wider than the screen; the whole page scrolls sideways by 134 px and the Updated column is cut off. Collapse to rows or cards on mobile, or put the table in a labelled scroll region.
- Explore (fe-ops): clean.

## Runs

| Route | Role | Width | Load | h1 | Tab stops | axe |
| --- | --- | ---: | --- | ---: | ---: | --- |
| `M/telemetry` | member | 1440 | ok | 1 | 76 | none |
| `M/telemetry` | member | 390 | ok | 1 | 68 | none |
| `M/telemetry` | admin | 1440 | ok | 1 | 77 | none |
| `M/telemetry` | admin | 390 | ok | 1 | 68 | none |
| `M/telemetry/dashboards` | member | 1440 | ok | 1 | 36 | none |
| `M/telemetry/dashboards` | member | 390 | ok | 1 | 29 | none |
| `M/telemetry/dashboards` | admin | 1440 | ok | 1 | 42 | none |
| `M/telemetry/dashboards` | admin | 390 | ok | 1 | 34 | none |
