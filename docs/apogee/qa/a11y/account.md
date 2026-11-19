# account: accessibility (§6)

Owner: fe-setup. Run 2, 2026-11-13 07:55-08:47Z (method: [README](README.md)).

## Findings

- No findings: axe clean at both widths for both roles, one h1, every tab stop visible with a focus indicator, no sideways scroll.

## Runs

| Route | Role | Width | Load | h1 | Tab stops | axe |
| --- | --- | ---: | --- | ---: | ---: | --- |
| `/console/account` | member | 1440 | ok | 1 | 100 | none |
| `/console/account` | member | 390 | ok | 1 | 101 | none |
| `/console/account` | admin | 1440 | ok | 1 | 120+ | none |
| `/console/account` | admin | 390 | ok | 1 | 120+ | none |
