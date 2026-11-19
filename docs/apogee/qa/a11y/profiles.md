# profiles: accessibility (§6)

Owner: fe-setup. Run 2, 2026-11-13 07:55-08:47Z (method: [README](README.md)).

## Findings

- **Kit (lead):** at 390 the table wrapper `div.overflow-x-auto` scrolls sideways but has no tab stop, role or name, so keyboard users can't scroll it (axe `scrollable-region-focusable`, serious). One kit fix covers every table: `tabindex="0"`, `role="region"` and an `aria-label` naming the table. Seen on History.

## Runs

| Route | Role | Width | Load | h1 | Tab stops | axe |
| --- | --- | ---: | --- | ---: | ---: | --- |
| `M/setup/profiles` | member | 1440 | ok | 1 | 17 | none |
| `M/setup/profiles` | member | 390 | ok | 1 | 3 | none |
| `M/setup/profiles` | admin | 1440 | ok | 1 | 23 | none |
| `M/setup/profiles` | admin | 390 | ok | 1 | 4 | none |
| `M/setup/profiles/profile-earendil-block-1` | member | 1440 | ok | 1 | 23 | none |
| `M/setup/profiles/profile-earendil-block-1` | member | 390 | ok | 1 | 10 | none |
| `M/setup/profiles/profile-earendil-block-1` | admin | 1440 | ok | 1 | 30 | none |
| `M/setup/profiles/profile-earendil-block-1` | admin | 390 | ok | 1 | 12 | none |
| `M/setup/profiles/profile-earendil-block-1/catalog` | member | 1440 | ok | 1 | 23 | none |
| `M/setup/profiles/profile-earendil-block-1/catalog` | member | 390 | ok | 1 | 10 | none |
| `M/setup/profiles/profile-earendil-block-1/catalog` | admin | 1440 | ok | 1 | 30 | none |
| `M/setup/profiles/profile-earendil-block-1/catalog` | admin | 390 | ok | 1 | 12 | none |
| `M/setup/profiles/profile-earendil-block-1/history` | member | 1440 | ok | 1 | 33 | none |
| `M/setup/profiles/profile-earendil-block-1/history` | member | 390 | ok | 1 | 20 | scrollable-region-focusable (serious, 1) |
| `M/setup/profiles/profile-earendil-block-1/history` | admin | 1440 | ok | 1 | 39 | none |
| `M/setup/profiles/profile-earendil-block-1/history` | admin | 390 | ok | 1 | 21 | scrollable-region-focusable (serious, 1) |
| `M/setup/profiles/profile-earendil-block-1/overrides` | member | 1440 | ok | 1 | 24 | none |
| `M/setup/profiles/profile-earendil-block-1/overrides` | member | 390 | ok | 1 | 11 | none |
| `M/setup/profiles/profile-earendil-block-1/overrides` | admin | 1440 | ok | 1 | 32 | none |
| `M/setup/profiles/profile-earendil-block-1/overrides` | admin | 390 | ok | 1 | 14 | none |
| `M/setup/profiles/profile-earendil-block-1/protocols` | member | 1440 | ok | 1 | 23 | none |
| `M/setup/profiles/profile-earendil-block-1/protocols` | member | 390 | ok | 1 | 10 | none |
| `M/setup/profiles/profile-earendil-block-1/protocols` | admin | 1440 | ok | 1 | 29 | none |
| `M/setup/profiles/profile-earendil-block-1/protocols` | admin | 390 | ok | 1 | 11 | none |
| `M/setup/profiles/profile-earendil-block-1/routing` | member | 1440 | ok | 1 | 24 | none |
| `M/setup/profiles/profile-earendil-block-1/routing` | member | 390 | ok | 1 | 11 | none |
| `M/setup/profiles/profile-earendil-block-1/routing` | admin | 1440 | ok | 1 | 31 | none |
| `M/setup/profiles/profile-earendil-block-1/routing` | admin | 390 | ok | 1 | 13 | none |
