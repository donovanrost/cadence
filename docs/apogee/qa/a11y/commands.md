# commands: accessibility (§6)

Owner: fe-ops. Run 2, 2026-11-13 07:55-08:47Z (method: [README](README.md)).

## Findings

- **api / fe-ops (console error):** with no saved draft, `GET /command-draft` answers 404 and the browser logs a console error on every Commands, Compose and Request load. Return 200 `{data: null}` or have the client skip the 404 quietly. (The e2e diagnostics guard would fail these pages.)

## Runs

| Route | Role | Width | Load | h1 | Tab stops | axe |
| --- | --- | ---: | --- | ---: | ---: | --- |
| `M/commands` | member | 1440 | ok | 1 | 18 | none |
| `M/commands` | member | 390 | ok | 1 | 11 | none |
| `M/commands` | admin | 1440 | ok | 1 | 19 | none |
| `M/commands` | admin | 390 | ok | 1 | 11 | none |
