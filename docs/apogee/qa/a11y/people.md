# people: accessibility (§6)

Owner: fe-setup. Run 2, 2026-11-13 07:55-08:47Z (method: [README](README.md)).

## Findings

- **Kit (lead):** at 390 the table wrapper `div.overflow-x-auto` scrolls sideways but has no tab stop, role or name, so keyboard users can't scroll it (axe `scrollable-region-focusable`, serious). One kit fix covers every table: `tabindex="0"`, `role="region"` and an `aria-label` naming the table. Seen on the person page (admin).
- **Member gating (fe-setup):** a member who opens `org/people?tab=services` or a person page by URL gets 403s (`service-identities`, `audit?actor_id=…`) and error panels. Say "Org admins see this" with no Retry (Retry can never succeed), and don't offer the route to members.

## Runs

| Route | Role | Width | Load | h1 | Tab stops | axe |
| --- | --- | ---: | --- | ---: | ---: | --- |
| `O/org/people` | member | 1440 | ok | 1 | 10 | none |
| `O/org/people` | member | 390 | ok | 1 | 11 | none |
| `O/org/people` | admin | 1440 | ok | 1 | 18 | none |
| `O/org/people` | admin | 390 | ok | 1 | 14 | none |
| `O/org/people/invite` | member | 1440 | ok | 1 | 10 | none |
| `O/org/people/invite` | member | 390 | ok | 1 | 11 | none |
| `O/org/people/invite` | admin | 1440 | ok | 1 | 18 | none |
| `O/org/people/invite` | admin | 390 | ok | 1 | 14 | none |
| `O/org/people/services/new` | member | 1440 | ok | 1 | 7 | none |
| `O/org/people/services/new` | member | 390 | ok | 1 | 7 | none |
| `O/org/people/services/new` | admin | 1440 | ok | 1 | 12 | none |
| `O/org/people/services/new` | admin | 390 | ok | 1 | 7 | none |
| `O/org/people/user_lbaulnjzha_4` | member | 1440 | ok | 1 | 5 | none |
| `O/org/people/user_lbaulnjzha_4` | member | 390 | ok | 1 | 5 | none |
| `O/org/people/user_lbaulnjzha_4` | admin | 1440 | ok | 1 | 13 | none |
| `O/org/people/user_lbaulnjzha_4` | admin | 390 | ok | 1 | 10 | scrollable-region-focusable (serious, 1) |
| `O/org/people?tab=services` | member | 1440 | ok | 1 | 4 | none |
| `O/org/people?tab=services` | member | 390 | ok | 1 | 5 | none |
| `O/org/people?tab=services` | admin | 1440 | ok | 1 | 9 | none |
| `O/org/people?tab=services` | admin | 390 | ok | 1 | 5 | none |
