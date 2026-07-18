# User Menu Popover Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the plain-text `display_name (email)` label in the top-right of every authenticated shell with a clickable user menu — trigger plus popover panel with identity, inline org switcher, platform-admin shortcut, and sign out.

**Architecture:** A stateless `CadenceWeb.UI.user_menu/1` function component (daisyUI `dropdown dropdown-end`, same primitive as `notifications_bell`) rendered by three shell templates (`user_shell`, `sidebar`, `mission_sidebar`). Data reaches the component via a new LiveView on-mount hook (`:attach_user_menu`) for LiveView-backed pages and a new plug (`AssignUserMenuContext`) for controller-backed pages. Org switching is a form POST to a new `UserSessionController.update/2` action that authorizes against a new `Cadence.Accounts.fetch_user_membership/2` helper and writes the existing `:current_organization_id` session key.

**Tech Stack:** Elixir/Phoenix 1.7 (LiveView + components), Ecto, daisyUI 5 + Tailwind v4, Tokyo Night HUD utility layer. No new JS. No new CSS.

**Spec:** `docs/superpowers/specs/2026-04-19-user-menu-popover-design.md`

---

## File structure

### New files

- `apps/cadence_web/lib/cadence_web/plugs/assign_user_menu_context.ex` — plug that assigns `:user_menu_memberships` and `:user_menu_platform_admin?` on `conn` for controller-rendered pages.
- `apps/cadence_web/test/cadence_web/plugs/assign_user_menu_context_test.exs` — plug tests.
- `apps/cadence_web/test/cadence_web/components/ui_test.exs` — component tests for `user_menu/1` (and backfills one smoke test for `notifications_bell/1` so the module has a home).

### Modified files

- `apps/cadence/lib/cadence/accounts.ex` — add `list_user_memberships/1` and `fetch_user_membership/2`.
- `apps/cadence/lib/cadence.ex` — facade proxies for both helpers.
- `apps/cadence/test/cadence/accounts_test.exs` — tests for new helpers.
- `apps/cadence_web/lib/cadence_web/components/ui.ex` — add `user_menu/1` function component.
- `apps/cadence_web/lib/cadence_web/live/user_auth.ex` — add `on_mount(:attach_user_menu, ...)` hook.
- `apps/cadence_web/test/cadence_web/live/user_auth_test.exs` — cover the new hook.
- `apps/cadence_web/lib/cadence_web/controllers/user_session_controller.ex` — add `update/2` action.
- `apps/cadence_web/test/cadence_web/controllers/user_session_controller_test.exs` — cover the new action (create file if missing).
- `apps/cadence_web/lib/cadence_web/router.ex` — wire `PUT /session/organization` route, attach plug to `:browser` pipeline, attach on-mount hook to live sessions.
- `apps/cadence_web/lib/cadence_web/components/layouts/user_shell.html.heex` — replace email span with `<.user_menu>`.
- `apps/cadence_web/lib/cadence_web/components/layouts/sidebar.html.heex` — replace desktop and mobile identity spans with `<.user_menu>`.
- `apps/cadence_web/lib/cadence_web/components/layouts/mission_sidebar.html.heex` — same as `sidebar`.

### Important deviation from spec (data shape)

The spec describes `memberships` as "a list of `%Cadence.Accounts.OrganizationMembership{}` with the `organization` association loaded." The `OrganizationMembership` domain struct **has no `organization` field** (see `apps/cadence/lib/cadence/accounts/organization_membership.ex`). The existing pattern for "rows with associated data" in `Cadence.Accounts` is a list of maps: `list_organization_members/1` returns `[%{membership: _, user: _}]`.

**Plan decision:** `list_user_memberships/1` returns `[%{membership: OrganizationMembership.t(), organization: Organization.t()}]` — mirrors the existing pattern, no schema changes. The `user_menu/1` attr is renamed to this shape in the implementation. This is an implementation-level concretization of the spec's abstract "association loaded" phrase, not a behavioral change.

---

## Task order rationale

Tasks are ordered so each produces working, committable code independent of later tasks:

1. **Accounts helpers** — pure domain, no web dependencies.
2. **Facade proxies** — trivial delegation.
3. **`UserSessionController.update/2`** — uses the accounts helpers; route + action self-contained.
4. **Router wiring for the switch route** — now the controller is reachable.
5. **`:attach_user_menu` on-mount hook** — uses accounts helpers; testable standalone.
6. **`AssignUserMenuContext` plug** — uses accounts helpers; testable standalone.
7. **Router wiring for the hook + plug** — no shells consume them yet; safe.
8. **`user_menu/1` component** — pure render; no runtime dependencies beyond assigns.
9. **Shell templates** — one at a time, each verifiable independently.
10. **Verification pass** — compile + credo + full test suite per app.

---

## Task 1: `Cadence.Accounts.list_user_memberships/1`

**Files:**
- Modify: `apps/cadence/lib/cadence/accounts.ex`
- Test: `apps/cadence/test/cadence/accounts_test.exs`

- [ ] **Step 1: Write the failing test**

Open `apps/cadence/test/cadence/accounts_test.exs`. Add a new `describe` block at the end of the module (before the final `end`):

```elixir
  describe "list_user_memberships/1" do
    test "returns active memberships with organizations, ordered by organization display_name" do
      user = persist_user!()
      org_b = Cadence.persist_organization!(display_name: "Beta Space")
      org_a = Cadence.persist_organization!(display_name: "Alpha Space")
      grant_membership!(user, org_a)
      grant_membership!(user, org_b)

      result = Cadence.Accounts.list_user_memberships(user.user_id)

      assert [
               %{membership: m1, organization: %{display_name: "Alpha Space"}},
               %{membership: m2, organization: %{display_name: "Beta Space"}}
             ] = result

      assert m1.user_id == user.user_id
      assert m2.user_id == user.user_id
      assert m1.lifecycle_state == :active
      assert m2.lifecycle_state == :active
    end

    test "excludes revoked memberships" do
      user = persist_user!()
      org_active = Cadence.persist_organization!(display_name: "Active Co")
      org_revoked = Cadence.persist_organization!(display_name: "Revoked Co")
      grant_membership!(user, org_active)
      grant_membership!(user, org_revoked, lifecycle_state: :revoked)

      result = Cadence.Accounts.list_user_memberships(user.user_id)

      assert [%{organization: %{display_name: "Active Co"}}] = result
    end

    test "returns empty list for a user with no memberships" do
      user = persist_user!()
      assert Cadence.Accounts.list_user_memberships(user.user_id) == []
    end
  end
```

The helpers `persist_user!`, `Cadence.persist_organization!`, and `grant_membership!` must exist in the test's scope. Check the top of `apps/cadence/test/cadence/accounts_test.exs` — if it does not already import or define them, add these helper adapters at the bottom of the module before the final `end`:

```elixir
  defp persist_user!(opts \\ []) do
    email = Keyword.get(opts, :email, "user-#{System.unique_integer([:positive])}@example.com")
    display_name = Keyword.get(opts, :display_name, "Test User")

    user =
      Cadence.Accounts.User.new(%{
        email: email,
        display_name: display_name,
        confirmed_at: DateTime.utc_now(),
        lifecycle_state: :active
      })

    {:ok, _row} =
      Cadence.Repo.insert(Cadence.Accounts.UserRow.changeset(user))

    user
  end

  defp grant_membership!(user, organization, opts \\ []) do
    membership =
      Cadence.Accounts.OrganizationMembership.new(%{
        user_id: user.user_id,
        organization_id: organization.organization_id,
        role: Keyword.get(opts, :role, :member),
        lifecycle_state: Keyword.get(opts, :lifecycle_state, :active)
      })

    {:ok, _row} =
      Cadence.Repo.insert(
        Cadence.Accounts.OrganizationMembershipRow.changeset(membership)
      )

    membership
  end
```

