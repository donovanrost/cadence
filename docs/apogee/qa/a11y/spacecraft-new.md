# spacecraft-new: accessibility (§6)

Owner: fe-setup. Run 2, 2026-11-13 07:55-08:47Z (method: [README](README.md)).

## Findings

- **Kit (lead):** at 390 the wizard step bar (`div.flex.md:flex-none … max-md:overflow-x-auto`) scrolls sideways with no tab stop (axe `scrollable-region-focusable`, serious, on all four steps).

## Runs

| Route | Role | Width | Load | h1 | Tab stops | axe |
| --- | --- | ---: | --- | ---: | ---: | --- |
| `M/setup/spacecraft/new` | member | 1440 | ok | 1 | 120+ | none |
| `M/setup/spacecraft/new` | member | 390 | ok | 1 | 2 | scrollable-region-focusable (serious, 1) |
| `M/setup/spacecraft/new` | admin | 1440 | ok | 1 | 22 | none |
| `M/setup/spacecraft/new` | admin | 390 | ok | 1 | 4 | scrollable-region-focusable (serious, 1) |
| `M/setup/spacecraft/new/identity` | member | 1440 | ok | 1 | 15 | none |
| `M/setup/spacecraft/new/identity` | member | 390 | ok | 1 | 2 | scrollable-region-focusable (serious, 1) |
| `M/setup/spacecraft/new/identity` | admin | 1440 | ok | 1 | 120+ | none |
| `M/setup/spacecraft/new/identity` | admin | 390 | ok | 1 | 3 | scrollable-region-focusable (serious, 1) |
| `M/setup/spacecraft/new/orbit` | member | 1440 | ok | 1 | 15 | none |
| `M/setup/spacecraft/new/orbit` | member | 390 | ok | 1 | 2 | scrollable-region-focusable (serious, 1) |
| `M/setup/spacecraft/new/orbit` | admin | 1440 | ok | 1 | 120+ | none |
| `M/setup/spacecraft/new/orbit` | admin | 390 | ok | 1 | 3 | scrollable-region-focusable (serious, 1) |
| `M/setup/spacecraft/new/review` | member | 1440 | ok | 1 | 15 | none |
| `M/setup/spacecraft/new/review` | member | 390 | ok | 1 | 2 | scrollable-region-focusable (serious, 2) |
| `M/setup/spacecraft/new/review` | admin | 1440 | ok | 1 | 21 | none |
| `M/setup/spacecraft/new/review` | admin | 390 | ok | 1 | 3 | scrollable-region-focusable (serious, 2) |
