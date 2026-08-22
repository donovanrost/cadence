# Operator → Organization UI Rewrite Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the premature `/operator` surface with an organization-scoped UI at `/` (Home + Missions), add mission list/view/create pages, and introduce a minimal mission-sidebar layout for future per-mission pages.

**Architecture:** Two new `live_session`s (`:organization` and `:mission`) behind the existing `:require_authenticated_scope` pipeline. Session-populated `Cadence.Auth.Scope` already carries the user's organization + membership, so on_mount hooks only need to gate access, not re-load data. `/operator` is deleted; non-admins land on `/`.

**Tech Stack:** Phoenix 1.7 LiveView, Tailwind v4 + daisyUI 5 (Tokyo Night dark theme, HUD utility layer), PostgreSQL via Ecto, per-app tests (`apps/cadence_web`). Domain API exposed through `Cadence.*` facade.

**Spec:** `docs/superpowers/specs/2026-04-18-operator-to-org-rewrite-design.md`

---

## File Structure

**Added:**

- `apps/cadence_web/test/support/fixtures.ex` — user/org/membership test helpers.
- `apps/cadence_web/lib/cadence_web/controllers/no_organization_controller.ex`
- `apps/cadence_web/lib/cadence_web/controllers/no_organization_html.ex`
- `apps/cadence_web/lib/cadence_web/controllers/no_organization_html/show.html.heex`
- `apps/cadence_web/lib/cadence_web/live/organization_auth.ex` — `:require_organization_scope` on_mount.
- `apps/cadence_web/lib/cadence_web/live/mission_auth.ex` — `:load_mission` on_mount.
- `apps/cadence_web/lib/cadence_web/live/organization_home_live.ex`
- `apps/cadence_web/lib/cadence_web/live/mission_list_live.ex`
- `apps/cadence_web/lib/cadence_web/live/mission_new_live.ex`
- `apps/cadence_web/lib/cadence_web/live/mission_show_live.ex`
- `apps/cadence_web/lib/cadence_web/components/layouts/mission_sidebar.html.heex`
- Tests for each module above under `apps/cadence_web/test/cadence_web/`.

**Modified:**

- `apps/cadence_web/lib/cadence_web/router.ex` — remove operator routes/controllers, add `:organization` and `:mission` live sessions + `/no-organization` route.
- `apps/cadence_web/lib/cadence_web/authenticated_entry.ex` — non-admin entry → `/`.
- `apps/cadence_web/lib/cadence_web/live/admin_auth.ex` — non-admin fallback redirect → `/`.
- `apps/cadence_web/lib/cadence_web/components/layouts/sidebar.html.heex` — add `:organization` branch, remove `:operator` branch.
- `apps/cadence_web/test/cadence_web/controllers/browser_shell_test.exs` — update `/operator` expectations to `/`.
- `apps/cadence_web/test/cadence_web/live/admin_live_test.exs` — update `/operator` expectations to `/`.

**Deleted:**

- `apps/cadence_web/lib/cadence_web/controllers/operator_entry_controller.ex`
- `apps/cadence_web/lib/cadence_web/controllers/operator_home_controller.ex`
- `apps/cadence_web/lib/cadence_web/controllers/operator_home_html.ex`
- `apps/cadence_web/lib/cadence_web/controllers/operator_home_html/` (directory + templates)

---

## Coding conventions (reminder)

- Run `mix format` on every touched Elixir file.
- `mix compile --warnings-as-errors` must pass.
- `mix credo --strict` — leave the codebase better than you found it.
- Per-app tests: `cd apps/cadence_web && mix test`.
- Templates: compose daisyUI + Tailwind utilities + HUD utilities only. **Never add rules to CSS files.**
- Form inputs: use `<.input>` from `CadenceWeb.CoreComponents`. No raw HTML form fields.
- Table row actions: use `<.action_menu>`. No inline action buttons.
- No render function over 50 lines; no file over 400 lines.
- Default to no comments; only write one when the WHY is non-obvious.

---

### Task 1: Test fixtures module

**Files:**

- Create: `apps/cadence_web/test/support/fixtures.ex`

This module centralizes the user/organization/membership setup logic currently duplicated across existing tests. New tests use it; existing tests stay as they are (out of scope to refactor).

- [ ] **Step 1: Create the fixtures module**

Write `apps/cadence_web/test/support/fixtures.ex`:

```elixir
defmodule CadenceWeb.TestFixtures do
  @moduledoc false

  import ExUnit.Assertions

  alias Cadence.Accounts.{OrganizationMembership, Password, User}
  alias Cadence.Ids
  alias Cadence.Organizations.Organization
  alias Cadence.Persistence.Schemas.{
    OrganizationMembershipRow,
    UserLocalCredentialRow,
    UserRow
  }
  alias Cadence.Repo

  @default_password "durable-password-123"

  def default_password, do: @default_password

  @spec persist_user!(keyword()) :: User.t()
  def persist_user!(opts \\ []) do
    email = Keyword.get(opts, :email, "user-#{System.unique_integer([:positive])}@example.com")
    password = Keyword.get(opts, :password, @default_password)
    display_name = Keyword.get(opts, :display_name, "Durable User")
    capabilities = Keyword.get(opts, :capabilities, [])

    user =
      User.new(%{
        user_id: Keyword.get(opts, :user_id, Ids.new("user")),
        email: email,
        display_name: display_name,
        capabilities: capabilities,
        confirmed_at: DateTime.utc_now(),
        lifecycle_state: :active,
        metadata: %{}
      })

    assert {:ok, _user_row} = Repo.insert(UserRow.changeset(user))

    password_document = Password.hash_password(password)

    assert {:ok, _credential_row} =
             Repo.insert(
               UserLocalCredentialRow.changeset(%{
                 local_credential_id: Ids.new("cred"),
                 user_id: user.user_id,
                 provider_key: "password",
                 password_hash: password_document.password_hash,
                 password_salt: password_document.password_salt,
                 password_iterations: password_document.password_iterations,
                 lifecycle_state: "active",
                 metadata: %{}
               })
             )

    user
  end

  @spec persist_org!(keyword()) :: Organization.t()
  def persist_org!(opts \\ []) do
    slug = Keyword.get(opts, :slug, "org-#{System.unique_integer([:positive])}")
    display_name = Keyword.get(opts, :display_name, "Cadence Org")

    org = Organization.new(%{display_name: display_name, slug: slug})
    assert {:ok, persisted} = Cadence.persist_organization(org)
    persisted
  end

  @spec grant_membership!(User.t(), Organization.t(), keyword()) :: OrganizationMembership.t()
  def grant_membership!(%User{} = user, %Organization{} = org, opts \\ []) do
    role = Keyword.get(opts, :role, :member)

    membership =
      OrganizationMembership.new(%{
        user_id: user.user_id,
        organization_id: org.organization_id,
        role: role,
        lifecycle_state: :active
      })

    assert {:ok, _row} = Repo.insert(OrganizationMembershipRow.changeset(membership))
    membership
  end

  @spec member_session_token!(User.t()) :: binary()
  def member_session_token!(%User{email: email}) do
    assert {:ok, session} = Cadence.sign_in(email, @default_password)
    session.session_token
  end

  @spec member_conn(User.t()) :: Plug.Conn.t()
  def member_conn(%User{} = user) do
    token = member_session_token!(user)
    Phoenix.ConnTest.build_conn() |> Plug.Test.init_test_session(%{user_session_token: token})
  end
end
```

- [ ] **Step 2: Verify `test/support` is compiled for tests**

The fixtures module lives at `apps/cadence_web/test/support/fixtures.ex`. Phoenix's default `mix.exs` already includes `"test/support"` in the test `elixirc_paths`. Run from the app dir:

```bash
cd apps/cadence_web && mix compile --warnings-as-errors
```

Expected: clean compile. If it errors about unknown module `OrganizationMembershipRow`, confirm the alias exists:

```bash
cd apps/cadence_web && grep -rn "OrganizationMembershipRow" ../../apps/cadence/lib | head
```

- [ ] **Step 3: Run credo + format**

```bash
cd apps/cadence_web && mix format test/support/fixtures.ex && mix credo --strict test/support/fixtures.ex
```

Expected: no issues.

- [ ] **Step 4: Commit**

```bash
git add apps/cadence_web/test/support/fixtures.ex
git commit -m "test(cadence_web): add fixtures module for user/org/membership setup"
```

---

### Task 2: `/no-organization` controller, view, template, and test

**Files:**

- Create: `apps/cadence_web/lib/cadence_web/controllers/no_organization_controller.ex`
- Create: `apps/cadence_web/lib/cadence_web/controllers/no_organization_html.ex`
- Create: `apps/cadence_web/lib/cadence_web/controllers/no_organization_html/show.html.heex`
- Modify: `apps/cadence_web/lib/cadence_web/router.ex`
- Test: `apps/cadence_web/test/cadence_web/controllers/no_organization_controller_test.exs`

- [ ] **Step 1: Write the failing controller test**