For `Cadence.persist_organization!`, check whether the `Cadence` facade already exposes a bang version. If it does not, add this call inline in the tests:

```elixir
{:ok, org_a} = Cadence.persist_organization(Cadence.Organizations.Organization.new(%{display_name: "Alpha Space", slug: "alpha-#{System.unique_integer([:positive])}"}))
```

…and drop the `persist_organization!` shorthand, rewriting the three test setups accordingly. **Do not add a new bang helper to the facade in this task** — scope discipline.

- [ ] **Step 2: Run the tests to verify they fail**

From the project root:

```bash
cd apps/cadence && mix test test/cadence/accounts_test.exs --only line:<line_number_of_first_new_test>
```

Expected: compilation passes (test module parses), but tests **fail** with `** (UndefinedFunctionError) function Cadence.Accounts.list_user_memberships/1 is undefined`.

- [ ] **Step 3: Implement `list_user_memberships/1`**

Open `apps/cadence/lib/cadence/accounts.ex`. Confirm the context-owned row aliases are available:

Look at the aliases at the top of the file. `OrganizationMembershipRow` now
lives under `Cadence.Accounts`, while `OrganizationRow` lives under
`Cadence.Organizations`:

```elixir
  alias Cadence.Accounts.OrganizationMembershipRow
  alias Cadence.Organizations.OrganizationRow
```

Then add the public function immediately after `preferred_organization_membership/2` (ends around line 250). The `active_membership_query/1` private helper already exists around line 905; reuse it by joining on `OrganizationRow`:

```elixir
  @spec list_user_memberships(binary()) :: [
          %{
            membership: OrganizationMembership.t(),
            organization: Cadence.Organizations.Organization.t()
          }
        ]
  def list_user_memberships(user_id) when is_binary(user_id) do
    user_id
    |> active_membership_query()
    |> join(:inner, [membership_row], organization_row in OrganizationRow,
      on: membership_row.organization_id == organization_row.organization_id
    )
    |> order_by([_membership_row, organization_row], asc: organization_row.display_name)
    |> select([membership_row, organization_row], {membership_row, organization_row})
    |> Repo.all()
    |> Enum.map(fn {membership_row, organization_row} ->
      %{
        membership: OrganizationMembershipRow.to_domain(membership_row),
        organization: OrganizationRow.to_domain(organization_row)
      }
    end)
  end
```

Note: we override the `order_by` from `active_membership_query/1` by calling `order_by/3` again; Ecto replaces the previous ordering when a new one is set on the same query. If that assumption is wrong at runtime (Ecto appends rather than replaces for `order_by`), restructure to build the query inline without reusing `active_membership_query/1`:

```elixir
  def list_user_memberships(user_id) when is_binary(user_id) do
    OrganizationMembershipRow
    |> where(
      [membership_row],
      membership_row.user_id == ^user_id and
        membership_row.lifecycle_state == ^Atom.to_string(:active)
    )
    |> join(:inner, [membership_row], organization_row in OrganizationRow,
      on: membership_row.organization_id == organization_row.organization_id
    )
    |> order_by([_membership_row, organization_row], asc: organization_row.display_name)
    |> Repo.all()
    |> Enum.map(fn membership_row ->
      organization_row = _load_org_row_via_join(membership_row)

      %{
        membership: OrganizationMembershipRow.to_domain(membership_row),
        organization: OrganizationRow.to_domain(organization_row)
      }
    end)
  end
```

Prefer the first (reuse + override) form; fall back to the inline form only if the override approach produces double ordering at query time.

- [ ] **Step 4: Run the tests to verify they pass**

```bash
cd apps/cadence && mix test test/cadence/accounts_test.exs
```

Expected: all `list_user_memberships/1` tests pass. No other tests regress.

- [ ] **Step 5: Run format + compile + credo gates**

```bash
cd apps/cadence && mix format lib/cadence/accounts.ex test/cadence/accounts_test.exs
cd apps/cadence && mix compile --warnings-as-errors
cd apps/cadence && mix credo --strict lib/cadence/accounts.ex
```

Expected: no output from format (file already in shape), clean compile, no credo findings for the touched file.

- [ ] **Step 6: Commit**

```bash
git add apps/cadence/lib/cadence/accounts.ex apps/cadence/test/cadence/accounts_test.exs
git commit -m "feat(cadence): add Accounts.list_user_memberships/1"
```

---

## Task 2: `Cadence.Accounts.fetch_user_membership/2`

**Files:**
- Modify: `apps/cadence/lib/cadence/accounts.ex`
- Test: `apps/cadence/test/cadence/accounts_test.exs`

- [ ] **Step 1: Write the failing tests**

Append to `apps/cadence/test/cadence/accounts_test.exs` after the `list_user_memberships/1` describe block:

```elixir
  describe "fetch_user_membership/2" do
    test "returns {:ok, membership} for an active membership" do
      user = persist_user!()
      org = Cadence.persist_organization!(display_name: "Fetch Co")
      _ = grant_membership!(user, org)

      assert {:ok, membership} =
               Cadence.Accounts.fetch_user_membership(user.user_id, org.organization_id)

      assert membership.user_id == user.user_id
      assert membership.organization_id == org.organization_id
      assert membership.lifecycle_state == :active
    end

    test "returns {:error, :not_found} for a revoked membership" do
      user = persist_user!()
      org = Cadence.persist_organization!(display_name: "Revoked")
      _ = grant_membership!(user, org, lifecycle_state: :revoked)

      assert {:error, :not_found} =
               Cadence.Accounts.fetch_user_membership(user.user_id, org.organization_id)
    end

    test "returns {:error, :not_found} when the user is not a member" do
      user = persist_user!()
      org = Cadence.persist_organization!(display_name: "Empty")

      assert {:error, :not_found} =
               Cadence.Accounts.fetch_user_membership(user.user_id, org.organization_id)
    end

    test "returns {:error, :not_found} for a mismatched user_id" do
      user_a = persist_user!()
      user_b = persist_user!()
      org = Cadence.persist_organization!(display_name: "Cross User")
      _ = grant_membership!(user_a, org)

      assert {:error, :not_found} =
               Cadence.Accounts.fetch_user_membership(user_b.user_id, org.organization_id)
    end
  end
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
cd apps/cadence && mix test test/cadence/accounts_test.exs
```

Expected: new tests fail with `** (UndefinedFunctionError) function Cadence.Accounts.fetch_user_membership/2 is undefined`.

- [ ] **Step 3: Implement `fetch_user_membership/2`**

Add immediately after `list_user_memberships/1`:

```elixir
  @spec fetch_user_membership(binary(), binary()) ::
          {:ok, OrganizationMembership.t()} | {:error, :not_found}
  def fetch_user_membership(user_id, organization_id)
      when is_binary(user_id) and is_binary(organization_id) do
    user_id
    |> active_membership_query()
    |> where([row], row.organization_id == ^organization_id)
    |> Repo.one()
    |> case do
      %OrganizationMembershipRow{} = row -> {:ok, OrganizationMembershipRow.to_domain(row)}
      nil -> {:error, :not_found}
    end
  end
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
cd apps/cadence && mix test test/cadence/accounts_test.exs
```

Expected: all four new tests pass.

- [ ] **Step 5: Format + compile + credo**

```bash
cd apps/cadence && mix format lib/cadence/accounts.ex test/cadence/accounts_test.exs
cd apps/cadence && mix compile --warnings-as-errors
cd apps/cadence && mix credo --strict lib/cadence/accounts.ex
```

- [ ] **Step 6: Commit**

```bash
git add apps/cadence/lib/cadence/accounts.ex apps/cadence/test/cadence/accounts_test.exs
git commit -m "feat(cadence): add Accounts.fetch_user_membership/2"
```

