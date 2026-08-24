defmodule CadenceWeb.CatalogIndexLive do
  @moduledoc false

  use CadenceWeb, :live_view

  alias Cadence.Catalog
  alias Cadence.Catalog.Events

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

  @impl true
  def handle_info({event, _run}, socket)
      when event in [
             :import_run_started,
             :import_run_updated,
             :import_run_completed,
             :import_run_failed
           ] do
    mission = socket.assigns.current_mission
    organization_id = socket.assigns.current_scope.organization_id

    {:noreply, assign_databases(socket, organization_id, mission.mission_id)}
  end

  defp assign_databases(socket, organization_id, mission_id) do
    databases = Catalog.list_databases(organization_id, mission_id)
    latest_revisions = Catalog.latest_revision_by_database(organization_id, mission_id)
    latest_runs = Catalog.latest_import_run_by_database(organization_id, mission_id)

    socket
    |> assign(:databases, databases)
    |> assign(:latest_revisions, latest_revisions)
    |> assign(:latest_runs, latest_runs)
    |> assign(
      :database_table_rows,
      Enum.map(databases, &database_table_row(&1, mission_id, latest_revisions, latest_runs))
    )
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <.page_header
        title="Catalog"
        subtitle="Mission database library. Revisions are imported here; runtime usage is selected later."
        breadcrumbs={[
          {@current_mission.display_name, ~p"/missions/#{@current_mission.mission_id}"},
          {"Catalog", nil}
        ]}
      >
        <:actions>
          <.button
            id="new-database-link"
            navigate={~p"/missions/#{@current_mission.mission_id}/catalog/new"}
            class="gap-1"
          >
            <span class="hero-plus h-4 w-4"></span> New database
          </.button>
        </:actions>
      </.page_header>

      <.databases_table
        current_mission={@current_mission}
        databases={@databases}
        latest_revisions={@latest_revisions}
        latest_runs={@latest_runs}
        database_table_rows={@database_table_rows}
      />
    </div>
    """
  end

  attr(:current_mission, :map, required: true)
  attr(:databases, :list, required: true)
  attr(:latest_revisions, :map, required: true)
  attr(:latest_runs, :map, required: true)
  attr(:database_table_rows, :list, required: true)

  defp databases_table(assigns) do
    ~H"""
    <%= if @databases == [] do %>
      <div id="catalog-database-list">
        <.empty_state
          title="No catalog databases yet"
          description="Use + New database above to import the first revision."
        />
      </div>
    <% else %>
      <.card id="catalog-database-list" padding={:none}>
        <.vue
          id="catalog-databases-table-component"
          v-component="CatalogDatabaseTable"
          rows={@database_table_rows}
          v-ssr={false}
        />
      </.card>
    <% end %>
    """
  end

  defp database_table_row(database, mission_id, latest_revisions, latest_runs) do
    database_id = database.catalog_database_id
    revision = Map.get(latest_revisions, database_id)
    run = Map.get(latest_runs, database_id)

    %{
      id: "catalog-database-row-#{database_id}",
      actions_id: "#{database_id}-actions",
      name: database.name,
      slug: database.slug,
      href: ~p"/missions/#{mission_id}/catalog/databases/#{database_id}",
      latest_revision: latest_revision_dto(revision, mission_id),
      latest_import: latest_import_dto(run, mission_id)
    }
  end

  defp latest_revision_dto(nil, _mission_id), do: nil

  defp latest_revision_dto(revision, mission_id) do
    %{
      label: revision.revision_label,
      href: ~p"/missions/#{mission_id}/catalog/revisions/#{revision.catalog_revision_id}"
    }
  end

  defp latest_import_dto(nil, _mission_id), do: nil

  defp latest_import_dto(run, mission_id) do
    %{
      status: import_status_badge(run.status),
      status_label: import_status_label(run.status),
      href: ~p"/missions/#{mission_id}/catalog/imports/#{run.import_run_id}"
    }
  end

  defp import_status_badge(:running), do: "info"
  defp import_status_badge(:completed), do: "ready"
  defp import_status_badge(:failed), do: "blocked"
  defp import_status_badge(_status), do: "info"

  defp import_status_label(:running), do: "Running"
  defp import_status_label(:completed), do: "Completed"
  defp import_status_label(:failed), do: "Failed"
  defp import_status_label(status), do: status |> to_string() |> String.capitalize()
end