Write `apps/cadence_web/test/cadence_web/controllers/no_organization_controller_test.exs`:

```elixir
defmodule CadenceWeb.NoOrganizationControllerTest do
  use CadenceWeb.ConnCase, async: false

  alias CadenceWeb.TestFixtures

  test "renders for authenticated user with no membership" do
    user = TestFixtures.persist_user!()
    conn = TestFixtures.member_conn(user)

    html =
      conn
      |> get("/no-organization")
      |> html_response(200)

    assert html =~ "don&#39;t have access"
    assert html =~ "Sign out"
  end

  test "redirects to /sign-in when unauthenticated", %{conn: conn} do
    conn = get(conn, "/no-organization")
    assert redirected_to(conn) == "/sign-in"
  end
end
```

- [ ] **Step 2: Run it to confirm it fails**

```bash
cd apps/cadence_web && mix test test/cadence_web/controllers/no_organization_controller_test.exs
```

Expected: compile error / route not found for `/no-organization`.

- [ ] **Step 3: Write the controller**

Create `apps/cadence_web/lib/cadence_web/controllers/no_organization_controller.ex`:

```elixir
defmodule CadenceWeb.NoOrganizationController do
  use CadenceWeb, :controller

  def show(conn, _params) do
    conn
    |> put_layout(html: {CadenceWeb.Layouts, :auth})
    |> render(:show)
  end
end
```

- [ ] **Step 4: Write the HTML view module**

Create `apps/cadence_web/lib/cadence_web/controllers/no_organization_html.ex`:

```elixir
defmodule CadenceWeb.NoOrganizationHTML do
  use CadenceWeb, :html

  embed_templates "no_organization_html/*"
end
```

- [ ] **Step 5: Write the template**

Create `apps/cadence_web/lib/cadence_web/controllers/no_organization_html/show.html.heex`:

```heex
<div class="space-y-4 text-center">
  <h1 class="text-xl font-bold text-base-content">No organization access</h1>
  <p class="text-sm text-base-content/70">
    You don't have access to any organization yet.
    Ask an administrator for an invitation.
  </p>
  <.form for={%{}} as={:session} action={~p"/session"} method="delete" class="w-full">
    <button type="submit" class="btn btn-ghost btn-sm w-full gap-2 text-xs uppercase tracking-wide">
      <span class="hero-arrow-right-start-on-rectangle h-4 w-4 opacity-80"></span>
      Sign out
    </button>
  </.form>
</div>
```

- [ ] **Step 6: Register the route**

In `apps/cadence_web/lib/cadence_web/router.ex`, add `no-organization` to the existing authenticated-only scope (same scope that holds `/`, `/operator`, `delete "/session"`). Locate the block starting `scope "/", CadenceWeb do` followed by `pipe_through [:browser, :require_authenticated_scope]` (currently around lines 48–64). Add this line after `delete "/session"`:

```elixir
get "/no-organization", NoOrganizationController, :show
```

- [ ] **Step 7: Run the test to confirm it passes**

```bash
cd apps/cadence_web && mix test test/cadence_web/controllers/no_organization_controller_test.exs
```

Expected: both tests pass.

- [ ] **Step 8: Format, credo, compile**

```bash
cd apps/cadence_web && mix format && mix credo --strict && mix compile --warnings-as-errors
```

Expected: clean.

- [ ] **Step 9: Commit**

```bash
git add apps/cadence_web/lib/cadence_web/controllers/no_organization_controller.ex \
        apps/cadence_web/lib/cadence_web/controllers/no_organization_html.ex \
        apps/cadence_web/lib/cadence_web/controllers/no_organization_html/ \
        apps/cadence_web/lib/cadence_web/router.ex \
        apps/cadence_web/test/cadence_web/controllers/no_organization_controller_test.exs
git commit -m "feat(cadence_web): add /no-organization page for users without memberships"
```

---

### Task 3: `OrganizationAuth` on_mount hook

**Files:**

- Create: `apps/cadence_web/lib/cadence_web/live/organization_auth.ex`
- Test: `apps/cadence_web/test/cadence_web/live/organization_auth_test.exs`

This hook runs in the `:organization` (and later `:mission`) live sessions. Because the browser pipeline already populates `current_scope` via `Cadence.authenticate_api_token/2`, the on_mount does not need to re-hit the DB — it just reads the scope from `assigns` or rebuilds it from the session token for the WS mount.

- [ ] **Step 1: Write the failing on_mount test**

Write `apps/cadence_web/test/cadence_web/live/organization_auth_test.exs`:

```elixir
defmodule CadenceWeb.OrganizationAuthTest do
  use CadenceWeb.ConnCase, async: false

  alias Cadence.Auth.Scope
  alias CadenceWeb.OrganizationAuth
  alias CadenceWeb.TestFixtures

  @moduletag :capture_log

  describe "on_mount :require_organization_scope" do
    test "continues and assigns nav_context when scope has an organization membership" do
      user = TestFixtures.persist_user!()
      org = TestFixtures.persist_org!(display_name: "Cadence Ops", slug: "cadence-ops")
      _membership = TestFixtures.grant_membership!(user, org)
      token = TestFixtures.member_session_token!(user)

      session = %{"user_session_token" => token}

      assert {:cont, socket} =
               OrganizationAuth.on_mount(
                 :require_organization_scope,
                 %{},
                 session,
                 %Phoenix.LiveView.Socket{}
               )

      assert socket.assigns.nav_context == :organization
      assert %Scope{organization: %{slug: "cadence-ops"}} = socket.assigns.current_scope
    end

    test "redirects to /no-organization when the scope has no membership" do
      user = TestFixtures.persist_user!()
      token = TestFixtures.member_session_token!(user)

      session = %{"user_session_token" => token}

      assert {:halt, socket} =
               OrganizationAuth.on_mount(
                 :require_organization_scope,
                 %{},
                 session,
                 %Phoenix.LiveView.Socket{}
               )

      assert socket.redirected == {:redirect, %{to: "/no-organization", status: 302}}
    end

    test "redirects to /sign-in when there is no session token" do
      session = %{}

      assert {:halt, socket} =
               OrganizationAuth.on_mount(
                 :require_organization_scope,
                 %{},
                 session,
                 %Phoenix.LiveView.Socket{}
               )

      assert socket.redirected == {:redirect, %{to: "/sign-in", status: 302}}
    end
  end
end
```

- [ ] **Step 2: Run the test to confirm it fails**

```bash
cd apps/cadence_web && mix test test/cadence_web/live/organization_auth_test.exs
```

Expected: compile error / `CadenceWeb.OrganizationAuth` not defined.

- [ ] **Step 3: Write the on_mount module**

Create `apps/cadence_web/lib/cadence_web/live/organization_auth.ex`:

```elixir
defmodule CadenceWeb.OrganizationAuth do
  @moduledoc false

  import Phoenix.Component
  import Phoenix.LiveView

  alias Cadence.Auth.Scope

  def on_mount(:require_organization_scope, _params, session, socket) do
    socket = assign_scope_from_session(socket, session)

    case socket.assigns[:current_scope] do
      %Scope{organization_membership: %_{} = _membership} ->
        {:cont, assign(socket, :nav_context, :organization)}

      %Scope{} ->
        {:halt, redirect(socket, to: "/no-organization")}

      _other ->
        {:halt, redirect(socket, to: "/sign-in")}
    end
  end

  defp assign_scope_from_session(socket, session) do
    case session["user_session_token"] do
      token when is_binary(token) ->
        case Cadence.authenticate_api_token(token,
               current_organization_id: session["current_organization_id"]
             ) do
          {:ok, %Scope{} = scope} -> assign(socket, :current_scope, scope)
          _error -> assign(socket, :current_scope, nil)
        end

      _other ->
        assign(socket, :current_scope, nil)
    end
  end
end
```

- [ ] **Step 4: Run the test to confirm it passes**

```bash
cd apps/cadence_web && mix test test/cadence_web/live/organization_auth_test.exs
```

Expected: all three tests pass.

- [ ] **Step 5: Format, credo, compile**

```bash
cd apps/cadence_web && mix format && mix credo --strict && mix compile --warnings-as-errors
```

- [ ] **Step 6: Commit**

```bash
git add apps/cadence_web/lib/cadence_web/live/organization_auth.ex \
        apps/cadence_web/test/cadence_web/live/organization_auth_test.exs
git commit -m "feat(cadence_web): add OrganizationAuth on_mount hook for org-scoped live sessions"
```

---

### Task 4: OrganizationHomeLive, sidebar `:organization` branch, `/` route, redirect updates

This task is the point of no return for `/operator`. It:

1. Adds `OrganizationHomeLive`.
2. Adds the `:organization` live session with a single `live "/"` route.
3. Removes `get "/", OperatorEntryController, :show` (conflicts with the new `live "/"`).
4. Points `AuthenticatedEntry` + `admin_auth` fallback at `/`.
5. Adds an `:organization` branch to the sidebar template.
6. Updates the two existing tests that asserted `/operator` redirects to now assert `/`.