---

## Task 3: Facade proxies in `Cadence`

**Files:**
- Modify: `apps/cadence/lib/cadence.ex`

- [ ] **Step 1: Add the proxies**

Open `apps/cadence/lib/cadence.ex`. Locate `list_organization_members/1` (around line 204). Add the new proxies immediately after it:

```elixir
  @spec list_user_memberships(binary()) :: [
          %{
            membership: Cadence.Accounts.OrganizationMembership.t(),
            organization: Cadence.Organizations.Organization.t()
          }
        ]
  def list_user_memberships(user_id) when is_binary(user_id) do
    Accounts.list_user_memberships(user_id)
  end

  @spec fetch_user_membership(binary(), binary()) ::
          {:ok, Cadence.Accounts.OrganizationMembership.t()} | {:error, :not_found}
  def fetch_user_membership(user_id, organization_id)
      when is_binary(user_id) and is_binary(organization_id) do
    Accounts.fetch_user_membership(user_id, organization_id)
  end
```

- [ ] **Step 2: Verify the `Accounts` alias already exists**

Confirm line 1-20 of `apps/cadence/lib/cadence.ex` contains `alias Cadence.Accounts` (or equivalent). If not, the existing `list_organization_members/1` proxy would not compile, so it is already there.

- [ ] **Step 3: Compile to verify**

```bash
cd apps/cadence && mix compile --warnings-as-errors
```

Expected: clean compile.

- [ ] **Step 4: Format + credo**

```bash
cd apps/cadence && mix format lib/cadence.ex
cd apps/cadence && mix credo --strict lib/cadence.ex
```

- [ ] **Step 5: Commit**

```bash
git add apps/cadence/lib/cadence.ex
git commit -m "feat(cadence): expose list_user_memberships and fetch_user_membership on facade"
```

---

## Task 4: `UserSessionController.update/2` — switch organization action

**Files:**
- Modify: `apps/cadence_web/lib/cadence_web/controllers/user_session_controller.ex`
- Modify: `apps/cadence_web/lib/cadence_web/router.ex`
- Test: `apps/cadence_web/test/cadence_web/controllers/user_session_controller_test.exs` (create if missing)

- [ ] **Step 1: Create (or extend) the controller test file**

Check whether `apps/cadence_web/test/cadence_web/controllers/user_session_controller_test.exs` exists. If not, create it with this content:

```elixir
defmodule CadenceWeb.UserSessionControllerTest do
  use CadenceWeb.ConnCase, async: false

  alias CadenceWeb.TestFixtures

  describe "PUT /session/organization" do
    test "switches the session current_organization_id for an active membership", %{conn: conn} do
      user = TestFixtures.persist_user!()
      org_a = TestFixtures.persist_org!(display_name: "Org A")
      org_b = TestFixtures.persist_org!(display_name: "Org B")
      _ = TestFixtures.grant_membership!(user, org_a)
      _ = TestFixtures.grant_membership!(user, org_b)

      conn = TestFixtures.member_conn(user)

      conn = put(conn, ~p"/session/organization", %{"organization_id" => org_b.organization_id})

      assert redirected_to(conn) == ~p"/"
      assert get_session(conn, :current_organization_id) == org_b.organization_id
    end

    test "rejects the switch when the user is not an active member of the target org", %{conn: conn} do
      user = TestFixtures.persist_user!()
      org_a = TestFixtures.persist_org!(display_name: "Org A")
      other_org = TestFixtures.persist_org!(display_name: "Not Mine")
      _ = TestFixtures.grant_membership!(user, org_a)

      conn = TestFixtures.member_conn(user)

      conn =
        put(conn, ~p"/session/organization", %{"organization_id" => other_org.organization_id})

      assert redirected_to(conn) == ~p"/"
      refute get_session(conn, :current_organization_id) == other_org.organization_id

      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "organization"
    end

    test "redirects unauthenticated requests to /sign-in", %{conn: conn} do
      conn = put(conn, ~p"/session/organization", %{"organization_id" => "org-anything"})

      assert redirected_to(conn) == ~p"/sign-in"
    end
  end
end
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
cd apps/cadence_web && mix test test/cadence_web/controllers/user_session_controller_test.exs
```

Expected: compile fails or tests fail with route-not-found (`Phoenix.Router.NoRouteError` from `put/3` attempting `PUT /session/organization`). Proceed past compile failure — the next steps fix this.

- [ ] **Step 3: Add the route to `apps/cadence_web/lib/cadence_web/router.ex`**

Locate the scope block containing `delete "/session", UserSessionController, :delete` (around line 48-52). Add the new route on the line directly after the `delete "/session"` line:

```elixir
    delete "/session", UserSessionController, :delete
    put "/session/organization", UserSessionController, :update
    get "/no-organization", NoOrganizationController, :show
```

The new route lives inside the `pipe_through [:browser, :require_authenticated_scope]` scope, so unauthenticated requests are already redirected to `/sign-in` by the existing plug — no extra work there.

- [ ] **Step 4: Add the `update/2` action to the controller**

Open `apps/cadence_web/lib/cadence_web/controllers/user_session_controller.ex`. Add this action after `delete/2` (around line 33):

```elixir
  def update(conn, %{"organization_id" => organization_id}) when is_binary(organization_id) do
    user_id = conn.assigns.current_scope.user.user_id

    case Cadence.fetch_user_membership(user_id, organization_id) do
      {:ok, _membership} ->
        conn
        |> put_session(:current_organization_id, organization_id)
        |> redirect(to: ~p"/")

      {:error, :not_found} ->
        conn
        |> put_flash(:error, "You do not have access to that organization.")
        |> redirect(to: ~p"/")
    end
  end

  def update(conn, _params) do
    conn
    |> put_flash(:error, "Select a valid organization.")
    |> redirect(to: ~p"/")
  end
```

- [ ] **Step 5: Run the tests to verify they pass**

```bash
cd apps/cadence_web && mix test test/cadence_web/controllers/user_session_controller_test.exs
```

Expected: all three tests pass.

- [ ] **Step 6: Format + compile + credo**

```bash
cd apps/cadence_web && mix format lib/cadence_web/controllers/user_session_controller.ex lib/cadence_web/router.ex test/cadence_web/controllers/user_session_controller_test.exs
cd apps/cadence_web && mix compile --warnings-as-errors
cd apps/cadence_web && mix credo --strict lib/cadence_web/controllers/user_session_controller.ex
```

- [ ] **Step 7: Commit**

```bash
git add apps/cadence_web/lib/cadence_web/controllers/user_session_controller.ex apps/cadence_web/lib/cadence_web/router.ex apps/cadence_web/test/cadence_web/controllers/user_session_controller_test.exs
git commit -m "feat(cadence_web): PUT /session/organization switches the active org"
```

---

## Task 5: `UserAuth.attach_user_menu` on-mount hook

**Files:**
- Modify: `apps/cadence_web/lib/cadence_web/live/user_auth.ex`
- Test: `apps/cadence_web/test/cadence_web/live/user_auth_test.exs`

- [ ] **Step 1: Write failing tests**

Open `apps/cadence_web/test/cadence_web/live/user_auth_test.exs`. Add this describe block (append if the file exists; the file pattern should already use `CadenceWeb.ConnCase`):

