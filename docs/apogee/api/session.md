# Session, hosting and bootstrap

Status: **implemented** (`CadenceWeb.Console.*`, tests in `apps/cadence_web/test/cadence_web/console/`).

## SPA document: `GET /console` and `GET /console/*path`

- Router: `scope "/console"` uses `[:browser, :require_authenticated_scope]`.
- Without a session the server answers `302 /sign-in` and stores the requested path plus query as
  the post-sign-in return target, so deep links survive sign-in.
- With a session it returns the SPA `index.html` with
  `<meta name="csrf-token" content="...">` injected just before `</head>`, plus
  `cache-control: no-store`.
- Hashed bundles are served statically at `/console/assets/*`
  (`cache-control: public, max-age=31536000, immutable`).
- **Built mode** (prod and test): reads `apps/cadence_web/priv/static/console/index.html`, the
  output of `vite build` (gitignored). If it is missing, the answer is `503` with a plain-text hint.
- **Dev mode** (`config/dev.exs`): Phoenix fetches `index.html` from the console Vite dev server
  (`CONSOLE_VITE_ORIGIN`, default `http://127.0.0.1:5181`) and rewrites root-relative
  `src="/console/..."` and `href="/console/..."` URLs to absolute dev-server URLs. Phoenix stays
  the page origin, so cookies, CSRF and the websocket are same-origin. Vite needs
  `base: '/console/'`, `server.port: 5181`, `strictPort`, `server.origin: 'http://127.0.0.1:5181'`
  and `cors: true`. Set `CONSOLE_VITE_ORIGIN=""` to serve the built output in dev.

## `GET /api/console/v1/session`

The bootstrap payload.

```json
{
  "data": {
    "user": {"id": "user_…", "email": "mira@example.com", "display_name": "Mira K."},
    "current_organization_id": "org_…",
    "admin_mode": false,
    "platform_admin_eligible": false,
    "capabilities": ["command.abort", "command.approve", "command.request", "org.invite",
                     "org.manage_members", "organization_admin"],
    "organizations": [
      {
        "id": "org_…", "slug": "reflect-orbital", "name": "Reflect Orbital",
        "role": "organization_admin",
        "capabilities": ["command.abort", "command.approve", "command.request", "org.invite",
                         "org.manage_members", "organization_admin"],
        "missions": [{"id": "mission_…", "slug": "earendil", "name": "Earendil"}]
      }
    ],
    "csrf_token": "…",
    "socket": {"path": "/socket/console"}
  }
}
```

- `organizations`: the user's active memberships, sorted by name. A platform admin in admin mode
  also sees the current organization even without a membership (`role` is then `null`).
  `missions` holds every mission in that organization; members can operate all of them.
- `role`: `organization_admin`, `member` or `null`.
- `organizations[].capabilities`: capabilities effective in **that** organization, sorted. Each is
  derived by calling the policy function that enforces it for that organization's scope
  (DECISIONS #38), so the list and enforcement agree (tested per role):
  - scope capabilities: `platform_admin` (only in admin mode), `organization_admin` (membership);
  - `command.request`, `command.approve`, `command.abort`: the command review policy, which
    request authoring, review and group abort/cancel all enforce today (organization admins, and
    platform admins in admin mode). These are the same names as the People read;
  - `org.invite`, `org.manage_members`: `:manage_organization_members`.

  Since the console scopes the organization by URL, gate UI on the capabilities of the organization
  that owns the mission on screen.
- `capabilities` (top level): the same list for `current_organization_id`. Every endpoint still
  enforces authorization on the server.
- `current_organization_id`: the session's default organization, used for org-level pages when
  the URL has no mission. It may be `null` for a user with no memberships.

Errors: `401 unauthenticated`.

## `PUT /api/console/v1/session/organization`

Sets the session's default organization (the org switcher). Body `{"organization_id": "org_…"}` or
`{"organization_slug": "reflect-orbital"}` (the shell uses the slug for an org in the URL it doesn't
know yet). A platform admin in admin mode can select **any** organization, after which it appears
in `organizations` with `role: null` and admin capabilities. Everyone else can select only their
memberships.
Requires `x-csrf-token`. Returns the same payload as `GET /session`, rebuilt for the new
organization.

Errors: `403 invalid_csrf`, `404 organization_not_found` (not a member and not in admin mode),
`422 invalid_params` (missing `organization_id`).

## `GET /api/console/v1/missions/:mission_id`

```json
{"data": {"id": "mission_…", "slug": "earendil", "name": "Earendil",
          "organization": {"id": "org_…", "slug": "reflect-orbital", "name": "Reflect Orbital"}}}
```

Errors: `404 mission_not_found`.

## Sign-out

`DELETE /session` (the existing browser route) also broadcasts `disconnect` to that session's
console sockets. After it, the next API call returns `401` and the SPA should redirect to
`/sign-in`.
