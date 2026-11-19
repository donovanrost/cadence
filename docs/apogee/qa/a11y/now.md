# now: accessibility (§6)

Owner: fe-ops. Run 2, 2026-11-13 07:55-08:47Z (method: [README](README.md)).

## Findings

- One admin run at 1440 timed out under load; the other three were clean.

## Runs

| Route | Role | Width | Load | h1 | Tab stops | axe |
| --- | --- | ---: | --- | ---: | ---: | --- |
| `M/now` | member | 1440 | ok | 1 | 29 | none |
| `M/now` | member | 390 | ok | 1 | 17 | none |
| `M/now` | admin | 1440 | timed out (load) | 0 | 0 | none |
| `M/now` | admin | 390 | ok | 1 | 12 | none |
