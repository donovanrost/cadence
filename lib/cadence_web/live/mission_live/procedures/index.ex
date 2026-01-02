defmodule CadenceWeb.MissionLive.Procedures.Index do
  @moduledoc """
  LiveView for the procedures list page.

  Provides a searchable, filterable list of procedures with:
  - Debounced search input
  - Clickable tag chips for filtering
  - Procedure cards with status and execution counts
  - Quick actions (Edit, Execute)
  """

  use CadenceWeb, :live_view

  alias Cadence.Procedures
  alias Cadence.Procedures.V2.ExecutionQueries
  alias Cadence.Reviews
  alias CadenceWeb.MissionLive.Procedures.Components

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

  defp apply_action(socket, :index, params) do
    mission = socket.assigns.mission
    search_query = params["q"] || ""
    selected_tags = parse_tags(params["tags"])

    # Fetch all data
    procedures = load_procedures(mission, search_query, selected_tags)
    available_tags = Procedures.list_tags(mission.organization_id, mission_id: mission.id)
    execution_counts = load_execution_counts(mission.id)
    version_statuses = load_version_statuses(procedures)
    approval_progress = load_approval_progress(procedures, version_statuses)

    socket
    |> assign(:page_title, "Procedures")
    |> assign(:procedures, procedures)
    |> assign(:available_tags, available_tags)
    |> assign(:selected_tags, selected_tags)
    |> assign(:search_query, search_query)
    |> assign(:execution_counts, execution_counts)
    |> assign(:version_statuses, version_statuses)
    |> assign(:approval_progress, approval_progress)
    |> assign(:stats, calculate_stats(procedures, execution_counts))
  end

  # Load procedures with optional search and tag filtering
  defp load_procedures(mission, search_query, tags) do
    procedures =
      Procedures.list_procedures(
        mission.organization_id,
        mission_id: mission.id,
        tags: tags
      )

    # Apply client-side search filtering
    if search_query != "" do
      query_lower = String.downcase(search_query)

      Enum.filter(procedures, fn p ->
        name_match = String.contains?(String.downcase(p.name), query_lower)
        desc_match = p.description && String.contains?(String.downcase(p.description), query_lower)
        tag_match = Enum.any?(p.tags || [], &String.contains?(&1, query_lower))

        name_match or desc_match or tag_match
      end)
    else
      procedures
    end
  end

  # Load execution counts per procedure (running + paused)
  defp load_execution_counts(mission_id) do
    ExecutionQueries.list_executions_for_mission(mission_id,
      status: [:running, :paused, :pausing]
    )
    |> Enum.reduce(%{}, fn execution, acc ->
      count = Map.get(acc, execution.procedure_id, 0)
      Map.put(acc, execution.procedure_id, count + 1)
    end)
  end

  # Load current version status for each procedure
  defp load_version_statuses(procedures) do
    procedures
    |> Enum.filter(& &1.current_version_id)
    |> Enum.map(fn p ->
      version = Procedures.get_version(p.current_version_id)
      {p.id, version && version.status}
    end)
    |> Map.new()
  end

  # Load approval progress for procedures with versions in review
  defp load_approval_progress(procedures, version_statuses) do
    # Get version IDs for procedures that are in review or have changes requested
    version_ids_in_review =
      procedures
      |> Enum.filter(fn p ->
        status = Map.get(version_statuses, p.id)
        status in [:in_review, :changes_requested]
      end)
      |> Enum.map(& &1.current_version_id)
      |> Enum.reject(&is_nil/1)

    # Get approval progress for those versions
    version_progress = Reviews.get_approval_progress_for_versions(version_ids_in_review)

    # Map back to procedure_id => progress
    procedures
    |> Enum.filter(& &1.current_version_id)
    |> Enum.map(fn p ->
      progress = Map.get(version_progress, p.current_version_id)
      {p.id, progress}
    end)
    |> Enum.reject(fn {_, progress} -> is_nil(progress) end)
    |> Map.new()
  end

  # Calculate stats for the header
  defp calculate_stats(procedures, execution_counts) do
    running =
      execution_counts
      |> Map.values()
      |> Enum.sum()

    %{
      total: length(procedures),
      running: running,
      paused: 0
    }
  end

  # ==========================================================================
  # Event Handlers
  # ==========================================================================

  @impl true
  def handle_event("search", %{"query" => query}, socket) do
    {:noreply, push_patch_with_filters(socket, search: query)}
  end

  def handle_event("toggle_tag", %{"tag" => tag}, socket) do
    current_tags = socket.assigns.selected_tags

    new_tags =
      if tag in current_tags do
        List.delete(current_tags, tag)
      else
        [tag | current_tags]
      end

    {:noreply, push_patch_with_filters(socket, tags: new_tags)}
  end

  def handle_event("clear_filters", _params, socket) do
    {:noreply, push_patch_with_filters(socket, search: "", tags: [])}
  end

  def handle_event("create_procedure", _params, socket) do
    mission = socket.assigns.mission
    scope = socket.assigns.current_scope

    default_name = "New Procedure #{Calendar.strftime(DateTime.utc_now(), "%Y%m%d-%H%M%S")}"

    attrs = %{
      name: default_name,
      description: nil,
      tags: [],
      organization_id: mission.organization_id,
      mission_id: mission.id
    }

    case Procedures.create_procedure_v2(attrs, user_id: scope.user.id) do
      {:ok, {procedure, version}} ->
        {:noreply,
         socket
         |> put_flash(:info, "Procedure created")
         |> push_navigate(
           to: ~p"/missions/#{mission}/procedures-v2/#{procedure.id}/versions/#{version.id}/edit"
         )}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to create procedure: #{inspect(reason)}")}
    end
  end

  # ==========================================================================
  # Helpers
  # ==========================================================================

  defp push_patch_with_filters(socket, opts) do
    mission = socket.assigns.mission
    search = Keyword.get(opts, :search, socket.assigns.search_query)
    tags = Keyword.get(opts, :tags, socket.assigns.selected_tags)

    query_params =
      []
      |> maybe_add_param("q", search, "")
      |> maybe_add_param("tags", Enum.join(tags, ","), "")

    path =
      if query_params == [] do
        ~p"/missions/#{mission}/procedures"
      else
        ~p"/missions/#{mission}/procedures?#{query_params}"
      end

    push_patch(socket, to: path)
  end

  defp maybe_add_param(params, _key, value, default) when value == default, do: params
  defp maybe_add_param(params, key, value, _default), do: [{key, value} | params]

  defp parse_tags(nil), do: []
  defp parse_tags(""), do: []

  defp parse_tags(tags) when is_binary(tags) do
    tags
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  # ==========================================================================
  # Template
  # ==========================================================================

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} variant={:bare}>
      <div class="max-w-6xl mx-auto px-4 py-4">
        <%!-- Header --%>
        <div class="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-2 mb-4">
          <div>
            <h1 class="text-xl font-bold text-base-content">Procedures</h1>
            <Components.stats_bar
              total_count={@stats.total}
              running_count={@stats.running}
              paused_count={@stats.paused}
            />
          </div>

          <button
            type="button"
            id="create-procedure"
            class="btn btn-primary btn-sm"
            phx-click="create_procedure"
          >
            <.icon name="hero-plus" class="h-4 w-4" />
            New Procedure
          </button>
        </div>

        <%!-- Search and Filters --%>
        <div class="space-y-3 mb-4">
          <%!-- Search Input --%>
          <div class="form-control">
            <div class="relative">
              <.icon
                name="hero-magnifying-glass"
                class="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-base-content/40"
              />
              <input
                type="text"
                placeholder="Search procedures..."
                class="input input-bordered input-sm w-full pl-9"
                value={@search_query}
                phx-keyup="search"
                phx-debounce="300"
                name="query"
                autofocus
              />
              <button
                :if={@search_query != ""}
                type="button"
                class="absolute right-2 top-1/2 -translate-y-1/2 btn btn-ghost btn-xs btn-circle"
                phx-click="search"
                phx-value-query=""
              >
                <.icon name="hero-x-mark" class="h-3 w-3" />
              </button>
            </div>
          </div>

          <%!-- Tag Filter Chips --%>
          <div :if={length(@available_tags) > 0} class="flex flex-wrap items-center gap-2">
            <span class="text-sm text-base-content/60 mr-1">Filter by tag:</span>
            <Components.tag_badge
              :for={tag <- @available_tags}
              tag={tag}
              selected={tag in @selected_tags}
            />

            <button
              :if={length(@selected_tags) > 0}
              type="button"
              class="btn btn-ghost btn-xs"
              phx-click="clear_filters"
            >
              Clear all
            </button>
          </div>
        </div>

        <%!-- Procedures Grid --%>
        <%= if Enum.empty?(@procedures) do %>
          <Components.empty_state
            search_query={@search_query}
            selected_tags={@selected_tags}
          />
        <% else %>
          <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
            <Components.procedure_card
              :for={procedure <- @procedures}
              procedure={procedure}
              mission={@mission}
              execution_count={Map.get(@execution_counts, procedure.id, 0)}
              current_version_status={Map.get(@version_statuses, procedure.id)}
              approval_progress={Map.get(@approval_progress, procedure.id)}
              selected_tags={@selected_tags}
            />
          </div>
        <% end %>
      </div>
    </Layouts.app>
    """
  end
end
