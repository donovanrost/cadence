# Spacecraft CRUD (basic pass) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship List + New + Show LiveViews for mission-owned spacecraft, mirroring the Missions pattern. No update/delete, no slug, no metadata editor.

**Architecture:** Three LiveViews (`SpacecraftListLive`, `SpacecraftNewLive`, `SpacecraftShowLive`) plus one `SpacecraftAuth` on_mount hook, nested under the existing `mission_sidebar` layout at `/missions/:mission_id/spacecraft*`. Data layer already exists; the plan adds three thin `Cadence` facade delegations on top of the existing `Cadence.SpacecraftStore`. Tests mirror the Missions LiveView tests one-for-one.

**Tech Stack:** Elixir 1.x, Phoenix LiveView, Ecto, daisyUI 5 + Tailwind v4, ExUnit. Follows the existing project conventions (facade → context → persistence; `<.input>`, `<.action_menu>`, `.empty_state`, `.detail_row`; HUD utility classes only, no new CSS).

**Spec:** `docs/superpowers/specs/2026-04-19-spacecraft-crud-design.md`

---

## File inventory

**Created:**
- `apps/cadence/test/cadence/cadence_spacecraft_facade_test.exs` — unit tests for the three new facade delegations.
- `apps/cadence_web/lib/cadence_web/live/spacecraft_auth.ex` — on_mount hook that loads `@current_spacecraft`.
- `apps/cadence_web/lib/cadence_web/live/spacecraft_list_live.ex`
- `apps/cadence_web/lib/cadence_web/live/spacecraft_new_live.ex`
- `apps/cadence_web/lib/cadence_web/live/spacecraft_show_live.ex`
- `apps/cadence_web/test/cadence_web/live/spacecraft_list_live_test.exs`
- `apps/cadence_web/test/cadence_web/live/spacecraft_new_live_test.exs`
- `apps/cadence_web/test/cadence_web/live/spacecraft_show_live_test.exs`

**Modified:**
- `apps/cadence/lib/cadence.ex` — append three `*_spacecraft` delegating functions.
- `apps/cadence_web/test/support/fixtures.ex` — append `persist_spacecraft!/2` fixture helper.
- `apps/cadence_web/lib/cadence_web/router.ex` — add two new `live_session` blocks (`:spacecraft` and `:spacecraft_show`).
- `apps/cadence_web/lib/cadence_web/components/layouts/mission_sidebar.html.heex` — add a second `<li>` under "Overview".

**Not touched (explicit):** `Cadence.Spacecraft`, `Cadence.SpacecraftStore`, `Cadence.Persistence.Schemas.SpacecraftRow`, any migrations.

---

### Task 1: Add `Cadence` facade delegations for spacecraft

**Files:**
- Create: `apps/cadence/test/cadence/cadence_spacecraft_facade_test.exs`
- Modify: `apps/cadence/lib/cadence.ex` (append after the existing `list_missions/1` at line ~250)

- [ ] **Step 1: Write failing test** (TDD — facade round-trip)

Create `apps/cadence/test/cadence/cadence_spacecraft_facade_test.exs`:

```elixir
defmodule Cadence.SpacecraftFacadeTest do
  use Cadence.DataCase, async: true

  alias Cadence.Missions.Mission
  alias Cadence.Organizations.Organization
  alias Cadence.Spacecraft

  defp seed_org_and_mission do
    org = Organization.new(%{display_name: "Acme", slug: "acme-#{System.unique_integer([:positive])}"})
    {:ok, org} = Cadence.persist_organization(org)

    mission =
      Mission.new(%{
        organization_id: org.organization_id,
        slug: "m-#{System.unique_integer([:positive])}",
        display_name: "Mission One"
      })

    {:ok, mission} = Cadence.persist_mission(mission)
    {org, mission}
  end

  test "persist_spacecraft/2 + fetch_spacecraft/3 round-trip" do
    {org, mission} = seed_org_and_mission()

    spacecraft =
      Spacecraft.new(%{
        mission_id: mission.mission_id,
        display_name: "Sat-1"
      })

    assert {:ok, persisted} = Cadence.persist_spacecraft(org.organization_id, spacecraft)
    assert persisted.organization_id == org.organization_id
    assert persisted.mission_id == mission.mission_id
    assert persisted.display_name == "Sat-1"

    assert {:ok, fetched} =
             Cadence.fetch_spacecraft(org.organization_id, mission.mission_id, persisted.spacecraft_id)

    assert fetched.spacecraft_id == persisted.spacecraft_id
    assert fetched.display_name == "Sat-1"
  end

  test "list_spacecraft/2 returns only spacecraft for the given org + mission" do
    {org_a, mission_a} = seed_org_and_mission()
    {_org_b, mission_b} = seed_org_and_mission()

    {:ok, _} =
      Cadence.persist_spacecraft(
        org_a.organization_id,
        Spacecraft.new(%{mission_id: mission_a.mission_id, display_name: "A1"})
      )

    {:ok, _} =
      Cadence.persist_spacecraft(
        org_a.organization_id,
        Spacecraft.new(%{mission_id: mission_a.mission_id, display_name: "A2"})
      )

    {:ok, _} =
      Cadence.persist_spacecraft(
        mission_b.organization_id,
        Spacecraft.new(%{mission_id: mission_b.mission_id, display_name: "B1"})
      )

    names = Cadence.list_spacecraft(org_a.organization_id, mission_a.mission_id) |> Enum.map(& &1.display_name)
    assert Enum.sort(names) == ["A1", "A2"]
  end

  test "fetch_spacecraft/3 returns error for the wrong organization" do
    {org_a, mission_a} = seed_org_and_mission()
    {org_b, _mission_b} = seed_org_and_mission()

    {:ok, persisted} =
      Cadence.persist_spacecraft(
        org_a.organization_id,
        Spacecraft.new(%{mission_id: mission_a.mission_id, display_name: "Cross-org test"})
      )

    assert {:error, :spacecraft_not_found} =
             Cadence.fetch_spacecraft(org_b.organization_id, mission_a.mission_id, persisted.spacecraft_id)
  end
end
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd apps/cadence && mix test test/cadence/cadence_spacecraft_facade_test.exs`
Expected: FAIL with `UndefinedFunctionError` for `Cadence.persist_spacecraft/2`, `fetch_spacecraft/3`, and `list_spacecraft/2`.

