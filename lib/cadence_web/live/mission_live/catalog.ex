defmodule CadenceWeb.MissionLive.Catalog do
  @moduledoc """
  LiveView for the Mission Catalog page.

  Provides unified search and browsing of:
  - Telemetry parameters
  - Command definitions
  - Derived items

  This is the operator-focused view for looking up definitions.
  For database version management, see MissionLive.Database.
  """
  use CadenceWeb, :live_view

  alias Cadence.MissionDatabase
  alias Cadence.Telemetry.Database.DerivedItem

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

    # Load databases with stats for the mission
    databases_with_stats = MissionDatabase.list_databases_with_stats(mission.id)

    # Build flat list of available definition sets with database info
    available_def_sets = build_available_definition_sets(databases_with_stats)

    # Default to first available definition set
    default_ds = List.first(available_def_sets)
    definition_set_id = if default_ds, do: default_ds.id, else: nil

    # Load initial catalog (empty query = all items)
    catalog = MissionDatabase.search_catalog(definition_set_id, mission.id, "", limit: 50)

    socket
    |> assign(:page_title, "Catalog")
    |> assign(:databases, databases_with_stats)
    |> assign(:available_definition_sets, available_def_sets)
    |> assign(:selected_definition_set_id, definition_set_id)
    |> assign(:catalog_items, catalog.items)
    |> assign(:total_count, catalog.total_count)
    |> assign(:has_more, catalog.has_more)
    |> assign(:search_query, "")
    |> assign(:type_filter, :all)
    |> assign(:page, 0)
    |> assign(:expanded_items, MapSet.new())
  end

  # Build a flat list of definition sets with their database info for the selector
  defp build_available_definition_sets(databases_with_stats) do
    databases_with_stats
    |> Enum.flat_map(fn %{database: db} ->
      db.definition_sets
      |> Enum.map(fn ds ->
        %{
          id: ds.id,
          version: ds.version,
          published_at: ds.published_at,
          database_name: db.name,
          database_slug: db.slug
        }
      end)
    end)
    |> Enum.sort_by(fn ds -> {ds.database_name, ds.version} end)
  end

  defp apply_action(socket, :new_derived, _params) do
    socket
    |> apply_action(:index, %{})
    |> assign(:page_title, "New Derived Item")
    |> assign(:derived_item, %DerivedItem{})
  end

  defp apply_action(socket, :edit_derived, %{"derived_id" => id}) do
    derived_item = DerivedItem.get!(id)

    socket
    |> apply_action(:index, %{})
    |> assign(:page_title, "Edit Derived Item")
    |> assign(:derived_item, derived_item)
  end

  @impl true
  def handle_event("search", %{"query" => query}, socket) do
    catalog =
      MissionDatabase.search_catalog(
        socket.assigns.selected_definition_set_id,
        socket.assigns.mission.id,
        query,
        type: socket.assigns.type_filter,
        limit: 50
      )

    {:noreply,
     socket
     |> assign(:search_query, query)
     |> assign(:catalog_items, catalog.items)
     |> assign(:total_count, catalog.total_count)
     |> assign(:has_more, catalog.has_more)
     |> assign(:page, 0)
     |> assign(:expanded_items, MapSet.new())}
  end

  @impl true
  def handle_event("filter", %{"type" => type}, socket) do
    type_atom = String.to_existing_atom(type)

    catalog =
      MissionDatabase.search_catalog(
        socket.assigns.selected_definition_set_id,
        socket.assigns.mission.id,
        socket.assigns.search_query,
        type: type_atom,
        limit: 50
      )

    {:noreply,
     socket
     |> assign(:type_filter, type_atom)
     |> assign(:catalog_items, catalog.items)
     |> assign(:total_count, catalog.total_count)
     |> assign(:has_more, catalog.has_more)
     |> assign(:page, 0)
     |> assign(:expanded_items, MapSet.new())}
  end

  @impl true
  def handle_event("change_definition_set", %{"definition_set_id" => ""}, socket) do
    # No selection - show nothing
    {:noreply,
     socket
     |> assign(:selected_definition_set_id, nil)
     |> assign(:catalog_items, [])
     |> assign(:total_count, 0)
     |> assign(:has_more, false)
     |> assign(:page, 0)}
  end

  @impl true
  def handle_event("change_definition_set", %{"definition_set_id" => ds_id}, socket) do
    catalog =
      MissionDatabase.search_catalog(
        ds_id,
        socket.assigns.mission.id,
        socket.assigns.search_query,
        type: socket.assigns.type_filter,
        limit: 50
      )

    {:noreply,
     socket
     |> assign(:selected_definition_set_id, ds_id)
     |> assign(:catalog_items, catalog.items)
     |> assign(:total_count, catalog.total_count)
     |> assign(:has_more, catalog.has_more)
     |> assign(:page, 0)
     |> assign(:expanded_items, MapSet.new())}
  end

  @impl true
  def handle_event("load_more", _params, socket) do
    next_page = socket.assigns.page + 1

    catalog =
      MissionDatabase.search_catalog(
        socket.assigns.selected_definition_set_id,
        socket.assigns.mission.id,
        socket.assigns.search_query,
        type: socket.assigns.type_filter,
        limit: 50,
        offset: next_page * 50
      )

    {:noreply,
     socket
     |> update(:catalog_items, &(&1 ++ catalog.items))
     |> assign(:has_more, catalog.has_more)
     |> assign(:page, next_page)}
  end

  @impl true
  def handle_event("toggle_expand", %{"id" => id}, socket) do
    expanded = socket.assigns.expanded_items

    new_expanded =
      if MapSet.member?(expanded, id) do
        MapSet.delete(expanded, id)
      else
        MapSet.put(expanded, id)
      end

    {:noreply, assign(socket, :expanded_items, new_expanded)}
  end

  @impl true
  def handle_info({CadenceWeb.DerivedItemLive.FormComponent, {:saved, _derived_item}}, socket) do
    # Reload catalog after derived item save
    catalog =
      MissionDatabase.search_catalog(
        socket.assigns.selected_definition_set_id,
        socket.assigns.mission.id,
        socket.assigns.search_query,
        type: socket.assigns.type_filter,
        limit: 50
      )

    {:noreply,
     socket
     |> assign(:catalog_items, catalog.items)
     |> assign(:total_count, catalog.total_count)
     |> assign(:has_more, catalog.has_more)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <!-- Header -->
      <.header>
        Catalog
        <:subtitle>Search and browse telemetry, commands, and derived items</:subtitle>
        <:actions>
          <.link patch={~p"/missions/#{@mission}/catalog/derived/new"}>
            <.button class="btn-ghost">New Derived Item</.button>
          </.link>
          <.link navigate={~p"/missions/#{@mission}/database"}>
            <.button class="btn-ghost">
              <.icon name="hero-circle-stack" class="h-4 w-4 mr-1" />
              Manage Database
            </.button>
          </.link>
        </:actions>
      </.header>

      <!-- Definition Set Selector -->
      <div class="flex items-center gap-4">
        <label class="text-sm font-medium text-base-content/70">Searching:</label>
        <select
          name="definition_set_id"
          phx-change="change_definition_set"
          class="select select-bordered select-sm min-w-[250px]"
        >
          <option value="">Select a database version...</option>
          <%= for ds <- @available_definition_sets do %>
            <option value={ds.id} selected={@selected_definition_set_id == ds.id}>
              <%= ds.database_name %> v<%= ds.version %><%= if ds.published_at, do: "", else: " (draft)" %>
            </option>
          <% end %>
        </select>
        <span class="text-sm text-base-content/60">
          <%= @total_count %> items in catalog
        </span>
      </div>

      <%= if Enum.empty?(@available_definition_sets) do %>
        <div class="alert">
          <.icon name="hero-information-circle" class="h-5 w-5" />
          <span>No databases available. <.link navigate={~p"/missions/#{@mission}/database"} class="link">Import one</.link> to search telemetry and commands.</span>
        </div>
      <% end %>

      <!-- Search and Filters -->
      <div class="space-y-4">
        <!-- Search Bar -->
        <div class="form-control">
          <div class="input-group">
            <span class="bg-base-200">
              <.icon name="hero-magnifying-glass" class="h-5 w-5" />
            </span>
            <input
              type="text"
              placeholder="Search telemetry, commands, derived items..."
              class="input input-bordered w-full"
              value={@search_query}
              phx-keyup="search"
              phx-debounce="300"
              phx-value-query={@search_query}
              name="query"
              autofocus
            />
          </div>
        </div>

        <!-- Filter Chips -->
        <div class="flex items-center justify-between">
          <div class="btn-group">
            <button
              class={"btn btn-sm #{if @type_filter == :all, do: "btn-active", else: ""}"}
              phx-click="filter"
              phx-value-type="all"
            >
              All
            </button>
            <button
              class={"btn btn-sm #{if @type_filter == :telemetry, do: "btn-active", else: ""}"}
              phx-click="filter"
              phx-value-type="telemetry"
            >
              Telemetry
            </button>
            <button
              class={"btn btn-sm #{if @type_filter == :commands, do: "btn-active", else: ""}"}
              phx-click="filter"
              phx-value-type="commands"
            >
              Commands
            </button>
            <button
              class={"btn btn-sm #{if @type_filter == :derived, do: "btn-active", else: ""}"}
              phx-click="filter"
              phx-value-type="derived"
            >
              Derived
            </button>
          </div>
          <span class="text-sm text-base-content/60">
            <%= @total_count %> <%= if @total_count == 1, do: "item", else: "items" %>
          </span>
        </div>
      </div>

      <!-- Results -->
      <div class="space-y-2">
        <%= if Enum.empty?(@catalog_items) do %>
          <div class="card bg-base-200">
            <div class="card-body items-center text-center py-12">
              <.icon name="hero-magnifying-glass" class="h-12 w-12 text-base-content/40" />
              <h3 class="text-lg font-semibold mt-4">No items found</h3>
              <p class="text-base-content/60">
                <%= if @search_query != "" do %>
                  Try adjusting your search terms or filters.
                <% else %>
                  No items available in this category.
                <% end %>
              </p>
              <%= if @search_query != "" or @type_filter != :all do %>
                <button
                  class="btn btn-ghost btn-sm mt-2"
                  phx-click="filter"
                  phx-value-type="all"
                >
                  Clear Filters
                </button>
              <% end %>
            </div>
          </div>
        <% else %>
          <%= for item <- @catalog_items do %>
            <.catalog_item
              item={item}
              expanded={MapSet.member?(@expanded_items, item.id)}
              mission={@mission}
            />
          <% end %>

          <!-- Load More Button -->
          <%= if @has_more do %>
            <div class="flex justify-center pt-4">
              <button class="btn btn-ghost" phx-click="load_more">
                Load More
                <.icon name="hero-chevron-down" class="h-4 w-4 ml-1" />
              </button>
            </div>
          <% end %>
        <% end %>
      </div>
    </div>

    <!-- Derived Item Modal -->
    <.modal
      :if={@live_action in [:new_derived, :edit_derived]}
      id="derived-modal"
      show
      on_cancel={JS.patch(~p"/missions/#{@mission}/catalog")}
    >
      <.live_component
        module={CadenceWeb.DerivedItemLive.FormComponent}
        id={@derived_item.id || :new}
        title={@page_title}
        action={if @live_action == :new_derived, do: :new, else: :edit}
        derived_item={@derived_item}
        mission={@mission}
        current_scope={@current_scope}
        patch={~p"/missions/#{@mission}/catalog"}
      />
    </.modal>
    """
  end

  # Catalog Item Component
  attr :item, :map, required: true
  attr :expanded, :boolean, default: false
  attr :mission, :map, required: true

  defp catalog_item(assigns) do
    ~H"""
    <div class="card bg-base-200 hover:bg-base-300/50 transition-colors">
      <div class="card-body p-4">
        <!-- Header Row -->
        <div class="flex items-center justify-between">
          <div class="flex items-center gap-3 flex-1 min-w-0">
            <!-- Type Badge -->
            <span class={[
              "badge badge-sm whitespace-nowrap",
              @item.type == :telemetry && "badge-info",
              @item.type == :command && "badge-warning",
              @item.type == :derived && "badge-secondary"
            ]}>
              <%= type_label(@item.type) %>
            </span>

            <!-- Name -->
            <span class="font-mono font-medium truncate"><%= @item.name %></span>

            <!-- Data Type -->
            <%= if @item.data_type do %>
              <span class="text-sm text-base-content/60"><%= @item.data_type %></span>
            <% end %>

            <!-- Units -->
            <%= if @item.units do %>
              <span class="text-sm text-base-content/50"><%= @item.units %></span>
            <% end %>

            <!-- Hazardous Badge for Commands -->
            <%= if @item.type == :command && @item.metadata.is_hazardous do %>
              <span class="badge badge-error badge-sm">Hazardous</span>
            <% end %>

            <!-- Disabled Badge for Derived -->
            <%= if @item.type == :derived && !@item.metadata.enabled do %>
              <span class="badge badge-ghost badge-sm">Disabled</span>
            <% end %>
          </div>

          <!-- Expand Button -->
          <button
            class="btn btn-ghost btn-sm"
            phx-click="toggle_expand"
            phx-value-id={@item.id}
          >
            <.icon name={if @expanded, do: "hero-chevron-up", else: "hero-chevron-down"} class="h-4 w-4" />
          </button>
        </div>

        <!-- Description -->
        <%= if @item.description do %>
          <p class="text-sm text-base-content/70 mt-1 line-clamp-1"><%= @item.description %></p>
        <% end %>

        <!-- Expanded Details -->
        <%= if @expanded do %>
          <div class="mt-4 pt-4 border-t border-base-300">
            <.item_details item={@item} mission={@mission} />
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  # Detailed view for each item type
  attr :item, :map, required: true
  attr :mission, :map, required: true

  defp item_details(assigns) do
    ~H"""
    <%= case @item.type do %>
      <% :telemetry -> %>
        <.telemetry_details item={@item} />
      <% :command -> %>
        <.command_details item={@item} />
      <% :derived -> %>
        <.derived_details item={@item} mission={@mission} />
    <% end %>
    """
  end

  defp telemetry_details(assigns) do
    ~H"""
    <div class="grid grid-cols-2 gap-4 text-sm">
      <div>
        <span class="text-base-content/60">Container:</span>
        <span class="ml-2 font-mono"><%= @item.container_name || "—" %></span>
      </div>
      <div>
        <span class="text-base-content/60">Parameter Source:</span>
        <span class="ml-2"><%= @item.metadata.parameter_source || "telemetry" %></span>
      </div>
      <div>
        <span class="text-base-content/60">Significance:</span>
        <span class="ml-2"><%= @item.metadata.significance || "none" %></span>
      </div>
      <div>
        <span class="text-base-content/60">Stale Timeout:</span>
        <span class="ml-2">
          <%= if @item.metadata.stale_timeout_ms, do: "#{@item.metadata.stale_timeout_ms}ms", else: "—" %>
        </span>
      </div>
    </div>
    """
  end

  defp command_details(assigns) do
    ~H"""
    <div class="space-y-4">
      <div class="grid grid-cols-2 gap-4 text-sm">
        <div>
          <span class="text-base-content/60">Opcode:</span>
          <span class="ml-2 font-mono">
            <%= if @item.metadata.opcode, do: "0x#{Integer.to_string(@item.metadata.opcode, 16)}", else: "—" %>
          </span>
        </div>
        <div>
          <span class="text-base-content/60">Significance:</span>
          <span class="ml-2"><%= @item.metadata.significance || "none" %></span>
        </div>
      </div>

      <%= if @item.metadata.is_hazardous && @item.metadata.hazard_description do %>
        <div class="alert alert-warning py-2">
          <.icon name="hero-exclamation-triangle" class="h-4 w-4" />
          <span class="text-sm"><%= @item.metadata.hazard_description %></span>
        </div>
      <% end %>

      <%= if length(@item.metadata.arguments) > 0 do %>
        <div>
          <h4 class="font-medium text-sm mb-2">Arguments (<%= length(@item.metadata.arguments) %>)</h4>
          <div class="overflow-x-auto">
            <table class="table table-xs">
              <thead>
                <tr>
                  <th>Name</th>
                  <th>Type</th>
                  <th>Required</th>
                  <th>Default</th>
                </tr>
              </thead>
              <tbody>
                <%= for arg <- @item.metadata.arguments do %>
                  <tr>
                    <td class="font-mono"><%= arg.name %></td>
                    <td><%= arg.data_type_ref %></td>
                    <td>
                      <%= if arg.required do %>
                        <span class="badge badge-xs badge-primary">Required</span>
                      <% else %>
                        <span class="text-base-content/50">Optional</span>
                      <% end %>
                    </td>
                    <td class="font-mono text-base-content/60"><%= arg.default_value || "—" %></td>
                  </tr>
                <% end %>
              </tbody>
            </table>
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  defp derived_details(assigns) do
    ~H"""
    <div class="space-y-4">
      <div>
        <span class="text-base-content/60 text-sm">Expression:</span>
        <pre class="mt-1 bg-base-300 rounded-lg p-3 text-sm font-mono overflow-x-auto"><%= @item.metadata.expression %></pre>
      </div>

      <%= if length(@item.metadata.source_items) > 0 do %>
        <div>
          <span class="text-base-content/60 text-sm">Source Items:</span>
          <div class="flex flex-wrap gap-1 mt-1">
            <%= for source <- @item.metadata.source_items do %>
              <span class="badge badge-outline badge-sm font-mono"><%= source %></span>
            <% end %>
          </div>
        </div>
      <% end %>

      <div class="flex gap-2">
        <.link
          patch={~p"/missions/#{@mission}/catalog/derived/#{@item.id}/edit"}
          class="btn btn-ghost btn-sm"
        >
          <.icon name="hero-pencil" class="h-4 w-4 mr-1" />
          Edit
        </.link>
      </div>
    </div>
    """
  end

  defp type_label(:telemetry), do: "Telemetry"
  defp type_label(:command), do: "Command"
  defp type_label(:derived), do: "Derived"
end
