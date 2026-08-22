# Spacecraft CRUD (basic pass) — Design

**Date:** 2026-04-19
**Status:** Approved for planning
**Scope:** List + New + Show LiveViews for mission-owned spacecraft. No update, no delete, no slug, no metadata editor. Backend domain model, persistence store, migration, and REST API controllers for spacecraft already exist; this spec covers the web UI and the facade plumbing that exposes the store to LiveViews.

## Goals

- Give operators a browser surface for registering spacecraft under a mission and viewing them.
- Mirror the Missions LiveView patterns exactly so conventions stay consistent and future work is obvious.
- Make zero changes to the existing `Cadence.Spacecraft` domain model, `Cadence.SpacecraftStore`, Ecto schema, or migrations.

## Non-goals (explicit)

- No update or delete operations in the store, facade, or UI. Delete has runtime-lifecycle implications the project isn't ready to address.
- No `slug` field on spacecraft; URLs and lookups use the generated `spacecraft_id`.
- No metadata editor. Read-only render only, and only when metadata is non-empty.
- No pagination, search, or sorting controls on the list view. Missions has none yet; defer until a mission carries many spacecraft.
- No tightening of the authorization model. Spacecraft carries forward the same loose "any active organization member" policy and `TODO(authz)` comment that `MissionNewLive` uses today.

## Architecture

Layering matches Missions one-for-one.

### Data layer (`apps/cadence`)

- `Cadence.Spacecraft` — unchanged.
- `Cadence.SpacecraftStore` — unchanged. Existing functions used: `persist_spacecraft/2`, `fetch_spacecraft/3`, `list_spacecraft/2`.
- `Cadence` facade (`apps/cadence/lib/cadence.ex`) — add three delegating functions so the web layer calls `Cadence.*` and not the store directly:
  - `persist_spacecraft(organization_id, %Spacecraft{})`
  - `fetch_spacecraft(organization_id, mission_id, spacecraft_id)`
  - `list_spacecraft(organization_id, mission_id)`

### Web layer (`apps/cadence_web`)

Three LiveViews, one auth hook, router additions, and one sidebar template update.

- `CadenceWeb.SpacecraftListLive` — list view.
- `CadenceWeb.SpacecraftNewLive` — create form. Carries the same `TODO(authz)` banner comment as `MissionNewLive`.
- `CadenceWeb.SpacecraftShowLive` — detail view.
- `CadenceWeb.SpacecraftAuth` — `on_mount(:load_spacecraft, ...)` hook. Calls `Cadence.fetch_spacecraft(org_id, mission_id, spacecraft_id)` using the scope and the route params; on error redirects to the mission's spacecraft list with a flash. Matches the shape of `CadenceWeb.MissionAuth`.

All three LiveViews render inside the existing `CadenceWeb.Layouts.mission_sidebar` layout and set `@nav_item = :spacecraft` so the sidebar entry stays highlighted throughout the flow.

## Routes

Added to `CadenceWeb.Router` inside the authenticated user scope, after the mission routes:

```elixir
live_session :spacecraft,
  on_mount: [
    {CadenceWeb.OrganizationAuth, :require_organization_scope},
    {CadenceWeb.MissionAuth, :load_mission},
    {CadenceWeb.UserAuth, :attach_user_menu}
  ],
  layout: {CadenceWeb.Layouts, :mission_sidebar} do
  live "/missions/:mission_id/spacecraft", SpacecraftListLive, :index
  live "/missions/:mission_id/spacecraft/new", SpacecraftNewLive, :new
end

live_session :spacecraft_show,
  on_mount: [
    {CadenceWeb.OrganizationAuth, :require_organization_scope},
    {CadenceWeb.MissionAuth, :load_mission},
    {CadenceWeb.SpacecraftAuth, :load_spacecraft},
    {CadenceWeb.UserAuth, :attach_user_menu}
  ],
  layout: {CadenceWeb.Layouts, :mission_sidebar} do
  live "/missions/:mission_id/spacecraft/:spacecraft_id", SpacecraftShowLive, :show
end
```