- [ ] **Step 3: Add the facade delegations**

Open `apps/cadence/lib/cadence.ex`. Find the end of `list_missions/1` (around line 250, in the missions section). Immediately after it, add:

```elixir
  @spec persist_spacecraft(binary(), Cadence.Spacecraft.t()) ::
          {:ok, Cadence.Spacecraft.t()} | {:error, term()}
  def persist_spacecraft(organization_id, %Cadence.Spacecraft{} = spacecraft)
      when is_binary(organization_id) do
    Cadence.SpacecraftStore.persist_spacecraft(organization_id, spacecraft)
  end

  @spec fetch_spacecraft(binary(), binary(), binary()) ::
          {:ok, Cadence.Spacecraft.t()} | {:error, term()}
  def fetch_spacecraft(organization_id, mission_id, spacecraft_id)
      when is_binary(organization_id) and is_binary(mission_id) and is_binary(spacecraft_id) do
    Cadence.SpacecraftStore.fetch_spacecraft(organization_id, mission_id, spacecraft_id)
  end

  @spec list_spacecraft(binary(), binary()) :: [Cadence.Spacecraft.t()]
  def list_spacecraft(organization_id, mission_id)
      when is_binary(organization_id) and is_binary(mission_id) do
    Cadence.SpacecraftStore.list_spacecraft(organization_id, mission_id)
  end
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd apps/cadence && mix test test/cadence/cadence_spacecraft_facade_test.exs`
Expected: PASS (3 tests).

- [ ] **Step 5: Compile-clean check**

Run: `cd apps/cadence && mix compile --warnings-as-errors`
Expected: exit 0.

- [ ] **Step 6: Commit**

```bash
git add apps/cadence/lib/cadence.ex apps/cadence/test/cadence/cadence_spacecraft_facade_test.exs
git commit -m "feat(cadence): expose spacecraft store on the Cadence facade"
```

---

### Task 2: Add `persist_spacecraft!/2` test fixture helper

**Files:**
- Modify: `apps/cadence_web/test/support/fixtures.ex` (append after the existing `member_conn/1`)

- [ ] **Step 1: Edit the fixture module**

Open `apps/cadence_web/test/support/fixtures.ex`. At the top of the file, extend the existing `alias Cadence.Ids` line context by adding an alias for `Cadence.Missions.Mission` **only if absent**; if already present, skip. Then append to the end of the module (before the closing `end`):

```elixir
  alias Cadence.Missions.Mission
  alias Cadence.Spacecraft

  @spec persist_mission!(Cadence.Organizations.Organization.t(), keyword()) :: Mission.t()
  def persist_mission!(org, opts \\ []) do
    slug = Keyword.get(opts, :slug, "mission-#{System.unique_integer([:positive])}")
    display_name = Keyword.get(opts, :display_name, "Fixture Mission")

    mission =
      Mission.new(%{
        organization_id: org.organization_id,
        slug: slug,
        display_name: display_name
      })

    assert {:ok, persisted} = Cadence.persist_mission(mission)
    persisted
  end

  @spec persist_spacecraft!(Mission.t(), keyword()) :: Spacecraft.t()
  def persist_spacecraft!(%Mission{} = mission, opts \\ []) do
    display_name =
      Keyword.get(opts, :display_name, "Spacecraft-#{System.unique_integer([:positive])}")

    spacecraft =
      Spacecraft.new(%{
        mission_id: mission.mission_id,
        display_name: display_name
      })

    assert {:ok, persisted} = Cadence.persist_spacecraft(mission.organization_id, spacecraft)
    persisted
  end
```

Note: if `alias Cadence.Missions.Mission` already exists at the top of the file, move the `alias Cadence.Spacecraft` next to it and delete the duplicate inside this append block.

- [ ] **Step 2: Verify compilation**

Run: `cd apps/cadence_web && mix compile --warnings-as-errors`
Expected: exit 0. No behavioral test yet — these helpers will be exercised by later tasks.