```elixir
  describe "on_mount(:attach_user_menu, ...)" do
    test "assigns empty memberships and platform_admin? false when no user in scope" do
      socket = %Phoenix.LiveView.Socket{assigns: %{__changed__: %{}, current_scope: nil}}

      assert {:cont, updated} =
               CadenceWeb.UserAuth.on_mount(:attach_user_menu, %{}, %{}, socket)

      assert updated.assigns.user_menu_memberships == []
      assert updated.assigns.user_menu_platform_admin? == false
    end

    test "assigns memberships for an authenticated user" do
      user = CadenceWeb.TestFixtures.persist_user!()
      org = CadenceWeb.TestFixtures.persist_org!(display_name: "Memberships Co")
      _ = CadenceWeb.TestFixtures.grant_membership!(user, org)

      {:ok, scope} =
        Cadence.authenticate_api_token(CadenceWeb.TestFixtures.member_session_token!(user))

      socket = %Phoenix.LiveView.Socket{
        assigns: %{__changed__: %{}, current_scope: scope}
      }

      assert {:cont, updated} =
               CadenceWeb.UserAuth.on_mount(:attach_user_menu, %{}, %{}, socket)

      assert [%{membership: membership, organization: loaded_org}] =
               updated.assigns.user_menu_memberships

      assert membership.user_id == user.user_id
      assert loaded_org.organization_id == org.organization_id
      assert updated.assigns.user_menu_platform_admin? == false
    end

    test "sets platform_admin? true when user scope includes :platform_admin capability" do
      user = CadenceWeb.TestFixtures.persist_user!(capabilities: [:platform_admin])

      {:ok, scope} =
        Cadence.authenticate_api_token(CadenceWeb.TestFixtures.member_session_token!(user))

      socket = %Phoenix.LiveView.Socket{assigns: %{__changed__: %{}, current_scope: scope}}

      assert {:cont, updated} =
               CadenceWeb.UserAuth.on_mount(:attach_user_menu, %{}, %{}, socket)

      assert updated.assigns.user_menu_platform_admin? == true
    end
  end
```

If `user_auth_test.exs` does not yet exist, create it with the standard `CadenceWeb.ConnCase` preamble:

```elixir
defmodule CadenceWeb.UserAuthTest do
  use CadenceWeb.ConnCase, async: false

  # describe blocks go here
end
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
cd apps/cadence_web && mix test test/cadence_web/live/user_auth_test.exs
```

Expected: `** (FunctionClauseError)` from `CadenceWeb.UserAuth.on_mount/4` — there is no clause for `:attach_user_menu`.

- [ ] **Step 3: Implement the hook**

Open `apps/cadence_web/lib/cadence_web/live/user_auth.ex`. Add these two new clauses at the bottom of the module, before the final `end`:

```elixir
  def on_mount(:attach_user_menu, _params, _session, socket) do
    {:cont,
     socket
     |> Phoenix.Component.assign(:user_menu_memberships, memberships_for(socket))
     |> Phoenix.Component.assign(:user_menu_platform_admin?, platform_admin?(socket))}
  end

  defp memberships_for(%{assigns: %{current_scope: %Scope{user: %{user_id: user_id}}}})
       when is_binary(user_id) do
    Cadence.list_user_memberships(user_id)
  end

  defp memberships_for(_socket), do: []

  defp platform_admin?(%{assigns: %{current_scope: %Scope{capabilities: capabilities}}})
       when not is_nil(capabilities) do
    MapSet.member?(capabilities, :platform_admin)
  end

  defp platform_admin?(_socket), do: false
```

The `Scope` alias already exists at the top of the module (line 6). `Phoenix.Component` is used fully-qualified because the module currently only imports `Phoenix.LiveView`.

- [ ] **Step 4: Run the tests to verify they pass**

```bash
cd apps/cadence_web && mix test test/cadence_web/live/user_auth_test.exs
```

Expected: all three new tests pass.

- [ ] **Step 5: Format + compile + credo**

```bash
cd apps/cadence_web && mix format lib/cadence_web/live/user_auth.ex test/cadence_web/live/user_auth_test.exs
cd apps/cadence_web && mix compile --warnings-as-errors
cd apps/cadence_web && mix credo --strict lib/cadence_web/live/user_auth.ex
```

- [ ] **Step 6: Commit**

```bash
git add apps/cadence_web/lib/cadence_web/live/user_auth.ex apps/cadence_web/test/cadence_web/live/user_auth_test.exs
git commit -m "feat(cadence_web): add :attach_user_menu on_mount hook"
```

---

## Task 6: `AssignUserMenuContext` plug

**Files:**
- Create: `apps/cadence_web/lib/cadence_web/plugs/assign_user_menu_context.ex`
- Create: `apps/cadence_web/test/cadence_web/plugs/assign_user_menu_context_test.exs`

- [ ] **Step 1: Write failing tests**

Create `apps/cadence_web/test/cadence_web/plugs/assign_user_menu_context_test.exs`:

```elixir
defmodule CadenceWeb.Plugs.AssignUserMenuContextTest do
  use CadenceWeb.ConnCase, async: false

  alias CadenceWeb.Plugs.AssignUserMenuContext
  alias CadenceWeb.TestFixtures

  describe "call/2" do
    test "assigns empty memberships and false platform_admin when no scope", %{conn: conn} do
      conn = assign(conn, :current_scope, nil)
      updated = AssignUserMenuContext.call(conn, [])

      assert updated.assigns.user_menu_memberships == []
      assert updated.assigns.user_menu_platform_admin? == false
    end

    test "assigns memberships for an authenticated user", %{conn: _conn} do
      user = TestFixtures.persist_user!()
      org = TestFixtures.persist_org!(display_name: "Plug Co")
      _ = TestFixtures.grant_membership!(user, org)

      conn = TestFixtures.member_conn(user)
      conn = CadenceWeb.Plugs.FetchBrowserCurrentScope.call(conn, [])

      updated = AssignUserMenuContext.call(conn, [])

      assert [%{organization: loaded_org}] = updated.assigns.user_menu_memberships
      assert loaded_org.organization_id == org.organization_id
      assert updated.assigns.user_menu_platform_admin? == false
    end

    test "marks platform admins", %{conn: _conn} do
      user = TestFixtures.persist_user!(capabilities: [:platform_admin])

      conn = TestFixtures.member_conn(user)
      conn = CadenceWeb.Plugs.FetchBrowserCurrentScope.call(conn, [])

      updated = AssignUserMenuContext.call(conn, [])

      assert updated.assigns.user_menu_platform_admin? == true
    end
  end
end
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
cd apps/cadence_web && mix test test/cadence_web/plugs/assign_user_menu_context_test.exs
```

Expected: `** (UndefinedFunctionError) function CadenceWeb.Plugs.AssignUserMenuContext.call/2 is undefined`.

- [ ] **Step 3: Create the plug**

Create `apps/cadence_web/lib/cadence_web/plugs/assign_user_menu_context.ex`:

```elixir
defmodule CadenceWeb.Plugs.AssignUserMenuContext do
  @moduledoc """
  Assigns `:user_menu_memberships` and `:user_menu_platform_admin?` on the
  connection so the `CadenceWeb.UI.user_menu/1` component can render for
  controller-backed pages.
  """

  import Plug.Conn

  alias Cadence.Auth.Scope

  def init(opts), do: opts

  def call(conn, _opts) do
    conn
    |> assign(:user_menu_memberships, memberships_for(conn))
    |> assign(:user_menu_platform_admin?, platform_admin?(conn))
  end

  defp memberships_for(%Plug.Conn{assigns: %{current_scope: %Scope{user: %{user_id: user_id}}}})
       when is_binary(user_id) do
    Cadence.list_user_memberships(user_id)
  end

  defp memberships_for(_conn), do: []

  defp platform_admin?(%Plug.Conn{
         assigns: %{current_scope: %Scope{capabilities: capabilities}}
       })
       when not is_nil(capabilities) do
    MapSet.member?(capabilities, :platform_admin)
  end

  defp platform_admin?(_conn), do: false
end
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
cd apps/cadence_web && mix test test/cadence_web/plugs/assign_user_menu_context_test.exs
```

Expected: all three tests pass.

