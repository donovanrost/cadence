defmodule CadenceWeb.CatalogIndexLive do
  @moduledoc false

  use CadenceWeb, :live_view

  import CadenceWeb.Catalog.Components

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
      />
    </div>
    """
  end

  attr :current_mission, :map, required: true
  attr :databases, :list, required: true
  attr :latest_revisions, :map, required: true
  attr :latest_runs, :map, required: true

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
        <.table id="catalog-databases-table" rows={@databases} row_accent={false}>
          <:col :let={database} label="Database">
            <.link
              navigate={
                ~p"/missions/#{@current_mission.mission_id}/catalog/databases/#{database.catalog_database_id}"
              }
              class="font-medium hover:underline"
            >
              {database.name}
            </.link>
            <p class="font-mono text-xs text-base-content/50">{database.slug}</p>
          </:col>
          <:col :let={database} label="Latest revision">
            <.latest_revision_cell
              revision={Map.get(@latest_revisions, database.catalog_database_id)}
              current_mission={@current_mission}
            />
          </:col>
          <:col :let={database} label="Latest import">
            <.latest_run_cell
              run={Map.get(@latest_runs, database.catalog_database_id)}
              current_mission={@current_mission}
            />
          </:col>
          <:col :let={_database} label="Runtime usage">
            <span class="badge badge-ghost badge-sm" id="catalog-runtime-usage-summary">
              No runtime bindings yet
            </span>
          </:col>
          <:col :let={database} label="Actions" align={:right}>
            <.action_menu id={"#{database.catalog_database_id}-actions"}>
              <:action>
                <.link navigate={
                  ~p"/missions/#{@current_mission.mission_id}/catalog/databases/#{database.catalog_database_id}"
                }>
                  View database
                </.link>
              </:action>
            </.action_menu>
          </:col>
        </.table>
      </.card>
    <% end %>
    """
  end

  attr :revision, :map, default: nil
  attr :current_mission, :map, required: true

  defp latest_revision_cell(%{revision: nil} = assigns) do
    ~H"""
    <span class="text-base-content/40 text-xs">No revisions</span>
    """
  end

  defp latest_revision_cell(assigns) do
    ~H"""
    <.link
      navigate={
        ~p"/missions/#{@current_mission.mission_id}/catalog/revisions/#{@revision.catalog_revision_id}"
      }
      class="font-mono text-sm hover:underline"
    >
      {@revision.revision_label}
    </.link>
    """
  end

  attr :run, :map, default: nil
  attr :current_mission, :map, required: true

  defp latest_run_cell(%{run: nil} = assigns) do
    ~H"""
    <span class="text-base-content/40 text-xs">—</span>
    """
  end

  defp latest_run_cell(assigns) do
    ~H"""
    <.link
      navigate={~p"/missions/#{@current_mission.mission_id}/catalog/imports/#{@run.import_run_id}"}
      class="inline-flex"
    >
      <.import_run_status_badge status={@run.status} />
    </.link>
    """
  end
end