- [ ] **Step 3: Commit**

```bash
git add apps/cadence_web/test/support/fixtures.ex
git commit -m "test(cadence_web): add mission + spacecraft fixture helpers"
```

---

### Task 3: Build `SpacecraftListLive` end-to-end (test → route → LV)

**Files:**
- Create: `apps/cadence_web/test/cadence_web/live/spacecraft_list_live_test.exs`
- Create: `apps/cadence_web/lib/cadence_web/live/spacecraft_list_live.ex`
- Modify: `apps/cadence_web/lib/cadence_web/router.ex` — add the `:spacecraft` live_session containing `/missions/:mission_id/spacecraft` and `/missions/:mission_id/spacecraft/new` (the new route is wired up-front so it compiles with the stubbed module in Task 4).

- [ ] **Step 1: Write the failing tests**

Create `apps/cadence_web/test/cadence_web/live/spacecraft_list_live_test.exs`:

```elixir
defmodule CadenceWeb.SpacecraftListLiveTest do
  use CadenceWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias CadenceWeb.TestFixtures

  defp signed_in_org_and_mission do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _ = TestFixtures.grant_membership!(user, org)
    mission = TestFixtures.persist_mission!(org, slug: "primary", display_name: "Primary Mission")
    {TestFixtures.member_conn(user), org, mission}
  end

  describe "mount" do
    test "renders empty state when there are no spacecraft" do
      {conn, _org, mission} = signed_in_org_and_mission()

      {:ok, _view, html} = live(conn, ~p"/missions/#{mission.mission_id}/spacecraft")

      assert html =~ "No spacecraft"
      assert html =~ ~p"/missions/#{mission.mission_id}/spacecraft/new"
    end

    test "renders spacecraft in a table" do
      {conn, _org, mission} = signed_in_org_and_mission()
      _s1 = TestFixtures.persist_spacecraft!(mission, display_name: "Alpha-1")
      _s2 = TestFixtures.persist_spacecraft!(mission, display_name: "Alpha-2")

      {:ok, _view, html} = live(conn, ~p"/missions/#{mission.mission_id}/spacecraft")

      assert html =~ "Alpha-1"
      assert html =~ "Alpha-2"
      assert html =~ "New Spacecraft"
    end

    test "shows only spacecraft belonging to this mission" do
      {conn, org, mission} = signed_in_org_and_mission()
      other_mission = TestFixtures.persist_mission!(org, slug: "secondary", display_name: "Secondary")

      _mine = TestFixtures.persist_spacecraft!(mission, display_name: "Mine-1")
      _theirs = TestFixtures.persist_spacecraft!(other_mission, display_name: "Theirs-1")

      {:ok, _view, html} = live(conn, ~p"/missions/#{mission.mission_id}/spacecraft")

      assert html =~ "Mine-1"
      refute html =~ "Theirs-1"
    end

    test "shows only spacecraft belonging to the current organization" do
      {conn, _org, mission} = signed_in_org_and_mission()

      other_org = TestFixtures.persist_org!(display_name: "Other", slug: "other-org")
      other_mission = TestFixtures.persist_mission!(other_org, slug: "remote", display_name: "Remote")
      _theirs = TestFixtures.persist_spacecraft!(other_mission, display_name: "Other-Org-Craft")

      {:ok, _view, html} = live(conn, ~p"/missions/#{mission.mission_id}/spacecraft")

      refute html =~ "Other-Org-Craft"
    end
  end

  describe "authorization" do
    test "unauthenticated request redirects to /sign-in", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/sign-in"}}} =
               live(conn, ~p"/missions/some-mission-id/spacecraft")
    end

    test "user without membership redirects to /no-organization" do
      user = TestFixtures.persist_user!()
      conn = TestFixtures.member_conn(user)

      assert {:error, {:redirect, %{to: "/no-organization"}}} =
               live(conn, ~p"/missions/some-mission-id/spacecraft")
    end

    test "missing mission redirects to /missions" do
      {conn, _org, _mission} = signed_in_org_and_mission()

      assert {:error, {:redirect, %{to: "/missions", flash: %{"error" => _}}}} =
               live(conn, ~p"/missions/missing-mission-id/spacecraft")
    end
  end
end
```

- [ ] **Step 2: Run the tests to verify they fail for the right reason**

Run: `cd apps/cadence_web && mix test test/cadence_web/live/spacecraft_list_live_test.exs`
Expected: FAIL — initially with a routing / `Phoenix.VerifiedRoutes` compile error (the route does not exist yet).

- [ ] **Step 3: Create the `SpacecraftListLive` module**

Create `apps/cadence_web/lib/cadence_web/live/spacecraft_list_live.ex`:

```elixir
defmodule CadenceWeb.SpacecraftListLive do
  @moduledoc false
  use CadenceWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    mission = socket.assigns.current_mission
    organization_id = socket.assigns.current_scope.organization_id
    spacecraft = Cadence.list_spacecraft(organization_id, mission.mission_id)

    {:ok,
     socket
     |> assign(:page_title, "Spacecraft")
     |> assign(:nav_item, :spacecraft)
     |> assign(:spacecraft, spacecraft)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <div>
        <.link
          navigate={~p"/missions/#{@current_mission.mission_id}"}
          class="text-sm text-primary hover:underline"
        >
          &larr; {@current_mission.display_name}
        </.link>
      </div>

      <div class="flex items-center justify-between">
        <h1 class="text-2xl font-bold text-base-content">Spacecraft</h1>
        <.link
          navigate={~p"/missions/#{@current_mission.mission_id}/spacecraft/new"}
          class="btn btn-primary btn-sm gap-1"
        >
          <span class="hero-plus h-4 w-4"></span> New Spacecraft
        </.link>
      </div>

      <%= if @spacecraft == [] do %>
        <.empty_state
          icon="hero-rocket-launch"
          title="No spacecraft yet"
          description="Register the first spacecraft for this mission."
          action_label="New Spacecraft"
          action_navigate={~p"/missions/#{@current_mission.mission_id}/spacecraft/new"}
        />
      <% else %>
        <div class="card bg-base-200 overflow-hidden">
          <table class="table">
            <thead>
              <tr>
                <th class="hud-label">Name</th>
                <th class="hud-label">Spacecraft ID</th>
                <th class="hud-label text-right">Actions</th>
              </tr>
            </thead>
            <tbody>
              <tr :for={spacecraft <- @spacecraft}>
                <td class="font-medium">{spacecraft.display_name}</td>
                <td class="font-mono text-sm text-base-content/70">{spacecraft.spacecraft_id}</td>
                <td class="text-right">
                  <.action_menu>
                    <:action>
                      <.link navigate={
                        ~p"/missions/#{@current_mission.mission_id}/spacecraft/#{spacecraft.spacecraft_id}"
                      }>
                        View
                      </.link>
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

- [ ] **Step 4: Wire the router — both `:spacecraft` routes at once**

Open `apps/cadence_web/lib/cadence_web/router.ex`. Find the existing `live_session :mission, ...` block (starts around line 67). **Immediately after the `end` that closes the `:mission` block**, insert the new `:spacecraft` block (Task 4 will add an LV for `/new` — wiring the route now, with a stub module in Task 4 step 3, lets this task's tests pass without regressing routes):

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
```

Do NOT add the `:spacecraft_show` block yet — that comes in Task 5.

- [ ] **Step 5: Create an empty stub for `SpacecraftNewLive`**

So the router compiles. Create `apps/cadence_web/lib/cadence_web/live/spacecraft_new_live.ex` with a placeholder body:

```elixir
defmodule CadenceWeb.SpacecraftNewLive do
  @moduledoc false
  use CadenceWeb, :live_view

  @impl true
  def mount(_params, _session, socket), do: {:ok, socket}

  @impl true
  def render(assigns) do
    ~H"""
    <div>Placeholder — implemented in Task 4.</div>
    """
  end
end
```

- [ ] **Step 6: Run the list-live tests to verify they pass**

Run: `cd apps/cadence_web && mix test test/cadence_web/live/spacecraft_list_live_test.exs`
Expected: PASS (all list tests green).

- [ ] **Step 7: Compile-clean check**

Run: `cd apps/cadence_web && mix compile --warnings-as-errors`
Expected: exit 0.

- [ ] **Step 8: Commit**

```bash
git add apps/cadence_web/lib/cadence_web/live/spacecraft_list_live.ex \
        apps/cadence_web/lib/cadence_web/live/spacecraft_new_live.ex \
        apps/cadence_web/lib/cadence_web/router.ex \
        apps/cadence_web/test/cadence_web/live/spacecraft_list_live_test.exs
git commit -m "feat(cadence_web): spacecraft list live view under mission sidebar"
```

---

### Task 4: Implement `SpacecraftNewLive`

**Files:**
- Create: `apps/cadence_web/test/cadence_web/live/spacecraft_new_live_test.exs`
- Modify: `apps/cadence_web/lib/cadence_web/live/spacecraft_new_live.ex` (replace the stub with the real implementation)

- [ ] **Step 1: Write the failing tests**

Create `apps/cadence_web/test/cadence_web/live/spacecraft_new_live_test.exs`:

```elixir
defmodule CadenceWeb.SpacecraftNewLiveTest do
  use CadenceWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias CadenceWeb.TestFixtures

  defp signed_in_org_and_mission do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _ = TestFixtures.grant_membership!(user, org)
    mission = TestFixtures.persist_mission!(org, slug: "primary", display_name: "Primary Mission")
    {TestFixtures.member_conn(user), org, mission}
  end

  describe "mount" do
    test "renders the form", %{} do
      {conn, _org, mission} = signed_in_org_and_mission()

      {:ok, _view, html} = live(conn, ~p"/missions/#{mission.mission_id}/spacecraft/new")

      assert html =~ "New Spacecraft"
      assert html =~ "Display Name"
      assert html =~ "Create Spacecraft"
    end

    test "unauthenticated redirects to /sign-in", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/sign-in"}}} =
               live(conn, ~p"/missions/m/spacecraft/new")
    end

    test "missing mission redirects to /missions" do
      {conn, _org, _mission} = signed_in_org_and_mission()

      assert {:error, {:redirect, %{to: "/missions", flash: %{"error" => _}}}} =
               live(conn, ~p"/missions/missing/spacecraft/new")
    end
  end

  describe "save" do
    test "creating with valid data persists and redirects to show page" do
      {conn, org, mission} = signed_in_org_and_mission()

      {:ok, view, _html} = live(conn, ~p"/missions/#{mission.mission_id}/spacecraft/new")

      assert {:error, {:live_redirect, %{to: target}}} =
               view
               |> form("#spacecraft-form", spacecraft: %{display_name: "Orbital-1"})
               |> render_submit()

      assert target =~ "/missions/#{mission.mission_id}/spacecraft/"

      [persisted] = Cadence.list_spacecraft(org.organization_id, mission.mission_id)
      assert persisted.display_name == "Orbital-1"
      assert target =~ persisted.spacecraft_id
    end

    test "blank display_name shows a flash error and stays on page" do
      {conn, _org, mission} = signed_in_org_and_mission()

      {:ok, view, _html} = live(conn, ~p"/missions/#{mission.mission_id}/spacecraft/new")

      html =
        view
        |> form("#spacecraft-form", spacecraft: %{display_name: "   "})
        |> render_submit()

      assert html =~ "Display name is required."
    end
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd apps/cadence_web && mix test test/cadence_web/live/spacecraft_new_live_test.exs`
Expected: FAIL — stub LV renders "Placeholder" and has no form.

- [ ] **Step 3: Replace the stub with the real implementation**

Overwrite `apps/cadence_web/lib/cadence_web/live/spacecraft_new_live.ex`:

```elixir
defmodule CadenceWeb.SpacecraftNewLive do
  @moduledoc false

  # TODO(authz): Any active organization member can create a spacecraft. This
  # gate should tighten once platform-wide authorization is defined (likely to
  # the :organization_admin role, possibly a finer capability).
  use CadenceWeb, :live_view

  alias Cadence.Spacecraft

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "New Spacecraft")
     |> assign(:nav_item, :spacecraft)
     |> assign(:form, empty_form())}
  end

  @impl true
  def handle_event("validate", %{"spacecraft" => params}, socket) do
    display_name = Map.get(params, "display_name", "")
    form = to_form(%{"display_name" => display_name}, as: :spacecraft)
    {:noreply, assign(socket, :form, form)}
  end

  @impl true
  def handle_event("save", %{"spacecraft" => params}, socket) do
    mission = socket.assigns.current_mission
    organization_id = socket.assigns.current_scope.organization_id
    display_name = normalize(params["display_name"])

    if is_nil(display_name) do
      {:noreply, put_flash(socket, :error, "Display name is required.")}
    else
      spacecraft =
        Spacecraft.new(%{
          mission_id: mission.mission_id,
          display_name: display_name
        })

      case Cadence.persist_spacecraft(organization_id, spacecraft) do
        {:ok, persisted} ->
          {:noreply,
           push_navigate(socket,
             to: ~p"/missions/#{mission.mission_id}/spacecraft/#{persisted.spacecraft_id}"
           )}

        {:error, :mission_not_found} ->
          {:noreply,
           socket
           |> put_flash(:error, "Mission not found.")
           |> push_navigate(to: ~p"/missions")}

        {:error, {:organization_mission_mismatch, _, _, _}} ->
          {:noreply, put_flash(socket, :error, "Could not create spacecraft.")}

        {:error, %Ecto.Changeset{} = changeset} ->
          {:noreply, put_flash(socket, :error, format_errors(changeset))}

        {:error, reason} ->
          {:noreply,
           put_flash(socket, :error, "Failed to create spacecraft: #{inspect(reason)}")}
      end
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6 max-w-xl">
      <div>
        <.link
          navigate={~p"/missions/#{@current_mission.mission_id}/spacecraft"}
          class="text-sm text-primary hover:underline"
        >
          &larr; Spacecraft
        </.link>
        <h1 class="text-2xl font-bold text-base-content mt-1">New Spacecraft</h1>
      </div>

      <.form
        for={@form}
        id="spacecraft-form"
        phx-change="validate"
        phx-submit="save"
        class="space-y-4"
      >
        <.input field={@form[:display_name]} type="text" label="Display Name" required />
        <div class="flex items-center gap-3">
          <button type="submit" class="btn btn-primary">Create Spacecraft</button>
          <.link
            navigate={~p"/missions/#{@current_mission.mission_id}/spacecraft"}
            class="btn btn-ghost"
          >
            Cancel
          </.link>
        </div>
      </.form>
    </div>
    """
  end

  defp empty_form, do: to_form(%{"display_name" => ""}, as: :spacecraft)

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

- [ ] **Step 4: Run the new-live tests to verify they pass**

Run: `cd apps/cadence_web && mix test test/cadence_web/live/spacecraft_new_live_test.exs`
Expected: PASS.

- [ ] **Step 5: Run the full app test suite to catch regressions**

Run: `cd apps/cadence_web && mix test`
Expected: 0 failures.

- [ ] **Step 6: Compile-clean check**

Run: `cd apps/cadence_web && mix compile --warnings-as-errors`
Expected: exit 0.

- [ ] **Step 7: Commit**

```bash
git add apps/cadence_web/lib/cadence_web/live/spacecraft_new_live.ex \
        apps/cadence_web/test/cadence_web/live/spacecraft_new_live_test.exs