`/operator` route and controller files remain until Task 10.

**Files:**

- Create: `apps/cadence_web/lib/cadence_web/live/organization_home_live.ex`
- Modify: `apps/cadence_web/lib/cadence_web/router.ex`
- Modify: `apps/cadence_web/lib/cadence_web/authenticated_entry.ex`
- Modify: `apps/cadence_web/lib/cadence_web/live/admin_auth.ex`
- Modify: `apps/cadence_web/lib/cadence_web/components/layouts/sidebar.html.heex`
- Modify: `apps/cadence_web/test/cadence_web/live/admin_live_test.exs`
- Modify: `apps/cadence_web/test/cadence_web/controllers/browser_shell_test.exs`
- Test: `apps/cadence_web/test/cadence_web/live/organization_home_live_test.exs`

- [ ] **Step 1: Write the failing OrganizationHomeLive test**

Write `apps/cadence_web/test/cadence_web/live/organization_home_live_test.exs`:

```elixir
defmodule CadenceWeb.OrganizationHomeLiveTest do
  use CadenceWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias CadenceWeb.TestFixtures

  describe "mount" do
    test "renders org display_name and slug" do
      user = TestFixtures.persist_user!()
      org = TestFixtures.persist_org!(display_name: "Cadence Ops", slug: "cadence-ops")
      _membership = TestFixtures.grant_membership!(user, org)

      conn = TestFixtures.member_conn(user)

      {:ok, _view, html} = live(conn, ~p"/")

      assert html =~ "Cadence Ops"
      assert html =~ "cadence-ops"
    end

    test "sidebar highlights the Home nav item" do
      user = TestFixtures.persist_user!()
      org = TestFixtures.persist_org!()
      _membership = TestFixtures.grant_membership!(user, org)

      {:ok, _view, html} = live(TestFixtures.member_conn(user), ~p"/")

      # Active nav item gets the primary highlight class
      assert html =~ ~r/border-primary[^"]*".*Home/s
    end
  end

  describe "authorization" do
    test "redirects unauthenticated users to /sign-in", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/sign-in"}}} = live(conn, ~p"/")
    end

    test "redirects user without membership to /no-organization" do
      user = TestFixtures.persist_user!()
      conn = TestFixtures.member_conn(user)

      assert {:error, {:redirect, %{to: "/no-organization"}}} = live(conn, ~p"/")
    end
  end
end
```

- [ ] **Step 2: Run the test to confirm it fails**

```bash
cd apps/cadence_web && mix test test/cadence_web/live/organization_home_live_test.exs
```

Expected: the `/` route still points at `OperatorEntryController`, so `live/2` will fail because `/` is not a LiveView. Compile may also fail if `OrganizationHomeLive` doesn't exist yet.

- [ ] **Step 3: Write the LiveView**

Create `apps/cadence_web/lib/cadence_web/live/organization_home_live.ex`:

```elixir
defmodule CadenceWeb.OrganizationHomeLive do
  @moduledoc false
  use CadenceWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    org = socket.assigns.current_scope.organization

    {:ok,
     socket
     |> assign(:page_title, org.display_name)
     |> assign(:nav_item, :organization_home)
     |> assign(:organization, org)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <div>
        <h1 class="text-2xl font-bold text-base-content">{@organization.display_name}</h1>
        <p class="mt-1 text-sm text-base-content/50 font-mono">{@organization.slug}</p>
      </div>
    </div>
    """
  end
end
```

Note: `current_scope` is already assigned by `OrganizationAuth.on_mount/4` and carries the full `%Organization{}` (populated by `Cadence.authenticate_api_token/2`).

- [ ] **Step 4: Update the sidebar template**

Open `apps/cadence_web/lib/cadence_web/components/layouts/sidebar.html.heex`. Find the `<nav>` block (around lines 46–80) that switches on `assigns[:nav_context]`. Add a new `:organization ->` clause **before** the catch-all `_ ->`:

```heex
<% :organization -> %>
  <div class="px-3 mb-2 sidebar-expanded-only">
    <span class="hud-label text-base-content/30">
      <%= if @current_scope && @current_scope.organization do %>
        {@current_scope.organization.display_name}
      <% else %>
        Organization
      <% end %>
    </span>
  </div>
  <ul class="menu menu-sm space-y-0.5">
    <li>
      <.link navigate={~p"/"} class={["flex items-center gap-2 px-3 py-2 text-xs tracking-wide uppercase border-l-2 transition-all", if(assigns[:nav_item] == :organization_home, do: "bg-primary/10 text-primary border-primary shadow-[inset_0_0_20px_rgba(125,207,255,0.1)]", else: "text-base-content/60 border-transparent hover:bg-primary/5 hover:text-base-content hover:border-primary/30")]}>
        <span class="hero-home h-4 w-4 opacity-80 flex-shrink-0"></span>
        <span class="sidebar-label">Home</span>
      </.link>
    </li>
  </ul>
```

Do NOT remove the existing `_ ->` catch-all (it still renders operator nav — we delete it in Task 10). The `:admin` clause stays untouched.

- [ ] **Step 5: Update the router — add `:organization` live session, remove operator `/` route**

Open `apps/cadence_web/lib/cadence_web/router.ex`. In the scope that pipes through `[:browser, :require_authenticated_scope]` (currently lines 48–64), make these edits:

1. Remove the line `get "/", OperatorEntryController, :show`.
2. Keep `get "/operator", OperatorHomeController, :show` (removed in Task 10).
3. Keep `delete "/session", UserSessionController, :delete`.
4. Add a new `live_session :organization` block BEFORE the existing `live_session :admin`:

```elixir
live_session :organization,
  on_mount: [{CadenceWeb.OrganizationAuth, :require_organization_scope}],
  layout: {CadenceWeb.Layouts, :sidebar} do
  live "/", OrganizationHomeLive, :show
end
```

After this step, the affected scope block looks like:

```elixir
scope "/", CadenceWeb do
  pipe_through [:browser, :require_authenticated_scope]

  get "/operator", OperatorHomeController, :show
  get "/no-organization", NoOrganizationController, :show
  delete "/session", UserSessionController, :delete

  live_session :organization,
    on_mount: [{CadenceWeb.OrganizationAuth, :require_organization_scope}],
    layout: {CadenceWeb.Layouts, :sidebar} do
    live "/", OrganizationHomeLive, :show
  end

  live_session :admin,
    on_mount: [{CadenceWeb.AdminAuth, :require_platform_admin}],
    layout: {CadenceWeb.Layouts, :sidebar} do
    live "/admin", AdminHomeLive, :index
    live "/admin/organizations", AdminOrganizationListLive, :index
    live "/admin/organizations/new", AdminOrganizationNewLive, :new
    live "/admin/organizations/:org_id", AdminOrganizationShowLive, :show
    live "/admin/organizations/:org_id/invite", AdminOrganizationInviteLive, :invite
  end
end
```

- [ ] **Step 6: Update `AuthenticatedEntry`**

Open `apps/cadence_web/lib/cadence_web/authenticated_entry.ex` and replace the whole module contents with:

```elixir
defmodule CadenceWeb.AuthenticatedEntry do
  @moduledoc false

  alias Cadence.Accounts.User
  alias Cadence.Auth.Scope

  @admin_path "/admin"
  @organization_path "/"

  @spec entry_path(Scope.t() | User.t()) :: binary()
  def entry_path(%Scope{} = scope) do
    if MapSet.member?(scope.capabilities, :platform_admin),
      do: @admin_path,
      else: @organization_path
  end

  def entry_path(%User{} = user) do
    if :platform_admin in user.capabilities,
      do: @admin_path,
      else: @organization_path
  end

  @spec redirect_path(binary() | nil, Scope.t() | User.t()) :: binary()
  def redirect_path(return_to, actor) when is_binary(return_to) do
    if entry_route?(return_to), do: entry_path(actor), else: return_to
  end

  def redirect_path(_return_to, actor), do: entry_path(actor)

  defp entry_route?(path) when is_binary(path) do
    exact_or_query_path?(path, "/") or
      exact_or_query_path?(path, "/sign-in") or
      exact_or_query_path?(path, @admin_path)
  end

  defp exact_or_query_path?(path, "/"), do: path == "/" or String.starts_with?(path, "/?")

  defp exact_or_query_path?(path, base_path) when is_binary(path) and is_binary(base_path) do
    path == base_path or String.starts_with?(path, base_path <> "?")
  end
end
```

- [ ] **Step 7: Update `admin_auth.ex` fallback redirect**

Open `apps/cadence_web/lib/cadence_web/live/admin_auth.ex`. Change the non-admin branch to redirect to `/` instead of `/operator`:

Replace:

```elixir
else
  {:halt, redirect(socket, to: "/operator")}
end
```

With:

```elixir
else
  {:halt, redirect(socket, to: "/")}
end
```

- [ ] **Step 8: Update `admin_live_test.exs` expectation**