- [ ] **Step 5: Format + compile + credo**

```bash
cd apps/cadence_web && mix format lib/cadence_web/plugs/assign_user_menu_context.ex test/cadence_web/plugs/assign_user_menu_context_test.exs
cd apps/cadence_web && mix compile --warnings-as-errors
cd apps/cadence_web && mix credo --strict lib/cadence_web/plugs/assign_user_menu_context.ex
```

- [ ] **Step 6: Commit**

```bash
git add apps/cadence_web/lib/cadence_web/plugs/assign_user_menu_context.ex apps/cadence_web/test/cadence_web/plugs/assign_user_menu_context_test.exs
git commit -m "feat(cadence_web): add AssignUserMenuContext plug"
```

---

## Task 7: Wire hook and plug into router

**Files:**
- Modify: `apps/cadence_web/lib/cadence_web/router.ex`

- [ ] **Step 1: Attach the plug to the `:browser` pipeline**

Locate the `pipeline :browser` block in `apps/cadence_web/lib/cadence_web/router.ex` (lines 4-12). The `AssignUserMenuContext` plug must run **after** `FetchBrowserCurrentScope` because it reads `conn.assigns.current_scope`. Append it:

```elixir
  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {CadenceWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug CadenceWeb.Plugs.FetchBrowserCurrentScope
    plug CadenceWeb.Plugs.AssignUserMenuContext
  end
```

- [ ] **Step 2: Attach the on-mount hook to every authenticated `live_session`**

In the same file, locate each `live_session` block inside the `scope "/", CadenceWeb do` that pipes through `[:browser, :require_authenticated_scope]`. There are four: `:organization`, `:mission`, `:user`, and `:admin`. Each has an `on_mount: [...]` option.

Append `{CadenceWeb.UserAuth, :attach_user_menu}` to each `on_mount` list. **Order matters**: it must come after `:require_user_scope`, `:require_organization_scope`, `:require_platform_admin`, or `:load_mission`, because those are responsible for assigning `current_scope`. Place it at the end of each list.

```elixir
    live_session :organization,
      on_mount: [
        {CadenceWeb.OrganizationAuth, :require_organization_scope},
        {CadenceWeb.UserAuth, :attach_user_menu}
      ],
      layout: {CadenceWeb.Layouts, :sidebar} do
      live "/", OrganizationHomeLive, :show
      live "/missions", MissionListLive, :index
      live "/missions/new", MissionNewLive, :new
    end

    live_session :mission,
      on_mount: [
        {CadenceWeb.OrganizationAuth, :require_organization_scope},
        {CadenceWeb.MissionAuth, :load_mission},
        {CadenceWeb.UserAuth, :attach_user_menu}
      ],
      layout: {CadenceWeb.Layouts, :mission_sidebar} do
      live "/missions/:mission_id", MissionShowLive, :show
    end

    live_session :user,
      on_mount: [
        {CadenceWeb.UserAuth, :require_user_scope},
        {CadenceWeb.UserAuth, :attach_notifications_bell},
        {CadenceWeb.UserAuth, :attach_user_menu}
      ],
      layout: {CadenceWeb.Layouts, :user_shell} do
      live "/notifications", NotificationsLive, :index
    end

    live_session :admin,
      on_mount: [
        {CadenceWeb.AdminAuth, :require_platform_admin},
        {CadenceWeb.UserAuth, :attach_user_menu}
      ],
      layout: {CadenceWeb.Layouts, :sidebar} do
      live "/admin", AdminHomeLive, :index
      live "/admin/organizations", AdminOrganizationListLive, :index
      live "/admin/organizations/new", AdminOrganizationNewLive, :new
      live "/admin/organizations/:org_id", AdminOrganizationShowLive, :show
      live "/admin/organizations/:org_id/invite", AdminOrganizationInviteLive, :invite
    end
```

- [ ] **Step 3: Run the full suite to confirm nothing regressed**

```bash
cd apps/cadence_web && mix test
```

Expected: all tests pass. The shells do not yet consume the new assigns, so the hooks are effectively inert from a rendering standpoint; but existing LiveView tests still mount through these sessions and will exercise the hooks for compilation.

- [ ] **Step 4: Format + compile + credo**

```bash
cd apps/cadence_web && mix format lib/cadence_web/router.ex
cd apps/cadence_web && mix compile --warnings-as-errors
cd apps/cadence_web && mix credo --strict lib/cadence_web/router.ex
```

- [ ] **Step 5: Commit**

```bash
git add apps/cadence_web/lib/cadence_web/router.ex
git commit -m "feat(cadence_web): wire user menu context into browser + live sessions"
```

---

## Task 8: `user_menu/1` component — identity + sign out (minimum viable render)

**Files:**
- Modify: `apps/cadence_web/lib/cadence_web/components/ui.ex`
- Create: `apps/cadence_web/test/cadence_web/components/ui_test.exs`

- [ ] **Step 1: Create the component test file with the first test**

Create `apps/cadence_web/test/cadence_web/components/ui_test.exs`:

```elixir
defmodule CadenceWeb.UITest do
  use CadenceWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias CadenceWeb.UI

  defp scope(user, organization \\ nil) do
    %Cadence.Auth.Scope{user: user, organization: organization, capabilities: MapSet.new()}
  end

  defp user_fixture(attrs \\ %{}) do
    Cadence.Accounts.User.new(
      Map.merge(
        %{
          email: "jane@example.com",
          display_name: "Jane Rost"
        },
        attrs
      )
    )
  end

  describe "user_menu/1" do
    test "renders display_name as trigger text" do
      html =
        render_component(&UI.user_menu/1,
          scope: scope(user_fixture()),
          memberships: [],
          platform_admin?: false
        )

      assert html =~ "Jane Rost"
    end

    test "renders identity block with name and email" do
      html =
        render_component(&UI.user_menu/1,
          scope: scope(user_fixture()),
          memberships: [],
          platform_admin?: false
        )

      assert html =~ "Jane Rost"
      assert html =~ "jane@example.com"
    end

    test "always renders sign-out form targeting DELETE /session" do
      html =
        render_component(&UI.user_menu/1,
          scope: scope(user_fixture()),
          memberships: [],
          platform_admin?: false
        )

      assert html =~ ~s|action="/session"|
      assert html =~ ~s|name="_method" value="delete"|
      assert html =~ "Sign out"
    end
  end
end
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
cd apps/cadence_web && mix test test/cadence_web/components/ui_test.exs
```

Expected: compile fails or `** (UndefinedFunctionError) function CadenceWeb.UI.user_menu/1 is undefined`.

- [ ] **Step 3: Implement the minimum-viable `user_menu/1`**

Open `apps/cadence_web/lib/cadence_web/components/ui.ex`. Add the component after `notifications_bell/1` (after the `format_count` private helpers at the bottom, but before the final module `end`):

