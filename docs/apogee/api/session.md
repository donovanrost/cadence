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

## `GET /api/v1/session`

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
    "socket": {"path": "/socket/console"},
    "pending_invitations_count": 1
  }
}
```

- `pending_invitations_count` (L21): how many pending, unexpired invitations are addressed to the
  user's current email (the org switcher footer's "1 invitation", `/no-organization`). Details
  come from `GET /account/invitations`.

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

## Admin mode (L6, api-ops)

- `GET /session` carries `admin_mode_expires_at`: ISO time admin mode ends, or `null` when it's
  off. It drives the 'ADMIN MODE · 52:10' chip.
- `POST /api/v1/session/admin-mode {password}` → `200 {expires_at}`: enters admin mode for
  one hour (the server's TTL). Entering while on starts a fresh hour. The password is checked
  through the attempt limit, like sign-in (§Attempt limit). Errors:
  - `422 password_incorrect` ("That password isn't right.");
  - `429 too_many_attempts` with `details.retry_after` and a `Retry-After` header;
  - `403 forbidden` for someone who isn't an eligible platform admin, before any password check;
  - `422 invalid_params` (`details.password`) when the password is missing.
- `DELETE /api/v1/session/admin-mode` → `204`. Leaves admin mode; idempotent.
- Both need `x-csrf-token`. After either one, refetch `GET /session`: capabilities and
  organizations change with admin mode.

## `PUT /api/v1/session/organization`

Sets the session's default organization (the org switcher). Body `{"organization_id": "org_…"}` or
`{"organization_slug": "reflect-orbital"}` (the shell uses the slug for an org in the URL it doesn't
know yet). A platform admin in admin mode can select **any** organization, after which it appears
in `organizations` with `role: null` and admin capabilities. Everyone else can select only their
memberships.
Requires `x-csrf-token`. Returns the same payload as `GET /session`, rebuilt for the new
organization.

Errors: `403 invalid_csrf`, `404 organization_not_found` (not a member and not in admin mode),
`422 invalid_params` (missing `organization_id`).

## `GET /api/v1/missions/:mission_id`

```json
{"data": {"id": "mission_…", "slug": "earendil", "name": "Earendil",
          "organization": {"id": "org_…", "slug": "reflect-orbital", "name": "Reflect Orbital"}}}