Open `apps/cadence_web/test/cadence_web/live/admin_live_test.exs`. Find the test `"non-admin user is redirected to /operator"` (around line 48) and change it to expect `/`:

```elixir
test "non-admin user is redirected to /" do
  durable_password = "durable-password-123"

  persist_durable_user!(
    email: "regular@example.com",
    password: durable_password,
    capabilities: []
  )

  {:ok, session} = Cadence.sign_in("regular@example.com", durable_password)
  conn = build_conn() |> init_test_session(%{user_session_token: session.session_token})

  assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/admin")
end
```

- [ ] **Step 8b: Add a unit test for `AuthenticatedEntry`**

Create `apps/cadence_web/test/cadence_web/authenticated_entry_test.exs`:

```elixir
defmodule CadenceWeb.AuthenticatedEntryTest do
  use ExUnit.Case, async: true

  alias Cadence.Accounts.User
  alias Cadence.Auth.Scope
  alias CadenceWeb.AuthenticatedEntry

  describe "entry_path/1" do
    test "platform admin scope routes to /admin" do
      scope = %Scope{capabilities: MapSet.new([:platform_admin])}
      assert AuthenticatedEntry.entry_path(scope) == "/admin"
    end

    test "non-admin scope routes to /" do
      scope = %Scope{capabilities: MapSet.new()}
      assert AuthenticatedEntry.entry_path(scope) == "/"
    end

    test "platform admin user routes to /admin" do
      user = %User{capabilities: [:platform_admin]}
      assert AuthenticatedEntry.entry_path(user) == "/admin"
    end

    test "non-admin user routes to /" do
      user = %User{capabilities: []}
      assert AuthenticatedEntry.entry_path(user) == "/"
    end
  end

  describe "redirect_path/2" do
    test "honors an explicit non-entry return path" do
      user = %User{capabilities: []}
      assert AuthenticatedEntry.redirect_path("/missions/alpha", user) == "/missions/alpha"
    end

    test "falls back to entry path when return_to is an entry route" do
      user = %User{capabilities: []}
      assert AuthenticatedEntry.redirect_path("/", user) == "/"
      assert AuthenticatedEntry.redirect_path("/sign-in", user) == "/"
      assert AuthenticatedEntry.redirect_path("/admin", user) == "/"
    end

    test "falls back to entry path when return_to is nil" do
      user = %User{capabilities: [:platform_admin]}
      assert AuthenticatedEntry.redirect_path(nil, user) == "/admin"
    end
  end
end
```

Run it to confirm pass:

```bash
cd apps/cadence_web && mix test test/cadence_web/authenticated_entry_test.exs
```

Expected: all tests pass.

- [ ] **Step 9: Update `browser_shell_test.exs` expectations**

Open `apps/cadence_web/test/cadence_web/controllers/browser_shell_test.exs`. Two tests reference `/operator`:

**Test `"durable user sign-in reaches operator home"` (around line 74)** — replace the whole test with:

```elixir
test "durable user sign-in reaches the organization home", %{conn: _conn} do
  durable_password = "durable-password-123"
  persist_durable_user!(email: "ops-lead@example.com", password: durable_password)

  org = Organization.new(%{display_name: "Cadence Operations", slug: "cadence-operations"})
  assert {:ok, persisted_org} = Cadence.persist_organization(org)

  assert {:ok, _result} =
           Cadence.Accounts.establish_organization_access(
             "ops-lead@example.com",
             persisted_org.organization_id,
             membership_role: :organization_admin,
             invited_by_user_id: "user_bootstrap_admin"
           )

  durable_conn =
    build_conn()
    |> post("/sign-in", %{
      "user" => %{
        "email" => "ops-lead@example.com",
        "password" => durable_password
      }
    })

  assert redirected_to(durable_conn) == "/"
end
```

**Test `"invitation acceptance creates a durable session and routes to operator"` (around line 111)** — replace the assertion `assert redirected_to(accepted_conn) == "/operator"` with `assert redirected_to(accepted_conn) == "/"`, and remove the subsequent `operator_response = ... get("/operator") ... assert response =~ "operator-home"` block (lines 156–164). Rename the test as well:

```elixir
test "invitation acceptance creates a durable session and routes to org home", %{conn: _conn} do
  org = Organization.new(%{display_name: "Cadence Operations", slug: "cadence-operations"})
  assert {:ok, persisted_org} = Cadence.persist_organization(org)

  assert {:ok, %{mode: :invited, invitation: invitation, invitation_token: token}} =
           Cadence.Accounts.establish_organization_access(
             "new-admin@example.com",
             persisted_org.organization_id,
             membership_role: :organization_admin,
             invited_by_user_id: "user_bootstrap_admin",
             display_name: "New Admin"
           )

  assert {:ok, email} =
           CadenceWeb.UserNotifier.deliver_organization_invitation(
             invitation,
             persisted_org,
             "http://localhost:4002/invitations/#{token}"
           )

  assert email.subject == "Cadence invitation for Cadence Operations"
  assert email.to == [{"", "new-admin@example.com"}]

  invitation_path = "/invitations/#{token}"

  invitation_response =
    build_conn()
    |> get(invitation_path)
    |> html_response(200)

  assert invitation_response =~ "organization-invitation-acceptance-form"
  assert invitation_response =~ "new-admin@example.com"

  accepted_conn =
    build_conn()
    |> post(invitation_path, %{
      "organization_invitation_acceptance" => %{
        "display_name" => "New Admin",
        "password" => "new-admin-password-123",
        "password_confirmation" => "new-admin-password-123"
      }
    })

  assert redirected_to(accepted_conn) == "/"
end
```

- [ ] **Step 10: Run the full test suite**

```bash
cd apps/cadence_web && mix test
```

Expected: all tests pass, including the new `OrganizationHomeLive` tests.

- [ ] **Step 11: Format, credo, compile**

```bash
cd apps/cadence_web && mix format && mix credo --strict && mix compile --warnings-as-errors
```

Expected: clean. If `mix credo --strict` raises **new** violations in your changes, fix them. Existing violations (not touched by your changes) are out of scope.

- [ ] **Step 12: Commit**

```bash
git add apps/cadence_web/lib/cadence_web/live/organization_home_live.ex \
        apps/cadence_web/lib/cadence_web/router.ex \
        apps/cadence_web/lib/cadence_web/authenticated_entry.ex \
        apps/cadence_web/lib/cadence_web/live/admin_auth.ex \
        apps/cadence_web/lib/cadence_web/components/layouts/sidebar.html.heex \
        apps/cadence_web/test/cadence_web/authenticated_entry_test.exs \
        apps/cadence_web/test/cadence_web/live/organization_home_live_test.exs \
        apps/cadence_web/test/cadence_web/live/admin_live_test.exs \
        apps/cadence_web/test/cadence_web/controllers/browser_shell_test.exs
git commit -m "feat(cadence_web): introduce organization home at / and drop /operator landing"
```

---

### Task 5: MissionListLive with empty state, sidebar Missions entry, Home mission count card

**Files:**

- Create: `apps/cadence_web/lib/cadence_web/live/mission_list_live.ex`
- Modify: `apps/cadence_web/lib/cadence_web/router.ex`
- Modify: `apps/cadence_web/lib/cadence_web/live/organization_home_live.ex`
- Modify: `apps/cadence_web/lib/cadence_web/components/layouts/sidebar.html.heex`
- Test: `apps/cadence_web/test/cadence_web/live/mission_list_live_test.exs`

- [ ] **Step 1: Write the failing MissionListLive test**

Write `apps/cadence_web/test/cadence_web/live/mission_list_live_test.exs`:

```elixir
defmodule CadenceWeb.MissionListLiveTest do
  use CadenceWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias Cadence.Missions.Mission
  alias CadenceWeb.TestFixtures

  defp signed_in_conn do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _ = TestFixtures.grant_membership!(user, org)
    {TestFixtures.member_conn(user), org}
  end

  defp persist_mission!(org, slug, display_name) do
    mission =
      Mission.new(%{
        organization_id: org.organization_id,
        slug: slug,
        display_name: display_name
      })

    assert {:ok, persisted} = Cadence.persist_mission(mission)
    persisted
  end

  describe "mount" do
    test "renders empty state when there are no missions" do
      {conn, _org} = signed_in_conn()

      {:ok, _view, html} = live(conn, ~p"/missions")

      assert html =~ "No missions"
    end

    test "renders missions in a table" do
      {conn, org} = signed_in_conn()
      _m1 = persist_mission!(org, "alpha", "Alpha Mission")
      _m2 = persist_mission!(org, "beta", "Beta Mission")

      {:ok, _view, html} = live(conn, ~p"/missions")

      assert html =~ "Alpha Mission"
      assert html =~ "alpha"
      assert html =~ "Beta Mission"
      assert html =~ "beta"
      assert html =~ "New Mission"
    end

    test "shows only missions belonging to the current organization" do
      {conn, org} = signed_in_conn()
      other_org = TestFixtures.persist_org!(display_name: "Other", slug: "other-org")
      _mine = persist_mission!(org, "mine", "My Mission")
      _theirs = persist_mission!(other_org, "theirs", "Their Mission")

      {:ok, _view, html} = live(conn, ~p"/missions")

      assert html =~ "My Mission"
      refute html =~ "Their Mission"
    end
  end

  describe "authorization" do
    test "unauthenticated request redirects to /sign-in", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/sign-in"}}} = live(conn, ~p"/missions")
    end

    test "user without membership redirects to /no-organization" do
      user = TestFixtures.persist_user!()
      conn = TestFixtures.member_conn(user)

      assert {:error, {:redirect, %{to: "/no-organization"}}} = live(conn, ~p"/missions")
    end
  end
end
```