```elixir
  @doc """
  Top-right user menu — trigger plus popover panel with identity, org context,
  platform-admin shortcut (when applicable), and sign out.

  Attrs:
    * `scope` — `%Cadence.Auth.Scope{}` with `:user` and optional `:organization`
    * `memberships` — list of `%{membership: OrganizationMembership.t(), organization: Organization.t()}`
    * `platform_admin?` — boolean
  """
  attr :scope, :any, required: true
  attr :memberships, :list, default: []
  attr :platform_admin?, :boolean, default: false

  def user_menu(assigns) do
    ~H"""
    <div class="dropdown dropdown-end">
      <button
        type="button"
        tabindex="0"
        class="btn btn-ghost btn-sm gap-1"
        aria-haspopup="menu"
      >
        <span class="text-xs text-base-content/60">{@scope.user.display_name}</span>
        <span class="hero-chevron-down h-3 w-3 opacity-60 transition-transform"></span>
      </button>

      <div
        tabindex="0"
        role="menu"
        class="dropdown-content menu bg-base-200 z-[100] w-72 p-2 shadow-lg border border-primary/20"
      >
        <li role="presentation" class="px-3 py-2">
          <p class="text-sm font-semibold text-base-content">{@scope.user.display_name}</p>
          <p class="text-xs text-base-content/50 truncate">{@scope.user.email}</p>
        </li>

        <li role="presentation" class="border-t border-primary/10 mt-1 pt-1">
          <.form for={%{}} as={:session} action={~p"/session"} method="delete">
            <button
              type="submit"
              role="menuitem"
              class="flex w-full items-center gap-2 px-3 py-2 text-xs tracking-wide uppercase text-base-content/70 hover:text-primary"
            >
              <span class="hero-arrow-right-start-on-rectangle h-4 w-4 opacity-80"></span>
              Sign out
            </button>
          </.form>
        </li>
      </div>
    </div>
    """
  end
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
cd apps/cadence_web && mix test test/cadence_web/components/ui_test.exs
```

Expected: all three tests pass.

- [ ] **Step 5: Format + compile + credo**

```bash
cd apps/cadence_web && mix format lib/cadence_web/components/ui.ex test/cadence_web/components/ui_test.exs
cd apps/cadence_web && mix compile --warnings-as-errors
cd apps/cadence_web && mix credo --strict lib/cadence_web/components/ui.ex
```

- [ ] **Step 6: Commit**

```bash
git add apps/cadence_web/lib/cadence_web/components/ui.ex apps/cadence_web/test/cadence_web/components/ui_test.exs
git commit -m "feat(cadence_web): add user_menu/1 component — identity + sign out"
```

---

## Task 9: `user_menu/1` — organization block (all three shapes)

**Files:**
- Modify: `apps/cadence_web/lib/cadence_web/components/ui.ex`
- Modify: `apps/cadence_web/test/cadence_web/components/ui_test.exs`

- [ ] **Step 1: Add failing tests for each shape**

Append inside the `describe "user_menu/1"` block in `apps/cadence_web/test/cadence_web/components/ui_test.exs`:

```elixir
    defp org_fixture(attrs \\ %{}) do
      Cadence.Organizations.Organization.new(
        Map.merge(
          %{
            display_name: "Acme Space",
            slug: "acme-#{System.unique_integer([:positive])}"
          },
          attrs
        )
      )
    end

    test "omits the organization block entirely when scope.organization is nil" do
      html =
        render_component(&UI.user_menu/1,
          scope: scope(user_fixture()),
          memberships: [],
          platform_admin?: false
        )

      refute html =~ "ORGANIZATION"
    end

    test "renders label-only org row for single-membership users" do
      org = org_fixture(%{display_name: "Acme Space"})
      membership_map = %{membership: %{}, organization: org}

      html =
        render_component(&UI.user_menu/1,
          scope: scope(user_fixture(), org),
          memberships: [membership_map],
          platform_admin?: false
        )

      assert html =~ "ORGANIZATION"
      assert html =~ "Acme Space"
      refute html =~ "<details"
      refute html =~ ~s|action="/session/organization"|
    end

    test "renders expandable switcher for multi-membership users" do
      current_org = org_fixture(%{display_name: "Acme Space"})
      other_org = org_fixture(%{display_name: "Beta Labs"})

      html =
        render_component(&UI.user_menu/1,
          scope: scope(user_fixture(), current_org),
          memberships: [
            %{membership: %{}, organization: current_org},
            %{membership: %{}, organization: other_org}
          ],
          platform_admin?: false
        )

      assert html =~ "ORGANIZATION"
      assert html =~ "Acme Space"
      assert html =~ "Beta Labs"
      assert html =~ ~s|action="/session/organization"|
      assert html =~ ~s|name="_method" value="put"|
      assert html =~ ~s|name="organization_id" value="#{other_org.organization_id}"|
      refute html =~ ~s|name="organization_id" value="#{current_org.organization_id}"|
    end
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
cd apps/cadence_web && mix test test/cadence_web/components/ui_test.exs
```

Expected: the three new tests fail. The single-membership assertion that refutes the `action="/session/organization"` fails because there is nothing, and that's fine — but the `assert html =~ "ORGANIZATION"` tests fail because the component does not yet render that section.

- [ ] **Step 3: Add the organization block to `user_menu/1`**

In `apps/cadence_web/lib/cadence_web/components/ui.ex`, modify the rendered template. Add a new `<li>` block between the identity `<li>` and the sign-out `<li>`:

```heex
        <%= if @scope.organization do %>
          <li role="presentation" class="border-t border-primary/10 mt-1 pt-1">
            <span class="hud-label text-base-content/60 px-3 py-1 block">Organization</span>
            <%= if length(@memberships) > 1 do %>
              <details class="group">
                <summary class="flex items-center justify-between gap-2 px-3 py-2 cursor-pointer text-sm text-base-content list-none">
                  <span class="truncate">{@scope.organization.display_name}</span>
                  <span class="hero-chevron-down h-3 w-3 opacity-60 transition-transform group-open:rotate-180"></span>
                </summary>
                <ul class="mt-1 space-y-0.5">
                  <li :for={%{organization: other} <- @memberships} :if={other.organization_id != @scope.organization.organization_id} role="presentation">
                    <.form for={%{}} as={:session} action={~p"/session/organization"} method="put">
                      <input type="hidden" name="organization_id" value={other.organization_id} />
                      <button
                        type="submit"
                        role="menuitem"
                        class="flex w-full items-center gap-2 px-3 py-2 text-xs text-base-content/70 hover:text-primary"
                      >
                        <span class="truncate">{other.display_name}</span>
                      </button>
                    </.form>
                  </li>
                </ul>
              </details>
            <% else %>
              <p class="px-3 py-2 text-sm text-base-content truncate">
                {@scope.organization.display_name}
              </p>
            <% end %>
          </li>
        <% end %>
```

Add this block **before** the sign-out `<li>` so the DOM order matches the spec (identity → org → admin → sign out).

- [ ] **Step 4: Run the tests to verify they pass**

```bash
cd apps/cadence_web && mix test test/cadence_web/components/ui_test.exs
```

Expected: all six tests pass (three from Task 8 plus three new).

- [ ] **Step 5: Format + compile + credo**

```bash
cd apps/cadence_web && mix format lib/cadence_web/components/ui.ex test/cadence_web/components/ui_test.exs
cd apps/cadence_web && mix compile --warnings-as-errors
cd apps/cadence_web && mix credo --strict lib/cadence_web/components/ui.ex
```

- [ ] **Step 6: Commit**

```bash
git add apps/cadence_web/lib/cadence_web/components/ui.ex apps/cadence_web/test/cadence_web/components/ui_test.exs
git commit -m "feat(cadence_web): add organization block (+ switcher) to user_menu"
```

---

## Task 10: `user_menu/1` — system administration link (platform admins only)

**Files:**
- Modify: `apps/cadence_web/lib/cadence_web/components/ui.ex`
- Modify: `apps/cadence_web/test/cadence_web/components/ui_test.exs`

- [ ] **Step 1: Add failing tests**

Append to the `describe "user_menu/1"` block in `ui_test.exs`:

```elixir
    test "does not render the system administration link when platform_admin? is false" do
      html =
        render_component(&UI.user_menu/1,
          scope: scope(user_fixture()),
          memberships: [],
          platform_admin?: false
        )

      refute html =~ "System administration"
    end

    test "renders the system administration link when platform_admin? is true" do
      html =
        render_component(&UI.user_menu/1,
          scope: scope(user_fixture()),
          memberships: [],
          platform_admin?: true
        )

      assert html =~ "System administration"
      assert html =~ ~s|href="/admin"|
    end
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
cd apps/cadence_web && mix test test/cadence_web/components/ui_test.exs
```

