defmodule CadenceWeb.MissionLive.Procedures.Show do
  @moduledoc """
  LiveView for the procedure detail page with tabbed navigation.

  Provides tabs for:
  - Overview: Procedure metadata, current version info, quick stats
  - Versions: Version list with status badges and actions
  - Executions: Execution history table
  - Reviews: Review status, threads, and actions (when in review workflow)
  """

  use CadenceWeb, :live_view

  alias Cadence.Procedures
  alias Cadence.Procedures.Procedure
  alias Cadence.Procedures.ProcedureVersion
  alias Cadence.Procedures.V2.ExecutionQueries
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

  # ==========================================================================
  # Apply Actions
  # ==========================================================================

  defp apply_action(socket, action, %{"procedure_id" => procedure_id} = params)
       when action in [:overview, :versions, :executions, :reviews, :show, :execute] do
    mission = socket.assigns.mission

    case load_procedure_for_mission(mission, procedure_id) do
      {:ok, procedure} ->
        # Normalize :show to :overview
        tab = if action == :show, do: :overview, else: action

        socket
        |> assign(:procedure, procedure)
        |> assign(:current_tab, tab)
        |> load_tab_data(tab, params)

      {:error, message} ->
        socket
        |> put_flash(:error, message)
        |> push_navigate(to: ~p"/missions/#{mission}/procedures")
    end
  end

  # Load data specific to each tab
  defp load_tab_data(socket, :overview, _params) do
    procedure = socket.assigns.procedure
    current_version = get_current_version(procedure)
    execution_stats = get_execution_stats(procedure.id)

    socket
    |> assign(:page_title, procedure.name)
    |> assign(:current_version, current_version)
    |> assign(:execution_stats, execution_stats)
  end

  defp load_tab_data(socket, :versions, _params) do
    procedure = socket.assigns.procedure
    versions = Procedures.list_versions(procedure.id)
    versions_with_status = attach_review_statuses(versions)

    socket
    |> assign(:page_title, "#{procedure.name} - Versions")
    |> assign(:versions, versions_with_status)
  end

  defp load_tab_data(socket, :executions, _params) do
    procedure = socket.assigns.procedure
    executions = ExecutionQueries.list_executions_for_procedure(procedure.id, limit: 50)

    socket
    |> assign(:page_title, "#{procedure.name} - Executions")
    |> assign(:executions, executions)
  end

  defp load_tab_data(socket, :reviews, _params) do
    procedure = socket.assigns.procedure
    current_version = get_current_version(procedure)

    review_data =
      if current_version && current_version.status in [:in_review, :changes_requested] do
        %{
          status: Procedures.get_review_status(current_version),
          threads: Procedures.list_threads(current_version.id),
          reviews: Procedures.list_reviews(current_version.id)
        }
      else
        nil
      end

    socket
    |> assign(:page_title, "#{procedure.name} - Reviews")
    |> assign(:current_version, current_version)
    |> assign(:review_data, review_data)
  end

  defp load_tab_data(socket, :execute, _params) do
    procedure = socket.assigns.procedure
    version = get_current_version(procedure)
    parameters = extract_parameters(version)

    execution_form =
      to_form(
        %{
          "target_id" => "",
          "parameters" => defaults_for_parameters(parameters)
        },
        as: :execution
      )

    socket
    |> assign(:page_title, "Execute #{procedure.name}")
    |> assign(:current_version, version)
    |> assign(:execution_form, execution_form)
    |> assign(:execution_parameters, parameters)
  end

  # ==========================================================================
  # Event Handlers
  # ==========================================================================

  @impl true
  def handle_event("start_execution", %{"execution" => params}, socket) do
    mission = socket.assigns.mission
    procedure = socket.assigns.procedure
    target_id = normalize_optional(params["target_id"])
    parameters = params["parameters"] || %{}

    case Procedures.start_execution(procedure.id,
           target_id: target_id,
           parameters: parameters,
           user_id: socket.assigns.current_scope.user.id,
           triggered_by: :manual
         ) do
      {:ok, execution} ->
        {:noreply,
         socket
         |> put_flash(:info, "Execution started")
         |> push_navigate(
           to: ~p"/missions/#{mission}/procedures-v2/#{procedure.id}/executions/#{execution.id}"
         )}

      {:error, {:validation, errors}} ->
        {:noreply, put_flash(socket, :error, "Invalid parameters: #{inspect(errors)}")}

      {:error, {:target_not_found, identifier}} ->
        {:noreply,
         put_flash(socket, :error, "Target #{inspect(identifier)} not found for this mission")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to start execution: #{inspect(reason)}")}
    end
  end

  def handle_event("create_version", _params, socket) do
    procedure = socket.assigns.procedure
    user_id = socket.assigns.current_scope.user.id

    # Copy source from current version or use empty steps
    current_version = get_current_version(procedure)

    attrs = %{
      source: (current_version && current_version.source) || %{"steps" => []},
      parameters_schema: (current_version && current_version.parameters_schema) || %{},
      execution_mode: (current_version && current_version.execution_mode) || :manual
    }

    case Procedures.create_version(procedure.id, attrs, user_id: user_id) do
      {:ok, %{version: version}} ->
        {:noreply,
         socket
         |> put_flash(:info, "New version created")
         |> push_navigate(
           to:
             ~p"/missions/#{socket.assigns.mission}/procedures-v2/#{procedure.id}/versions/#{version.id}/edit"
         )}

      {:error, _step, reason, _changes} ->
        {:noreply, put_flash(socket, :error, "Failed to create version: #{inspect(reason)}")}
    end
  end

  # ==========================================================================
  # Helpers
  # ==========================================================================

  defp load_procedure_for_mission(mission, procedure_id) do
    case Procedures.get_procedure(procedure_id) do
      nil ->
        {:error, "Procedure not found"}

      %Procedure{mission_id: mission_id} = procedure when mission_id == mission.id ->
        {:ok, procedure}

      _procedure ->
        {:error, "Procedure not found in this mission"}
    end
  end

  defp get_current_version(nil), do: nil
  defp get_current_version(%Procedure{current_version_id: nil}), do: nil

  defp get_current_version(%Procedure{current_version_id: version_id}) do
    Procedures.get_version(version_id)
  end

  defp get_execution_stats(procedure_id) do
    executions = ExecutionQueries.list_executions_for_procedure(procedure_id)

    %{
      total: length(executions),
      running: Enum.count(executions, &(&1.status in [:running, :pausing])),
      completed: Enum.count(executions, &(&1.status == :completed)),
      failed: Enum.count(executions, &(&1.status == :failed))
    }
  end

  defp attach_review_statuses(versions) do
    Enum.map(versions, fn version ->
      if version.status in [:in_review, :changes_requested] do
        Map.put(version, :review_status, Procedures.get_review_status(version))
      else
        version
      end
    end)
  end

  defp extract_parameters(nil), do: []

  defp extract_parameters(%ProcedureVersion{parameters_schema: %{"parameters" => params}})
       when is_list(params) do
    params
  end

  defp extract_parameters(_), do: []

  defp defaults_for_parameters(params) do
    Enum.reduce(params, %{}, fn param, acc ->
      Map.put(acc, param["name"], param["default"])
    end)
  end

  defp normalize_optional(nil), do: nil
  defp normalize_optional(""), do: nil
  defp normalize_optional(value), do: value

  defp tab_path(mission, procedure, :overview), do: ~p"/missions/#{mission}/procedures/#{procedure}"
  defp tab_path(mission, procedure, :versions), do: ~p"/missions/#{mission}/procedures/#{procedure}/versions"
  defp tab_path(mission, procedure, :executions), do: ~p"/missions/#{mission}/procedures/#{procedure}/executions"
  defp tab_path(mission, procedure, :reviews), do: ~p"/missions/#{mission}/procedures/#{procedure}/reviews"

  # ==========================================================================
  # Render
  # ==========================================================================

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} variant={:bare}>
      <div class="max-w-6xl mx-auto px-4 py-4">
        <%!-- Compact Header --%>
        <div class="flex items-center justify-between gap-4 mb-4">
          <div class="flex items-center gap-3 min-w-0">
            <.link
              navigate={~p"/missions/#{@mission}/procedures"}
              class="btn btn-ghost btn-sm btn-circle shrink-0"
              title="Back to Procedures"
            >
              <.icon name="hero-arrow-left" class="h-4 w-4" />
            </.link>
            <div class="min-w-0">
              <h1 class="text-xl font-bold text-base-content truncate">{@procedure.name}</h1>
              <div class="flex items-center gap-2 text-sm text-base-content/60">
                <span :if={@procedure.description} class="truncate max-w-md">
                  {@procedure.description}
                </span>
                <span :if={!@procedure.description} class="italic">No description</span>
                <span :if={@procedure.tags && length(@procedure.tags) > 0} class="flex items-center gap-1">
                  <span class="text-base-content/30">•</span>
                  <span :for={tag <- Enum.take(@procedure.tags, 3)} class="badge badge-outline badge-xs">
                    {tag}
                  </span>
                  <span :if={length(@procedure.tags) > 3} class="text-xs">
                    +{length(@procedure.tags) - 3}
                  </span>
                </span>
              </div>
            </div>
          </div>

          <%!-- Action buttons --%>
          <div class="flex items-center gap-2 shrink-0">
            <.link
              :if={@procedure.current_version_id}
              navigate={~p"/missions/#{@mission}/procedures-v2/#{@procedure.id}/versions/#{@procedure.current_version_id}/edit"}
              class="btn btn-ghost btn-sm"
            >
              <.icon name="hero-pencil-square" class="h-4 w-4" />
              Edit
            </.link>
            <.link
              navigate={~p"/missions/#{@mission}/procedures/#{@procedure.id}/execute"}
              class="btn btn-primary btn-sm"
            >
              <.icon name="hero-play" class="h-4 w-4" />
              Execute
            </.link>
          </div>
        </div>

        <%!-- Tab Navigation --%>
        <div class="tabs tabs-bordered mb-4">
          <.link
            :for={tab <- [:overview, :versions, :executions]}
            patch={tab_path(@mission, @procedure, tab)}
            class={["tab", @current_tab == tab && "tab-active"]}
          >
            {tab_label(tab)}
          </.link>
        </div>

        <%!-- Tab Content --%>
        <div class="space-y-6">
          <%= case @current_tab do %>
            <% :overview -> %>
              <.overview_tab
                procedure={@procedure}
                current_version={@current_version}
                execution_stats={@execution_stats}
                mission={@mission}
              />
            <% :versions -> %>
              <.versions_tab
                procedure={@procedure}
                versions={@versions}
                mission={@mission}
              />
            <% :executions -> %>
              <.executions_tab
                procedure={@procedure}
                executions={@executions}
                mission={@mission}
              />
            <% :reviews -> %>
              <%!-- Redirect to mission-scoped reviews page --%>
              <div class="text-center py-12">
                <p class="text-base-content/60 mb-4">
                  Reviews have moved to a dedicated section.
                </p>
                <.link
                  navigate={~p"/missions/#{@mission}/procedures/reviews"}
                  class="btn btn-primary"
                >
                  Go to Reviews
                </.link>
              </div>
            <% :execute -> %>
              <.execute_tab
                procedure={@procedure}
                current_version={@current_version}
                execution_form={@execution_form}
                execution_parameters={@execution_parameters}
                mission={@mission}
              />
          <% end %>
        </div>
      </div>
    </Layouts.app>
    """
  end

  defp tab_label(:overview), do: "Overview"
  defp tab_label(:versions), do: "Versions"
  defp tab_label(:executions), do: "Executions"
  defp tab_label(:reviews), do: "Reviews"

  # ==========================================================================
  # Overview Tab
  # ==========================================================================

  attr :procedure, :map, required: true
  attr :current_version, :map
  attr :execution_stats, :map, required: true
  attr :mission, :map, required: true

  defp overview_tab(assigns) do
    ~H"""
    <div class="grid grid-cols-1 lg:grid-cols-3 gap-6">
      <%!-- Main Info Card --%>
      <div class="lg:col-span-2 space-y-6">
        <%!-- Current Version Info --%>
        <div class="card bg-base-200">
          <div class="card-body">
            <h3 class="card-title text-base">Current Version</h3>
            <%= if @current_version do %>
              <div class="flex items-center gap-3">
                <span class="text-lg font-semibold">v{@current_version.version_number}</span>
                <Components.version_status_badge status={@current_version.status} />
              </div>
              <div class="text-sm text-base-content/60 mt-2">
                <p>Execution mode: <span class="font-medium">{format_execution_mode(@current_version.execution_mode)}</span></p>
                <p :if={@current_version.change_summary} class="mt-1">
                  {@current_version.change_summary}
                </p>
              </div>
              <div class="card-actions justify-end mt-4">
                <.link
                  navigate={~p"/missions/#{@mission}/procedures-v2/#{@procedure.id}/versions/#{@current_version.id}/edit"}
                  class="btn btn-sm btn-ghost"
                >
                  Open in Editor
                </.link>
              </div>
            <% else %>
              <p class="text-base-content/60">No version available</p>
            <% end %>
          </div>
        </div>

        <%!-- Procedure Details --%>
        <div class="card bg-base-200">
          <div class="card-body">
            <h3 class="card-title text-base">Details</h3>
            <dl class="grid grid-cols-2 gap-4 text-sm">
              <div>
                <dt class="text-base-content/60">Type</dt>
                <dd class="font-medium">{format_type(@procedure.type)}</dd>
              </div>
              <div>
                <dt class="text-base-content/60">Created</dt>
                <dd class="font-medium">{format_datetime(@procedure.inserted_at)}</dd>
              </div>
              <div>
                <dt class="text-base-content/60">Last Updated</dt>
                <dd class="font-medium">{format_datetime(@procedure.updated_at)}</dd>
              </div>
              <div>
                <dt class="text-base-content/60">Tags</dt>
                <dd class="font-medium">{length(@procedure.tags || [])} tags</dd>
              </div>
            </dl>
          </div>
        </div>
      </div>

      <%!-- Stats Sidebar --%>
      <div class="space-y-4">
        <div class="card bg-base-200">
          <div class="card-body">
            <h3 class="card-title text-base">Execution Stats</h3>
            <div class="stats stats-vertical bg-base-100 w-full">
              <div class="stat py-3">
                <div class="stat-title">Total Runs</div>
                <div class="stat-value text-2xl">{@execution_stats.total}</div>
              </div>
              <div class="stat py-3">
                <div class="stat-title">Running</div>
                <div class="stat-value text-2xl text-success">{@execution_stats.running}</div>
              </div>
              <div class="stat py-3">
                <div class="stat-title">Completed</div>
                <div class="stat-value text-2xl">{@execution_stats.completed}</div>
              </div>
              <div class="stat py-3">
                <div class="stat-title">Failed</div>
                <div class="stat-value text-2xl text-error">{@execution_stats.failed}</div>
              </div>
            </div>
          </div>
        </div>

        <%!-- Quick Actions --%>
        <div class="card bg-base-200">
          <div class="card-body">
            <h3 class="card-title text-base">Quick Actions</h3>
            <div class="space-y-2">
              <.link
                navigate={~p"/missions/#{@mission}/procedures/#{@procedure.id}/execute"}
                class="btn btn-primary btn-block"
              >
                <.icon name="hero-play" class="h-4 w-4" />
                Execute Procedure
              </.link>
              <button
                type="button"
                phx-click="create_version"
                class="btn btn-ghost btn-block"
              >
                <.icon name="hero-plus" class="h-4 w-4" />
                New Version
              </button>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # ==========================================================================
  # Versions Tab
  # ==========================================================================

  attr :procedure, :map, required: true
  attr :versions, :list, required: true
  attr :mission, :map, required: true

  defp versions_tab(assigns) do
    ~H"""
    <div class="space-y-4">
      <div class="flex items-center justify-between">
        <h3 class="text-lg font-semibold">{length(@versions)} Versions</h3>
        <button type="button" phx-click="create_version" class="btn btn-primary btn-sm">
          <.icon name="hero-plus" class="h-4 w-4" />
          New Version
        </button>
      </div>

      <%= if Enum.empty?(@versions) do %>
        <div class="card bg-base-200">
          <div class="card-body items-center text-center py-12">
            <.icon name="hero-document-text" class="h-12 w-12 text-base-content/30" />
            <p class="text-base-content/60">No versions yet</p>
          </div>
        </div>
      <% else %>
        <div class="space-y-2">
          <div :for={version <- @versions} class="card bg-base-200">
            <div class="card-body p-4">
              <div class="flex items-center justify-between">
                <div class="flex items-center gap-3">
                  <span class="text-lg font-semibold">v{version.version_number}</span>
                  <Components.version_status_badge status={version.status} />
                  <span
                    :if={@procedure.current_version_id == version.id}
                    class="badge badge-primary badge-sm"
                  >
                    Current
                  </span>
                </div>
                <div class="flex items-center gap-2">
                  <.link
                    :if={version.status in [:in_review, :changes_requested]}
                    navigate={~p"/missions/#{@mission}/procedures-v2/#{@procedure.id}/versions/#{version.id}/review"}
                    class="btn btn-ghost btn-sm gap-1"
                  >
                    <.icon name="hero-chat-bubble-left-right" class="h-4 w-4" />
                    Review
                  </.link>
                  <.link
                    navigate={~p"/missions/#{@mission}/procedures-v2/#{@procedure.id}/versions/#{version.id}/edit"}
                    class="btn btn-ghost btn-sm"
                  >
                    Open
                  </.link>
                </div>
              </div>

              <%!-- Review Status for in_review/changes_requested --%>
              <div :if={Map.get(version, :review_status)} class="mt-2 text-sm flex items-center gap-2">
                <span class="text-success">{version.review_status.approved_count}</span>/<span>{version.review_status.required}</span> approvals
                <span :if={version.review_status.changes_requested_count > 0} class="text-warning">
                  · {version.review_status.changes_requested_count} requesting changes
                </span>
              </div>

              <div class="text-sm text-base-content/60 mt-2">
                <p :if={version.change_summary}>{version.change_summary}</p>
                <p class="mt-1">
                  Created {format_datetime(version.inserted_at)}
                  {if version.submitted_at, do: " · Submitted #{format_datetime(version.submitted_at)}", else: ""}
                </p>
              </div>
            </div>
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  # ==========================================================================
  # Executions Tab
  # ==========================================================================

  attr :procedure, :map, required: true
  attr :executions, :list, required: true
  attr :mission, :map, required: true

  defp executions_tab(assigns) do
    ~H"""
    <div class="space-y-4">
      <div class="flex items-center justify-between">
        <h3 class="text-lg font-semibold">{length(@executions)} Executions</h3>
        <.link
          navigate={~p"/missions/#{@mission}/procedures/#{@procedure.id}/execute"}
          class="btn btn-primary btn-sm"
        >
          <.icon name="hero-play" class="h-4 w-4" />
          Start New
        </.link>
      </div>

      <%= if Enum.empty?(@executions) do %>
        <div class="card bg-base-200">
          <div class="card-body items-center text-center py-12">
            <.icon name="hero-play-circle" class="h-12 w-12 text-base-content/30" />
            <p class="text-base-content/60">No executions yet</p>
            <.link
              navigate={~p"/missions/#{@mission}/procedures/#{@procedure.id}/execute"}
              class="btn btn-primary btn-sm mt-4"
            >
              Start First Execution
            </.link>
          </div>
        </div>
      <% else %>
        <div class="overflow-x-auto">
          <table class="table">
            <thead>
              <tr>
                <th>ID</th>
                <th>Status</th>
                <th>Version</th>
                <th>Started</th>
                <th>Duration</th>
                <th></th>
              </tr>
            </thead>
            <tbody>
              <tr :for={execution <- @executions} class="hover">
                <td class="font-mono text-sm">{short_id(execution.id)}</td>
                <td>
                  <.execution_status_badge status={execution.status} />
                </td>
                <td>v{execution.procedure_version.version_number}</td>
                <td class="text-sm text-base-content/70">{format_datetime(execution.inserted_at)}</td>
                <td class="text-sm text-base-content/70">{format_duration(execution)}</td>
                <td>
                  <.link
                    navigate={~p"/missions/#{@mission}/procedures-v2/#{@procedure.id}/executions/#{execution.id}"}
                    class="btn btn-ghost btn-xs"
                  >
                    View
                  </.link>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      <% end %>
    </div>
    """
  end

  # ==========================================================================
  # Execute Tab (Modal-style)
  # ==========================================================================

  attr :procedure, :map, required: true
  attr :current_version, :map
  attr :execution_form, :any, required: true
  attr :execution_parameters, :list, required: true
  attr :mission, :map, required: true

  defp execute_tab(assigns) do
    ~H"""
    <div class="max-w-2xl">
      <div class="card bg-base-200">
        <div class="card-body">
          <h3 class="card-title">Execute Procedure</h3>
          <p class="text-sm text-base-content/60 mb-4">
            Configure parameters and start a new execution of <span class="font-medium">{@procedure.name}</span>.
          </p>

          <.form for={@execution_form} id="procedure-execution-form" phx-submit="start_execution" class="space-y-4">
            <.input
              field={@execution_form[:target_id]}
              type="text"
              label="Target ID (optional)"
              placeholder="e.g., SC-001"
            />

            <div :if={length(@execution_parameters) > 0} class="space-y-3">
              <h4 class="text-sm font-semibold text-base-content/70 uppercase tracking-wide">
                Parameters
              </h4>
              <.input
                :for={param <- @execution_parameters}
                type={parameter_input_type(param)}
                name={"execution[parameters][#{param["name"]}]"}
                value={param["default"]}
                label={param["name"]}
                placeholder={param["description"]}
                required={param["required"] == true}
              />
            </div>

            <div :if={Enum.empty?(@execution_parameters)} class="text-sm text-base-content/60">
              No parameters required for this procedure.
            </div>

            <div class="card-actions justify-end mt-6">
              <.link
                navigate={~p"/missions/#{@mission}/procedures/#{@procedure.id}"}
                class="btn btn-ghost"
              >
                Cancel
              </.link>
              <button type="submit" class="btn btn-primary">
                <.icon name="hero-play" class="h-4 w-4" />
                Start Execution
              </button>
            </div>
          </.form>
        </div>
      </div>
    </div>
    """
  end

  defp parameter_input_type(%{"type" => "number"}), do: "number"
  defp parameter_input_type(%{"type" => "boolean"}), do: "checkbox"
  defp parameter_input_type(_), do: "text"

  attr :status, :atom, required: true

  defp execution_status_badge(assigns) do
    ~H"""
    <span class={[
      "badge badge-sm",
      @status == :running && "badge-success",
      @status == :paused && "badge-warning",
      @status == :pausing && "badge-warning",
      @status == :completed && "badge-info",
      @status == :failed && "badge-error",
      @status == :cancelled && "badge-ghost"
    ]}>
      {@status}
    </span>
    """
  end

  # ==========================================================================
  # Formatters
  # ==========================================================================

  defp format_type(:dag), do: "DAG (Step-based)"
  defp format_type(:script), do: "Script (Lua)"
  defp format_type(other), do: to_string(other)

  defp format_execution_mode(:manual), do: "Manual"
  defp format_execution_mode(:assisted), do: "Assisted"
  defp format_execution_mode(:automatic), do: "Automatic"
  defp format_execution_mode(other), do: to_string(other)

  defp format_datetime(nil), do: "—"

  defp format_datetime(datetime) do
    Calendar.strftime(datetime, "%b %d, %Y %H:%M")
  end

  defp format_duration(%{completed_at: nil}), do: "—"
  defp format_duration(%{completed_at: completed, inserted_at: started}) do
    seconds = DateTime.diff(completed, started, :second)

    cond do
      seconds < 60 -> "#{seconds}s"
      seconds < 3600 -> "#{div(seconds, 60)}m #{rem(seconds, 60)}s"
      true -> "#{div(seconds, 3600)}h #{div(rem(seconds, 3600), 60)}m"
    end
  end

  defp short_id(id) when is_binary(id) do
    id |> String.split("-") |> List.first() |> String.upcase()
  end
end
