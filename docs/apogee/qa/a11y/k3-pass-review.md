# k3-pass-review: accessibility (§6)

Owner: fe-ops. Run 2, 2026-11-13 07:55-08:47Z (method: [README](README.md)).

## Findings

- **Kit (lead):** at 390 the table wrapper `div.overflow-x-auto` scrolls sideways but has no tab stop, role or name, so keyboard users can't scroll it (axe `scrollable-region-focusable`, serious). One kit fix covers every table: `tabindex="0"`, `role="region"` and an `aria-label` naming the table.

## Runs

| Route | Role | Width | Load | h1 | Tab stops | axe |
| --- | --- | ---: | --- | ---: | ---: | --- |
| `M/contacts/review` | member | 1440 | ok | 1 | 20 | none |
| `M/contacts/review` | member | 390 | ok | 1 | 14 | scrollable-region-focusable (serious, 1) |
| `M/contacts/review` | admin | 1440 | ok | 1 | 21 | none |
| `M/contacts/review` | admin | 390 | ok | 1 | 14 | scrollable-region-focusable (serious, 1) |
