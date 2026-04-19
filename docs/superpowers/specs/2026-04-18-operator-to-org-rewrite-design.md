# Operator → Organization UI Rewrite

**Date:** 2026-04-18
**Status:** Design approved, plan pending

## Context

Cadence's current `cadence_web` surface has three user-facing areas:

- `/admin/*` — platform-admin organization management.
- `/operator` — a prematurely built placeholder for authenticated non-admin users.
- `/sign-in` and `/invitations/*` — auth entry.

`/operator` was built before we knew what the authenticated surface should be. The plan is to delete it and replace it with an **organization-scoped** surface that mirrors the patterns from legacy Cadence (`legacy/cadence_legacy/`): implicit-scope URLs (no `:org_id` in the path), a dedicated organization home, and mission-scoped pages behind their own layout.

The backend is already multi-tenant. `Cadence.Missions` exposes `list_missions/1`, `fetch_mission/2`, and `persist_mission/1` keyed by `organization_id`. `Cadence.Accounts.preferred_organization_membership/2` already picks a current org for a user. Nothing in the domain layer needs to change.

## Goals

1. Replace `/operator` with a dedicated organization home at `/`.
2. Introduce an organization-scoped sidebar layout with **Home** and **Missions** entries.
3. Ship mission list, view, and create pages.
4. Introduce a minimal mission sidebar layout so later per-mission pages have an established pattern to slot into.
5. Handle the edge case of an authenticated user with no active membership.

## Non-Goals

- Mission editing, deletion, or archiving.
- Authorization for mission creation (any active member can create; see TODO).
- Per-mission pages beyond Overview (spacecraft, commands, telemetry, schedules all land later).
- Subdomain-based tenancy. The implicit URL scope is chosen partly to keep this door open, but the work here is not subdomain routing.
- Org-level sections beyond Home + Missions (members, settings, service identities, notifications, reviews) — built when needed.

## Key Decisions

### URL shape: implicit org scope

Paths do not include the org slug or id. The current organization is read from `current_scope.current_organization_id` in the session. `/missions`, `/missions/:mission_id`, etc.

Reasons:

- Matches legacy Cadence's pattern.
- Keeps future subdomain-per-tenant routing (`acme.cadence.com/missions`) clean — the subdomain becomes the tenant discriminator without slug duplication in the path.
- Avoids the attack surface where a malicious actor enumerates org slugs to identify customers.

### Organization landing page

`/` is a dedicated LiveView with the organization sidebar, not a redirect to `/missions`. It gives the org its own identity and is where future org-level content (activity, recent missions, alerts) will land.

### Sidebar contents

Start with only what exists: **Home** and **Missions**. Do not stub members/settings/etc. Grow the sidebar as each section is built.

### Mission show uses a separate layout

`/missions/:mission_id` renders under a new `:mission_sidebar` layout, even though the mission sidebar itself is minimal for now (just "Overview"). This establishes the layout split now so it is trivial to extend when per-mission pages arrive.

### Mission create authorization

Any active organization member can create a mission. A `TODO(authz)` comment in `MissionNewLive` marks this as a gap to close when platform authorization policy is defined.

### Slug handling on create

The form has `display_name` and `slug`. Slug auto-derives from `display_name` until the user edits the slug field, at which point auto-derivation stops. Both fields are submitted and validated by `Cadence.Missions.Mission.new/1`.

### `/operator` is deleted outright

No redirect. No backwards-compat shim. The controllers, HEEx templates, and router entries are removed. `AuthenticatedEntry` is simplified.

### No-membership error page

Authenticated users with no active organization membership are redirected to `/no-organization`, which renders a static "ask an administrator for an invitation" page under the narrow-centered `:auth` layout. Reached via the `OrganizationAuth.require_organization_scope` on_mount hook when `Cadence.Accounts.preferred_organization_membership/2` returns `nil`.

## Architecture

### Routing

`CadenceWeb.Router` gains two new live sessions inside the `:require_authenticated_scope` pipeline; `/operator`, `OperatorEntryController`, and `OperatorHomeController` are removed.

