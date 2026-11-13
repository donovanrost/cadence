# spacecraft: accessibility (§6)

Owner: fe-setup. Run 2, 2026-11-13 07:55-08:47Z (method: [README](README.md)).

## Findings

- **Kit (lead):** at 390 the table wrapper `div.overflow-x-auto` scrolls sideways but has no tab stop, role or name, so keyboard users can't scroll it (axe `scrollable-region-focusable`, serious). One kit fix covers every table: `tabindex="0"`, `role="region"` and an `aria-label` naming the table. Seen on the spacecraft detail page.

## Runs

| Route | Role | Width | Load | h1 | Tab stops | axe |
| --- | --- | ---: | --- | ---: | ---: | --- |
| `M/setup/spacecraft` | member | 1440 | ok | 1 | 120+ | none |
| `M/setup/spacecraft` | member | 390 | ok | 1 | 120+ | none |
| `M/setup/spacecraft` | admin | 1440 | ok | 1 | 120+ | none |
| `M/setup/spacecraft` | admin | 390 | timed out (load) | 1 | 0 | none |
| `M/setup/spacecraft/spacecraft-earendil-001` | member | 1440 | ok | 1 | 20 | none |
| `M/setup/spacecraft/spacecraft-earendil-001` | member | 390 | ok | 1 | 8 | scrollable-region-focusable (serious, 1) |
| `M/setup/spacecraft/spacecraft-earendil-001` | admin | 1440 | ok | 1 | 25 | none |
| `M/setup/spacecraft/spacecraft-earendil-001` | admin | 390 | ok | 1 | 8 | scrollable-region-focusable (serious, 1) |