Two sessions are needed because only `:show` requires `SpacecraftAuth` to pre-load `@current_spacecraft`. This mirrors the split between `:organization` and `:mission` in the existing router.

URL summary:
- `GET /missions/:mission_id/spacecraft` — list
- `GET /missions/:mission_id/spacecraft/new` — create form
- `GET /missions/:mission_id/spacecraft/:spacecraft_id` — detail

## Sidebar navigation

`apps/cadence_web/lib/cadence_web/components/layouts/mission_sidebar.html.heex` gains a second `<li>` beneath the existing "Overview" entry:

- Icon: `hero-rocket-launch`.
- Label: "Spacecraft".
- Navigate target: `~p"/missions/#{@current_mission.mission_id}/spacecraft"`.
- Active when `@nav_item == :spacecraft`.

The existing Overview entry, styling classes, and highlight logic remain untouched; the new entry reuses the same class list pattern.

## LiveView detail

All three LiveViews use `<.input>`, `<.action_menu>`, `.empty_state`, `.detail_row`, daisyUI cards, and HUD utility classes (`hud-label`, `hover-glow-cyan`, `hud-grid`). No new CSS. Render functions stay under the 50-line cap; any drift is extracted into a private function component.

### `SpacecraftListLive`

- **Mount:** reads `current_scope.organization_id` and `current_mission.mission_id`, calls `Cadence.list_spacecraft(org_id, mission_id)`, assigns `@page_title`, `@nav_item = :spacecraft`, and `@spacecraft`.
- **Header:** back link `← {mission.display_name}`, page title "Spacecraft", right-aligned `+ New Spacecraft` link navigating to `.../spacecraft/new`.
- **Empty state:** `.empty_state` component — icon `hero-rocket-launch`, title "No spacecraft yet", description "Register the first spacecraft for this mission.", action link pointing at the new page.
- **Populated state:** a daisyUI `table table-sm` inside a `card bg-base-200`. Columns:
  1. **Name** — `display_name`.
  2. **Spacecraft ID** — monospaced, `text-base-content/60`.
  3. **Actions** — `<.action_menu>` with a single "View" entry that navigates to the show page.
- No per-row click target beyond the action menu (accessible, matches the user-menu hover feedback preference).

### `SpacecraftNewLive`

- **Mount:** assigns `@page_title = "New Spacecraft"`, `@nav_item = :spacecraft`, and `@form` (bare form with a single `display_name` field).
- **Carries** the same `TODO(authz)` module comment as `MissionNewLive`.
- **Render:** `<.link navigate={~p"/missions/#{mission.mission_id}/spacecraft"}>← Spacecraft</.link>`, heading, and a `<.form for={@form} phx-change="validate" phx-submit="save">` with:
  - `<.input field={@form[:display_name]} type="text" label="Display Name" required />`
  - Submit button "Create Spacecraft" and cancel link back to the list.