Expected: the "renders the system administration link when platform_admin? is true" test fails (component does not render it yet). The "does not render" test passes (because nothing emits that text yet).

- [ ] **Step 3: Add the admin link block**

In `user_menu/1`, insert between the organization `<li>` and the sign-out `<li>`:

```heex
        <li :if={@platform_admin?} role="presentation" class="border-t border-primary/10 mt-1 pt-1">
          <.link
            navigate={~p"/admin"}
            role="menuitem"
            class="flex items-center gap-2 px-3 py-2 text-xs tracking-wide uppercase text-base-content/70 hover:text-primary"
          >
            <span class="hero-cog-6-tooth h-4 w-4 opacity-80"></span>
            System administration
          </.link>
        </li>
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
cd apps/cadence_web && mix test test/cadence_web/components/ui_test.exs
```

Expected: all eight tests pass.

- [ ] **Step 5: Format + compile + credo**

```bash
cd apps/cadence_web && mix format lib/cadence_web/components/ui.ex test/cadence_web/components/ui_test.exs
cd apps/cadence_web && mix compile --warnings-as-errors
cd apps/cadence_web && mix credo --strict lib/cadence_web/components/ui.ex
```

- [ ] **Step 6: Commit**

```bash
git add apps/cadence_web/lib/cadence_web/components/ui.ex apps/cadence_web/test/cadence_web/components/ui_test.exs
git commit -m "feat(cadence_web): add platform-admin shortcut to user_menu"
```

---

## Task 11: Swap `user_shell.html.heex` header

**Files:**
- Modify: `apps/cadence_web/lib/cadence_web/components/layouts/user_shell.html.heex`

- [ ] **Step 1: Replace the email span with `<.user_menu>`**

Open `apps/cadence_web/lib/cadence_web/components/layouts/user_shell.html.heex`. Locate lines 12-14:

```heex
      <%= if @current_scope && @current_scope.user do %>
        <span class="text-xs text-base-content/60">{@current_scope.user.email}</span>
      <% end %>
```

Replace with:

```heex
      <%= if @current_scope && @current_scope.user do %>
        <.user_menu
          scope={@current_scope}
          memberships={assigns[:user_menu_memberships] || []}
          platform_admin?={assigns[:user_menu_platform_admin?] || false}
        />
      <% end %>
```

The existing `<.form action={~p"/session"} method="delete">` block below (lines 15-20) is **untouched** per the spec (shell-level sign out stays).

- [ ] **Step 2: Verify `<.user_menu>` is importable in the template**

Check that `CadenceWeb.UI` is imported where shell templates are rendered. Look at `apps/cadence_web/lib/cadence_web.ex` (or the module that defines `html_helpers`/`live_view` macros). If `CadenceWeb.UI` is not already imported there alongside `CadenceWeb.CoreComponents`, add an import statement so every template has access:

```bash
# Inspect the web definition module
```

