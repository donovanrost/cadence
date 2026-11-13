# home: accessibility (§6)

Owner: lead (shell). Run 2, 2026-11-13 07:55-08:47Z (method: [README](README.md)).

## Findings

- One member run at 1440 hit a transient `/session` 500 while the reloader recompiled (`Cadence.Auth.Policy` briefly not loaded). The other three runs were clean.

## Runs

| Route | Role | Width | Load | h1 | Tab stops | axe |
| --- | --- | ---: | --- | ---: | ---: | --- |
| `/console/` | member | 1440 | timed out (load) | 0 | 0 | none |
| `/console/` | member | 390 | ok | 1 | 17 | none |
| `/console/` | admin | 1440 | ok | 1 | 30 | none |
| `/console/` | admin | 390 | ok | 1 | 17 | none |
