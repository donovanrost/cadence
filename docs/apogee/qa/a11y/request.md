# request: accessibility (§6)

Owner: fe-ops. Run 2, 2026-11-13 07:55-08:47Z (method: [README](README.md)).

## Findings

- Same `command-draft` 404 console error as Commands. h1 and landmarks are fine (run 1 used a request id where the route takes a group id; fixed in run 2).

## Runs

| Route | Role | Width | Load | h1 | Tab stops | axe |
| --- | --- | ---: | --- | ---: | ---: | --- |
| `M/commands/command_group_hrqhaia2di_NJZD` | member | 1440 | ok | 1 | 5 | none |
| `M/commands/command_group_hrqhaia2di_NJZD` | member | 390 | ok | 1 | 1 | none |
| `M/commands/command_group_hrqhaia2di_NJZD` | admin | 1440 | ok | 1 | 5 | none |
| `M/commands/command_group_hrqhaia2di_NJZD` | admin | 390 | timed out (load) | 0 | 0 | none |
| `M/commands/command_group_hrqhaia2di_NJZD/review` | member | 1440 | ok | 1 | 0 | none |
| `M/commands/command_group_hrqhaia2di_NJZD/review` | member | 390 | ok | 1 | 9 | none |
| `M/commands/command_group_hrqhaia2di_NJZD/review` | admin | 1440 | ok | 1 | 0 | none |
| `M/commands/command_group_hrqhaia2di_NJZD/review` | admin | 390 | ok | 1 | 1 | none |
| `M/commands/command_group_hrqhaia2di_NJZD/uplink` | member | 1440 | ok | 1 | 5 | none |
| `M/commands/command_group_hrqhaia2di_NJZD/uplink` | member | 390 | ok | 1 | 11 | none |
| `M/commands/command_group_hrqhaia2di_NJZD/uplink` | admin | 1440 | ok | 1 | 19 | none |
| `M/commands/command_group_hrqhaia2di_NJZD/uplink` | admin | 390 | ok | 1 | 9 | none |