Open `apps/cadence_web/lib/cadence_web.ex`. Find the `html_helpers` private function (or similar — it's the `quote` block aliased by `use CadenceWeb, :html` / `:live_view`). Check if `import CadenceWeb.UI` appears. If it doesn't, the `notifications_bell` usages in the existing templates would not compile — so it's already imported. **Do not modify `cadence_web.ex` unless the shells fail to compile after the swap.**

- [ ] **Step 3: Compile to verify**

```bash
cd apps/cadence_web && mix compile --warnings-as-errors
```

Expected: clean compile.

- [ ] **Step 4: Run the full web test suite**

```bash
cd apps/cadence_web && mix test
```

Expected: all tests pass. In particular the `notifications_live_test.exs` (which renders under `user_shell`) should still pass.

- [ ] **Step 5: Format**

```bash
cd apps/cadence_web && mix format lib/cadence_web/components/layouts/user_shell.html.heex
```

- [ ] **Step 6: Commit**

```bash
git add apps/cadence_web/lib/cadence_web/components/layouts/user_shell.html.heex
git commit -m "feat(cadence_web): render user_menu in user_shell header"
```

---

## Task 12: Swap `sidebar.html.heex` headers (desktop + mobile)

**Files:**
- Modify: `apps/cadence_web/lib/cadence_web/components/layouts/sidebar.html.heex`

- [ ] **Step 1: Replace the mobile identity span (lines 10-18)**

Open `apps/cadence_web/lib/cadence_web/components/layouts/sidebar.html.heex`. Locate the mobile header block (lines 5-19). Lines 10-18 contain:

```heex
      <div class="flex items-center gap-2">
        <%= if @current_scope && @current_scope.user do %>
          <.notifications_bell
            count={assigns[:unread_notifications_count] || 0}
            notifications={assigns[:recent_notifications] || []}
          />
          <span class="text-xs text-base-content/60">{@current_scope.user.email}</span>
        <% end %>
      </div>
```

Replace the `<span>` with `<.user_menu>`:

```heex
      <div class="flex items-center gap-2">
        <%= if @current_scope && @current_scope.user do %>
          <.notifications_bell
            count={assigns[:unread_notifications_count] || 0}
            notifications={assigns[:recent_notifications] || []}
          />
          <.user_menu
            scope={@current_scope}
            memberships={assigns[:user_menu_memberships] || []}
            platform_admin?={assigns[:user_menu_platform_admin?] || false}
          />
        <% end %>
      </div>
```

- [ ] **Step 2: Replace the desktop identity spans (lines 21-30)**

Lines 21-30 contain:

```heex
    <div class="hidden lg:flex items-center justify-end gap-3 px-4 h-10 border-b border-primary/20 bg-base-200 hud-grid shrink-0">
      <%= if @current_scope && @current_scope.user do %>
        <.notifications_bell
          count={assigns[:unread_notifications_count] || 0}
          notifications={assigns[:recent_notifications] || []}
        />
        <span class="text-xs text-base-content/60">{@current_scope.user.display_name}</span>
        <span class="text-xs text-base-content/40">({@current_scope.user.email})</span>
      <% end %>
    </div>
```

Replace the two `<span>` lines with `<.user_menu>`:

```heex
    <div class="hidden lg:flex items-center justify-end gap-3 px-4 h-10 border-b border-primary/20 bg-base-200 hud-grid shrink-0">
      <%= if @current_scope && @current_scope.user do %>
        <.notifications_bell
          count={assigns[:unread_notifications_count] || 0}
          notifications={assigns[:recent_notifications] || []}
        />
        <.user_menu
          scope={@current_scope}
          memberships={assigns[:user_menu_memberships] || []}
          platform_admin?={assigns[:user_menu_platform_admin?] || false}
        />
      <% end %>
    </div>
```

The sidebar drawer footer (lines 104-111) with its own "Sign out" form is **untouched** per the spec.

- [ ] **Step 3: Compile + full suite**

```bash
cd apps/cadence_web && mix compile --warnings-as-errors
cd apps/cadence_web && mix test
```

Expected: clean compile, all tests pass.

- [ ] **Step 4: Format**

```bash
cd apps/cadence_web && mix format lib/cadence_web/components/layouts/sidebar.html.heex
```

- [ ] **Step 5: Commit**

```bash
git add apps/cadence_web/lib/cadence_web/components/layouts/sidebar.html.heex
git commit -m "feat(cadence_web): render user_menu in sidebar shell headers"
```

---

## Task 13: Swap `mission_sidebar.html.heex` headers

**Files:**
- Modify: `apps/cadence_web/lib/cadence_web/components/layouts/mission_sidebar.html.heex`

- [ ] **Step 1: Apply the same two swaps as Task 12**

Open `apps/cadence_web/lib/cadence_web/components/layouts/mission_sidebar.html.heex`. The structure is identical to `sidebar.html.heex` for the mobile (lines 10-18) and desktop (lines 21-30) header blocks.

Apply the exact same replacements as in Task 12 — replace the `<span class="text-xs text-base-content/60">{@current_scope.user.email}</span>` in the mobile block and the two desktop `<span>` lines with `<.user_menu>` invocations carrying the same three props.

```heex
      <div class="flex items-center gap-2">
        <%= if @current_scope && @current_scope.user do %>
          <.notifications_bell
            count={assigns[:unread_notifications_count] || 0}
            notifications={assigns[:recent_notifications] || []}
          />
          <.user_menu
            scope={@current_scope}
            memberships={assigns[:user_menu_memberships] || []}
            platform_admin?={assigns[:user_menu_platform_admin?] || false}
          />
        <% end %>
      </div>
```

```heex
    <div class="hidden lg:flex items-center justify-end gap-3 px-4 h-10 border-b border-primary/20 bg-base-200 hud-grid shrink-0">
      <%= if @current_scope && @current_scope.user do %>
        <.notifications_bell
          count={assigns[:unread_notifications_count] || 0}
          notifications={assigns[:recent_notifications] || []}
        />
        <.user_menu
          scope={@current_scope}
          memberships={assigns[:user_menu_memberships] || []}
          platform_admin?={assigns[:user_menu_platform_admin?] || false}
        />
      <% end %>
    </div>
```

The mission sidebar drawer footer sign-out is **untouched**.

- [ ] **Step 2: Compile + full suite**

```bash
cd apps/cadence_web && mix compile --warnings-as-errors
cd apps/cadence_web && mix test
```

Expected: clean compile, all tests pass including `mission_show_live_test.exs`.

- [ ] **Step 3: Format**

```bash
cd apps/cadence_web && mix format lib/cadence_web/components/layouts/mission_sidebar.html.heex
```

- [ ] **Step 4: Commit**

```bash
git add apps/cadence_web/lib/cadence_web/components/layouts/mission_sidebar.html.heex
git commit -m "feat(cadence_web): render user_menu in mission_sidebar headers"
```

---

## Task 14: Final verification pass

**Files:** (none — validation only)

- [ ] **Step 1: Cadence app full suite**

```bash
cd apps/cadence && mix compile --warnings-as-errors
cd apps/cadence && mix test
cd apps/cadence && mix credo --strict
```

Expected: clean compile, all tests pass, no credo violations in modified files (`lib/cadence/accounts.ex`, `lib/cadence.ex`). Existing credo violations in unrelated files are acceptable ("burning down" per CLAUDE.md); do **not** fix unrelated violations in this plan.

- [ ] **Step 2: Cadence_web app full suite**

```bash
cd apps/cadence_web && mix compile --warnings-as-errors
cd apps/cadence_web && mix test
cd apps/cadence_web && mix credo --strict
```

Expected: clean compile, all tests pass, no credo violations in modified or new files.

- [ ] **Step 3: Format audit across touched files**

From the project root:

```bash
mix format --check-formatted apps/cadence/lib/cadence/accounts.ex apps/cadence/lib/cadence.ex apps/cadence/test/cadence/accounts_test.exs apps/cadence_web/lib/cadence_web/components/ui.ex apps/cadence_web/lib/cadence_web/components/layouts/user_shell.html.heex apps/cadence_web/lib/cadence_web/components/layouts/sidebar.html.heex apps/cadence_web/lib/cadence_web/components/layouts/mission_sidebar.html.heex apps/cadence_web/lib/cadence_web/live/user_auth.ex apps/cadence_web/lib/cadence_web/plugs/assign_user_menu_context.ex apps/cadence_web/lib/cadence_web/controllers/user_session_controller.ex apps/cadence_web/lib/cadence_web/router.ex apps/cadence_web/test/cadence_web/components/ui_test.exs apps/cadence_web/test/cadence_web/live/user_auth_test.exs apps/cadence_web/test/cadence_web/plugs/assign_user_menu_context_test.exs apps/cadence_web/test/cadence_web/controllers/user_session_controller_test.exs
```

Expected: no output (all formatted).

- [ ] **Step 4: Manual smoke test**

Start the dev server and click through the three shells:

```bash
mix phx.server
```

For each surface, verify:

| Surface | Test |
| --- | --- |
| `user_shell` (e.g. `/notifications`) | Click the name in top-right → popover opens → shows identity + sign out. No org block (scope has no organization in the `:user` live_session). |
| `sidebar` desktop (e.g. `/`) | Click name → popover shows identity + org label (or switcher if multi-org) + sign out. Platform admin users see "System administration". |
| `sidebar` mobile (< 1024px) | Same popover opens from the mobile top-bar trigger. |
| `mission_sidebar` (e.g. `/missions/:id`) | Same as `sidebar`. |
| Org switcher | Multi-membership user → click current org → list of other orgs appears in the same panel → click one → redirect to `/` with new org scope. |
| Sign out from panel | Click → lands on `/sign-in`. |
| Sign out from drawer footer | Still works (shell-level sign out untouched). |

If any surface is broken, do not proceed — fix in a new commit. Per CLAUDE.md: "For UI or frontend changes, start the dev server and use the feature in a browser before reporting the task as complete."

- [ ] **Step 5: Final commit (only if step 4 surfaced issues)**

If step 4 passed with no fixes, there is nothing to commit — the branch is done. If fixes were required, each fix should have been committed in its own commit while addressing it; ensure none are lingering unstaged.

```bash
git status
```

Expected: clean working tree.

---

## Out-of-scope reminders

- Sidebar drawer footer org summary — separate future spec.
- Panel avatar / initials — separate future spec.
- Switcher search / recents — only when org counts warrant it.
- Removing shell-level sign out buttons — explicitly kept, do not touch.

## Post-implementation self-review

**Spec coverage check:**
- Goals (identity interactive, org switch, admin shortcut, header density, no new CSS/primitives) — all delivered by Tasks 4, 8-13.
- Non-goals respected — no sidebar footer, no theme toggle, no avatar, no slide rail, no shell-button removal, no chooser page.
- Affected surfaces (three shells) — Tasks 11-13 cover all three, both desktop and mobile variants.
- Component contract (`scope`, `memberships`, `platform_admin?`) — Task 8.
- Trigger (ghost button, display name + chevron, email dropped) — Task 8.
- Panel (w-72, bg-base-200, border-primary/20, sharp corners, p-2, border-t dividers) — Task 8-10.
- Four content blocks (identity, org, admin, sign out) — Tasks 8-10.
- Three org shapes (hidden / label / switcher) — Task 9.
- Data flow (`:attach_user_menu` hook + `AssignUserMenuContext` plug) — Tasks 5-7.
- Accounts API (`list_user_memberships/1`, `fetch_user_membership/2`) — Tasks 1-3.
- `PUT /session/organization` with authorization guard — Task 4.
- Sticky switch via existing `:current_organization_id` session key — Task 4.
- All tests called out in the spec — Tasks 1, 2, 4, 5, 6, 8, 9, 10.
- A11y (button, aria-haspopup, role="menu", role="menuitem", role="presentation") — Tasks 8-10.
- Responsive — mobile trigger already exists in shell templates and Task 12 re-uses the same component.

**Placeholder scan:** All steps contain runnable commands and complete code. The only note is in Task 1 ("prefer the first form; fall back to the inline form only if…") — that is an explicit contingency with the fallback spelled out, not a placeholder.

**Type consistency:** `%{membership: _, organization: _}` is the shape used uniformly across Tasks 1, 2 (for fetch's return is the bare membership, not a map — consistent with `preferred_organization_membership`), 5, 6, 8, 9. Component attrs `scope`, `memberships`, `platform_admin?` are used identically in every task that references them.
