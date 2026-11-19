# Console API conventions

Owner: **api**. Every contract the console SPA uses is documented in this folder before or with its code.

| Doc | Covers |
| --- | --- |
| [session.md](session.md) | SPA hosting, auth, bootstrap, organization switch |
| [realtime.md](realtime.md) | `/socket/console`, `mission:<id>` channel |
| [ops.md](ops.md) | Now / Investigate reads (owner: api-ops) |
| [setup.md](setup.md) | Readiness, spacecraft, profiles, catalog, people |
| [changes.md](changes.md) | Mission change sets and configuration revisions |
| [domain.md](domain.md) | domain's facade contracts (owner: domain) |
| [commanding.md](commanding.md) | Command catalog, requests, preflight (api-ops) |
| [alarms-console.md](alarms-console.md) | Alarm episodes: list, show, ack/assign/hand-off/notes (api-ops) |
| [inventory.md](inventory.md) | What existed before the console API, and the gaps |

## Base and auth

- Base path: `/api/console/v1`. Same-origin with the SPA, served by Phoenix.
- Auth: the browser session cookie (`_cadence_web_key`), set by `/sign-in`. No bearer tokens.
- CSRF: every non-GET request sends `x-csrf-token: <token>`. Read the token from
  `<meta name="csrf-token">` in the SPA document, or from `csrf_token` in `GET /session`.
- Send `accept: application/json`. Responses are always JSON, including errors and unknown routes.

## Mission addressing

Mission-scoped endpoints live under `/api/console/v1/missions/:mission_id/...`. **There is no
organization in the URL.** The server finds the mission's organization and checks that the user
can operate it there (an active member of that organization, or a platform admin in admin mode).
So a user in several organizations can open missions from different organizations in different
tabs without switching. A mission the user cannot operate gets the same answer as a missing one:
`404 mission_not_found`.

Organization-scoped endpoints (members, invitations, service identities) will live under
`/api/console/v1/organizations/:organization_id/...` and check membership plus the matching
capability.

## Envelope

Success: `{"data": ...}`. Lists may add `"meta"`, for example `{"next_cursor": ...}`.

Error:

```json
{"error": {"code": "mission_not_found", "message": "Mission not found.", "details": {}}}
```

`code` is stable and snake_case; switch on it. `message` is for people and may change. `details`
is optional; for `invalid_params` it maps field to problem.

| Status | Codes |
| --- | --- |
| 401 | `unauthenticated`: no or expired session. Send the user to `/sign-in?return_to` (the server stores the return path for full-page GETs under `/console`) |
| 403 | `invalid_csrf`, `forbidden`, `scope_mismatch` |
| 404 | `not_found`, `mission_not_found`, `organization_not_found`, and `<thing>_not_found` |
| 422 | `invalid_params` and domain rejections (`code` names the reason) |

## Wire conventions

- IDs are opaque strings. Field names are snake_case.
- Timestamps are ISO-8601 UTC strings (`2026-11-08T02:41:17Z`). Durations are integer seconds with a
  `_s` suffix (`stale_after_s`).
- The server decides staleness (ux ruling U9). Freshness fields come with the server's
  `stale_after_s` and a computed `stale` boolean.
- Enumerations are lowercase strings. Each doc lists the full set.
- Absent optional values are `null`, never omitted.
- No invented values. When the backend doesn't know something, the field is `null`, or the
  endpoint returns an explicit `not_set_up` / `not_installed` state the UI can show.
