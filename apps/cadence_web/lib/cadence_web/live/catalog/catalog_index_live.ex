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
    """
  end

  attr :current_mission, :map, required: true
  attr :databases, :list, required: true
  attr :latest_revisions, :map, required: true
  attr :latest_runs, :map, required: true

  defp databases_table(assigns) do
    ~H"""
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
    <% else %>
      <div class="card bg-base-200" id="catalog-database-list">
        <table class="table">
          <thead>
            <tr>
              <th class="hud-label">Database</th>
              <th class="hud-label">Latest revision</th>
              <th class="hud-label">Latest import</th>
              <th class="hud-label">Runtime usage</th>
              <th class="hud-label text-right">Actions</th>
            </tr>
          </thead>
          <tbody>
            <tr :for={database <- @databases}>
              <td>
                <.link
                  navigate={
                    ~p"/missions/#{@current_mission.mission_id}/catalog/databases/#{database.catalog_database_id}"
                  }
                  class="font-medium hover:underline"
                >
                  {database.name}
                </.link>
                <p class="font-mono text-xs text-base-content/50">{database.slug}</p>
              </td>
              <td>
                <.latest_revision_cell
                  revision={Map.get(@latest_revisions, database.catalog_database_id)}
                  current_mission={@current_mission}
                />
              </td>
              <td>
                <.latest_run_cell
                  run={Map.get(@latest_runs, database.catalog_database_id)}
                  current_mission={@current_mission}
                />
              </td>
              <td>
                <span class="badge badge-ghost badge-sm" id="catalog-runtime-usage-summary">
                  No runtime bindings yet
                </span>
              </td>
              <td class="text-right">
                <.action_menu>
                  <:action>
                    <.link navigate={
                      ~p"/missions/#{@current_mission.mission_id}/catalog/databases/#{database.catalog_database_id}"
                    }>
                      View database
                    </.link>
                  </:action>
                </.action_menu>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
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