- [ ] **Step 2: Run the test to confirm it fails**

```bash
cd apps/cadence_web && mix test test/cadence_web/live/mission_list_live_test.exs
```

Expected: compile error / `MissionListLive` not found, or route `/missions` missing.

- [ ] **Step 3: Write the LiveView**

Create `apps/cadence_web/lib/cadence_web/live/mission_list_live.ex`:

```elixir
defmodule CadenceWeb.MissionListLive do
  @moduledoc false
  use CadenceWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    organization_id = socket.assigns.current_scope.organization_id
    missions = Cadence.list_missions(organization_id)

    {:ok,
     socket
     |> assign(:page_title, "Missions")
     |> assign(:nav_item, :missions)
     |> assign(:missions, missions)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <div class="flex items-center justify-between">
        <h1 class="text-2xl font-bold text-base-content">Missions</h1>
        <.link navigate={~p"/missions/new"} class="btn btn-primary btn-sm gap-1">
          <span class="hero-plus h-4 w-4"></span> New Mission
        </.link>
      </div>

      <%= if @missions == [] do %>
        <.empty_state
          icon="hero-rocket-launch"
          title="No missions yet"
          description="Create your first mission to get started."
          action_label="New Mission"
          action_navigate={~p"/missions/new"}
        />
      <% else %>
        <div class="card bg-base-200 overflow-hidden">
          <table class="table">
            <thead>
              <tr>
                <th class="hud-label">Mission</th>
                <th class="hud-label">Slug</th>
                <th class="hud-label text-right">Actions</th>
              </tr>
            </thead>
            <tbody>
              <tr :for={mission <- @missions}>
                <td class="font-medium">{mission.display_name}</td>
                <td class="font-mono text-sm text-base-content/70">{mission.slug}</td>
                <td class="text-right">
                  <.action_menu>
                    <:action>
                      <.link navigate={~p"/missions/#{mission.mission_id}"}>View</.link>
                    </:action>
                  </.action_menu>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      <% end %>
    </div>
    """
  end
end
```

Note: `<.empty_state>` and `<.action_menu>` are already defined in `CadenceWeb.CoreComponents` (verified via `apps/cadence_web/lib/cadence_web/core_components.ex`).

- [ ] **Step 4: Add `/missions` to the router**

Open `apps/cadence_web/lib/cadence_web/router.ex`. Inside the `:organization` live_session block, add `live "/missions"` alongside `live "/"`:

```elixir
live_session :organization,
  on_mount: [{CadenceWeb.OrganizationAuth, :require_organization_scope}],
  layout: {CadenceWeb.Layouts, :sidebar} do
  live "/", OrganizationHomeLive, :show
  live "/missions", MissionListLive, :index
end
```

- [ ] **Step 5: Add the sidebar "Missions" entry**

Open `apps/cadence_web/lib/cadence_web/components/layouts/sidebar.html.heex`. In the `<% :organization -> %>` block added in Task 4, add a second `<li>` after the Home one:

```heex
<li>
  <.link navigate={~p"/missions"} class={["flex items-center gap-2 px-3 py-2 text-xs tracking-wide uppercase border-l-2 transition-all", if(assigns[:nav_item] == :missions, do: "bg-primary/10 text-primary border-primary shadow-[inset_0_0_20px_rgba(125,207,255,0.1)]", else: "text-base-content/60 border-transparent hover:bg-primary/5 hover:text-base-content hover:border-primary/30")]}>
    <span class="hero-rocket-launch h-4 w-4 opacity-80 flex-shrink-0"></span>
    <span class="sidebar-label">Missions</span>
  </.link>
</li>
```

- [ ] **Step 6: Update OrganizationHomeLive to include the Missions card**

Replace the render function in `apps/cadence_web/lib/cadence_web/live/organization_home_live.ex`. Also add `mission_count` to mount:

```elixir
defmodule CadenceWeb.OrganizationHomeLive do
  @moduledoc false
  use CadenceWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    org = socket.assigns.current_scope.organization
    mission_count = org.organization_id |> Cadence.list_missions() |> length()

    {:ok,
     socket
     |> assign(:page_title, org.display_name)
     |> assign(:nav_item, :organization_home)
     |> assign(:organization, org)
     |> assign(:mission_count, mission_count)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <div>
        <h1 class="text-2xl font-bold text-base-content">{@organization.display_name}</h1>
        <p class="mt-1 text-sm text-base-content/50 font-mono">{@organization.slug}</p>
      </div>

      <div class="card bg-base-200 hover-glow-cyan transition-glow max-w-md">
        <div class="card-body p-6">
          <p class="hud-label">Missions</p>
          <p class="text-3xl font-bold mt-2">{@mission_count}</p>
          <.link navigate={~p"/missions"} class="btn btn-primary btn-sm mt-4 w-full">
            View Missions
          </.link>
        </div>
      </div>
    </div>
    """
  end
end
```

- [ ] **Step 7: Update the organization home test for the mission count card**

In `apps/cadence_web/test/cadence_web/live/organization_home_live_test.exs`, add one more test to the `"mount"` describe block:

```elixir
test "shows the current mission count and link to /missions" do
  user = TestFixtures.persist_user!()
  org = TestFixtures.persist_org!()
  _ = TestFixtures.grant_membership!(user, org)

  mission =
    Cadence.Missions.Mission.new(%{
      organization_id: org.organization_id,
      slug: "alpha",
      display_name: "Alpha"
    })

  assert {:ok, _} = Cadence.persist_mission(mission)

  {:ok, _view, html} = live(TestFixtures.member_conn(user), ~p"/")

  assert html =~ "View Missions"
  assert html =~ ~s(href="/missions")
  # Mission count appears prominently in the card.
  assert html =~ ~r/>\s*1\s*</
end
```

- [ ] **Step 8: Run both LiveView test files**

```bash
cd apps/cadence_web && mix test test/cadence_web/live/mission_list_live_test.exs test/cadence_web/live/organization_home_live_test.exs
```

Expected: all tests pass.

- [ ] **Step 9: Run the full test suite**

```bash
cd apps/cadence_web && mix test
```

Expected: green.

- [ ] **Step 10: Format, credo, compile**

```bash
cd apps/cadence_web && mix format && mix credo --strict && mix compile --warnings-as-errors
```

- [ ] **Step 11: Commit**

```bash
git add apps/cadence_web/lib/cadence_web/live/mission_list_live.ex \
        apps/cadence_web/lib/cadence_web/live/organization_home_live.ex \
        apps/cadence_web/lib/cadence_web/router.ex \
        apps/cadence_web/lib/cadence_web/components/layouts/sidebar.html.heex \
        apps/cadence_web/test/cadence_web/live/mission_list_live_test.exs \
        apps/cadence_web/test/cadence_web/live/organization_home_live_test.exs
git commit -m "feat(cadence_web): add /missions list page and Missions nav + home card"
```

---

### Task 6: MissionNewLive with auto-slug

**Files:**

- Create: `apps/cadence_web/lib/cadence_web/live/mission_new_live.ex`
- Modify: `apps/cadence_web/lib/cadence_web/router.ex`
- Test: `apps/cadence_web/test/cadence_web/live/mission_new_live_test.exs`

- [ ] **Step 1: Write the failing test**

Write `apps/cadence_web/test/cadence_web/live/mission_new_live_test.exs`:

