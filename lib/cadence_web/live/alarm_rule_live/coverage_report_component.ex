defmodule CadenceWeb.AlarmRuleLive.CoverageReportComponent do
  @moduledoc """
  Reusable component that displays alarm coverage analysis.

  Shows:
  - View mode toggle (database vs per-target)
  - Summary stats bar with coverage percentage
  - Uncovered parameters table with ability to create rules
  - Orphaned rules warning (rules that don't match any parameters)
  """

  use CadenceWeb, :live_component

  alias Cadence.Alarms.CoverageAnalyzer

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <%= if @loading do %>
        <div class="flex items-center justify-center py-8">
          <div class="animate-spin rounded-full h-8 w-8 border-b-2 border-primary"></div>
        </div>
      <% else %>
        <%= if @error do %>
          <div class="alert alert-warning rounded-sm">
            <svg class="h-5 w-5" viewBox="0 0 20 20" fill="currentColor">
              <path
                fill-rule="evenodd"
                d="M8.485 2.495c.673-1.167 2.357-1.167 3.03 0l6.28 10.875c.673 1.167-.17 2.625-1.516 2.625H3.72c-1.347 0-2.189-1.458-1.515-2.625L8.485 2.495zM10 5a.75.75 0 01.75.75v3.5a.75.75 0 01-1.5 0v-3.5A.75.75 0 0110 5zm0 9a1 1 0 100-2 1 1 0 000 2z"
                clip-rule="evenodd"
              />
            </svg>
            <div>
              <h3 class="font-medium">No Active Database</h3>
              <p class="text-sm opacity-80">
                Publish a telemetry database to see alarm coverage analysis.
              </p>
            </div>
          </div>
        <% else %>
          <!-- View Mode Toggle -->
          <.render_view_mode_toggle
            view_mode={@view_mode}
            targets_using_database={@targets_using_database}
            selected_target_id={@selected_target_id}
            myself={@myself}
          />
          <div class="space-y-4">
            <div class="flex items-center justify-between">
              <h4 class="text-sm font-medium text-base-content">Coverage Summary</h4>
              <%= if @summary.total_parameters_with_limits > 0 do %>
                <span class="text-sm text-base-content/60">
                  {@summary.covered_count} of {@summary.total_parameters_with_limits} parameters covered
                </span>
              <% end %>
            </div>

            <%= if @summary.total_parameters_with_limits > 0 do %>
              <div class="w-full bg-base-300 rounded-sm h-4 overflow-hidden">
                <div
                  class={[
                    "h-full rounded-sm transition-all duration-500",
                    @summary.coverage_percentage >= 80 && "bg-success",
                    @summary.coverage_percentage >= 50 && @summary.coverage_percentage < 80 &&
                      "bg-warning",
                    @summary.coverage_percentage < 50 && "bg-error"
                  ]}
                  style={"width: #{@summary.coverage_percentage}%"}
                >
                </div>
              </div>
              <div class="flex justify-between text-xs text-base-content/50">
                <span>{Float.round(@summary.coverage_percentage, 1)}% covered</span>
                <span>{@summary.uncovered_count} uncovered</span>
              </div>
            <% else %>
              <p class="text-sm text-base-content/50 italic">
                No parameters with limits defined in the database.
              </p>
            <% end %>
          </div>

          <%= if @summary.orphaned_rules_count > 0 do %>
            <div class="alert alert-warning rounded-sm">
              <svg class="h-5 w-5 shrink-0" viewBox="0 0 20 20" fill="currentColor">
                <path
                  fill-rule="evenodd"
                  d="M8.485 2.495c.673-1.167 2.357-1.167 3.03 0l6.28 10.875c.673 1.167-.17 2.625-1.516 2.625H3.72c-1.347 0-2.189-1.458-1.515-2.625L8.485 2.495zM10 5a.75.75 0 01.75.75v3.5a.75.75 0 01-1.5 0v-3.5A.75.75 0 0110 5zm0 9a1 1 0 100-2 1 1 0 000 2z"
                  clip-rule="evenodd"
                />
              </svg>
              <div>
                <h3 class="font-medium">
                  {@summary.orphaned_rules_count} Orphaned {ngettext(
                    "Rule",
                    "Rules",
                    @summary.orphaned_rules_count
                  )}
                </h3>
                <div class="mt-2 text-sm opacity-80">
                  <p>These rules don't match any parameters in the current database:</p>
                  <ul class="mt-2 list-disc list-inside space-y-1">
                    <%= for %{rule: rule, reason: reason} <- @analysis.orphaned_rules do %>
                      <li>
                        <span class="font-medium">{rule.name}</span>
                        <span class="opacity-70">
                          ({format_orphan_reason(reason)})
                        </span>
                      </li>
                    <% end %>
                  </ul>
                </div>
              </div>
            </div>
          <% end %>

          <%= if @summary.uncovered_count > 0 do %>
            <div class="space-y-3">
              <div class="flex items-center justify-between">
                <h4 class="text-sm font-medium text-base-content">Uncovered Parameters</h4>
                <.button
                  phx-click="open_bulk_create"
                  phx-target={@myself}
                  class="px-2 py-1 text-sm"
                >
                  Create Rules for All
                </.button>
              </div>

              <div class="overflow-hidden rounded-sm border border-base-300">
                <table class="min-w-full divide-y divide-base-300">
                  <thead class="bg-base-200">
                    <tr>
                      <th class="px-4 py-2 text-left hud-label">
                        Parameter
                      </th>
                      <th class="px-4 py-2 text-left hud-label">
                        Container
                      </th>
                      <th class="px-4 py-2 text-right hud-label">
                        Actions
                      </th>
                    </tr>
                  </thead>
                  <tbody class="bg-base-100 divide-y divide-base-200">
                    <%= for param <- @analysis.uncovered do %>
                      <tr class="hover:bg-base-200/50">
                        <td class="px-4 py-2 text-sm font-mono text-base-content">
                          {param.parameter.name}
                        </td>
                        <td class="px-4 py-2 text-sm text-base-content/60">
                          {param.container_name}
                        </td>
                        <td class="px-4 py-2 text-right">
                          <button
                            phx-click="create_single_rule"
                            phx-target={@myself}
                            phx-value-param={param.qualified_name}
                            class="text-sm text-primary hover:text-primary/80"
                          >
                            Create Rule
                          </button>
                        </td>
                      </tr>
                    <% end %>
                  </tbody>
                </table>
              </div>
            </div>
          <% else %>
            <%= if @summary.total_parameters_with_limits > 0 do %>
              <div class="alert alert-success rounded-sm">
                <svg class="h-5 w-5 shrink-0" viewBox="0 0 20 20" fill="currentColor">
                  <path
                    fill-rule="evenodd"
                    d="M10 18a8 8 0 100-16 8 8 0 000 16zm3.857-9.809a.75.75 0 00-1.214-.882l-3.483 4.79-1.88-1.88a.75.75 0 10-1.06 1.061l2.5 2.5a.75.75 0 001.137-.089l4-5.5z"
                    clip-rule="evenodd"
                  />
                </svg>
                <div>
                  <h3 class="font-medium">Full Coverage</h3>
                  <p class="text-sm opacity-80">
                    All parameters with limits have corresponding alarm rules.
                  </p>
                </div>
              </div>
            <% end %>
          <% end %>
        <% end %>
      <% end %>
    </div>
    """
  end

  @impl true
  def update(%{mission: mission, definition_set_id: definition_set_id} = assigns, socket) do
    # Subscribe to rule changes for this mission (only on first mount)
    if not connected_or_subscribed?(socket, mission.id) do
      Phoenix.PubSub.subscribe(Cadence.PubSub, "mission:#{mission.id}:alarm_rules")
    end

    # Preserve view mode state across updates, default to :database
    view_mode = Map.get(socket.assigns, :view_mode, :database)
    selected_target_id = Map.get(socket.assigns, :selected_target_id)

    socket =
      socket
      |> assign(assigns)
      |> assign(:subscribed_mission_id, mission.id)
      |> assign(:view_mode, view_mode)
      |> assign(:selected_target_id, selected_target_id)
      |> load_coverage_for_view_mode(definition_set_id, mission.id, view_mode, selected_target_id)

    {:ok, socket}
  end

  def update(%{mission: _mission} = assigns, socket) do
    # No definition_set_id provided - show error state
    {:ok,
     socket
     |> assign(assigns)
     |> assign(:loading, false)
     |> assign(:error, :no_active_database)
     |> assign(:analysis, nil)
     |> assign(:summary, nil)
     |> assign(:view_mode, :database)
     |> assign(:selected_target_id, nil)
     |> assign(:targets_using_database, [])}
  end

  defp connected_or_subscribed?(socket, mission_id) do
    # Check if we've already subscribed to this mission
    Map.get(socket.assigns, :subscribed_mission_id) == mission_id
  end

  # Note: handle_info works in LiveComponents when they have a parent LiveView
  # that forwards messages via send_update or when subscribed to PubSub
  def handle_info({:alarm_rule_changed, _event_type, _rule}, socket) do
    # Refresh coverage analysis when rules change
    socket =
      if socket.assigns[:definition_set_id] && socket.assigns[:mission] do
        load_coverage_for_view_mode(
          socket,
          socket.assigns.definition_set_id,
          socket.assigns.mission.id,
          socket.assigns.view_mode,
          socket.assigns.selected_target_id
        )
      else
        socket
      end

    {:noreply, socket}
  end

  @impl true
  def handle_event("set_view_mode", %{"mode" => "database"}, socket) do
    socket =
      socket
      |> assign(:view_mode, :database)
      |> load_coverage_for_view_mode(
        socket.assigns.definition_set_id,
        socket.assigns.mission.id,
        :database,
        nil
      )

    {:noreply, socket}
  end

  def handle_event("set_view_mode", %{"mode" => "target"}, socket) do
    # Switch to target view, select first target if none selected
    targets = socket.assigns.targets_using_database

    selected_target_id =
      socket.assigns.selected_target_id || targets |> List.first() |> then(&(&1 && &1.id))

    socket =
      socket
      |> assign(:view_mode, :target)
      |> assign(:selected_target_id, selected_target_id)
      |> load_coverage_for_view_mode(
        socket.assigns.definition_set_id,
        socket.assigns.mission.id,
        :target,
        selected_target_id
      )

    {:noreply, socket}
  end

  def handle_event("select_target", %{"value" => target_id}, socket) do
    socket =
      socket
      |> assign(:selected_target_id, target_id)
      |> load_coverage_for_view_mode(
        socket.assigns.definition_set_id,
        socket.assigns.mission.id,
        :target,
        target_id
      )

    {:noreply, socket}
  end

  def handle_event("open_bulk_create", _params, socket) do
    target_id = if socket.assigns.view_mode == :target, do: socket.assigns.selected_target_id

    send(
      self(),
      {__MODULE__,
       {:open_bulk_create, socket.assigns.definition_set_id, socket.assigns.mission.id, target_id}}
    )

    {:noreply, socket}
  end

  def handle_event("create_single_rule", %{"param" => qualified_name}, socket) do
    target_id = if socket.assigns.view_mode == :target, do: socket.assigns.selected_target_id

    send(
      self(),
      {__MODULE__,
       {:create_single_rule, socket.assigns.definition_set_id, socket.assigns.mission.id,
        qualified_name, target_id}}
    )

    {:noreply, socket}
  end

  defp load_coverage_for_view_mode(socket, definition_set_id, mission_id, :database, _target_id) do
    case CoverageAnalyzer.analyze(definition_set_id, mission_id) do
      {:ok, analysis} ->
        summary = build_summary(analysis)
        targets = Map.get(analysis, :targets_using_database, [])

        socket
        |> assign(:loading, false)
        |> assign(:error, nil)
        |> assign(:analysis, analysis)
        |> assign(:summary, summary)
        |> assign(:targets_using_database, targets)

      {:error, :definition_set_not_found} ->
        socket
        |> assign(:loading, false)
        |> assign(:error, :no_active_database)
        |> assign(:analysis, nil)
        |> assign(:summary, nil)
        |> assign(:targets_using_database, [])

      {:error, _reason} ->
        socket
        |> assign(:loading, false)
        |> assign(:error, :analysis_failed)
        |> assign(:analysis, nil)
        |> assign(:summary, nil)
        |> assign(:targets_using_database, [])
    end
  end

  defp load_coverage_for_view_mode(socket, _definition_set_id, _mission_id, :target, nil) do
    # No target selected, keep current state but clear analysis
    socket
    |> assign(:loading, false)
    |> assign(:error, nil)
    |> assign(:analysis, %{covered: [], uncovered: [], orphaned_rules: []})
    |> assign(:summary, %{
      total_parameters_with_limits: 0,
      covered_count: 0,
      uncovered_count: 0,
      orphaned_rules_count: 0,
      coverage_percentage: 100.0
    })
  end

  defp load_coverage_for_view_mode(socket, _definition_set_id, _mission_id, :target, target_id) do
    case CoverageAnalyzer.analyze_for_target(target_id) do
      {:ok, analysis} ->
        summary = build_summary(analysis)

        socket
        |> assign(:loading, false)
        |> assign(:error, nil)
        |> assign(:analysis, analysis)
        |> assign(:summary, summary)

      {:error, :target_not_found} ->
        socket
        |> assign(:loading, false)
        |> assign(:error, :target_not_found)
        |> assign(:analysis, nil)
        |> assign(:summary, nil)

      {:error, _reason} ->
        socket
        |> assign(:loading, false)
        |> assign(:error, :analysis_failed)
        |> assign(:analysis, nil)
        |> assign(:summary, nil)
    end
  end

  defp build_summary(analysis) do
    covered_count = length(analysis.covered)
    uncovered_count = length(analysis.uncovered)
    total = covered_count + uncovered_count

    %{
      total_parameters_with_limits: total,
      covered_count: covered_count,
      uncovered_count: uncovered_count,
      orphaned_rules_count: length(analysis.orphaned_rules),
      coverage_percentage:
        if(total == 0, do: 100.0, else: Float.round(covered_count / total * 100, 1))
    }
  end

  defp format_orphan_reason(:item_not_found), do: "item no longer exists"
  defp format_orphan_reason(:pattern_no_matches), do: "pattern matches nothing"
  defp format_orphan_reason(_), do: "unknown reason"

  # View Mode Toggle Component
  defp render_view_mode_toggle(assigns) do
    ~H"""
    <div class="flex items-center gap-4 pb-4 border-b border-base-300">
      <div class="flex items-center gap-1">
        <button
          phx-click="set_view_mode"
          phx-target={@myself}
          phx-value-mode="database"
          class={[
            "px-3 py-1.5 text-sm rounded-sm transition-colors",
            @view_mode == :database && "bg-primary text-primary-content",
            @view_mode != :database && "bg-base-200 text-base-content hover:bg-base-300"
          ]}
        >
          All Targets ({length(@targets_using_database)})
        </button>
        <button
          phx-click="set_view_mode"
          phx-target={@myself}
          phx-value-mode="target"
          disabled={Enum.empty?(@targets_using_database)}
          class={[
            "px-3 py-1.5 text-sm rounded-sm transition-colors",
            @view_mode == :target && "bg-primary text-primary-content",
            @view_mode != :target && "bg-base-200 text-base-content hover:bg-base-300",
            Enum.empty?(@targets_using_database) && "opacity-50 cursor-not-allowed"
          ]}
        >
          Per Target
        </button>
      </div>

      <%= if @view_mode == :target and not Enum.empty?(@targets_using_database) do %>
        <select
          phx-change="select_target"
          phx-target={@myself}
          class="select select-sm w-48"
        >
          <%= for target <- @targets_using_database do %>
            <option value={target.id} selected={target.id == @selected_target_id}>
              {target.identifier}
            </option>
          <% end %>
        </select>
      <% end %>

      <%= if Enum.empty?(@targets_using_database) do %>
        <span class="text-sm text-warning italic">
          No targets assigned to this database
        </span>
      <% end %>
    </div>
    """
  end
end
