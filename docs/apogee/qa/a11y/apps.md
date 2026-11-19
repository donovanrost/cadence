# apps: accessibility (§6)

Owner: fe-setup. Run 2, 2026-11-13 07:55-08:47Z (method: [README](README.md)).

## Findings

- A module-federation `mf-manifest.json` asset 404s on Apps › Comms (console error); the app host page still renders. Owner: whoever ships the comms surface remote (L9).

## Runs

| Route | Role | Width | Load | h1 | Tab stops | axe |
| --- | --- | ---: | --- | ---: | ---: | --- |
| `M/setup/apps` | member | 1440 | ok | 1 | 23 | none |
| `M/setup/apps` | member | 390 | ok | 1 | 10 | none |
| `M/setup/apps` | admin | 1440 | ok | 1 | 28 | none |
| `M/setup/apps` | admin | 390 | ok | 1 | 10 | none |
| `M/setup/apps/comms` | member | 1440 | ok | 1 | 34 | none |
| `M/setup/apps/comms` | member | 390 | ok | 1 | 20 | none |
| `M/setup/apps/comms` | admin | 1440 | ok | 1 | 39 | none |
| `M/setup/apps/comms` | admin | 390 | ok | 1 | 20 | none |
