# audit: accessibility (§6)

Owner: fe-setup. Run 2, 2026-11-13 07:55-08:47Z (method: [README](README.md)).

## Findings

- **Member gating (fe-setup):** a member who opens Audit by URL gets a 403, "You do not have permission to do that." with **Retry**, and an empty org-level left rail. Say "Org admins see this" with no Retry (Retry can never succeed), and don't offer the route to members.

## Runs

| Route | Role | Width | Load | h1 | Tab stops | axe |
| --- | --- | ---: | --- | ---: | ---: | --- |
| `O/org/audit` | member | 1440 | ok | 1 | 8 | none |
| `O/org/audit` | member | 390 | ok | 1 | 8 | none |
| `O/org/audit` | admin | 1440 | ok | 1 | 14 | none |
| `O/org/audit` | admin | 390 | ok | 1 | 9 | none |