git commit -m "feat(cadence_web): spacecraft creation form"
```

---

### Task 5: Build `SpacecraftAuth` + `SpacecraftShowLive` end-to-end

**Files:**
- Create: `apps/cadence_web/lib/cadence_web/live/spacecraft_auth.ex`
- Create: `apps/cadence_web/lib/cadence_web/live/spacecraft_show_live.ex`
- Create: `apps/cadence_web/test/cadence_web/live/spacecraft_show_live_test.exs`
- Modify: `apps/cadence_web/lib/cadence_web/router.ex` — add the `:spacecraft_show` live_session.

- [ ] **Step 1: Write the failing tests**

Create `apps/cadence_web/test/cadence_web/live/spacecraft_show_live_test.exs`:

```elixir
defmodule CadenceWeb.SpacecraftShowLiveTest do
  use CadenceWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias CadenceWeb.TestFixtures

  defp signed_in_org_and_mission do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _ = TestFixtures.grant_membership!(user, org)
    mission = TestFixtures.persist_mission!(org, slug: "primary", display_name: "Primary Mission")
    {TestFixtures.member_conn(user), user, org, mission}
  end

  describe "mount" do
    test "renders spacecraft detail" do
      {conn, _user, _org, mission} = signed_in_org_and_mission()
      spacecraft = TestFixtures.persist_spacecraft!(mission, display_name: "Nova-1")

      {:ok, _view, html} =
        live(conn, ~p"/missions/#{mission.mission_id}/spacecraft/#{spacecraft.spacecraft_id}")

      assert html =~ "Nova-1"
      assert html =~ spacecraft.spacecraft_id
      assert html =~ mission.display_name
    end

    test "unauthenticated redirects to /sign-in", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/sign-in"}}} =
               live(conn, ~p"/missions/m/spacecraft/s")
    end

    test "unknown spacecraft redirects to the mission's spacecraft list" do
      {conn, _user, _org, mission} = signed_in_org_and_mission()

      assert {:error,
              {:redirect,
               %{to: path, flash: %{"error" => _}}}} =
               live(conn, ~p"/missions/#{mission.mission_id}/spacecraft/missing-id")

      assert path == ~p"/missions/#{mission.mission_id}/spacecraft"
    end

    test "spacecraft belonging to a sibling mission is not found" do
      {conn, _user, org, mission} = signed_in_org_and_mission()
      other_mission = TestFixtures.persist_mission!(org, slug: "secondary", display_name: "Secondary")
      other_spacecraft = TestFixtures.persist_spacecraft!(other_mission, display_name: "Sibling")

      assert {:error, {:redirect, %{to: path, flash: %{"error" => _}}}} =
               live(
                 conn,
                 ~p"/missions/#{mission.mission_id}/spacecraft/#{other_spacecraft.spacecraft_id}"
               )

      assert path == ~p"/missions/#{mission.mission_id}/spacecraft"
    end

    test "spacecraft belonging to another organization is not found" do
      {conn, _user, _org, mission} = signed_in_org_and_mission()

      other_org = TestFixtures.persist_org!(display_name: "Other", slug: "other-org")
      other_mission = TestFixtures.persist_mission!(other_org, slug: "remote", display_name: "Remote")
      other_spacecraft = TestFixtures.persist_spacecraft!(other_mission, display_name: "Foreign")

      assert {:error, {:redirect, %{to: path, flash: %{"error" => _}}}} =
               live(
                 conn,
                 ~p"/missions/#{mission.mission_id}/spacecraft/#{other_spacecraft.spacecraft_id}"
               )

      assert path == ~p"/missions/#{mission.mission_id}/spacecraft"
    end
  end
end
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd apps/cadence_web && mix test test/cadence_web/live/spacecraft_show_live_test.exs`
Expected: FAIL — the show route doesn't exist.

- [ ] **Step 3: Create the `SpacecraftAuth` on_mount hook**

Create `apps/cadence_web/lib/cadence_web/live/spacecraft_auth.ex`:

```elixir
defmodule CadenceWeb.SpacecraftAuth do
  @moduledoc false

  import Phoenix.Component
  import Phoenix.LiveView

  def on_mount(
        :load_spacecraft,
        %{"mission_id" => mission_id, "spacecraft_id" => spacecraft_id},
        _session,
        socket
      ) do
    organization_id = socket.assigns.current_scope.organization_id

    case Cadence.fetch_spacecraft(organization_id, mission_id, spacecraft_id) do
      {:ok, spacecraft} ->
        {:cont, assign(socket, :current_spacecraft, spacecraft)}

      {:error, _reason} ->
        {:halt,
         socket
         |> put_flash(:error, "Spacecraft not found.")
         |> redirect(to: "/missions/#{mission_id}/spacecraft")}
    end
  end