```elixir
scope "/", CadenceWeb do
  pipe_through [:browser, :require_authenticated_scope]

  delete "/session", UserSessionController, :delete

  live_session :organization,
    on_mount: [{CadenceWeb.OrganizationAuth, :require_organization_scope}],
    layout: {CadenceWeb.Layouts, :sidebar} do
    live "/",             OrganizationHomeLive, :show
    live "/missions",     MissionListLive,      :index
    live "/missions/new", MissionNewLive,       :new
  end

  live_session :mission,
    on_mount: [
      {CadenceWeb.OrganizationAuth, :require_organization_scope},
      {CadenceWeb.MissionAuth, :load_mission}
    ],
    layout: {CadenceWeb.Layouts, :mission_sidebar} do
    live "/missions/:mission_id", MissionShowLive, :show
  end

  live_session :admin,
    on_mount: [{CadenceWeb.AdminAuth, :require_platform_admin}],
    layout: {CadenceWeb.Layouts, :sidebar} do
    # (unchanged — existing admin routes)
  end
end

scope "/", CadenceWeb do
  pipe_through [:browser, :require_authenticated_scope]

  get "/no-organization", NoOrganizationController, :show
end
```

`AuthenticatedEntry.entry_path/1` becomes:

- Platform admin → `/admin`
- Otherwise → `/`

The no-membership branch is handled downstream by the `:organization` live session's on_mount, not by `entry_path/1`. This keeps `entry_path/1` pure (no DB access) and routes all no-membership handling through one place.

### on_mount hooks

**`CadenceWeb.OrganizationAuth.require_organization_scope/3`** (new module).

- Reads `socket.assigns.current_scope`.
- Calls `Cadence.Accounts.preferred_organization_membership(user_id, current_organization_id)`.
- If an active membership exists: fetches the `%Organization{}`, assigns `:current_organization` and `:current_membership` on the socket, and reassigns `:current_scope` with `current_organization_id` populated when it was `nil`. Returns `{:cont, socket}`.
- If not: `{:halt, redirect(socket, to: "/no-organization")}`.

**`CadenceWeb.MissionAuth.load_mission/3`** (new module).

- Reads `mission_id` from params and `organization_id` from the scope.
- Calls `Cadence.Missions.fetch_mission(organization_id, mission_id)`.
- On `{:ok, mission}`: assigns `:current_mission`, returns `{:cont, socket}`.
- On `{:error, :not_found}`: `raise Phoenix.Router.NoRouteError` so Phoenix renders a 404 (matches existing codebase behavior for missing resources).

### Layouts

**`CadenceWeb.Layouts.sidebar/1` (existing)** — extended to handle `@nav_context = :organization`.

The existing template branches on `@nav_context` to render `:admin` vs `:operator` sections. Actions:

- Add an `:organization` branch that renders:
  - Header: org `display_name`, muted slug underneath.
  - Nav items:
    - **Home** (`nav_item = :organization_home`) → `/`
    - **Missions** (`nav_item = :missions`) → `/missions`
  - Footer: user email + sign-out link (same markup as admin sidebar).
- Remove the `:operator` branch. No operator navigation remains.

**`CadenceWeb.Layouts.mission_sidebar/1` (new template)** — added to the existing `CadenceWeb.Layouts` module (not a new module), mirroring how `sidebar` and `auth` already coexist there.

- Back link: `← <org display_name>` → `/`.
- Header: mission `display_name`, muted slug underneath.
- Nav items:
  - **Overview** (`nav_item = :mission_overview`) → `/missions/:mission_id`
- Footer: user email + sign-out link.

Both layouts compose existing daisyUI + HUD utility classes (`hud-label`, `hover-glow-cyan`, etc.). No new CSS rules — per CLAUDE.md UI discipline, the CSS set is frozen.

### LiveViews & controller

**`CadenceWeb.OrganizationHomeLive`** — `/`

- `mount/3` assigns `page_title`, `nav_context: :organization`, `nav_item: :organization_home`, and `mission_count` via `Cadence.Missions.list_missions(org_id) |> length/1`.
- Render: page header with org display_name and muted slug; one `card bg-base-200` titled "Missions" showing the mission count and a `btn btn-primary` "View Missions" → `/missions`.
- No "Coming Soon" cards.

**`CadenceWeb.MissionListLive`** — `/missions`