- **`validate`:** no-op that just echoes the input back into `@form`. Wired up to keep the form template shape identical to Missions' for consistency and easy future extension.
- **`save`:**
  1. `normalize(display_name)` (trim; empty → `nil`).
  2. If `nil`: `put_flash(:error, "Display name is required.")` and stay.
  3. Otherwise build `Cadence.Spacecraft.new(%{mission_id: mission.mission_id, display_name: display_name})`.
  4. Call `Cadence.persist_spacecraft(org_id, spacecraft)`.
  5. Success → `push_navigate` to the show page.
  6. Changeset error → `put_flash(:error, format_errors(changeset))`. Duplicate the small `format_errors/1` helper from `mission_new_live.ex`; don't extract a shared module for two callers.
  7. `{:error, :mission_not_found}` → `put_flash(:error, "Mission not found.")` + `push_navigate` to `/missions`.
  8. `{:error, {:organization_mission_mismatch, _, _, _}}` → `put_flash(:error, "Could not create spacecraft.")` (defense-in-depth; shouldn't be reachable via UI).

### `SpacecraftShowLive`

- **Mount:** assigns `@page_title = current_spacecraft.display_name` and `@nav_item = :spacecraft`. `@current_spacecraft` is already on the socket from the auth hook.
- **Render:**
  - Back link `← Spacecraft` to the list page.
  - Title `current_spacecraft.display_name`.
  - `.detail_row` entries for Display Name, Spacecraft ID (mono), Mission (a link to the mission show page), Organization ID (muted).
  - Metadata: a collapsed `<details>` block rendering a `<pre>` JSON dump **only** when `metadata != %{}`.

## Error handling

Covered inline in the LiveView detail. Key cross-cutting behaviors:

- **Fetch miss, wrong org, or wrong mission** — `SpacecraftAuth` redirects to the mission's spacecraft list with a `"Spacecraft not found."` flash. Because the fetch is scoped by the `(organization_id, mission_id, spacecraft_id)` tuple, cross-mission and cross-org URL tampering collapse to the same not-found path with no information leakage.
- **Mission miss in the URL (for list/new)** — handled by the existing `MissionAuth` hook exactly as it is for mission show today.
- **Unauthenticated access** — handled by `OrganizationAuth` / `UserAuth` exactly as for missions today (redirect to `/sign-in`).

## Testing

Tests mirror the Missions test suite structure. All files live in `apps/cadence_web/test/cadence_web/live/`.

### `spacecraft_list_live_test.exs`

- Unauthenticated visitor redirects to `/sign-in`.
- Non-member of the org is redirected (standard `OrganizationAuth` behavior).
- Member with missing mission ID is redirected to `/missions` with a flash.
- Member, empty list, renders the `.empty_state` block with the "Register the first spacecraft" CTA.
- Member, populated list, renders each spacecraft's `display_name` and `spacecraft_id`, and the action menu "View" item navigates to the show page.
- Cross-org isolation: spacecraft belonging to another organization's mission do not appear in the current org's list.

### `spacecraft_new_live_test.exs`

- Unauthenticated visitor redirects.
- Member with a blank `display_name` sees a flash error and stays on the page.
- Member with a valid submission is redirected to the new spacecraft's show page, and the spacecraft appears in `Cadence.list_spacecraft/2`.
- Member hitting a URL with a missing/invalid mission ID is redirected to `/missions` with a flash.

### `spacecraft_show_live_test.exs`

- Unauthenticated visitor redirects.
- Spacecraft not found redirects to the mission's spacecraft list with a flash.
- Cross-mission tampering (spacecraft_id from a sibling mission in the current URL's mission_id slot) hits the not-found path.
- Cross-org tampering hits the not-found path.
- Happy path renders `display_name`, `spacecraft_id`, the mission link, and organization id. Sidebar shows "Spacecraft" highlighted.
- Non-empty metadata renders the collapsed `<details>` block; empty metadata does not.

### Fixtures

Reuse `persist_user!`, `persist_org!`, `grant_membership!`, `member_conn`, and the existing mission creation helper in `apps/cadence_web/test/support/fixtures.ex`. Add one helper:

```elixir
def persist_spacecraft!(mission, opts \\ []) do
  display_name = Keyword.get(opts, :display_name, "Spacecraft #{System.unique_integer([:positive])}")
  spacecraft = Cadence.Spacecraft.new(%{mission_id: mission.mission_id, display_name: display_name})
  {:ok, persisted} = Cadence.persist_spacecraft(mission.organization_id, spacecraft)
  persisted
end
```

### Verification commands

Must pass before claiming the work complete:

- `mix compile --warnings-as-errors`
- `mix format` on all touched Elixir files
- `mix credo --strict` on touched files (repo-wide strictness is still being burned down; leave touched files no worse than found)
- `cd apps/cadence && mix test`
- `cd apps/cadence_web && mix test`

## Authorization

Unchanged from Missions: any active organization member can list, view, or create spacecraft. `SpacecraftNewLive` carries a `TODO(authz)` module doc identical in spirit to `MissionNewLive`'s, noting the gate will tighten once platform-wide authorization is defined (likely `:organization_admin` or a finer capability).

## Open questions

None at time of writing. Tweaks to nav highlighting logic, metadata rendering, or the empty-state copy are acceptable during implementation.