```elixir
defmodule CadenceWeb.MissionNewLiveTest do
  use CadenceWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias CadenceWeb.TestFixtures

  defp signed_in_conn do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _ = TestFixtures.grant_membership!(user, org)
    {TestFixtures.member_conn(user), org}
  end

  describe "render" do
    test "renders the empty form" do
      {conn, _org} = signed_in_conn()

      {:ok, _view, html} = live(conn, ~p"/missions/new")

      assert html =~ "New Mission"
      assert html =~ "Display Name"
      assert html =~ "Slug"
    end
  end

  describe "auto slug" do
    test "derives slug from display_name on validate when slug is empty" do
      {conn, _org} = signed_in_conn()

      {:ok, view, _html} = live(conn, ~p"/missions/new")

      html =
        view
        |> form("#mission-form", mission: %{display_name: "Alpha Mission", slug: ""})
        |> render_change()

      assert html =~ ~s(value="alpha-mission")
    end

    test "preserves user-entered slug even when display_name changes" do
      {conn, _org} = signed_in_conn()

      {:ok, view, _html} = live(conn, ~p"/missions/new")

      view
      |> form("#mission-form", mission: %{display_name: "Foo", slug: "custom-slug"})
      |> render_change()

      html =
        view
        |> form("#mission-form", mission: %{display_name: "Bar", slug: "custom-slug"})
        |> render_change()

      assert html =~ ~s(value="custom-slug")
    end
  end

  describe "submit" do
    test "creates the mission and navigates to its show page" do
      {conn, org} = signed_in_conn()

      {:ok, view, _html} = live(conn, ~p"/missions/new")

      view
      |> form("#mission-form", mission: %{display_name: "Alpha", slug: "alpha"})
      |> render_submit()

      assert_redirect(view, ~r|^/missions/mission_|)

      # Persisted.
      assert [mission] = Cadence.list_missions(org.organization_id)
      assert mission.slug == "alpha"
      assert mission.display_name == "Alpha"
    end

    test "flashes an error when display_name is blank" do
      {conn, _org} = signed_in_conn()

      {:ok, view, _html} = live(conn, ~p"/missions/new")

      html =
        view
        |> form("#mission-form", mission: %{display_name: "", slug: "alpha"})
        |> render_submit()

      assert html =~ "required"
    end
  end

  describe "authorization" do
    test "unauthenticated request redirects to /sign-in", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/sign-in"}}} = live(conn, ~p"/missions/new")
    end

    test "user without membership redirects to /no-organization" do
      user = TestFixtures.persist_user!()
      conn = TestFixtures.member_conn(user)

      assert {:error, {:redirect, %{to: "/no-organization"}}} = live(conn, ~p"/missions/new")
    end
  end
end
```

- [ ] **Step 2: Run the test to confirm it fails**

```bash
cd apps/cadence_web && mix test test/cadence_web/live/mission_new_live_test.exs
```

Expected: compile error / `MissionNewLive` not defined.

- [ ] **Step 3: Write the LiveView**

Create `apps/cadence_web/lib/cadence_web/live/mission_new_live.ex`:

```elixir
defmodule CadenceWeb.MissionNewLive do
  @moduledoc false

  # TODO(authz): Any active organization member can create a mission. This gate
  # should tighten once platform-wide authorization is defined (likely to the
  # :organization_admin role, possibly a finer capability).
  use CadenceWeb, :live_view

  alias Cadence.Missions.Mission

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "New Mission")
     |> assign(:nav_item, :missions)
     |> assign(:slug_auto, true)
     |> assign(:last_auto_slug, "")
     |> assign(:form, empty_form())}
  end

  @impl true
  def handle_event("validate", %{"mission" => params}, socket) do
    display_name = Map.get(params, "display_name", "")
    slug_input = Map.get(params, "slug", "")

    slug_auto =
      socket.assigns.slug_auto and slug_input == socket.assigns.last_auto_slug

    {slug, last_auto_slug} =
      if slug_auto do
        derived = slugify(display_name)
        {derived, derived}
      else
        {slug_input, socket.assigns.last_auto_slug}
      end

    form = to_form(%{"display_name" => display_name, "slug" => slug}, as: :mission)

    {:noreply,
     socket
     |> assign(:form, form)
     |> assign(:slug_auto, slug_auto)
     |> assign(:last_auto_slug, last_auto_slug)}
  end

  @impl true
  def handle_event("save", %{"mission" => params}, socket) do
    display_name = normalize(params["display_name"])
    slug = normalize(params["slug"])

    cond do
      is_nil(display_name) ->
        {:noreply, put_flash(socket, :error, "Display name is required.")}

      is_nil(slug) ->
        {:noreply, put_flash(socket, :error, "Slug is required.")}

      true ->
        mission =
          Mission.new(%{
            organization_id: socket.assigns.current_scope.organization_id,
            slug: slug,
            display_name: display_name
          })

        case Cadence.persist_mission(mission) do
          {:ok, persisted} ->
            {:noreply, push_navigate(socket, to: ~p"/missions/#{persisted.mission_id}")}

          {:error, %Ecto.Changeset{} = changeset} ->
            {:noreply, put_flash(socket, :error, format_errors(changeset))}

          {:error, reason} ->
            {:noreply,
             put_flash(socket, :error, "Failed to create mission: #{inspect(reason)}")}
        end
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6 max-w-xl">
      <div>
        <.link navigate={~p"/missions"} class="text-sm text-primary hover:underline">
          &larr; Missions
        </.link>
        <h1 class="text-2xl font-bold text-base-content mt-1">New Mission</h1>
      </div>

      <.form for={@form} id="mission-form" phx-change="validate" phx-submit="save" class="space-y-4">
        <.input field={@form[:display_name]} type="text" label="Display Name" required />
        <.input field={@form[:slug]} type="text" label="Slug" required />
        <div class="flex items-center gap-3">
          <button type="submit" class="btn btn-primary">Create Mission</button>
          <.link navigate={~p"/missions"} class="btn btn-ghost">Cancel</.link>
        </div>
      </.form>
    </div>
    """
  end

  defp empty_form do
    to_form(%{"display_name" => "", "slug" => ""}, as: :mission)
  end

  defp slugify(value) when is_binary(value) do
    value
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/, "-")
    |> String.trim("-")
  end

  defp normalize(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp normalize(_other), do: nil

  defp format_errors(%Ecto.Changeset{} = changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
    |> Enum.map_join(", ", fn {field, messages} ->
      "#{Phoenix.Naming.humanize(field)} #{Enum.join(messages, ", ")}"
    end)
  end
end
```

- [ ] **Step 4: Add `/missions/new` to the router**

Open `apps/cadence_web/lib/cadence_web/router.ex`. Extend the `:organization` live_session:

```elixir
live_session :organization,
  on_mount: [{CadenceWeb.OrganizationAuth, :require_organization_scope}],
  layout: {CadenceWeb.Layouts, :sidebar} do
  live "/", OrganizationHomeLive, :show
  live "/missions", MissionListLive, :index
  live "/missions/new", MissionNewLive, :new
end
```

- [ ] **Step 5: Run the test to confirm it passes**

```bash
cd apps/cadence_web && mix test test/cadence_web/live/mission_new_live_test.exs
```

Expected: all tests pass. The "flashes an error when display_name is blank" test exercises the `required` HTML attribute — the assertion `html =~ "required"` will match the rendered input's `required` attribute, which is the check we want.

- [ ] **Step 6: Run the full test suite**

```bash
cd apps/cadence_web && mix test
```

Expected: green.

- [ ] **Step 7: Format, credo, compile**

```bash
cd apps/cadence_web && mix format && mix credo --strict && mix compile --warnings-as-errors
```

- [ ] **Step 8: Commit**

```bash
git add apps/cadence_web/lib/cadence_web/live/mission_new_live.ex \
        apps/cadence_web/lib/cadence_web/router.ex \
        apps/cadence_web/test/cadence_web/live/mission_new_live_test.exs
git commit -m "feat(cadence_web): add /missions/new with auto-derived slug"
```

---

### Task 7: `MissionAuth` on_mount hook

**Files:**

- Create: `apps/cadence_web/lib/cadence_web/live/mission_auth.ex`
- Test: `apps/cadence_web/test/cadence_web/live/mission_auth_test.exs`

- [ ] **Step 1: Write the failing test**

Write `apps/cadence_web/test/cadence_web/live/mission_auth_test.exs`:

```elixir
defmodule CadenceWeb.MissionAuthTest do
  use CadenceWeb.ConnCase, async: false

  alias Cadence.Missions.Mission
  alias CadenceWeb.MissionAuth
  alias CadenceWeb.TestFixtures

  defp socket_with_scope_for(org) do
    user = TestFixtures.persist_user!()
    membership = TestFixtures.grant_membership!(user, org)
    {:ok, scope} = Cadence.authenticate_api_token(TestFixtures.member_session_token!(user))
    _ = membership
    %Phoenix.LiveView.Socket{assigns: %{__changed__: %{}, current_scope: scope}}
  end

  defp persist_mission!(org, slug) do
    mission =
      Mission.new(%{
        organization_id: org.organization_id,
        slug: slug,
        display_name: "Mission #{slug}"
      })

    assert {:ok, persisted} = Cadence.persist_mission(mission)
    persisted
  end

  describe "on_mount :load_mission" do
    test "assigns the mission when it belongs to the scope's organization" do
      org = TestFixtures.persist_org!()
      mission = persist_mission!(org, "alpha")
      socket = socket_with_scope_for(org)

      assert {:cont, socket} =
               MissionAuth.on_mount(
                 :load_mission,
                 %{"mission_id" => mission.mission_id},
                 %{},
                 socket
               )

      assert socket.assigns.current_mission.mission_id == mission.mission_id
      assert socket.assigns.nav_context == :mission
    end

    test "raises Phoenix.Router.NoRouteError when mission id does not exist" do
      org = TestFixtures.persist_org!()
      socket = socket_with_scope_for(org)

      assert_raise Phoenix.Router.NoRouteError, fn ->
        MissionAuth.on_mount(:load_mission, %{"mission_id" => "mission_missing"}, %{}, socket)
      end
    end

    test "raises Phoenix.Router.NoRouteError when mission belongs to another org" do
      mine = TestFixtures.persist_org!(slug: "mine")
      other = TestFixtures.persist_org!(slug: "other")
      mission = persist_mission!(other, "alpha")
      socket = socket_with_scope_for(mine)

      assert_raise Phoenix.Router.NoRouteError, fn ->
        MissionAuth.on_mount(:load_mission, %{"mission_id" => mission.mission_id}, %{}, socket)
      end
    end
  end
end
```