- `mount/3` assigns `nav_context: :organization`, `nav_item: :missions`, and `missions` via `Cadence.Missions.list_missions/1`.
- Render: page header "Missions" with a `btn btn-primary` "New Mission" → `/missions/new` on the right.
- If `missions == []`: empty-state card with "No missions yet" copy and a secondary CTA.
- Else: daisyUI `table` with columns **Mission Name**, **Slug**, **Actions**. The actions cell uses `<.action_menu>` (per CLAUDE.md rule 6) with one item: "View" → `/missions/:mission_id`.

**`CadenceWeb.MissionNewLive`** — `/missions/new`

- `mount/3` assigns `nav_context: :organization`, `nav_item: :missions`, a blank changeset-like form map (`display_name: "", slug: "", slug_auto: true`), and the org's display_name for context.
- `handle_event("validate", %{"mission" => params}, socket)`:
  - If `slug_auto` is true and `display_name` changed: regenerate slug from display_name (lowercase, non-alnum → `-`, collapsed).
  - If the user has typed into the slug field directly: set `slug_auto` to false and preserve their input.
- `handle_event("save", %{"mission" => params}, socket)`:
  - Build `%Mission{}` via `Cadence.Missions.Mission.new/1` with `organization_id` from the scope.
  - Call `Cadence.Missions.persist_mission/1`.
  - On success: `push_navigate` to `/missions/:mission_id`.
  - On error: assign the changeset back to the form and re-render.
- `<.simple_form>` with two `<.input>` fields (display_name, slug). Submit button + cancel link to `/missions`.
- Module-level comment:

  ```elixir
  # TODO(authz): Any active organization member can create a mission. This gate
  # should tighten once platform-wide authorization is defined (likely to
  # :organization_admin role, possibly a finer capability).
  ```

**`CadenceWeb.MissionShowLive`** — `/missions/:mission_id`

- `mount/3` assigns `nav_context: :mission`, `nav_item: :mission_overview`. `current_mission` comes from the on_mount hook.
- Render: main content is a single "Overview" card listing mission_id, display_name, slug. No spacecraft, no telemetry. Uses the mission_sidebar layout so the mission name + back link live in the sidebar.

**`CadenceWeb.NoOrganizationController`** — `/no-organization`

- Plain controller with `show/2` rendering `NoOrganizationHTML.show/1`.
- Uses the `:auth` layout (narrow centered, same as `/sign-in`).
- Content: headline + message ("You don't have access to any organization yet. Ask an administrator for an invitation.") + sign-out link.

### Files changed / added

**Added:**

- `apps/cadence_web/lib/cadence_web/organization_auth.ex`
- `apps/cadence_web/lib/cadence_web/mission_auth.ex`
- `apps/cadence_web/lib/cadence_web/live/organization_home_live.ex`
- `apps/cadence_web/lib/cadence_web/live/mission_list_live.ex`
- `apps/cadence_web/lib/cadence_web/live/mission_new_live.ex`
- `apps/cadence_web/lib/cadence_web/live/mission_show_live.ex`
- `apps/cadence_web/lib/cadence_web/controllers/no_organization_controller.ex`
- `apps/cadence_web/lib/cadence_web/controllers/no_organization_html.ex`
- `apps/cadence_web/lib/cadence_web/controllers/no_organization_html/show.html.heex`
- Test files mirroring each of the above under `apps/cadence_web/test/`.

**Modified:**

- `apps/cadence_web/lib/cadence_web/router.ex` — remove `/operator` and `/`, add new live sessions and no-organization route.
- `apps/cadence_web/lib/cadence_web/authenticated_entry.ex` — drop `/operator` case; non-admins → `/`.
- `apps/cadence_web/lib/cadence_web/components/layouts/sidebar.html.heex` — add `:organization` branch, remove `:operator` branch.

**Added (layout templates):**

- `apps/cadence_web/lib/cadence_web/components/layouts/mission_sidebar.html.heex` — auto-wired by the existing `embed_templates "layouts/*"` in `CadenceWeb.Layouts`.

**Deleted:**