```

Errors: `404 mission_not_found`.

## Sign-out

`DELETE /session` (the existing browser route) also broadcasts `disconnect` to that session's
console sockets. After it, the next API call returns `401` and the SPA should redirect to
`/sign-in`.

## Account: my invitations (§11 L21)

The signed-in user's own pending invitations. People who aren't signed in accept through the
emailed link (`/invitations/:token`, server-rendered; api-ops' L5 token path).

- `GET /api/v1/account/invitations` → `{invitations: [{id, organization {id, slug,
  name}, role, invited_by {name} | null, invited_at, expires_at}]}`, oldest first. Only pending,
  unexpired invitations addressed to my current email (the same rule as
  `pending_invitations_count`).
- `POST /api/v1/account/invitations/:id/accept` → `{organization {id, slug, name}, role}`.
  The membership exists at once. The session is a boot snapshot, so open the new organization
  with a full navigation (re-bootstrap).
- `POST /api/v1/account/invitations/:id/decline` → `{id, status: "declined"}`. Final; the
  inviter's People list shows it as declined.
- Errors: `404 invitation_not_found` for an unknown id **or** one addressed to someone else (the
  same answer, so ids don't leak); `409 invitation_not_pending` with `details.status` `accepted |
  revoked | declined | expired` when it was already answered or has lapsed.

## Account: password and sessions (backlog)

The signed-in user's own account, under `/api/v1/account` (no organization or mission).

- `PUT /account/password {current_password, new_password}` → `204`. The new password needs at
  least 12 characters and must differ from the current one. Every **other** session of the user is
  signed out; this one stays signed in. Errors: `422 current_password_incorrect`, `422
  invalid_params` (`details.new_password`), `409 password_managed_externally` (the environment
  admin's password comes from the environment), `429 too_many_attempts` (below).
- `GET /account/sessions` → `{sessions: [{id, started_at, expires_at, current}]}`: the user's
  unexpired sessions, newest first; `current` marks the one making the request. Sessions record no
  device or address.
- `DELETE /account/sessions/:id` → `204`: signs that session out. Revoking the current one signs
  you out here too (the session cookie is dropped). Errors: `404 session_not_found`.
- `DELETE /account/sessions` → `{revoked: n}`: signs out every session except the current one.

### Attempt limit (api-ops)

Every password check (sign-in, the current password here, admin mode) is throttled
(`Cadence.Accounts.AttemptLimit`). There's no lockout, only waits:

- Failures count per account from one address (5 free), per account from anywhere (20 free) and
  per address (50 free). Past its free failures, a bucket makes the next check wait 1 s,
  doubling per failure up to **5 min**. A check that has to wait doesn't count, so waiting always
  works. A bucket forgets its failures 15 min after the last one, and a right password clears
  the account's buckets.
- The account bucket is keyed by email whether or not an account has it, so a wait never says
  whether the account exists. An unknown email also takes as long as a wrong password.
- Here: `429 too_many_attempts` with `details.retry_after` (seconds, an integer ≥ 1) and a
  `Retry-After` header. The password wasn't checked, so even the right one gets the 429 until
  the wait is over. Suggested words: "Too many wrong passwords. Try again in N seconds."
- `/sign-in` and admin mode are server-rendered forms: they redirect back with the flash "Too
  many wrong passwords. Try again in N seconds" (or "N minutes") and a `Retry-After` header.
- **Unlock:** waits are capped, so anyone, the environment admin included, gets in after at
  most 5 min. To let someone in sooner, an operator runs
  `Cadence.Accounts.AttemptLimit.clear("person@example.com")` on the node's remote console. A
  restart also forgets everything (the counts are in memory, per node).
- Addresses are `conn.remote_ip`. Behind a proxy that doesn't pass the client address on, every
  client shares one address bucket. Deploy with the client address forwarded.

### Audit

Each change is an organization audit entry (`kind: "account"`, setup.md §AU1), recorded in the
same transaction: "Changed their password" (with "and signed out N other sessions" when it
did), "Signed out one of their other sessions", "Signed out of the session they were using",
"Signed out N other sessions" (`DELETE /account/sessions`, only when N > 0). The actor is the
member and `target` is `null`. Entries hold ids and counts, never a password, token or digest.
They show in every organization the person is or was a member of.

## Sign-in and invitation links (L5, api-ops)

The SPA serves the auth screens itself: `GET /console/sign-in`, `/console/invitations/:token` and
`/console/no-organization` return the SPA document **without** a console session, with the
`csrf-token` meta. The JSON lives under `/api/v1/auth`. It works signed out, but every
write still needs `x-csrf-token` from that meta. After a successful sign-in or accept the session
is renewed (against fixation), so the CSRF token changes: refetch `GET /session`.

- `POST /auth/sign-in {email, password, return_to?}` → `200 {redirect_to}` and the session
  cookie. `redirect_to` is `return_to` when it's a same-origin relative path (not `//…`, no
  scheme or host, not an auth page), else the target stored when `/console` bounced the browser,
  else `/console`. Errors:
  - `422 credentials_incorrect` for any wrong pair, unknown email or disabled account. It never
    says which.
  - `429 too_many_attempts {retry_after}`.
  - `422 invalid_params`.
- `GET /auth/invitations/:token` → `{case, organization: {name} | null, role | null, invited_by:
  {name} | null, invited_at | null, email | null, expires_at | null}`.
  - `case`: `new_account`, `existing_account` (signed out, by whether the invited email has an
    account), `signed_in_match`, `signed_in_other`, `expired`, `withdrawn`, `used`, `declined`
    or `unknown`. Decode it with `known()`.
  - `email` is set only for the four open cases. `unknown` has every field `null`.
  - Account existence is told only to a valid token's holder, never by email lookup.
- `POST /auth/invitations/:token/accept {kind, …}` → `200 {organization_id, redirect_to:
  "/console"}`, plus a session when signed out.
  - `kind`: `new_account {name, password}` (12+ characters), `existing_account {password}` (the
    account's current password, through the attempt limit; the account is never changed) or
    `signed_in_match {}`. The server works out the case itself. When `kind` differs from it:
    `409 invitation_case_changed {case}`; refetch.
  - Errors: `422 credentials_incorrect`, `429 too_many_attempts {retry_after}`, `403
    account_disabled` (only after a right password), `422 invalid_params` (`details.name`,
    `details.password`), `409 invitation_unavailable {case: expired | withdrawn | used | declined
    | unavailable}`, `409 invitation_for_another_account`, `404 invitation_not_found`.
- `POST /auth/invitations/:token/decline` → `204`, signed in as the addressee only. It uses
  `Accounts.decline_invitation_as_user` (L21), so the status becomes `declined`. Signed out:
  `401 unauthenticated`. Someone else: `409 invitation_for_another_account`.