end
```

- [ ] **Step 4: Create `SpacecraftShowLive`**

Create `apps/cadence_web/lib/cadence_web/live/spacecraft_show_live.ex`:

```elixir
defmodule CadenceWeb.SpacecraftShowLive do
  @moduledoc false
  use CadenceWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    spacecraft = socket.assigns.current_spacecraft

    {:ok,
     socket
     |> assign(:page_title, spacecraft.display_name)
     |> assign(:nav_item, :spacecraft)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <div>
        <.link
          navigate={~p"/missions/#{@current_mission.mission_id}/spacecraft"}
          class="text-sm text-primary hover:underline"
        >
          &larr; Spacecraft
        </.link>
        <h1 class="text-2xl font-bold text-base-content mt-1">
          {@current_spacecraft.display_name}
        </h1>
      </div>

      <div class="card bg-base-200">
        <div class="card-body p-6">
          <p class="hud-label mb-4">Overview</p>
          <div class="divide-y divide-base-300">
            <.detail_row
              label="Spacecraft ID"
              value={@current_spacecraft.spacecraft_id}
              mono
            />
            <.detail_row label="Display name" value={@current_spacecraft.display_name} />
            <.detail_row label="Mission">
              <.link
                navigate={~p"/missions/#{@current_mission.mission_id}"}
                class="text-primary hover:underline"
              >
                {@current_mission.display_name}
              </.link>
            </.detail_row>
            <.detail_row
              label="Organization ID"
              value={@current_spacecraft.organization_id}
              mono
            />
          </div>

          <div :if={map_size(@current_spacecraft.metadata) > 0} class="mt-6">
            <details class="text-sm">
              <summary class="cursor-pointer text-base-content/60 hover:text-base-content">
                Metadata
              </summary>
              <pre class="mt-2 p-3 bg-base-300 rounded-sm overflow-x-auto text-xs font-mono">{Jason.encode!(@current_spacecraft.metadata, pretty: true)}</pre>
            </details>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
```

- [ ] **Step 5: Wire the router — add `:spacecraft_show` live_session**

Open `apps/cadence_web/lib/cadence_web/router.ex`. After the `live_session :spacecraft, ...` block (added in Task 3), append:

```elixir
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

- [ ] **Step 6: Run the show-live tests to verify they pass**

Run: `cd apps/cadence_web && mix test test/cadence_web/live/spacecraft_show_live_test.exs`
Expected: PASS.

- [ ] **Step 7: Run the full app test suite**

Run: `cd apps/cadence_web && mix test`
Expected: 0 failures.

- [ ] **Step 8: Compile-clean check**

Run: `cd apps/cadence_web && mix compile --warnings-as-errors`
Expected: exit 0.

- [ ] **Step 9: Commit**

```bash
git add apps/cadence_web/lib/cadence_web/live/spacecraft_auth.ex \
        apps/cadence_web/lib/cadence_web/live/spacecraft_show_live.ex \
        apps/cadence_web/lib/cadence_web/router.ex \
        apps/cadence_web/test/cadence_web/live/spacecraft_show_live_test.exs
git commit -m "feat(cadence_web): spacecraft detail view with auth hook"
```

---

### Task 6: Add "Spacecraft" nav entry to `mission_sidebar`

**Files:**
- Modify: `apps/cadence_web/lib/cadence_web/components/layouts/mission_sidebar.html.heex`

- [ ] **Step 1: Extend an existing test to cover the sidebar entry**

Open `apps/cadence_web/test/cadence_web/live/spacecraft_show_live_test.exs` and **inside the "mount" describe block**, append this test:

```elixir
    test "sidebar highlights the Spacecraft nav entry" do
      {conn, _user, _org, mission} = signed_in_org_and_mission()
      spacecraft = TestFixtures.persist_spacecraft!(mission, display_name: "Nav-Check")

      {:ok, _view, html} =
        live(conn, ~p"/missions/#{mission.mission_id}/spacecraft/#{spacecraft.spacecraft_id}")

      # The sidebar label is uppercased by CSS; check for the raw "Spacecraft" text
      # occurring in a menu-item link that points at the list URL.
      list_url = ~p"/missions/#{mission.mission_id}/spacecraft"
      assert html =~ list_url
      assert html =~ "Spacecraft"
    end
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd apps/cadence_web && mix test test/cadence_web/live/spacecraft_show_live_test.exs`
Expected: likely PASS for the URL assertion (the show page back link already includes it) but possibly FAIL on the "Spacecraft" label if no sidebar entry is rendered. If it passes, strengthen the assertion:

```elixir
      assert html =~ ~s(navigate="#{list_url}")
```

Re-run. The intent is to fail until the sidebar `<li>` exists.

- [ ] **Step 3: Add the Spacecraft nav entry**

Open `apps/cadence_web/lib/cadence_web/components/layouts/mission_sidebar.html.heex`. Find the existing `<li :if={assigns[:current_mission]}>` block that renders the Overview link (around lines 80-85). Immediately **after** its closing `</li>` (and still inside the `<ul>`), add:

```heex
          <li :if={assigns[:current_mission]}>
            <.link navigate={~p"/missions/#{@current_mission.mission_id}/spacecraft"} class={["flex items-center gap-2 px-3 py-2 text-xs tracking-wide uppercase border-l-2 transition-all", if(assigns[:nav_item] == :spacecraft, do: "bg-primary/10 text-primary border-primary shadow-[inset_0_0_20px_rgba(125,207,255,0.1)]", else: "text-base-content/60 border-transparent hover:bg-primary/5 hover:text-base-content hover:border-primary/30")]}>
              <span class="hero-rocket-launch h-4 w-4 opacity-80 flex-shrink-0"></span>
              <span class="sidebar-label">Spacecraft</span>
            </.link>
          </li>
```

Note: match the exact class string used by the Overview entry (copy-paste from the existing `<li>` and change the icon + label + `nav_item` comparison). If the Overview class list has drifted from what's shown above, use the file's current class list as the source of truth.

- [ ] **Step 4: Run the test to verify it now passes**

Run: `cd apps/cadence_web && mix test test/cadence_web/live/spacecraft_show_live_test.exs`
Expected: PASS.

- [ ] **Step 5: Run the full test suite to make sure the new markup didn't break other pages**

Run: `cd apps/cadence_web && mix test`
Expected: 0 failures.

- [ ] **Step 6: Commit**

```bash
git add apps/cadence_web/lib/cadence_web/components/layouts/mission_sidebar.html.heex \
        apps/cadence_web/test/cadence_web/live/spacecraft_show_live_test.exs
git commit -m "feat(cadence_web): add spacecraft entry to mission sidebar"
```

---

### Task 7: Final verification

- [ ] **Step 1: Format all touched Elixir files**

Run: `mix format` (from repo root).
Expected: no diff remaining in staged files.

- [ ] **Step 2: Full compile with warnings-as-errors**

Run: `mix compile --warnings-as-errors` (from repo root).
Expected: exit 0.

- [ ] **Step 3: Full test suites**

Run, from repo root:

```bash
cd apps/cadence && mix test && cd ../.. && \
cd apps/cadence_web && mix test && cd ../..
```

Expected: 0 failures in both apps.

- [ ] **Step 4: Credo on touched files**

Run: `mix credo --strict apps/cadence/lib/cadence.ex apps/cadence_web/lib/cadence_web/live/spacecraft_list_live.ex apps/cadence_web/lib/cadence_web/live/spacecraft_new_live.ex apps/cadence_web/lib/cadence_web/live/spacecraft_show_live.ex apps/cadence_web/lib/cadence_web/live/spacecraft_auth.ex apps/cadence_web/lib/cadence_web/router.ex apps/cadence_web/test/support/fixtures.ex`

Expected: no new violations introduced beyond what exists on `main`. If any warnings appear in the new files, fix them before committing. Do NOT attempt a repo-wide burndown in this plan.

- [ ] **Step 5: Manual browser smoke (per CLAUDE.md UI rule)**

Start the dev server and exercise the flow end-to-end:

```bash
mix phx.server
```

Check in the browser:
1. Log in, pick an org, open a mission.
2. Click "Spacecraft" in the sidebar. Expect the empty state.
3. Click "New Spacecraft". Submit with a blank name — flash error appears.
4. Submit with a valid name — redirects to the show page with the name and ID visible.
5. Click "← Spacecraft" back to the list; the new row is there.
6. Hit a bogus URL `/missions/<real-mission>/spacecraft/does-not-exist`; you land on the list with the "Spacecraft not found." flash.
7. Confirm the sidebar highlights the Spacecraft entry while on list, new, and show.

- [ ] **Step 6: Any follow-up fixes**

If manual smoke surfaces a copy/spacing issue (e.g., label wording, flash styling), fix in a small additional commit. Do NOT add new features in this pass.

---

## Self-review

**Spec coverage:**

- Goals "operators can register and view spacecraft under a mission" → Tasks 3–5.
- Non-goals (no update/delete/slug/metadata editor) → not introduced in any task.
- `Cadence` facade delegations → Task 1.
- Three LiveViews + `SpacecraftAuth` hook → Tasks 3, 4, 5.
- Router additions (two `live_session` blocks) → Tasks 3 and 5.
- Sidebar nav entry → Task 6.
- `persist_spacecraft!` fixture → Task 2.
- Test suites mirroring Missions (list/new/show) → Tasks 3, 4, 5.
- Verification commands (compile/format/credo/tests) → Task 7.

**Placeholder scan:** No "TBD", "handle edge cases", "similar to Task N", or unspecified error handling; every error branch has explicit code.

**Type/name consistency:**

- `Cadence.persist_spacecraft/2`, `Cadence.fetch_spacecraft/3`, `Cadence.list_spacecraft/2` — consistent across Tasks 1, 3, 4, 5, Auth hook.
- `CadenceWeb.SpacecraftAuth.on_mount(:load_spacecraft, ...)` — consistent between router entry (Task 5 Step 5) and hook definition (Task 5 Step 3).
- `@nav_item = :spacecraft` — consistent across all three LiveViews and the sidebar highlight check.
- Route URLs (`/missions/:mission_id/spacecraft`, `.../new`, `.../:spacecraft_id`) — consistent across router wiring, LiveViews, redirects, and tests.
- `persist_mission!/2` + `persist_spacecraft!/2` — defined in Task 2, used in Tasks 3–6.