- [ ] **Step 2: Run the test to confirm it fails**

```bash
cd apps/cadence_web && mix test test/cadence_web/live/mission_auth_test.exs
```

Expected: compile error / `MissionAuth` not defined.

- [ ] **Step 3: Write the on_mount module**

Create `apps/cadence_web/lib/cadence_web/live/mission_auth.ex`:

```elixir
defmodule CadenceWeb.MissionAuth do
  @moduledoc false

  import Phoenix.Component

  def on_mount(:load_mission, %{"mission_id" => mission_id}, _session, socket) do
    organization_id = socket.assigns.current_scope.organization_id

    case Cadence.fetch_mission(organization_id, mission_id) do
      {:ok, mission} ->
        {:cont,
         socket
         |> assign(:current_mission, mission)
         |> assign(:nav_context, :mission)}

      {:error, _reason} ->
        raise Phoenix.Router.NoRouteError,
          conn: %Plug.Conn{},
          router: CadenceWeb.Router
    end
  end
end
```

- [ ] **Step 4: Run the test to confirm it passes**

```bash
cd apps/cadence_web && mix test test/cadence_web/live/mission_auth_test.exs
```

Expected: all three tests pass.

- [ ] **Step 5: Format, credo, compile**

```bash
cd apps/cadence_web && mix format && mix credo --strict && mix compile --warnings-as-errors
```

- [ ] **Step 6: Commit**

```bash
git add apps/cadence_web/lib/cadence_web/live/mission_auth.ex \
        apps/cadence_web/test/cadence_web/live/mission_auth_test.exs
git commit -m "feat(cadence_web): add MissionAuth on_mount to load org-scoped mission"
```

---

### Task 8: `mission_sidebar` layout template

**Files:**

- Create: `apps/cadence_web/lib/cadence_web/components/layouts/mission_sidebar.html.heex`

Templates under `layouts/` are auto-wired by `embed_templates "layouts/*"` in `CadenceWeb.Layouts` — no module edits required.

- [ ] **Step 1: Create the template**

Write `apps/cadence_web/lib/cadence_web/components/layouts/mission_sidebar.html.heex`:

```heex
<div class="drawer lg:drawer-open">
  <input id="sidebar-drawer" type="checkbox" class="drawer-toggle" />

  <div class="drawer-content flex flex-col">
    <div class="lg:hidden flex items-center justify-between p-4 border-b border-base-300">
      <label for="sidebar-drawer" class="btn btn-ghost btn-sm">
        <span class="hero-bars-3 h-5 w-5"></span>
      </label>
      <div class="flex-1 text-center font-semibold text-sm tracking-wider uppercase">Cadence</div>
      <div class="flex items-center gap-2">
        <%= if @current_scope && @current_scope.user do %>
          <span class="text-xs text-base-content/60">{@current_scope.user.email}</span>
        <% end %>
      </div>
    </div>

    <div class="hidden lg:flex items-center justify-end gap-3 px-4 h-10 border-b border-primary/20 bg-base-200 hud-grid shrink-0">
      <%= if @current_scope && @current_scope.user do %>
        <span class="text-xs text-base-content/60">{@current_scope.user.display_name}</span>
        <span class="text-xs text-base-content/40">({@current_scope.user.email})</span>
      <% end %>
    </div>

    <main class="flex-1 overflow-y-auto bg-base-100">
      <div class="p-6">
        {@inner_content}
      </div>
    </main>
  </div>

  <div class="drawer-side">
    <label for="sidebar-drawer" aria-label="close sidebar" class="drawer-overlay"></label>
    <div
      data-sidebar-collapsible
      class="sidebar-collapsible sidebar-expanded min-h-full bg-base-200 flex flex-col border-r border-primary/20 hud-grid relative"
    >
      <div class="px-3 h-10 flex items-center border-b border-primary/20">
        <.link navigate={~p"/"} class="flex items-center gap-2 text-xs text-base-content/60 hover:text-base-content">
          <span class="hero-chevron-left h-3 w-3"></span>
          <span class="sidebar-label tracking-wide uppercase">
            <%= if @current_scope && @current_scope.organization do %>
              {@current_scope.organization.display_name}
            <% else %>
              Organization
            <% end %>
          </span>
        </.link>
      </div>

      <div class="px-3 pt-4 pb-2 sidebar-expanded-only">
        <p class="text-sm font-bold text-base-content truncate">
          <%= if assigns[:current_mission] do %>
            {@current_mission.display_name}
          <% else %>
            Mission
          <% end %>
        </p>
        <p :if={assigns[:current_mission]} class="text-xs text-base-content/50 font-mono truncate">
          {@current_mission.slug}
        </p>
      </div>

      <nav class="flex-1 overflow-y-auto py-2">
        <ul class="menu menu-sm space-y-0.5">
          <li :if={assigns[:current_mission]}>
            <.link navigate={~p"/missions/#{@current_mission.mission_id}"} class={["flex items-center gap-2 px-3 py-2 text-xs tracking-wide uppercase border-l-2 transition-all", if(assigns[:nav_item] == :mission_overview, do: "bg-primary/10 text-primary border-primary shadow-[inset_0_0_20px_rgba(125,207,255,0.1)]", else: "text-base-content/60 border-transparent hover:bg-primary/5 hover:text-base-content hover:border-primary/30")]}>
              <span class="hero-chart-bar-square h-4 w-4 opacity-80 flex-shrink-0"></span>
              <span class="sidebar-label">Overview</span>
            </.link>
          </li>
        </ul>
      </nav>

      <div class="px-2 py-2 border-t border-primary/20">
        <.form for={%{}} as={:session} action={~p"/session"} method="delete" class="w-full">
          <button type="submit" class="btn btn-ghost btn-sm w-full justify-start gap-2 text-xs uppercase tracking-wide text-base-content/60">
            <span class="hero-arrow-right-start-on-rectangle h-4 w-4 opacity-80"></span>
            <span class="sidebar-label">Sign out</span>
          </button>
        </.form>
      </div>

      <button
        type="button"
        class="sidebar-toggle-btn hidden lg:flex"
        onclick="document.querySelectorAll('[data-sidebar-collapsible]').forEach(function(el){el.classList.toggle('sidebar-expanded');el.classList.toggle('sidebar-collapsed')})"
        title="Toggle sidebar"
      >
        <span class="hero-chevron-left h-3 w-3 toggle-chevron transition-transform"></span>
      </button>
    </div>
  </div>
</div>

<.flash_stack flash={@flash} />
```

- [ ] **Step 2: Compile**

```bash
cd apps/cadence_web && mix compile --warnings-as-errors
```

Expected: clean compile. The template uses `~p` for `/` and `/missions/:mission_id`. `/missions/:mission_id` does not exist yet — we register it in the next task. If compilation complains about unverified routes, proceed to Task 9 before committing.

- [ ] **Step 3: Commit (deferred to end of Task 9)**

Do NOT commit until Task 9 wires up `/missions/:mission_id`. Proceed directly to Task 9.

---

### Task 9: MissionShowLive + `:mission` live_session

**Files:**

- Create: `apps/cadence_web/lib/cadence_web/live/mission_show_live.ex`
- Modify: `apps/cadence_web/lib/cadence_web/router.ex`
- Test: `apps/cadence_web/test/cadence_web/live/mission_show_live_test.exs`

- [ ] **Step 1: Write the failing test**

Write `apps/cadence_web/test/cadence_web/live/mission_show_live_test.exs`:

```elixir
defmodule CadenceWeb.MissionShowLiveTest do
  use CadenceWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias Cadence.Missions.Mission
  alias CadenceWeb.TestFixtures

  defp signed_in_conn do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!(display_name: "Cadence Ops", slug: "cadence-ops")
    _ = TestFixtures.grant_membership!(user, org)
    {TestFixtures.member_conn(user), org}
  end

  defp persist_mission!(org, slug, display_name) do
    mission =
      Mission.new(%{
        organization_id: org.organization_id,
        slug: slug,
        display_name: display_name
      })

    assert {:ok, persisted} = Cadence.persist_mission(mission)
    persisted
  end

  describe "mount" do
    test "renders mission details in the mission sidebar layout" do
      {conn, org} = signed_in_conn()
      mission = persist_mission!(org, "alpha", "Alpha Mission")

      {:ok, _view, html} = live(conn, ~p"/missions/#{mission.mission_id}")

      assert html =~ "Alpha Mission"
      assert html =~ "alpha"
      assert html =~ mission.mission_id
      # Sidebar shows the Overview entry highlighted.
      assert html =~ ~r/border-primary[^"]*".*Overview/s
      # Sidebar back link shows the org name.
      assert html =~ "Cadence Ops"
    end
  end

  describe "authorization" do
    test "404s when mission id is unknown" do
      {conn, _org} = signed_in_conn()

      assert_raise Phoenix.Router.NoRouteError, fn ->
        live(conn, ~p"/missions/mission_unknown")
      end
    end

    test "404s when mission belongs to another org" do
      {conn, _mine} = signed_in_conn()
      other = TestFixtures.persist_org!(slug: "other")
      their_mission = persist_mission!(other, "theirs", "Their Mission")

      assert_raise Phoenix.Router.NoRouteError, fn ->
        live(conn, ~p"/missions/#{their_mission.mission_id}")
      end
    end

    test "unauthenticated request redirects to /sign-in", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/sign-in"}}} =
               live(conn, ~p"/missions/mission_anything")
    end
  end
end
```

- [ ] **Step 2: Run the test to confirm it fails**

```bash
cd apps/cadence_web && mix test test/cadence_web/live/mission_show_live_test.exs
```

Expected: compile error / missing module or route.

- [ ] **Step 3: Write the LiveView**

Create `apps/cadence_web/lib/cadence_web/live/mission_show_live.ex`:

```elixir
defmodule CadenceWeb.MissionShowLive do
  @moduledoc false
  use CadenceWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    mission = socket.assigns.current_mission

    {:ok,
     socket
     |> assign(:page_title, mission.display_name)
     |> assign(:nav_item, :mission_overview)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <div>
        <h1 class="text-2xl font-bold text-base-content">{@current_mission.display_name}</h1>
        <p class="mt-1 text-sm text-base-content/50 font-mono">{@current_mission.slug}</p>
      </div>

      <div class="card bg-base-200">
        <div class="card-body p-6">
          <p class="hud-label mb-4">Overview</p>
          <div class="divide-y divide-base-300">
            <.detail_row label="Mission ID" value={@current_mission.mission_id} mono />
            <.detail_row label="Display name" value={@current_mission.display_name} />
            <.detail_row label="Slug" value={@current_mission.slug} mono />
          </div>
        </div>
      </div>
    </div>
    """
  end
end
```

- [ ] **Step 4: Add `:mission` live_session to the router**

Open `apps/cadence_web/lib/cadence_web/router.ex`. Add a `:mission` live_session AFTER the `:organization` one, inside the same authenticated scope:

```elixir
live_session :mission,
  on_mount: [
    {CadenceWeb.OrganizationAuth, :require_organization_scope},
    {CadenceWeb.MissionAuth, :load_mission}
  ],
  layout: {CadenceWeb.Layouts, :mission_sidebar} do
  live "/missions/:mission_id", MissionShowLive, :show
end
```

- [ ] **Step 5: Run the test to confirm it passes**

```bash
cd apps/cadence_web && mix test test/cadence_web/live/mission_show_live_test.exs
```

Expected: all tests pass.

- [ ] **Step 6: Run the full suite**

```bash
cd apps/cadence_web && mix test
```

Expected: green.

- [ ] **Step 7: Format, credo, compile**

```bash
cd apps/cadence_web && mix format && mix credo --strict && mix compile --warnings-as-errors
```

- [ ] **Step 8: Commit (Tasks 8 + 9 together)**

```bash
git add apps/cadence_web/lib/cadence_web/components/layouts/mission_sidebar.html.heex \
        apps/cadence_web/lib/cadence_web/live/mission_show_live.ex \
        apps/cadence_web/lib/cadence_web/router.ex \
        apps/cadence_web/test/cadence_web/live/mission_show_live_test.exs
git commit -m "feat(cadence_web): add mission sidebar layout and /missions/:mission_id overview"
```

---

### Task 10: Delete `/operator` leftovers

Now that nothing links to `/operator` and no tests expect it, remove the files and routes.

**Files:**

- Delete: `apps/cadence_web/lib/cadence_web/controllers/operator_entry_controller.ex`
- Delete: `apps/cadence_web/lib/cadence_web/controllers/operator_home_controller.ex`
- Delete: `apps/cadence_web/lib/cadence_web/controllers/operator_home_html.ex`
- Delete: `apps/cadence_web/lib/cadence_web/controllers/operator_home_html/` (directory + any templates inside)
- Modify: `apps/cadence_web/lib/cadence_web/router.ex`
- Modify: `apps/cadence_web/lib/cadence_web/components/layouts/sidebar.html.heex`

- [ ] **Step 1: Enumerate files to delete**

Run from the repo root to confirm what exists:

```bash
ls apps/cadence_web/lib/cadence_web/controllers/operator_entry_controller.ex \
   apps/cadence_web/lib/cadence_web/controllers/operator_home_controller.ex \
   apps/cadence_web/lib/cadence_web/controllers/operator_home_html.ex
ls apps/cadence_web/lib/cadence_web/controllers/operator_home_html/
```

Expected: all paths exist.

- [ ] **Step 2: Delete the route from the router**

Open `apps/cadence_web/lib/cadence_web/router.ex`. Remove the line:

```elixir
get "/operator", OperatorHomeController, :show
```

- [ ] **Step 3: Delete the controller and view files**

```bash
git rm apps/cadence_web/lib/cadence_web/controllers/operator_entry_controller.ex
git rm apps/cadence_web/lib/cadence_web/controllers/operator_home_controller.ex
git rm apps/cadence_web/lib/cadence_web/controllers/operator_home_html.ex
git rm -r apps/cadence_web/lib/cadence_web/controllers/operator_home_html/
```

- [ ] **Step 4: Remove the `:operator` branch from the sidebar**

Open `apps/cadence_web/lib/cadence_web/components/layouts/sidebar.html.heex`. Replace the existing catch-all block:

```heex
<% _ -> %>
  <div class="px-3 mb-2 sidebar-expanded-only">
    <span class="hud-label text-base-content/30">Operator</span>
  </div>
  <ul class="menu menu-sm space-y-0.5">
    <li>
      <.link navigate={~p"/operator"} class={["flex items-center gap-2 px-3 py-2 text-xs tracking-wide uppercase border-l-2 transition-all", if(assigns[:nav_item] == :operator_home, do: "bg-primary/10 text-primary border-primary shadow-[inset_0_0_20px_rgba(125,207,255,0.1)]", else: "text-base-content/60 border-transparent hover:bg-primary/5 hover:text-base-content hover:border-primary/30")]}>
        <span class="hero-home h-4 w-4 opacity-80 flex-shrink-0"></span>
        <span class="sidebar-label">Home</span>
      </.link>
    </li>
  </ul>
```

with:

```heex
<% _ -> %>
```

This leaves an empty catch-all that renders nothing — preferable to removing the arrow entirely, which would crash if `@nav_context` ever lands on an unexpected value.

- [ ] **Step 5: Check for any remaining references**

```bash
cd apps/cadence_web && grep -rn "operator" lib test | grep -v "organization_membership" | grep -v "operator@example.com" | grep -vi "operator credentials" || true
```

Expected: no hits for `/operator`, `OperatorEntry`, `OperatorHome`, or `:operator_home`. Matches on `operator@example.com` / `operator credentials` (copy in sign-in prompt / fixture emails) are OK.

- [ ] **Step 6: Run the full suite**

```bash
cd apps/cadence_web && mix test
```

Expected: green.

- [ ] **Step 7: Format, credo, compile**

```bash
cd apps/cadence_web && mix format && mix credo --strict && mix compile --warnings-as-errors
```

Expected: clean.

- [ ] **Step 8: Commit**

```bash
git add apps/cadence_web/lib/cadence_web/router.ex \
        apps/cadence_web/lib/cadence_web/components/layouts/sidebar.html.heex
git commit -m "chore(cadence_web): remove /operator routes, controllers, and sidebar branch"
```

---

## Self-Review Checklist (run before declaring done)

- [ ] Smoke test by hand: `mix phx.server`, log in as a durable member → lands on `/`, sidebar shows Home + Missions, Missions nav + create works, mission show loads under mission sidebar, no-membership user lands on `/no-organization`, admin still lands on `/admin`.
- [ ] `cd apps/cadence_web && mix test` — green.
- [ ] `cd apps/cadence_web && mix credo --strict` — no new violations.
- [ ] `mix compile --warnings-as-errors` — clean across the umbrella.
- [ ] `mix format` applied everywhere.
- [ ] No CSS file has been modified.
- [ ] No new raw HTML form inputs — all fields use `<.input>`.
- [ ] No render function over 50 lines, no file over 400 lines.
- [ ] Table row action uses `<.action_menu>` (mission list).
