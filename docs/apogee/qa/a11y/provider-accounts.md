# provider-accounts: accessibility (§6)

Owner: fe-setup. Run 2, 2026-11-13 07:55-08:47Z (method: [README](README.md)).

## Findings

- **fe-setup:** on the provider account page, the "Audit log" link inside the text differs from the text only by colour (axe `link-in-text-block`, serious). Underline it like the other in-text links.
- **Member gating (fe-setup):** a member who opens Provider accounts by URL gets a 403 and "You do not have permission to do that." with **Retry**. Say "Org admins see this" with no Retry (Retry can never succeed), and don't offer the route to members.

## Runs

| Route | Role | Width | Load | h1 | Tab stops | axe |
| --- | --- | ---: | --- | ---: | ---: | --- |
| `O/org/provider-accounts` | member | 1440 | ok | 1 | 3 | none |
| `O/org/provider-accounts` | member | 390 | ok | 1 | 3 | none |
| `O/org/provider-accounts` | admin | 1440 | ok | 1 | 9 | none |
| `O/org/provider-accounts` | admin | 390 | ok | 1 | 4 | none |
| `O/org/provider-accounts/account-earendil-demo` | member | 1440 | ok | 1 | 3 | none |
| `O/org/provider-accounts/account-earendil-demo` | member | 390 | ok | 1 | 3 | none |
| `O/org/provider-accounts/account-earendil-demo` | admin | 1440 | ok | 1 | 15 | link-in-text-block (serious, 1) |
| `O/org/provider-accounts/account-earendil-demo` | admin | 390 | ok | 1 | 11 | link-in-text-block (serious, 1) |