- `apps/cadence_web/lib/cadence_web/controllers/operator_entry_controller.ex`
- `apps/cadence_web/lib/cadence_web/controllers/operator_home_controller.ex`
- `apps/cadence_web/lib/cadence_web/controllers/operator_home_html.ex`
- `apps/cadence_web/lib/cadence_web/controllers/operator_home_html/` (directory and all templates)
- Any associated test files.

## Data Flow (illustrative)

### Login → org home

1. User POSTs to `/sign-in`.
2. `UserSessionController.create/2` authenticates, puts scope in session, redirects via `AuthenticatedEntry.redirect_path/2`.
3. Non-admin → `/`.
4. `OrganizationHomeLive.mount/3` runs through `:organization` live session on_mounts:
   - `fetch_browser_current_scope` (pipeline) loads the scope.
   - `OrganizationAuth.require_organization_scope` loads the preferred active membership and organization, assigning them to the socket.
5. LiveView renders the org home.

### Create mission

1. User at `/missions` clicks "New Mission" → `/missions/new`.
2. `MissionNewLive` renders the form. User types a display name; slug auto-fills.
3. User submits. `handle_event("save", ...)` builds a `%Mission{}` with `organization_id` from scope and calls `Cadence.Missions.persist_mission/1`.
4. On success: `push_navigate(socket, to: ~p"/missions/#{mission.mission_id}")`.
5. `MissionShowLive.mount/3` runs through `:mission` live session on_mounts (org scope + `MissionAuth.load_mission`), renders overview.

### No-membership user

1. User with no active membership signs in, `AuthenticatedEntry.entry_path/1` returns `/`.
2. `OrganizationHomeLive.mount/3` triggers `OrganizationAuth.require_organization_scope` on_mount.
3. `Cadence.Accounts.preferred_organization_membership/2` returns `nil`.
4. On_mount redirects to `/no-organization`.
5. `NoOrganizationController` renders the error page under the `:auth` layout.

## Error Handling

- **No active membership** → `/no-organization` (see above).
- **Missing mission** (`/missions/:mission_id` with bad id, or an id belonging to another org) → `MissionAuth.load_mission` raises `Phoenix.Router.NoRouteError` → Phoenix 404.
- **Mission create validation failure** → form re-renders with errors inline via `<.input>`'s built-in error display.
- **Persistence error** (e.g., unique slug conflict) → `persist_mission/1` returns `{:error, changeset}`, form re-renders with errors.

## Testing

Per-app, matching project convention (`cd apps/cadence_web && mix test`).

**`apps/cadence_web/test/cadence_web/`:**

- `authenticated_entry_test.exs` — update: platform admin → `/admin`, else → `/`. Remove `/operator` expectations.
- `organization_auth_test.exs` (new) — on_mount behavior: active membership assigns scope; no membership halts + redirects to `/no-organization`.
- `mission_auth_test.exs` (new) — on_mount behavior: valid mission assigned; mismatched org or missing id raises.

**`apps/cadence_web/test/cadence_web/live/`:**

- `organization_home_live_test.exs` — mount success, org name rendered, mission count reflects fixtures, "View Missions" link present.
- `mission_list_live_test.exs` — empty state, populated table, "New Mission" link, action_menu "View" link.
- `mission_new_live_test.exs` — render form, auto-slug behavior via `phx-change`, successful submit creates mission and redirects, validation error re-renders form.
- `mission_show_live_test.exs` — renders mission fields, 404 on bad id.

**`apps/cadence_web/test/cadence_web/controllers/`:**

- `no_organization_controller_test.exs` (new) — renders for authenticated user, contains sign-out link.
- Delete `operator_entry_controller_test.exs` and `operator_home_controller_test.exs` if present.

**Domain tests** — none. `Cadence.Missions` and `Cadence.Accounts` are unchanged.

**Gates (every commit):**

- `mix compile --warnings-as-errors`
- `mix format` on touched Elixir files
- `mix credo --strict` — no new violations
- Per-app `mix test` passes

## Open Questions

None blocking. Items deferred by explicit decision:

- Authorization tightening for mission create (tracked via `TODO(authz)` comment).
- Org-level sections beyond Home + Missions (members, settings, service identities, notifications, reviews).
- Per-mission sections beyond Overview (spacecraft, commands, telemetry, schedules).
- Mission edit and delete.
- Subdomain-based multi-tenancy.
