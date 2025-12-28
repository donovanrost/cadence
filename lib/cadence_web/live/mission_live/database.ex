defmodule CadenceWeb.MissionLive.Database do
  @moduledoc """
  LiveView for the Mission Database Catalog management page.

  Provides database catalog management:
  - List all databases in the mission catalog
  - Create/edit databases
  - View database versions (DefinitionSets)
  - Import new versions

  For searching/browsing definitions, see MissionLive.Catalog.
  """
  use CadenceWeb, :live_view

  require Logger

  alias Cadence.MissionDatabase
  alias Cadence.MissionDatabase.DefinitionSet

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    mission = socket.assigns.mission

    case Bodyguard.permit(Cadence.Missions.Policy, :view, socket.assigns.current_scope, mission) do
      :ok ->
        {:noreply, apply_action(socket, socket.assigns.live_action, params)}

      {:error, _} ->
        {:noreply,
         socket
         |> put_flash(:error, "You don't have permission to view this mission")
         |> push_navigate(to: ~p"/missions")}
    end
  end

  defp apply_action(socket, :index, _params) do
    mission = socket.assigns.mission

    # Load all databases with their stats
    databases = MissionDatabase.list_databases_with_stats(mission.id)

    Logger.debug(
      "Database catalog loaded for mission #{mission.id}: #{length(databases)} databases"
    )

    socket
    |> assign(:page_title, "Database Catalog")
    |> assign(:databases, databases)
    |> assign(:selected_database, nil)
  end

  defp apply_action(socket, :new_database, _params) do
    socket
    |> apply_action(:index, %{})
    |> assign(:page_title, "New Database")
  end

  defp apply_action(socket, :edit_database, %{"database_id" => database_id}) do
    database = MissionDatabase.get_database(database_id)

    socket
    |> apply_action(:index, %{})
    |> assign(:page_title, "Edit Database")
    |> assign(:editing_database, database)
  end

  defp apply_action(socket, :show_database, %{"database_id" => database_id}) do
    database = MissionDatabase.get_database(database_id)
    definition_sets = MissionDatabase.list_definition_sets(database_id)

    socket
    |> apply_action(:index, %{})
    |> assign(:page_title, database.name)
    |> assign(:selected_database, database)
    |> assign(:definition_sets, definition_sets)
  end

  defp apply_action(socket, :import, %{"database_id" => database_id}) do
    database = MissionDatabase.get_database(database_id)

    socket
    |> apply_action(:show_database, %{"database_id" => database_id})
    |> assign(:page_title, "Import Version")
    |> assign(:importing_to_database, database)
  end

  defp apply_action(socket, :show_version, %{
         "database_id" => database_id,
         "version_id" => version_id
       }) do
    socket
    |> apply_action(:show_database, %{"database_id" => database_id})
    |> assign(:page_title, "Version Details")
    |> assign(:viewing_version_id, version_id)
  end

  @impl true
  def handle_event("publish", %{"id" => id}, socket) do
    case MissionDatabase.get_definition_set(id) do
      nil ->
        {:noreply, put_flash(socket, :error, "Version not found")}

      definition_set ->
        case DefinitionSet.publish(definition_set) do
          {:ok, published} ->
            Logger.info("Published database version #{published.version}")
            {:noreply, reload_database(socket)}

          {:error, _reason} ->
            {:noreply, put_flash(socket, :error, "Failed to publish version")}
        end
    end
  end

  @impl true
  def handle_event("delete_database", %{"id" => id}, socket) do
    case MissionDatabase.get_database(id) do
      nil ->
        {:noreply, put_flash(socket, :error, "Database not found")}

      database ->
        case MissionDatabase.delete_database(database) do
          {:ok, _deleted} ->
            {:noreply,
             socket
             |> put_flash(:info, "Database #{database.name} deleted")
             |> push_patch(to: ~p"/missions/#{socket.assigns.mission}/database")}

          {:error, _reason} ->
            {:noreply, put_flash(socket, :error, "Failed to delete database")}
        end
    end
  end

  @impl true
  def handle_info({CadenceWeb.DatabaseLive.FormComponent, {:saved, _definition_set}}, socket) do
    Logger.info("Database import completed")
    {:noreply, reload_database(socket)}
  end

  @impl true
  def handle_info({CadenceWeb.DatabaseLive.DatabaseFormComponent, {:saved, _database}}, socket) do
    Logger.info("Database created/updated")
    {:noreply, reload_all(socket)}
  end

  @impl true
  def handle_info({CadenceWeb.DatabaseLive.ShowComponent, {:published, _definition_set}}, socket) do
    {:noreply, reload_database(socket)}
  end

  @impl true
  def handle_info({CadenceWeb.DatabaseLive.ShowComponent, {:deleted, _definition_set}}, socket) do
    {:noreply, reload_database(socket)}
  end

  @impl true
  def handle_info({:database_saved, _database}, socket) do
    {:noreply, reload_all(socket)}
  end

  defp reload_all(socket) do
    mission_id = socket.assigns.mission.id
    databases = MissionDatabase.list_databases_with_stats(mission_id)

    socket
    |> assign(:databases, databases)
  end

  defp reload_database(socket) do
    socket = reload_all(socket)

    if socket.assigns[:selected_database] do
      database_id = socket.assigns.selected_database.id
      definition_sets = MissionDatabase.list_definition_sets(database_id)
      assign(socket, :definition_sets, definition_sets)
    else
      socket
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <%= if @selected_database do %>
        <.breadcrumb items={[
          {"Database Catalog", ~p"/missions/#{@mission}/database"},
          {@selected_database.name, nil}
        ]} />
      <% end %>
      
    <!-- Header -->
      <.header>
        Database Catalog
        <:subtitle>Manage command and telemetry database definitions</:subtitle>
        <:actions>
          <.link navigate={~p"/missions/#{@mission}/catalog"}>
            <.button class="btn-ghost">
              <.icon name="hero-magnifying-glass" class="h-4 w-4 mr-1" /> Browse Catalog
            </.button>
          </.link>
          <.link patch={~p"/missions/#{@mission}/database/new"}>
            <.button>
              <.icon name="hero-plus" class="h-4 w-4 mr-1" /> New Database
            </.button>
          </.link>
        </:actions>
      </.header>

      <%= if @selected_database do %>
        <!-- Database Detail View -->
        <.database_detail_view
          database={@selected_database}
          definition_sets={@definition_sets}
          mission={@mission}
        />
      <% else %>
        <!-- Catalog Grid -->
        <%= if Enum.empty?(@databases) do %>
          <div class="card bg-base-200">
            <div class="card-body items-center text-center py-12">
              <div class="rounded-full bg-base-300 p-4 mb-4">
                <.icon name="hero-circle-stack" class="h-12 w-12 text-base-content/40" />
              </div>
              <h3 class="text-lg font-semibold">No Databases Yet</h3>
              <p class="text-base-content/60 max-w-md">
                Create a database to organize command and telemetry definitions for your spacecraft.
              </p>
              <.link patch={~p"/missions/#{@mission}/database/new"} class="mt-4">
                <.button>
                  <.icon name="hero-plus" class="-ml-1 mr-2 h-5 w-5" /> Create Database
                </.button>
              </.link>
            </div>
          </div>
        <% else %>
          <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
            <%= for %{database: db, version_count: version_count, latest_version: latest_version} <- @databases do %>
              <.link
                patch={~p"/missions/#{@mission}/database/#{db.id}"}
                class="card bg-base-200 hover:bg-base-300/50 transition-colors cursor-pointer"
              >
                <div class="card-body p-5">
                  <div class="flex items-start justify-between">
                    <div class="flex items-center gap-3">
                      <div class="rounded-full bg-primary/20 p-2">
                        <.icon name="hero-circle-stack" class="h-5 w-5 text-primary" />
                      </div>
                      <div>
                        <h3 class="font-semibold">{db.name}</h3>
                        <p class="text-xs text-base-content/50 font-mono">{db.slug}</p>
                      </div>
                    </div>
                    <%= if latest_version do %>
                      <span class="badge badge-sm">v{latest_version}</span>
                    <% end %>
                  </div>

                  <%= if db.description do %>
                    <p class="text-sm text-base-content/70 mt-2 line-clamp-2">{db.description}</p>
                  <% end %>

                  <div class="flex items-center justify-between mt-4 text-sm text-base-content/60">
                    <span>
                      {version_count} {if version_count == 1, do: "version", else: "versions"}
                    </span>
                    <.icon name="hero-chevron-right" class="h-4 w-4" />
                  </div>
                </div>
              </.link>
            <% end %>
          </div>
        <% end %>
      <% end %>
    </div>

    <!-- New/Edit Database Modal -->
    <.modal
      :if={@live_action in [:new_database, :edit_database]}
      id="database-form-modal"
      show
      on_cancel={JS.patch(~p"/missions/#{@mission}/database")}
    >
      <.live_component
        module={CadenceWeb.DatabaseLive.DatabaseFormComponent}
        id={if @live_action == :new_database, do: :new, else: @editing_database.id}
        title={if @live_action == :new_database, do: "New Database", else: "Edit Database"}
        action={if @live_action == :new_database, do: :new, else: :edit}
        database={
          if @live_action == :new_database,
            do: %Cadence.MissionDatabase.Database{},
            else: @editing_database
        }
        mission={@mission}
        current_scope={@current_scope}
        patch={~p"/missions/#{@mission}/database"}
      />
    </.modal>

    <!-- Import Version Modal -->
    <.modal
      :if={@live_action == :import}
      id="import-modal"
      show
      on_cancel={JS.patch(~p"/missions/#{@mission}/database/#{@selected_database.id}")}
    >
      <.live_component
        module={CadenceWeb.DatabaseLive.FormComponent}
        id={:new}
        title="Import Version"
        database={@importing_to_database}
        mission={@mission}
        current_scope={@current_scope}
        patch={~p"/missions/#{@mission}/database/#{@selected_database.id}"}
      />
    </.modal>

    <!-- Version Details Modal -->
    <.modal
      :if={@live_action == :show_version}
      id="version-modal"
      show
      on_cancel={JS.patch(~p"/missions/#{@mission}/database/#{@selected_database.id}")}
    >
      <.live_component
        module={CadenceWeb.DatabaseLive.ShowComponent}
        id={@viewing_version_id}
        definition_set={find_version(@definition_sets, @viewing_version_id)}
        mission={@mission}
        current_scope={@current_scope}
        patch={~p"/missions/#{@mission}/database/#{@selected_database.id}"}
      />
    </.modal>
    """
  end

  # Database detail view component
  attr :database, :map, required: true
  attr :definition_sets, :list, required: true
  attr :mission, :map, required: true

  defp database_detail_view(assigns) do
    ~H"""
    <div class="space-y-6">
      <!-- Header -->
      <div class="flex items-center gap-4">
        <div class="flex-1">
          <h2 class="text-xl font-bold">{@database.name}</h2>
          <p class="text-sm text-base-content/60 font-mono">{@database.slug}</p>
        </div>
        <.link patch={~p"/missions/#{@mission}/database/#{@database.id}/import"}>
          <.button>
            <.icon name="hero-arrow-up-tray" class="h-4 w-4 mr-1" /> Import Version
          </.button>
        </.link>
      </div>

      <%= if @database.description do %>
        <p class="text-base-content/70">{@database.description}</p>
      <% end %>
      
    <!-- Versions List -->
      <div class="space-y-4">
        <h3 class="text-lg font-semibold">Versions</h3>

        <%= if Enum.empty?(@definition_sets) do %>
          <div class="card bg-base-200">
            <div class="card-body items-center text-center py-8">
              <p class="text-base-content/60">No versions imported yet.</p>
              <.link patch={~p"/missions/#{@mission}/database/#{@database.id}/import"} class="mt-2">
                <.button class="btn-sm">Import First Version</.button>
              </.link>
            </div>
          </div>
        <% else %>
          <div class="overflow-x-auto">
            <table class="table">
              <thead>
                <tr>
                  <th>Version</th>
                  <th>Description</th>
                  <th>Status</th>
                  <th>Created</th>
                  <th class="w-16"></th>
                </tr>
              </thead>
              <tbody>
                <%= for ds <- @definition_sets do %>
                  <tr class="hover">
                    <td class="font-mono font-medium">v{ds.version}</td>
                    <td class="max-w-xs truncate text-base-content/70">
                      {ds.description || "—"}
                    </td>
                    <td>
                      <.version_status definition_set={ds} />
                    </td>
                    <td class="text-sm text-base-content/60">
                      {format_datetime(ds.inserted_at)}
                    </td>
                    <td>
                      <.dropdown id={"version-actions-#{ds.id}"}>
                        <:trigger>
                          <button class="btn btn-ghost btn-xs btn-square">
                            <.icon name="hero-ellipsis-vertical" class="h-4 w-4" />
                          </button>
                        </:trigger>
                        <li>
                          <.link patch={
                            ~p"/missions/#{@mission}/database/#{@database.id}/versions/#{ds.id}"
                          }>
                            <.icon name="hero-eye" class="h-4 w-4" /> View Details
                          </.link>
                        </li>
                        <%= if is_nil(ds.published_at) do %>
                          <li>
                            <button phx-click="publish" phx-value-id={ds.id}>
                              <.icon name="hero-arrow-up-circle" class="h-4 w-4" /> Publish
                            </button>
                          </li>
                        <% end %>
                      </.dropdown>
                    </td>
                  </tr>
                <% end %>
              </tbody>
            </table>
          </div>
        <% end %>
      </div>
      
    <!-- Danger Zone -->
      <div class="collapse collapse-arrow bg-error/10 border border-error/20">
        <input type="checkbox" />
        <div class="collapse-title font-medium text-error">
          Danger Zone
        </div>
        <div class="collapse-content">
          <p class="text-sm text-base-content/70 mb-4">
            Deleting this database will remove all versions and cannot be undone.
            Targets using this database will need to be reassigned.
          </p>
          <button
            class="btn btn-error btn-sm"
            phx-click="delete_database"
            phx-value-id={@database.id}
            data-confirm="Are you sure you want to delete this database and all its versions?"
          >
            Delete Database
          </button>
        </div>
      </div>
    </div>
    """
  end

  attr :definition_set, :map, required: true

  defp version_status(assigns) do
    ~H"""
    <%= cond do %>
      <% DefinitionSet.active?(@definition_set) -> %>
        <span class="badge badge-success badge-sm">Active</span>
      <% @definition_set.published_at && @definition_set.superseded_at -> %>
        <div class="flex flex-col gap-1">
          <span class="badge badge-ghost badge-sm">Superseded</span>
          <span class="text-xs text-base-content/50">
            {format_datetime(@definition_set.superseded_at)}
          </span>
        </div>
      <% true -> %>
        <span class="badge badge-warning badge-sm">Draft</span>
    <% end %>
    """
  end

  defp find_version(definition_sets, id) do
    Enum.find(definition_sets, fn ds -> ds.id == id end)
  end

  defp format_datetime(nil), do: "—"

  defp format_datetime(datetime) do
    Calendar.strftime(datetime, "%b %d, %Y %H:%M")
  end
end
