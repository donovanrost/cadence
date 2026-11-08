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
  (`CONSOLE_VITE_ORIGIN`, default `http://127.0.0.1:5180`) and rewrites root-relative
  `src="/console/..."` and `href="/console/..."` URLs to absolute dev-server URLs. Phoenix stays
  the page origin, so cookies, CSRF and the websocket are same-origin. Vite needs
  `base: '/console/'`, `server.port: 5180`, `strictPort`, `server.origin: 'http://127.0.0.1:5180'`
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
    "capabilities": ["organization_admin"],
    "organizations": [
      {
        "id": "org_…", "slug": "reflect-orbital", "name": "Reflect Orbital",
        "role": "organization_admin",
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
- `capabilities`: capabilities effective in the **current** organization: user capabilities
  (`platform_admin` only while in admin mode) plus membership capabilities
  (`organization_admin`). Gate UI on these (director decision 2). Every endpoint still enforces
  authorization on the server.
- `current_organization_id`: the session's default organization, used for org-level pages when
  the URL has no mission. It may be `null` for a user with no memberships.

Errors: `401 unauthenticated`.

## `PUT /api/console/v1/session/organization`

Sets the session's default organization (the org switcher). Body `{"organization_id": "org_…"}`.
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
