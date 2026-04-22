# Catalog UI — Progressive Disclosure + Family Removal Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move both catalog upload forms behind progressive disclosure (dedicated page for new database, inline reveal for add revision) and strip `catalog_family` badges and columns from all four catalog LiveView surfaces. Domain behavior is untouched.

**Architecture:** Four tasks ordered for minimum rework:
1. Delete the Family UI everywhere (pure subtraction; shrinks the files we're about to edit).
2. Create `CatalogDatabaseNewLive` + route. Logic moves verbatim from `CatalogIndexLive.perform_upload/3`.
3. Swap the inline upload card on the index for a `+ New database` CTA that navigates to the new page.
4. Gate the database-detail `revision_upload_card` behind a `@show_revision_form` toggle.

Each task is TDD: add failing assertion(s) first, verify red, implement, verify green, commit.

**Tech Stack:** Phoenix LiveView, daisyUI 5 + Tailwind v4, ExUnit + Phoenix.LiveViewTest. All work in `apps/cadence_web`.

**Related spec:** `docs/superpowers/specs/2026-04-21-catalog-ui-progressive-disclosure-design.md`

---

## File Structure

**Created:**
- `apps/cadence_web/lib/cadence_web/live/catalog/catalog_database_new_live.ex` — new LiveView mirroring `SpacecraftNewLive`, owns the form that was previously the index's `upload_card`.
- `apps/cadence_web/test/cadence_web/live/catalog/catalog_database_new_live_test.exs` — tests for the new page (no-match, happy path).

**Modified:**
- `apps/cadence_web/lib/cadence_web/router.ex` — add `/catalog/new` inside `live_session :catalog`.
- `apps/cadence_web/lib/cadence_web/live/catalog/components.ex` — delete `catalog_family_badge/1` + `family_badge_class/1` + `family_label/1`; drop the family badge from `detected_preview/1`.
- `apps/cadence_web/lib/cadence_web/live/catalog/catalog_index_live.ex` — remove upload card + handlers + helpers, add CTA button, drop Family column.
- `apps/cadence_web/lib/cadence_web/live/catalog/catalog_database_show_live.ex` — drop Family badge/column; wrap revision upload card in a toggle.
- `apps/cadence_web/lib/cadence_web/live/catalog/catalog_revision_show_live.ex` — drop Family badge from the header.
- `apps/cadence_web/test/cadence_web/live/catalog/catalog_index_live_test.exs` — replace upload-flow tests with CTA/empty-state tests; add `refute` on Family column.
- `apps/cadence_web/test/cadence_web/live/catalog/catalog_database_show_live_test.exs` — cover inline toggle; `refute` on Family surfaces.
- `apps/cadence_web/test/cadence_web/live/catalog/catalog_revision_show_live_test.exs` — `refute` on Family badge.

---

## Task 1: Remove Family UI from all catalog surfaces

**Files:**
- Modify: `apps/cadence_web/lib/cadence_web/live/catalog/components.ex`
- Modify: `apps/cadence_web/lib/cadence_web/live/catalog/catalog_index_live.ex`
- Modify: `apps/cadence_web/lib/cadence_web/live/catalog/catalog_database_show_live.ex`
- Modify: `apps/cadence_web/lib/cadence_web/live/catalog/catalog_revision_show_live.ex`
- Test: `apps/cadence_web/test/cadence_web/live/catalog/catalog_index_live_test.exs`
- Test: `apps/cadence_web/test/cadence_web/live/catalog/catalog_database_show_live_test.exs`
- Test: `apps/cadence_web/test/cadence_web/live/catalog/catalog_revision_show_live_test.exs`

Rationale: pure subtraction. Shrinks the files we're about to edit in Tasks 2–4. Default catalog fixtures persist databases with `catalog_family: :combined`, so current renders contain the literal string "Combined" and `<th>Family</th>`. Removing those is the visible signal.

- [ ] **Step 1: Add failing `refute` assertions in the three existing test files**

In `apps/cadence_web/test/cadence_web/live/catalog/catalog_index_live_test.exs`, inside the existing test `"lists persisted catalog databases with latest revision and import status"` (lines 31–43), add after the existing asserts:

```elixir
refute html =~ ">Family<"
refute html =~ "Combined"
```

In `apps/cadence_web/test/cadence_web/live/catalog/catalog_database_show_live_test.exs`, inside the existing test `"renders database metadata, revision history, and import attempts"` (lines 21–38), add after the existing asserts:

```elixir
refute html =~ ">Family<"
refute html =~ "Combined"
```

In `apps/cadence_web/test/cadence_web/live/catalog/catalog_revision_show_live_test.exs`, inside the existing test `"renders revision provenance and snapshot summaries"` (lines 21–39), add after the existing asserts:

```elixir
refute html =~ "Combined"
```

- [ ] **Step 2: Run the three tests and verify they fail**

```bash
cd apps/cadence_web && mix test test/cadence_web/live/catalog/catalog_index_live_test.exs test/cadence_web/live/catalog/catalog_database_show_live_test.exs test/cadence_web/live/catalog/catalog_revision_show_live_test.exs
```

Expected: the three tests above fail with messages like `Expected false or nil, got true` on the `refute`s. The header-match test in the database page may also match "Combined" from the family badge — that is what we want to prove is there.

- [ ] **Step 3: Remove the family badge from `detected_preview/1`**

Order matters here: every caller of `catalog_family_badge/1` must be removed before we delete the function itself, otherwise intermediate edits leave the file temporarily uncompilable.

In `apps/cadence_web/lib/cadence_web/live/catalog/components.ex`, find the `{:ok, %{descriptor: descriptor}}` branch of `detected_preview/1` and replace:

```heex
      <% {:ok, %{descriptor: descriptor}} -> %>
        <div class="flex items-center gap-2 text-sm text-base-content/80">
          <span class="hero-check-circle h-4 w-4 text-success"></span>
          Detected importer:
          <span class="font-medium">{descriptor.display_name}</span>
          <.catalog_family_badge family={descriptor.catalog_family} />
        </div>
```

with:

```heex
      <% {:ok, %{descriptor: descriptor}} -> %>
        <div class="flex items-center gap-2 text-sm text-base-content/80">
          <span class="hero-check-circle h-4 w-4 text-success"></span>
          Detected importer:
          <span class="font-medium">{descriptor.display_name}</span>
        </div>
```

- [ ] **Step 4: Remove the Family column from the index databases table**

In `apps/cadence_web/lib/cadence_web/live/catalog/catalog_index_live.ex`, inside `databases_table/1`, delete the `<th class="hud-label">Family</th>` entry from the `<thead>` and the corresponding `<td><.catalog_family_badge family={database.catalog_family} /></td>` cell from the row body. The resulting thead row reads:

```heex
            <tr>
              <th class="hud-label">Database</th>
              <th class="hud-label">Latest revision</th>
              <th class="hud-label">Latest import</th>
              <th class="hud-label">Runtime usage</th>
              <th class="hud-label text-right">Actions</th>
            </tr>
```

And the row body keeps four `<td>`s (Database, Latest revision, Latest import, Runtime usage) plus the Actions cell.

- [ ] **Step 5: Remove the family badge and Family column from the database-show page**

In `apps/cadence_web/lib/cadence_web/live/catalog/catalog_database_show_live.ex`, in `render/1`, delete the line:

```heex
          <.catalog_family_badge family={@database.catalog_family} />
```

(it sits inside the header flex container).

In the same file, inside `revision_history/1`, delete the `<th class="hud-label">Family</th>` entry from the thead and the corresponding `<td><.catalog_family_badge family={revision.catalog_family} /></td>` cell from the row body. After the edit, the thead row reads:

```heex
              <tr>
                <th class="hud-label">Revision</th>
                <th class="hud-label">Telemetry</th>
                <th class="hud-label">Command</th>
                <th class="hud-label text-right">Actions</th>
              </tr>
```

- [ ] **Step 6: Remove the family badge from the revision-show page**

In `apps/cadence_web/lib/cadence_web/live/catalog/catalog_revision_show_live.ex`, in `render/1`, delete the line:

```heex
          <.catalog_family_badge family={@revision.catalog_family} />
```

- [ ] **Step 7: Delete `catalog_family_badge/1` and its helpers from `Catalog.Components`**

With all callers gone, the function is unused. In `apps/cadence_web/lib/cadence_web/live/catalog/components.ex`, delete the entire block below:

```elixir
  @doc "Colored badge for a catalog family atom (`:telemetry | :command | :combined`)."
  attr :family, :atom, required: true

  def catalog_family_badge(assigns) do
    ~H"""
    <span class={[
      "badge badge-sm",
      family_badge_class(@family)
    ]}>
      {family_label(@family)}
    </span>
    """
  end

  defp family_badge_class(:telemetry), do: "badge-info"
  defp family_badge_class(:command), do: "badge-warning"
  defp family_badge_class(:combined), do: "badge-primary"
  defp family_badge_class(_), do: "badge-ghost"

  defp family_label(:telemetry), do: "Telemetry"
  defp family_label(:command), do: "Command"
  defp family_label(:combined), do: "Combined"

  defp family_label(other) when is_atom(other),
    do: other |> Atom.to_string() |> String.capitalize()
```

- [ ] **Step 8: Run the three affected tests and verify they pass**

```bash
cd apps/cadence_web && mix test test/cadence_web/live/catalog/catalog_index_live_test.exs test/cadence_web/live/catalog/catalog_database_show_live_test.exs test/cadence_web/live/catalog/catalog_revision_show_live_test.exs
```

Expected: all tests pass.

- [ ] **Step 9: Run `mix compile --warnings-as-errors` to catch any stray reference**

```bash
cd apps/cadence_web && mix compile --warnings-as-errors
```

Expected: clean build. If a warning surfaces about an unused import or a call to `catalog_family_badge/1`, chase it down — it means one surface was missed.

- [ ] **Step 10: Commit**

```bash
git add apps/cadence_web/lib/cadence_web/live/catalog/components.ex apps/cadence_web/lib/cadence_web/live/catalog/catalog_index_live.ex apps/cadence_web/lib/cadence_web/live/catalog/catalog_database_show_live.ex apps/cadence_web/lib/cadence_web/live/catalog/catalog_revision_show_live.ex apps/cadence_web/test/cadence_web/live/catalog/catalog_index_live_test.exs apps/cadence_web/test/cadence_web/live/catalog/catalog_database_show_live_test.exs apps/cadence_web/test/cadence_web/live/catalog/catalog_revision_show_live_test.exs
git commit -m "refactor(cadence_web): remove catalog_family UI surfaces"
```

---

## Task 2: Create `CatalogDatabaseNewLive` and route

**Files:**
- Create: `apps/cadence_web/lib/cadence_web/live/catalog/catalog_database_new_live.ex`
- Create: `apps/cadence_web/test/cadence_web/live/catalog/catalog_database_new_live_test.exs`
- Modify: `apps/cadence_web/lib/cadence_web/router.ex`

Rationale: create the page and test in isolation, before we touch the index. The index still has its inline upload in Task 2; Task 3 removes it. This ordering keeps the plan reversible: if Task 3 is skipped, Task 2's only side effect is an unused route.

The new LiveView must replicate the index's upload behavior exactly: it reads a single file, detects the importer via `Catalog.Registry`, creates a `CatalogDatabase`, builds an `Artifact`, starts a revision import with `Catalog.start_revision_import/7`, and navigates to the import run detail page.

- [ ] **Step 1: Write the failing test file**

Create `apps/cadence_web/test/cadence_web/live/catalog/catalog_database_new_live_test.exs`:

```elixir
defmodule CadenceWeb.CatalogDatabaseNewLiveTest do
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

  test "renders the new database form" do
    {conn, _org, mission} = signed_in_org_and_mission()

    {:ok, _view, html} = live(conn, ~p"/missions/#{mission.mission_id}/catalog/new")

    assert html =~ "New catalog database"
    assert html =~ "catalog-upload-form"
  end

  test "shows a friendly banner when no importer matches the file" do
    {conn, _org, mission} = signed_in_org_and_mission()

    {:ok, view, _html} = live(conn, ~p"/missions/#{mission.mission_id}/catalog/new")

    uploads =
      file_input(view, "#catalog-upload-form", :artifact, [
        %{
          name: "mission.bin",
          content: "anything",
          type: "application/octet-stream",
          last_modified: 1_700_000_000_000
        }
      ])

    _ = render_upload(uploads, "mission.bin")

    html = render(view)
    assert html =~ "No importer supports"
    assert html =~ "mission.bin"
  end

  test "uploading a valid YAML file creates a database revision import and navigates to the run" do
    {conn, _org, mission} = signed_in_org_and_mission()

    {:ok, view, _html} = live(conn, ~p"/missions/#{mission.mission_id}/catalog/new")

    yaml = """
    packets:
      - name: HEALTH
        items:
          - name: mode
            data_type: uint
            bit_offset: 0
            bit_size: 8
    commands: []
    """

    uploads =
      file_input(view, "#catalog-upload-form", :artifact, [
        %{
          name: "mission.yaml",
          content: yaml,
          type: "application/yaml",
          last_modified: 1_700_000_000_000
        }
      ])

    _ = render_upload(uploads, "mission.yaml")

    assert render(view) =~ "Cadence YAML Database"

    result =
      render_submit(view, "save", %{
        "catalog_database" => %{"name" => "Mission DB", "revision_label" => "Rev A"}
      })

    assert {:error, {:live_redirect, %{to: to}}} = result
    assert to =~ ~r"/missions/.+/catalog/imports/"

    assert [database] =
             Cadence.Catalog.list_databases(mission.organization_id, mission.mission_id)

    assert database.name == "Mission DB"
  end

  describe "authorization" do
    test "unauthenticated request redirects to /sign-in", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/sign-in"}}} =
               live(conn, ~p"/missions/any/catalog/new")
    end
  end
end
```

- [ ] **Step 2: Run the test and verify it fails because the route does not exist**

```bash
cd apps/cadence_web && mix test test/cadence_web/live/catalog/catalog_database_new_live_test.exs
```

Expected: all four tests fail. The first three raise because `~p"/missions/#{id}/catalog/new"` is an unknown verified route (compile-time error inside `Phoenix.VerifiedRoutes`). Fix: add the route next.

- [ ] **Step 3: Add the route**

In `apps/cadence_web/lib/cadence_web/router.ex`, inside the existing `live_session :catalog do ... end` block, add the route before the databases show route:

```elixir
      live "/missions/:mission_id/catalog", CatalogIndexLive, :index

      live "/missions/:mission_id/catalog/new", CatalogDatabaseNewLive, :new

      live "/missions/:mission_id/catalog/databases/:catalog_database_id",
           CatalogDatabaseShowLive,
           :show
```

- [ ] **Step 4: Create the LiveView module**

Create `apps/cadence_web/lib/cadence_web/live/catalog/catalog_database_new_live.ex`:

```elixir
defmodule CadenceWeb.CatalogDatabaseNewLive do
  @moduledoc false

  # TODO(authz): any signed-in mission member can create a catalog database.
  # Tighten once platform-wide authorization is defined.
  use CadenceWeb, :live_view

  import CadenceWeb.Catalog.Components

  alias Cadence.Catalog
  alias Cadence.Catalog.Artifact

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "New catalog database")
     |> assign(:nav_item, :catalog)
     |> assign(:database_form, empty_database_form())
     |> allow_upload(:artifact,
       accept: :any,
       max_entries: 1,
       max_file_size: 50 * 1024 * 1024
     )}
  end

  @impl true
  def handle_event("validate", %{"catalog_database" => params}, socket) do
    {:noreply, assign(socket, :database_form, to_form(params, as: :catalog_database))}
  end

  def handle_event("validate", _params, socket), do: {:noreply, socket}

  def handle_event("cancel_upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :artifact, ref)}
  end

  def handle_event("save", params, socket) do
    form_params = Map.get(params, "catalog_database", %{})

    case detect_importer_from_entries(socket.assigns.uploads.artifact.entries) do
      {:ok, registration} ->
        perform_upload(socket, registration, form_params)

      _ ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "Pick a file with a supported format before uploading."
         )}
    end
  end

  defp perform_upload(socket, %{descriptor: descriptor}, form_params) do
    mission = socket.assigns.current_mission
    organization_id = socket.assigns.current_scope.organization_id
    uploaded_by = uploader_identity(socket)

    [artifact_or_error | _] =
      consume_uploaded_entries(socket, :artifact, fn %{path: path}, entry ->
        case File.read(path) do
          {:ok, bytes} ->
            upload = %{
              filename: entry.client_name,
              bytes: bytes,
              client_type: entry.client_type
            }

            {:ok, {upload, descriptor}}

          {:error, reason} ->
            {:ok, {:error, {:file_read_failed, reason}}}
        end
      end)

    case artifact_or_error do
      {%{filename: filename} = upload, descriptor} ->
        with {:ok, database} <-
               create_catalog_database(
                 organization_id,
                 mission.mission_id,
                 descriptor,
                 form_params,
                 filename,
                 uploaded_by
               ),
             artifact <-
               Artifact.build_from_upload(mission.mission_id, descriptor, upload,
                 uploaded_by: uploaded_by,
                 catalog_database_id: database.catalog_database_id
               ),
             {:ok, run} <-
               Catalog.start_revision_import(
                 organization_id,
                 mission.mission_id,
                 database.catalog_database_id,
                 artifact,
                 descriptor.importer_key,
                 requested_by: uploaded_by,
                 metadata: revision_metadata(form_params)
               ) do
          {:noreply,
           push_navigate(socket,
             to: ~p"/missions/#{mission.mission_id}/catalog/imports/#{run.import_run_id}"
           )}
        else
          {:error, reason} ->
            {:noreply,
             put_flash(socket, :error, "Failed to start revision import: #{inspect(reason)}")}
        end

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to read uploaded file: #{inspect(reason)}")}
    end
  end

  defp create_catalog_database(
         organization_id,
         mission_id,
         descriptor,
         form_params,
         filename,
         uploaded_by
       ) do
    name = normalize(form_params["name"]) || filename |> Path.rootname() |> String.trim()
    revision_label = normalize(form_params["revision_label"]) || "Revision 1"

    Catalog.create_database(organization_id, mission_id, %{
      name: name,
      slug: slugify(name),
      catalog_family: descriptor.catalog_family,
      default_importer_key: descriptor.importer_key,
      created_by: uploaded_by,
      metadata: %{"initial_revision_label" => revision_label}
    })
  end

  defp revision_metadata(form_params) do
    %{
      "revision_label" => normalize(form_params["revision_label"]) || "Revision 1",
      "revision_notes" => normalize(form_params["revision_notes"]) || ""
    }
  end

  defp uploader_identity(socket) do
    case socket.assigns.current_scope do
      %{user: %{id: id, email: email}} -> %{user_id: id, email: email}
      %{user: %{email: email}} -> %{email: email}
      _ -> %{}
    end
  end

  defp empty_database_form do
    to_form(%{"name" => "", "revision_label" => "", "revision_notes" => ""},
      as: :catalog_database
    )
  end

  defp normalize(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp normalize(_other), do: nil

  defp slugify(value) when is_binary(value) do
    value
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/, "-")
    |> String.trim("-")
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6 max-w-2xl">
      <div>
        <.link
          navigate={~p"/missions/#{@current_mission.mission_id}/catalog"}
          class="text-sm text-primary hover:underline"
        >
          &larr; Catalog
        </.link>
        <h1 class="text-2xl font-bold text-base-content mt-1">New catalog database</h1>
      </div>

      <.upload_card uploads={@uploads} form={@database_form} />

      <div>
        <.link
          navigate={~p"/missions/#{@current_mission.mission_id}/catalog"}
          class="btn btn-ghost"
        >
          Cancel
        </.link>
      </div>
    </div>
    """
  end
end
```

- [ ] **Step 5: Run the new test file and verify everything passes**

```bash
cd apps/cadence_web && mix test test/cadence_web/live/catalog/catalog_database_new_live_test.exs
```

Expected: all four tests pass.

- [ ] **Step 6: Run `mix compile --warnings-as-errors` and `mix format`**

```bash
cd apps/cadence_web && mix format lib/cadence_web/live/catalog/catalog_database_new_live.ex lib/cadence_web/router.ex && mix compile --warnings-as-errors
```

Expected: clean build.

- [ ] **Step 7: Commit**

```bash
git add apps/cadence_web/lib/cadence_web/live/catalog/catalog_database_new_live.ex apps/cadence_web/test/cadence_web/live/catalog/catalog_database_new_live_test.exs apps/cadence_web/lib/cadence_web/router.ex
git commit -m "feat(cadence_web): add CatalogDatabaseNewLive page for creating databases"
```

---

## Task 3: Swap inline upload card on the index for a `+ New database` CTA

**Files:**
- Modify: `apps/cadence_web/lib/cadence_web/live/catalog/catalog_index_live.ex`
- Modify: `apps/cadence_web/test/cadence_web/live/catalog/catalog_index_live_test.exs`

Rationale: the new page is live and tested; the index's own upload is now redundant. Strip the upload flow out of the index and replace with a CTA that links to `/catalog/new`. This removes `handle_event("validate" | "cancel_upload" | "save", ...)`, `allow_upload/3`, `:database_form`, and seven helpers.

- [ ] **Step 1: Update the index test — replace the `upload flow` describe block**

In `apps/cadence_web/test/cadence_web/live/catalog/catalog_index_live_test.exs`, delete the entire `describe "upload flow" do ... end` block (currently the final describe, roughly lines 95–161).

Replace the `"shows empty state when no catalog databases exist"` test body (lines 22–29) with:

```elixir
    test "shows empty state with a new-database CTA when no catalog databases exist" do
      {conn, _org, mission} = signed_in_org_and_mission()

      {:ok, _view, html} = live(conn, ~p"/missions/#{mission.mission_id}/catalog")

      assert html =~ "No catalog databases"
      assert html =~ "id=\"new-database-link\""
      assert html =~ ~p"/missions/#{mission.mission_id}/catalog/new"
      refute html =~ "catalog-upload-form"
      refute html =~ "Create catalog database revision"
    end
```

Add a new test immediately after:

```elixir
    test "renders a + New database CTA in the page header" do
      {conn, _org, mission} = signed_in_org_and_mission()
      _database = TestFixtures.persist_catalog_database!(mission, name: "Existing Catalog")

      {:ok, _view, html} = live(conn, ~p"/missions/#{mission.mission_id}/catalog")

      assert html =~ "id=\"new-database-link\""
      assert html =~ "New database"
      assert html =~ ~p"/missions/#{mission.mission_id}/catalog/new"
      refute html =~ "catalog-upload-form"
    end
```

- [ ] **Step 2: Run the index test and verify the new assertions fail**

```bash
cd apps/cadence_web && mix test test/cadence_web/live/catalog/catalog_index_live_test.exs
```

Expected: the empty-state test and the new CTA test fail because (a) `catalog-upload-form` is still in the rendered HTML and (b) `new-database-link` is not yet emitted.

- [ ] **Step 3: Strip upload plumbing from `CatalogIndexLive`**

In `apps/cadence_web/lib/cadence_web/live/catalog/catalog_index_live.ex`:

Replace `mount/3` with this shorter version (drops `database_form` and `allow_upload`):

```elixir
  @impl true
  def mount(_params, _session, socket) do
    mission = socket.assigns.current_mission
    organization_id = socket.assigns.current_scope.organization_id

    if connected?(socket), do: Events.subscribe_import_runs(mission.mission_id)

    {:ok,
     socket
     |> assign(:page_title, "Catalog")
     |> assign(:nav_item, :catalog)
     |> assign_databases(organization_id, mission.mission_id)}
  end
```

Delete these four `handle_event` clauses from the module:

```elixir
  @impl true
  def handle_event("validate", %{"catalog_database" => params}, socket) do
    {:noreply, assign(socket, :database_form, to_form(params, as: :catalog_database))}
  end

  def handle_event("validate", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("cancel_upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :artifact, ref)}
  end

  def handle_event("save", params, socket) do
    form_params = Map.get(params, "catalog_database", %{})

    case detect_from_uploads(socket) do
      {:ok, registration} ->
        perform_upload(socket, registration, form_params)

      _ ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "Pick a file with a supported format before uploading."
         )}
    end
  end
```

Delete, by name, every one of these private helpers from the module — each was only used by the upload flow and becomes dead code once the `handle_event` clauses above are gone:

- `perform_upload/3`
- `create_catalog_database/6`
- `revision_metadata/1`
- `detect_from_uploads/1`
- `uploader_identity/1`
- `empty_database_form/0`
- both clauses of `normalize/1`
- `slugify/1`

The `alias Cadence.Catalog.Artifact` line at the top of the module also becomes unused — delete it. The `alias Cadence.Catalog` alias is still used (in `assign_databases/3`), keep it. The `import CadenceWeb.Catalog.Components` is still used (for `import_run_status_badge`, `action_menu` stays in core components) — double-check after the edit that all remaining calls resolve.

- [ ] **Step 4: Replace the render header with a CTA + remove `<.upload_card ...>`**

In the same file, replace the current `render/1` body:

```heex
    <div class="space-y-6">
      <div class="flex items-start justify-between gap-4">
        <div>
          <h1 class="text-2xl font-bold text-base-content">Catalog</h1>
          <p class="text-sm text-base-content/60 mt-1">
            Mission database library. Revisions are imported here; runtime usage is selected later.
          </p>
        </div>
      </div>

      <.upload_card uploads={@uploads} form={@database_form} />

      <.databases_table
        current_mission={@current_mission}
        databases={@databases}
        latest_revisions={@latest_revisions}
        latest_runs={@latest_runs}
      />
    </div>
```

with:

```heex
    <div class="space-y-6">
      <div class="flex items-start justify-between gap-4">
        <div>
          <h1 class="text-2xl font-bold text-base-content">Catalog</h1>
          <p class="text-sm text-base-content/60 mt-1">
            Mission database library. Revisions are imported here; runtime usage is selected later.
          </p>
        </div>
        <.link
          id="new-database-link"
          navigate={~p"/missions/#{@current_mission.mission_id}/catalog/new"}
          class="btn btn-primary"
        >
          + New database
        </.link>
      </div>

      <.databases_table
        current_mission={@current_mission}
        databases={@databases}
        latest_revisions={@latest_revisions}
        latest_runs={@latest_runs}
      />
    </div>
```

- [ ] **Step 5: Update the empty-state block inside `databases_table/1`**

In the same file, inside `databases_table/1`, replace the empty-state branch:

```heex
    <%= if @databases == [] do %>
      <div class="card bg-base-200" id="catalog-database-list">
        <div class="card-body p-6 text-center">
          <p class="hud-label text-base-content/60">No catalog databases yet</p>
          <p class="text-sm text-base-content/50 mt-1">
            Upload a command and telemetry database to create the first immutable revision.
          </p>
        </div>
      </div>
```

with:

```heex
    <%= if @databases == [] do %>
      <div class="card bg-base-200" id="catalog-database-list">
        <div class="card-body p-6 text-center space-y-3">
          <p class="hud-label text-base-content/60">No catalog databases yet</p>
          <p class="text-sm text-base-content/50">
            Upload a command and telemetry database to create the first immutable revision.
          </p>
          <.link
            id="new-database-link"
            navigate={~p"/missions/#{@current_mission.mission_id}/catalog/new"}
            class="btn btn-primary btn-sm"
          >
            + New database
          </.link>
        </div>
      </div>
```

Note the empty-state uses the same `id="new-database-link"` as the header link. Because `databases_table/1` only renders the empty-state branch when `@databases == []`, the header link is the only one present when any databases exist, so the ID is never duplicated in the DOM.

- [ ] **Step 6: Run the index test and verify it passes**

```bash
cd apps/cadence_web && mix test test/cadence_web/live/catalog/catalog_index_live_test.exs
```

Expected: all tests pass.

- [ ] **Step 7: Run the full `cadence_web` test suite**

```bash
cd apps/cadence_web && mix test
```

Expected: clean green. Watch for unexpected failures in any test that touched the old inline upload form.

- [ ] **Step 8: Run `mix compile --warnings-as-errors` and `mix format`**

```bash
cd apps/cadence_web && mix format lib/cadence_web/live/catalog/catalog_index_live.ex && mix compile --warnings-as-errors
```

Expected: clean build, no `alias Cadence.Catalog.Artifact` left over.

- [ ] **Step 9: Commit**

```bash
git add apps/cadence_web/lib/cadence_web/live/catalog/catalog_index_live.ex apps/cadence_web/test/cadence_web/live/catalog/catalog_index_live_test.exs
git commit -m "feat(cadence_web): replace catalog index upload card with + New database CTA"
```

---

## Task 4: Inline-reveal "Add revision" on database detail

**Files:**
- Modify: `apps/cadence_web/lib/cadence_web/live/catalog/catalog_database_show_live.ex`
- Modify: `apps/cadence_web/test/cadence_web/live/catalog/catalog_database_show_live_test.exs`

Rationale: the database-detail page currently renders `revision_upload_card/1` unconditionally. Gate it behind a `@show_revision_form` assign that defaults to `false`. A single button in the page header toggles the state (`+ Add revision` when closed; `Cancel` when open). Cancelling also releases any in-flight upload entries and resets the form to blanks.

- [ ] **Step 1: Add failing assertions for the toggle behavior**

In `apps/cadence_web/test/cadence_web/live/catalog/catalog_database_show_live_test.exs`, add these tests at the end of the file, inside the existing module:

```elixir
  test "add-revision form is hidden by default and shown on toggle" do
    {conn, _org, mission} = signed_in_org_and_mission()
    database = TestFixtures.persist_catalog_database!(mission, name: "Payload Catalog")

    {:ok, view, html} =
      live(
        conn,
        ~p"/missions/#{mission.mission_id}/catalog/databases/#{database.catalog_database_id}"
      )

    refute html =~ "catalog-revision-upload-form"
    assert html =~ "id=\"add-revision-toggle\""
    assert html =~ "Add revision"

    html_after_open =
      view
      |> element("#add-revision-toggle")
      |> render_click()

    assert html_after_open =~ "catalog-revision-upload-form"
    assert html_after_open =~ "Cancel"
  end

  test "cancelling the add-revision reveal hides the form" do
    {conn, _org, mission} = signed_in_org_and_mission()
    database = TestFixtures.persist_catalog_database!(mission, name: "Payload Catalog")

    {:ok, view, _html} =
      live(
        conn,
        ~p"/missions/#{mission.mission_id}/catalog/databases/#{database.catalog_database_id}"
      )

    _ = view |> element("#add-revision-toggle") |> render_click()
    assert render(view) =~ "catalog-revision-upload-form"

    html_after_cancel =
      view
      |> element("#add-revision-toggle")
      |> render_click()

    refute html_after_cancel =~ "catalog-revision-upload-form"
    assert html_after_cancel =~ "Add revision"
  end
```

- [ ] **Step 2: Run the database-show test and verify the new tests fail**

```bash
cd apps/cadence_web && mix test test/cadence_web/live/catalog/catalog_database_show_live_test.exs
```

Expected: the two new tests fail. The first fails on `refute html =~ "catalog-revision-upload-form"` because the form is currently rendered unconditionally. The second fails on the `element("#add-revision-toggle")` lookup because no such element exists.

- [ ] **Step 3: Add the `@show_revision_form` assign and toggle handler**

In `apps/cadence_web/lib/cadence_web/live/catalog/catalog_database_show_live.ex`, update `mount/3` to initialize the assign. The current mount returns a socket piped through several assigns; add `|> assign(:show_revision_form, false)` just before `|> assign_database_details(...)`. Resulting mount body:

```elixir
      {:ok, database} ->
        if connected?(socket), do: Events.subscribe_import_runs(mission.mission_id)

        {:ok,
         socket
         |> assign(:page_title, database.name)
         |> assign(:nav_item, :catalog)
         |> assign(:database, database)
         |> assign(:revision_form, empty_revision_form())
         |> assign(:show_revision_form, false)
         |> assign_database_details(organization_id, mission.mission_id, catalog_database_id)
         |> allow_upload(:artifact,
           accept: :any,
           max_entries: 1,
           max_file_size: 50 * 1024 * 1024
         )}
```

Add a new `handle_event` clause above the existing `"validate"` clauses:

```elixir
  @impl true
  def handle_event("toggle_revision_form", _params, socket) do
    toggled = !socket.assigns.show_revision_form

    socket =
      if toggled do
        socket
      else
        socket
        |> cancel_active_uploads(:artifact)
        |> assign(:revision_form, empty_revision_form())
      end

    {:noreply, assign(socket, :show_revision_form, toggled)}
  end
```

Add the helper near the bottom of the module (above the last `defp normalize/1` clause):

```elixir
  defp cancel_active_uploads(socket, name) do
    socket.assigns.uploads
    |> Map.get(name)
    |> case do
      nil ->
        socket

      upload ->
        Enum.reduce(upload.entries, socket, fn entry, acc ->
          cancel_upload(acc, name, entry.ref)
        end)
    end
  end
```

- [ ] **Step 4: Render the toggle button and gate the form**

In the same file's `render/1`, replace the page header `<div>` that wraps the title with this version — the title row now holds the `+ Add revision` / `Cancel` toggle button on the right:

```heex
      <div>
        <.link navigate={~p"/missions/#{@current_mission.mission_id}/catalog"} class="text-sm text-primary hover:underline">
          &larr; Catalog
        </.link>
        <div class="mt-1 flex items-start justify-between gap-4">
          <div>
            <h1 class="text-2xl font-bold text-base-content">{@database.name}</h1>
            <p class="font-mono text-sm text-base-content/50">{@database.slug}</p>
          </div>
          <button
            id="add-revision-toggle"
            type="button"
            phx-click="toggle_revision_form"
            class={[if(@show_revision_form, do: "btn btn-ghost", else: "btn btn-primary")]}
          >
            {if @show_revision_form, do: "Cancel", else: "+ Add revision"}
          </button>
        </div>
      </div>
```

Then replace the bare `<.revision_upload_card ... />` call with a guarded version:

```heex
      <.revision_upload_card :if={@show_revision_form} uploads={@uploads} form={@revision_form} />
```

- [ ] **Step 5: Run the database-show tests and verify they pass**

```bash
cd apps/cadence_web && mix test test/cadence_web/live/catalog/catalog_database_show_live_test.exs
```

Expected: all tests pass, including both toggle tests.

- [ ] **Step 6: Run the full `cadence_web` suite and `mix compile --warnings-as-errors`**

```bash
cd apps/cadence_web && mix test && mix format lib/cadence_web/live/catalog/catalog_database_show_live.ex && mix compile --warnings-as-errors
```

Expected: clean green, clean build.

- [ ] **Step 7: Manually verify in the browser**

From the repo root:

```bash
mix phx.server
```

Then in a browser:
1. Sign in, navigate to any mission's catalog (`/missions/<id>/catalog`).
2. Confirm there is a `+ New database` button in the top-right and no inline upload card.
3. Click it, arrive at `/catalog/new`, create a database by uploading a valid YAML artifact — should navigate to the import run detail.
4. From the catalog page, click into the database detail; confirm the revision history renders and `+ Add revision` is the only way to reveal the form. Click it, confirm the form appears; click `Cancel`, confirm the form hides and the form fields reset.

Report the manual check in the commit message or plan checklist.

- [ ] **Step 8: Commit**

```bash
git add apps/cadence_web/lib/cadence_web/live/catalog/catalog_database_show_live.ex apps/cadence_web/test/cadence_web/live/catalog/catalog_database_show_live_test.exs
git commit -m "feat(cadence_web): gate add-revision form behind a toggle"
```

---

## Final Verification

- [ ] **Step 1: Run the full test suite for both apps**

```bash
cd apps/cadence && mix test
cd ../cadence_web && mix test
```

Expected: clean green across both apps.

- [ ] **Step 2: Run `mix compile --warnings-as-errors` at the umbrella root**

```bash
mix compile --warnings-as-errors
```

Expected: clean build.

- [ ] **Step 3: Run `mix credo --strict` and leave the codebase no worse than found**

```bash
mix credo --strict
```

Expected: no new violations introduced by these changes. (Pre-existing violations may still appear; do not mix cleanup into this plan.)

- [ ] **Step 4: Run `mix format` on touched files**

```bash
mix format apps/cadence_web/lib/cadence_web/live/catalog/*.ex apps/cadence_web/lib/cadence_web/router.ex apps/cadence_web/test/cadence_web/live/catalog/*.ex
```
