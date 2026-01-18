defmodule CadenceWeb.OpsConsoleLive.Queue do
  @moduledoc """
  Queue mode for OPS Console.

  Provides:
  - Queue overview with metrics
  - Per-target queue management
  - Filterable queue table

  Uses CSS from assets/css/modes/queue-mode.css
  """

  use CadenceWeb, :live_view

  alias Cadence.{Alarms, Commands, Targets}
  alias Cadence.Time.Timer, as: TimeTimer

  @impl true
  def mount(_params, _session, socket) do
    mission = socket.assigns.mission
    mission_id = mission.id

    # Load targets
    targets = Targets.list_targets(mission)

    # Load queue entries (for mode display)
    all_queue_entries =
      Commands.list_queue_entries(mission_id,
        status: [:pending, :executing, :completed, :failed, :cancelled],
        limit: 200
      )

    # Load data for layout (status bar and context panel)
    active_alarms = Alarms.list_active_alarms(mission_id)
    alarm_counts = calculate_alarm_counts(active_alarms)

    context_queue_entries = build_context_queue_entries(mission_id, targets)

    fleet_health = calculate_fleet_health(targets)

    # Calculate queue status per target
    target_queue_counts = calculate_target_queue_counts(all_queue_entries)

    # Load paused state for each target
    paused_targets = load_paused_targets(mission_id, targets)

    # Subscribe to queue and alarm updates
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Cadence.PubSub, "mission:#{mission_id}:queue")
      Phoenix.PubSub.subscribe(Cadence.PubSub, "mission:#{mission_id}:alarms")
      TimeTimer.send_interval(1000, self(), :tick)
    end

    socket =
      socket
      |> assign(:page_title, "Queue - #{mission.name}")
      |> assign(:targets, targets)
      |> assign(:all_queue_entries, all_queue_entries)
      |> stream(:queue_entries, all_queue_entries)
      |> assign(:queue_metrics, calculate_metrics(all_queue_entries))
      |> assign(:selected_target, nil)
      |> assign(:target_entries, [])
      |> assign(:selected_targets, MapSet.new())
      |> assign(:target_queue_counts, target_queue_counts)
      |> assign(:paused_targets, paused_targets)
      |> assign(:target_search, "")
      |> assign(:status_filter, :all)
      |> assign(:search, "")
      |> assign(:selected_entries, MapSet.new())
      |> assign(:view_mode, "compact")
      |> assign(:metrics_expanded, true)
      # Layout data
      |> assign(:alarm_counts, alarm_counts)
      |> assign(:alarms, active_alarms)
      |> assign(:queue_entries, context_queue_entries)
      |> assign(:fleet_health, fleet_health)
      |> assign(:running_procedures, [])
      |> assign(:current_time, DateTime.utc_now())
      |> assign(:dashboards, [])
      |> assign(:current_mode, :queue)

    {:ok, socket, layout: {CadenceWeb.Layouts, :ops_console_mode}}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="queue-mode-container">
      <div class="queue-mode-layout">
        <%= case @live_action do %>
          <% :overview -> %>
            <.queue_overview_view
              metrics={@queue_metrics}
              all_queue_entries={@all_queue_entries}
              targets={@targets}
              target_queue_counts={@target_queue_counts}
            />
          <% :manage -> %>
            <.queue_manage_view
              targets={@targets}
              selected_target={@selected_target}
              target_entries={@target_entries}
              target_queue_counts={@target_queue_counts}
              target_search={@target_search}
              paused_targets={@paused_targets}
              mission_id={@mission.id}
            />
          <% _table_or_default -> %>
            <.queue_table_view
              targets={@targets}
              selected_targets={@selected_targets}
              target_search={@target_search}
              view_mode={@view_mode}
              streams={@streams}
              status_filter={@status_filter}
              search={@search}
              selected_entries={@selected_entries}
              queue_metrics={@queue_metrics}
              metrics_expanded={@metrics_expanded}
            />
        <% end %>
        
    <!-- View Tabs / Controls Bar -->
        <.queue_controls
          live_action={@live_action}
          mission_id={@mission.id}
          selected_entries={@selected_entries}
        />
      </div>
    </div>
    """
  end

  # ============================================================================
  # Queue Controls (Bottom Bar)
  # ============================================================================

  attr :live_action, :atom, required: true
  attr :mission_id, :string, required: true
  attr :selected_entries, :any, required: true

  defp queue_controls(assigns) do
    ~H"""
    <div class="queue-controls">
      <div class="queue-view-tabs">
        <.link
          navigate={~p"/missions/#{@mission_id}/ops/queue"}
          class={["queue-view-tab", @live_action == :overview && "active"]}
        >
          Overview
        </.link>
        <.link
          navigate={~p"/missions/#{@mission_id}/ops/queue/manage"}
          class={["queue-view-tab", @live_action == :manage && "active"]}
        >
          Manage
        </.link>
        <.link
          navigate={~p"/missions/#{@mission_id}/ops/queue/table"}
          class={["queue-view-tab", @live_action in [:table, :index] && "active"]}
        >
          Table
        </.link>
      </div>

      <div class="queue-global-actions">
        <span :if={MapSet.size(@selected_entries) > 0} class="queue-selected-count">
          {MapSet.size(@selected_entries)} selected
        </span>
        <button type="button" phx-click="refresh" class="btn btn-ghost btn-xs">
          <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path
              stroke-linecap="round"
              stroke-linejoin="round"
              stroke-width="2"
              d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15"
            />
          </svg>
          Refresh
        </button>
      </div>
    </div>
    """
  end

  # ============================================================================
  # Overview View
  # ============================================================================

  attr :metrics, :map, required: true
  attr :all_queue_entries, :list, required: true
  attr :targets, :list, required: true
  attr :target_queue_counts, :map, required: true

  defp queue_overview_view(assigns) do
    # Calculate status breakdown
    status_breakdown =
      calculate_status_breakdown(assigns.all_queue_entries, assigns.metrics.total)

    # Top targets by queue count
    top_targets =
      assigns.target_queue_counts
      |> Enum.sort_by(fn {_id, count} -> count end, :desc)
      |> Enum.take(8)
      |> Enum.map(fn {target_id, count} ->
        target = Enum.find(assigns.targets, &(&1.id == target_id))
        %{name: if(target, do: target.name, else: target_id), count: count}
      end)

    max_target_count = if top_targets != [], do: hd(top_targets).count, else: 0

    assigns =
      assigns
      |> assign(:status_breakdown, status_breakdown)
      |> assign(:top_targets, top_targets)
      |> assign(:max_target_count, max_target_count)

    ~H"""
    <div class="queue-overview">
      <!-- Metric Cards -->
      <div class="queue-overview-metrics">
        <div class="queue-metric-card-lg queue-metric-queued">
          <span class="queue-metric-card-value">{@metrics.total}</span>
          <span class="queue-metric-card-label">TOTAL QUEUED</span>
        </div>
        <div class="queue-metric-card-lg queue-metric-pending">
          <span class="queue-metric-card-value">{@metrics.pending}</span>
          <span class="queue-metric-card-label">PENDING</span>
        </div>
        <div class="queue-metric-card-lg queue-metric-executing">
          <span class="queue-metric-card-value">{@metrics.executing}</span>
          <span class="queue-metric-card-label">EXECUTING</span>
        </div>
        <div class="queue-metric-card-lg queue-metric-failed">
          <span class="queue-metric-card-value">{@metrics.failed}</span>
          <span class="queue-metric-card-label">FAILED</span>
        </div>
        <div class="queue-metric-card-lg queue-metric-success">
          <span class="queue-metric-card-value">{@metrics.success_rate}%</span>
          <span class="queue-metric-card-label">SUCCESS RATE</span>
        </div>
      </div>
      
    <!-- Charts Row -->
      <div class="queue-overview-charts">
        <!-- Status Breakdown -->
        <div class="queue-chart-panel">
          <div class="queue-chart-header">
            <span class="mc-label-subsystem">STATUS BREAKDOWN</span>
          </div>
          <div class="queue-status-chart">
            <.status_bar_item
              :for={status <- @status_breakdown}
              name={status.name}
              count={status.count}
              percentage={status.percentage}
              color={status.color}
            />
          </div>
        </div>
        
    <!-- Target Activity -->
        <div class="queue-chart-panel">
          <div class="queue-chart-header">
            <span class="mc-label-subsystem">TARGET ACTIVITY</span>
          </div>
          <div class="queue-target-activity">
            <div :if={@top_targets == []} class="queue-chart-empty">
              No queue activity
            </div>
            <.target_bar_item
              :for={target <- @top_targets}
              name={target.name}
              count={target.count}
              max_count={@max_target_count}
            />
          </div>
        </div>
      </div>
      
    <!-- Quick Actions -->
      <div class="queue-overview-actions">
        <span class="mc-label-subsystem">QUICK ACTIONS</span>
        <div class="queue-quick-actions">
          <button type="button" phx-click="retry_all_failed" class="btn btn-ghost btn-sm">
            <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                stroke-width="2"
                d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15"
              />
            </svg>
            Retry Failed
          </button>
          <button type="button" phx-click="clear_completed" class="btn btn-ghost btn-sm">
            <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                stroke-width="2"
                d="M5 13l4 4L19 7"
              />
            </svg>
            Clear Completed
          </button>
          <button type="button" phx-click="pause_all" class="btn btn-ghost btn-sm">
            <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                stroke-width="2"
                d="M10 9v6m4-6v6m7-3a9 9 0 11-18 0 9 9 0 0118 0z"
              />
            </svg>
            Pause All
          </button>
        </div>
      </div>
    </div>
    """
  end

  attr :name, :string, required: true
  attr :count, :integer, required: true
  attr :percentage, :float, required: true
  attr :color, :string, required: true

  defp status_bar_item(assigns) do
    ~H"""
    <div class="queue-status-bar-item">
      <div class="queue-status-bar-label">
        <span class="queue-status-bar-name">{@name}</span>
        <span class="queue-status-bar-count">{@count}</span>
      </div>
      <div class="queue-status-bar-track">
        <div class="queue-status-bar-fill" style={"width: #{@percentage}%; background: #{@color};"}>
        </div>
      </div>
    </div>
    """
  end

  attr :name, :string, required: true
  attr :count, :integer, required: true
  attr :max_count, :integer, required: true

  defp target_bar_item(assigns) do
    percentage = if assigns.max_count > 0, do: assigns.count / assigns.max_count * 100, else: 0
    assigns = assign(assigns, :percentage, percentage)

    ~H"""
    <div class="queue-target-bar-item">
      <div class="queue-target-bar-label">
        <span class="queue-target-bar-name">{@name}</span>
        <span class="queue-target-bar-count">{@count}</span>
      </div>
      <div class="queue-target-bar-track">
        <div class="queue-target-bar-fill" style={"width: #{@percentage}%;"}></div>
      </div>
    </div>
    """
  end

  # ============================================================================
  # Manage View
  # ============================================================================

  attr :targets, :list, required: true
  attr :selected_target, :map, default: nil
  attr :target_entries, :list, required: true
  attr :target_queue_counts, :map, required: true
  attr :target_search, :string, required: true
  attr :paused_targets, :any, required: true
  attr :mission_id, :string, required: true

  defp queue_manage_view(assigns) do
    # Filter targets by search
    filtered_targets =
      if assigns.target_search == "" do
        assigns.targets
      else
        search_lower = String.downcase(assigns.target_search)

        Enum.filter(assigns.targets, fn t ->
          String.contains?(String.downcase(t.name || ""), search_lower)
        end)
      end

    assigns = assign(assigns, :filtered_targets, filtered_targets)

    ~H"""
    <div class="queue-manage-view">
      <!-- Target List Panel -->
      <div class="queue-manage-target-panel">
        <div class="queue-panel-header">
          <div class="queue-panel-title">
            <span class="mc-label-subsystem">TARGETS</span>
          </div>
        </div>

        <div class="queue-target-filters">
          <input
            type="text"
            class="queue-target-search"
            placeholder="Search targets..."
            value={@target_search}
            phx-keyup="filter_targets"
            phx-debounce="150"
          />
        </div>

        <div class="queue-manage-target-list">
          <.manage_target_item
            :for={target <- @filtered_targets}
            target={target}
            queue_count={Map.get(@target_queue_counts, target.id, 0)}
            selected={@selected_target && @selected_target.id == target.id}
            paused={MapSet.member?(@paused_targets, target.id)}
          />
        </div>
      </div>
      
    <!-- Queue Detail Panel -->
      <div class="queue-manage-detail-panel">
        <div :if={!@selected_target} class="queue-manage-empty-state">
          <svg class="w-16 h-16" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path
              stroke-linecap="round"
              stroke-linejoin="round"
              stroke-width="1"
              d="M19 11H5m14 0a2 2 0 012 2v6a2 2 0 01-2 2H5a2 2 0 01-2-2v-6a2 2 0 012-2m14 0V9a2 2 0 00-2-2M5 11V9a2 2 0 012-2m0 0V5a2 2 0 012-2h6a2 2 0 012 2v2M7 7h10"
            />
          </svg>
          <p>Select a target to view its queue</p>
        </div>

        <div :if={@selected_target} class="flex flex-col h-full">
          <!-- Detail Header -->
          <div class="queue-detail-header">
            <div class="queue-detail-title">
              <span class="queue-detail-target-name">{@selected_target.name}</span>
              <span class="queue-detail-status active">ACTIVE</span>
            </div>
            <div class="queue-detail-stats">
              <span>Queued: <strong>{length(@target_entries)}</strong></span>
              <span>
                Pending: <strong>{Enum.count(@target_entries, &(&1.status == :pending))}</strong>
              </span>
            </div>
          </div>
          
    <!-- Detail Actions -->
          <div class="queue-detail-actions">
            <button
              type="button"
              phx-click="pause_target"
              phx-value-id={@selected_target.id}
              class="btn btn-ghost btn-xs"
            >
              Pause Queue
            </button>
            <button
              type="button"
              phx-click="clear_target_queue"
              phx-value-id={@selected_target.id}
              class="btn btn-ghost btn-xs"
            >
              Clear Queue
            </button>
          </div>
          
    <!-- Detail Table -->
          <div class="queue-detail-table-wrapper">
            <div :if={@target_entries == []} class="queue-detail-empty">
              No commands in queue
            </div>
            <table :if={@target_entries != []} class="queue-detail-table">
              <thead>
                <tr>
                  <th class="queue-detail-th-pos">#</th>
                  <th class="queue-detail-th-pri">PRI</th>
                  <th>COMMAND</th>
                  <th class="queue-detail-th-status">STATUS</th>
                  <th class="queue-detail-th-actions"></th>
                </tr>
              </thead>
              <tbody>
                <.queue_detail_row
                  :for={{entry, idx} <- Enum.with_index(@target_entries)}
                  entry={entry}
                  position={idx + 1}
                />
              </tbody>
            </table>
          </div>
        </div>
      </div>
    </div>
    """
  end

  attr :target, :map, required: true
  attr :queue_count, :integer, required: true
  attr :selected, :boolean, required: true
  attr :paused, :boolean, required: true

  defp manage_target_item(assigns) do
    ~H"""
    <div
      class={["queue-manage-target-item", @selected && "selected", @paused && "paused"]}
      phx-click="select_target"
      phx-value-id={@target.id}
    >
      <div class="queue-manage-target-info">
        <span class="queue-manage-target-name">{@target.name}</span>
        <span class="queue-manage-target-stats">
          {if @paused, do: "PAUSED", else: "#{@queue_count} queued"}
        </span>
      </div>
      <button
        type="button"
        class={["queue-manage-pause-btn", @paused && "paused"]}
        phx-click="toggle_target_pause"
        phx-value-id={@target.id}
        title={if @paused, do: "Resume", else: "Pause"}
      >
        <%= if @paused do %>
          <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path
              stroke-linecap="round"
              stroke-linejoin="round"
              stroke-width="2"
              d="M14.752 11.168l-3.197-2.132A1 1 0 0010 9.87v4.263a1 1 0 001.555.832l3.197-2.132a1 1 0 000-1.664z"
            />
          </svg>
        <% else %>
          <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M10 9v6m4-6v6" />
          </svg>
        <% end %>
      </button>
    </div>
    """
  end

  attr :entry, :map, required: true
  attr :position, :integer, required: true

  defp queue_detail_row(assigns) do
    has_params = assigns.entry.parameters && map_size(assigns.entry.parameters) > 0
    assigns = assign(assigns, :has_params, has_params)

    ~H"""
    <tr class={["queue-detail-row", "queue-status-#{@entry.status}"]}>
      <td class="queue-detail-td-pos">{@position}</td>
      <td>
        <span class={"queue-priority-badge queue-priority-#{@entry.priority}"}>
          {@entry.priority}
        </span>
      </td>
      <td class="queue-detail-td-cmd">
        <span class={["queue-cmd-name", @has_params && "has-params"]}>
          {@entry.command_name}
          <.params_tooltip :if={@has_params} params={@entry.parameters} />
        </span>
      </td>
      <td><.queue_status_badge status={@entry.status} /></td>
      <td>
        <button
          :if={@entry.status in [:pending]}
          type="button"
          class="queue-cancel-entry-btn"
          phx-click="cancel_entry"
          phx-value-id={@entry.id}
          title="Cancel"
        >
          <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path
              stroke-linecap="round"
              stroke-linejoin="round"
              stroke-width="2"
              d="M6 18L18 6M6 6l12 12"
            />
          </svg>
        </button>
      </td>
    </tr>
    """
  end

  attr :params, :map, required: true

  defp params_tooltip(assigns) do
    ~H"""
    <span class="queue-params-tooltip">
      <div :for={{key, value} <- @params} class="queue-param-row">
        <span class="queue-param-key">{key}:</span>
        <span class="queue-param-value">{format_param_value(value)}</span>
      </div>
    </span>
    """
  end

  defp format_param_value(value) when is_binary(value), do: "\"#{value}\""
  defp format_param_value(value) when is_number(value), do: to_string(value)
  defp format_param_value(value) when is_boolean(value), do: to_string(value)
  defp format_param_value(value) when is_nil(value), do: "null"
  defp format_param_value(value), do: inspect(value)

  # ============================================================================
  # Table View
  # ============================================================================

  attr :targets, :list, required: true
  attr :selected_targets, :any, required: true
  attr :target_search, :string, required: true
  attr :view_mode, :string, required: true
  attr :streams, :map, required: true
  attr :status_filter, :atom, required: true
  attr :search, :string, required: true
  attr :selected_entries, :any, required: true
  attr :queue_metrics, :map, required: true
  attr :metrics_expanded, :boolean, required: true

  defp queue_table_view(assigns) do
    # Filter targets by search
    filtered_targets =
      if assigns.target_search == "" do
        assigns.targets
      else
        search_lower = String.downcase(assigns.target_search)

        Enum.filter(assigns.targets, fn t ->
          String.contains?(String.downcase(t.name || ""), search_lower)
        end)
      end

    assigns = assign(assigns, :filtered_targets, filtered_targets)

    ~H"""
    <div class="queue-table-view">
      <!-- Metrics Bar (collapsible) -->
      <div class={["queue-metrics-bar", !@metrics_expanded && "collapsed"]}>
        <button type="button" class="queue-metrics-toggle" phx-click="toggle_metrics">
          <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path
              stroke-linecap="round"
              stroke-linejoin="round"
              stroke-width="2"
              d={if @metrics_expanded, do: "M19 9l-7 7-7-7", else: "M5 15l7-7 7 7"}
            />
          </svg>
        </button>
        <div class="queue-metrics-summary">
          <div class="queue-metric queue-metric-total">
            <span class="queue-metric-value">{@queue_metrics.total}</span>
            <span class="queue-metric-label">QUEUED</span>
          </div>
          <div class="queue-metric queue-metric-pending">
            <span class="queue-metric-value">{@queue_metrics.pending}</span>
            <span class="queue-metric-label">PENDING</span>
          </div>
          <div class="queue-metric queue-metric-executing">
            <span class="queue-metric-value">{@queue_metrics.executing}</span>
            <span class="queue-metric-label">EXEC</span>
          </div>
          <div class="queue-metric queue-metric-failed">
            <span class="queue-metric-value">{@queue_metrics.failed}</span>
            <span class="queue-metric-label">FAILED</span>
          </div>
          <div class="queue-metric queue-metric-success">
            <span class="queue-metric-value">{@queue_metrics.success_rate}%</span>
            <span class="queue-metric-label">SUCCESS</span>
          </div>
        </div>
      </div>
      
    <!-- Two-Panel Row -->
      <div class="queue-panels-row">
        <!-- Target Selection Panel -->
        <div class="queue-target-panel">
          <div class="queue-panel-header">
            <div class="queue-panel-title">
              <span class="mc-label-subsystem">TARGETS</span>
            </div>
            <span class="queue-selection-count">
              {MapSet.size(@selected_targets)}/{length(@targets)}
            </span>
            <div class="queue-panel-actions">
              <button
                type="button"
                class={["queue-view-toggle", @view_mode == "compact" && "active"]}
                phx-click="set_view_mode"
                phx-value-mode="compact"
                title="Compact view"
              >
                <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path
                    stroke-linecap="round"
                    stroke-linejoin="round"
                    stroke-width="2"
                    d="M4 6h16M4 10h16M4 14h16M4 18h16"
                  />
                </svg>
              </button>
              <button
                type="button"
                class={["queue-view-toggle", @view_mode == "detailed" && "active"]}
                phx-click="set_view_mode"
                phx-value-mode="detailed"
                title="Detailed view"
              >
                <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path
                    stroke-linecap="round"
                    stroke-linejoin="round"
                    stroke-width="2"
                    d="M4 6a2 2 0 012-2h2a2 2 0 012 2v2a2 2 0 01-2 2H6a2 2 0 01-2-2V6zM14 6a2 2 0 012-2h2a2 2 0 012 2v2a2 2 0 01-2 2h-2a2 2 0 01-2-2V6zM4 16a2 2 0 012-2h2a2 2 0 012 2v2a2 2 0 01-2 2H6a2 2 0 01-2-2v-2zM14 16a2 2 0 012-2h2a2 2 0 012 2v2a2 2 0 01-2 2h-2a2 2 0 01-2-2v-2z"
                  />
                </svg>
              </button>
            </div>
          </div>

          <div class="queue-target-filters">
            <input
              type="text"
              class="queue-target-search"
              placeholder="Search targets..."
              value={@target_search}
              phx-keyup="filter_targets"
              phx-debounce="150"
            />
          </div>

          <div class={["queue-target-grid", @view_mode == "detailed" && "detailed"]}>
            <div :if={@filtered_targets == []} class="queue-target-empty">
              No targets found
            </div>
            <.queue_target_cell
              :for={target <- @filtered_targets}
              target={target}
              selected={MapSet.member?(@selected_targets, target.id)}
              view_mode={@view_mode}
            />
          </div>

          <div :if={MapSet.size(@selected_targets) > 0} class="queue-selection-actions">
            <button
              type="button"
              phx-click="clear_target_selection"
              class="btn btn-ghost btn-xs btn-block"
            >
              Clear Selection
            </button>
          </div>
        </div>
        
    <!-- Main Queue Panel -->
        <div class="queue-main-panel">
          <!-- Filter Bar -->
          <div class="queue-filter-bar">
            <div class="queue-filter-row">
              <input
                type="text"
                class="queue-search"
                placeholder="Search commands..."
                value={@search}
                phx-keyup="search"
                phx-debounce="150"
              />

              <div class="queue-status-filters">
                <button
                  type="button"
                  class={["queue-status-btn", @status_filter == :all && "active"]}
                  phx-click="filter_status"
                  phx-value-status="all"
                >
                  All
                </button>
                <button
                  type="button"
                  class={["queue-status-btn", @status_filter == :pending && "active"]}
                  phx-click="filter_status"
                  phx-value-status="pending"
                >
                  Pending
                </button>
                <button
                  type="button"
                  class={["queue-status-btn", @status_filter == :executing && "active"]}
                  phx-click="filter_status"
                  phx-value-status="executing"
                >
                  Exec
                </button>
                <button
                  type="button"
                  class={["queue-status-btn", @status_filter == :failed && "active"]}
                  phx-click="filter_status"
                  phx-value-status="failed"
                >
                  Failed
                </button>
              </div>

              <div class="queue-filter-actions">
                <span class="queue-entry-count">Showing entries</span>
              </div>
            </div>
          </div>
          
    <!-- Queue Table -->
          <div class="queue-table-container">
            <table class="queue-table">
              <thead>
                <tr>
                  <th class="queue-th queue-th-checkbox">
                    <input type="checkbox" class="checkbox checkbox-xs" phx-click="toggle_select_all" />
                  </th>
                  <th class="queue-th queue-th-target sortable">Target</th>
                  <th class="queue-th queue-th-command sortable">Command</th>
                  <th class="queue-th queue-th-status sortable">Status</th>
                  <th class="queue-th queue-th-priority sortable">Pri</th>
                  <th class="queue-th queue-th-scheduled sortable">Queued</th>
                  <th class="queue-th queue-th-actions">Actions</th>
                </tr>
              </thead>
              <tbody id="queue-entries" phx-update="stream">
                <.queue_table_row
                  :for={{dom_id, entry} <- @streams.queue_entries}
                  dom_id={dom_id}
                  entry={entry}
                  selected={MapSet.member?(@selected_entries, entry.id)}
                />
              </tbody>
            </table>

            <div :if={@streams.queue_entries == []} class="queue-table-empty">
              <svg class="w-16 h-16" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  stroke-width="1"
                  d="M19 11H5m14 0a2 2 0 012 2v6a2 2 0 01-2 2H5a2 2 0 01-2-2v-6a2 2 0 012-2m14 0V9a2 2 0 00-2-2M5 11V9a2 2 0 012-2m0 0V5a2 2 0 012-2h6a2 2 0 012 2v2M7 7h10"
                />
              </svg>
              <p>No queue entries</p>
            </div>
          </div>
        </div>
      </div>
      
    <!-- Bulk Actions Bar -->
      <div :if={MapSet.size(@selected_entries) > 0} class="queue-bulk-bar">
        <span class="queue-selected-count">{MapSet.size(@selected_entries)} selected</span>
        <button type="button" phx-click="cancel_selected" class="btn btn-ghost btn-xs">
          Cancel Selected
        </button>
        <button type="button" phx-click="retry_selected" class="btn btn-ghost btn-xs">
          Retry Selected
        </button>
      </div>
    </div>
    """
  end

  attr :target, :map, required: true
  attr :selected, :boolean, required: true
  attr :view_mode, :string, required: true

  defp queue_target_cell(assigns) do
    status_class =
      case assigns.target.status do
        s when s in [:nominal, :active, :online] -> "status-online"
        s when s in [:degraded, :warning, :standby] -> "status-standby"
        _ -> "status-offline"
      end

    assigns = assign(assigns, :status_class, status_class)

    ~H"""
    <div
      class={["queue-target-cell", @status_class, @selected && "selected"]}
      phx-click="toggle_target"
      phx-value-id={@target.id}
    >
      <span class="queue-target-name">{@target.name}</span>
    </div>
    """
  end

  attr :dom_id, :string, required: true
  attr :entry, :map, required: true
  attr :selected, :boolean, required: true

  defp queue_table_row(assigns) do
    ~H"""
    <tr id={@dom_id} class={["queue-row", "queue-status-#{@entry.status}", @selected && "selected"]}>
      <td class="queue-td queue-td-checkbox">
        <input
          type="checkbox"
          class="checkbox checkbox-xs"
          checked={@selected}
          phx-click="toggle_entry"
          phx-value-id={@entry.id}
        />
      </td>
      <td class="queue-td queue-td-target">
        <span class="queue-target-name">{@entry.target && @entry.target.name}</span>
      </td>
      <td class="queue-td">
        <span class="queue-command-name">{@entry.command_name}</span>
      </td>
      <td class="queue-td">
        <.queue_status_badge status={@entry.status} />
      </td>
      <td class="queue-td queue-td-priority">
        <span class={"queue-priority-badge queue-priority-#{@entry.priority}"}>
          {@entry.priority}
        </span>
      </td>
      <td class="queue-td queue-td-scheduled">
        <.format_queue_time time={@entry.inserted_at} />
      </td>
      <td class="queue-td queue-td-actions">
        <div class="queue-row-actions">
          <button
            :if={@entry.status in [:pending]}
            type="button"
            class="btn btn-ghost btn-xs"
            phx-click="cancel_entry"
            phx-value-id={@entry.id}
            title="Cancel"
          >
            <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                stroke-width="2"
                d="M6 18L18 6M6 6l12 12"
              />
            </svg>
          </button>
          <button
            :if={@entry.status == :failed}
            type="button"
            class="btn btn-ghost btn-xs"
            phx-click="retry_entry"
            phx-value-id={@entry.id}
            title="Retry"
          >
            <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                stroke-width="2"
                d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15"
              />
            </svg>
          </button>
        </div>
      </td>
    </tr>
    """
  end

  attr :status, :atom, required: true

  defp queue_status_badge(assigns) do
    ~H"""
    <span class={"queue-status-badge queue-status-#{@status}"}>
      {status_label(@status)}
    </span>
    """
  end

  defp status_label(:pending), do: "PEND"
  defp status_label(:executing), do: "EXEC"
  defp status_label(:completed), do: "DONE"
  defp status_label(:failed), do: "FAIL"
  defp status_label(:cancelled), do: "CANC"
  defp status_label(other), do: other |> to_string() |> String.upcase() |> String.slice(0, 4)

  attr :time, :any, required: true

  defp format_queue_time(assigns) do
    formatted =
      case assigns.time do
        nil -> "—"
        %DateTime{} = dt -> Calendar.strftime(dt, "%H:%M:%S")
        _ -> "—"
      end

    assigns = assign(assigns, :formatted, formatted)

    ~H"""
    <span class="font-mono text-xs">{@formatted}</span>
    """
  end

  # ============================================================================
  # Event handlers
  # ============================================================================

  @impl true
  def handle_event("refresh", _, socket) do
    {:noreply, refresh_queue_state(socket)}
  end

  def handle_event("select_target", %{"id" => id}, socket) do
    target = Enum.find(socket.assigns.targets, &(&1.id == id))
    mission_id = socket.assigns.mission.id

    # Fetch entries from runtime queue (sorted by priority, sequence)
    target_entries = Commands.list_target_queue(mission_id, id)

    socket =
      socket
      |> assign(:selected_target, target)
      |> assign(:target_entries, target_entries)

    {:noreply, socket}
  end

  def handle_event("toggle_target", %{"id" => id}, socket) do
    selected_targets =
      if MapSet.member?(socket.assigns.selected_targets, id) do
        MapSet.delete(socket.assigns.selected_targets, id)
      else
        MapSet.put(socket.assigns.selected_targets, id)
      end

    {:noreply, assign(socket, :selected_targets, selected_targets)}
  end

  def handle_event("clear_target_selection", _, socket) do
    {:noreply, assign(socket, :selected_targets, MapSet.new())}
  end

  def handle_event("filter_targets", %{"value" => value}, socket) do
    {:noreply, assign(socket, :target_search, value)}
  end

  def handle_event("search", %{"value" => value}, socket) do
    {:noreply, assign(socket, :search, value)}
  end

  def handle_event("filter_status", %{"status" => value}, socket) do
    status = if value == "all", do: :all, else: String.to_existing_atom(value)
    {:noreply, assign(socket, :status_filter, status)}
  end

  def handle_event("set_view_mode", %{"mode" => mode}, socket) do
    {:noreply, assign(socket, :view_mode, mode)}
  end

  def handle_event("toggle_metrics", _, socket) do
    {:noreply, assign(socket, :metrics_expanded, !socket.assigns.metrics_expanded)}
  end

  def handle_event("toggle_entry", %{"id" => id}, socket) do
    selected_entries =
      if MapSet.member?(socket.assigns.selected_entries, id) do
        MapSet.delete(socket.assigns.selected_entries, id)
      else
        MapSet.put(socket.assigns.selected_entries, id)
      end

    {:noreply, assign(socket, :selected_entries, selected_entries)}
  end

  def handle_event("toggle_select_all", _, socket) do
    # TODO: Implement select all from stream
    {:noreply, socket}
  end

  def handle_event("cancel_entry", %{"id" => id}, socket) do
    mission_id = socket.assigns.mission.id

    case Commands.get_queue_entry(id) do
      nil ->
        {:noreply, put_flash(socket, :error, "Entry not found")}

      entry ->
        case Commands.cancel_queued(mission_id, entry.target_id, entry.id) do
          {:ok, updated_entry} ->
            {:noreply, stream_insert(socket, :queue_entries, updated_entry)}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, "Failed to cancel")}
        end
    end
  end

  def handle_event("retry_entry", %{"id" => _id}, socket) do
    # TODO: Implement retry
    {:noreply, put_flash(socket, :info, "Retry not yet implemented")}
  end

  def handle_event("cancel_selected", _, socket) do
    # TODO: Implement bulk cancel
    {:noreply, put_flash(socket, :info, "Bulk cancel not yet implemented")}
  end

  def handle_event("retry_selected", _, socket) do
    # TODO: Implement bulk retry
    {:noreply, put_flash(socket, :info, "Bulk retry not yet implemented")}
  end

  def handle_event("retry_all_failed", _, socket) do
    # TODO: Implement retry_all_failed in Commands module
    {:noreply, put_flash(socket, :info, "Retry all failed not yet implemented")}
  end

  def handle_event("clear_completed", _, socket) do
    # TODO: Implement clear_completed in Commands module
    {:noreply, put_flash(socket, :info, "Clear completed not yet implemented")}
  end

  def handle_event("pause_all", _, socket) do
    Commands.pause_all_targets(socket.assigns.mission.id)
    {:noreply, put_flash(socket, :info, "All targets paused")}
  end

  def handle_event("pause_target", %{"id" => id}, socket) do
    Commands.pause_target(socket.assigns.mission.id, id)
    {:noreply, put_flash(socket, :info, "Target paused")}
  end

  def handle_event("toggle_target_pause", %{"id" => id}, socket) do
    mission_id = socket.assigns.mission.id
    paused_targets = socket.assigns.paused_targets
    is_paused = MapSet.member?(paused_targets, id)

    new_paused_targets =
      if is_paused do
        Commands.resume_target(mission_id, id)
        MapSet.delete(paused_targets, id)
      else
        Commands.pause_target(mission_id, id)
        MapSet.put(paused_targets, id)
      end

    {:noreply, assign(socket, :paused_targets, new_paused_targets)}
  end

  def handle_event("clear_target_queue", %{"id" => id}, socket) do
    case Commands.cancel_all_queued_for_target(socket.assigns.mission.id, id) do
      {:ok, _} ->
        socket =
          socket
          |> put_flash(:info, "Target queue cleared")
          |> refresh_queue_state()

        {:noreply, socket}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to clear queue")}
    end
  end

  # Alarm action handlers (from context panel)
  def handle_event("acknowledge_alarm", %{"id" => id}, socket) do
    alarm = Alarms.get_alarm!(id)
    user = socket.assigns.current_scope.user

    case Alarms.acknowledge_alarm(alarm, user.id) do
      {:ok, _updated_alarm} ->
        active_alarms = Alarms.list_active_alarms(socket.assigns.mission.id)

        {:noreply,
         socket
         |> assign(:alarms, active_alarms)
         |> assign(:alarm_counts, calculate_alarm_counts(active_alarms))}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to acknowledge alarm")}
    end
  end

  def handle_event("clear_alarm", %{"id" => id}, socket) do
    alarm = Alarms.get_alarm!(id)
    user = socket.assigns.current_scope.user

    case Alarms.clear_alarm(alarm, user.id) do
      {:ok, _cleared_alarm} ->
        active_alarms = Alarms.list_active_alarms(socket.assigns.mission.id)

        {:noreply,
         socket
         |> assign(:alarms, active_alarms)
         |> assign(:alarm_counts, calculate_alarm_counts(active_alarms))}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to clear alarm")}
    end
  end

  @impl true
  def handle_info({:queue_updated, entry}, socket) do
    _ = entry
    {:noreply, refresh_queue_state(socket)}
  end

  def handle_info(:tick, socket) do
    {:noreply, assign(socket, :current_time, DateTime.utc_now())}
  end

  def handle_info({:alarm_triggered, _alarm}, socket) do
    active_alarms = Alarms.list_active_alarms(socket.assigns.mission.id)

    socket =
      socket
      |> assign(:alarm_counts, calculate_alarm_counts(active_alarms))
      |> assign(:alarms, active_alarms)

    {:noreply, socket}
  end

  def handle_info({:alarm_cleared, _alarm}, socket) do
    active_alarms = Alarms.list_active_alarms(socket.assigns.mission.id)

    socket =
      socket
      |> assign(:alarm_counts, calculate_alarm_counts(active_alarms))
      |> assign(:alarms, active_alarms)

    {:noreply, socket}
  end

  def handle_info(_, socket), do: {:noreply, socket}

  # ============================================================================
  # Private helpers
  # ============================================================================

  defp refresh_queue_state(socket) do
    mission_id = socket.assigns.mission.id
    targets = socket.assigns.targets

    all_queue_entries =
      Commands.list_queue_entries(mission_id,
        status: [:pending, :executing, :completed, :failed, :cancelled],
        limit: 200
      )

    target_queue_counts = calculate_target_queue_counts(all_queue_entries)
    queue_metrics = calculate_metrics(all_queue_entries)
    context_queue_entries = build_context_queue_entries(mission_id, targets)

    socket
    |> assign(:all_queue_entries, all_queue_entries)
    |> stream(:queue_entries, all_queue_entries, reset: true)
    |> assign(:queue_metrics, queue_metrics)
    |> assign(:target_queue_counts, target_queue_counts)
    |> assign(:queue_entries, context_queue_entries)
  end

  defp calculate_metrics(entries) do
    total = length(entries)
    pending = Enum.count(entries, &(&1.status == :pending))
    executing = Enum.count(entries, &(&1.status == :executing))
    completed = Enum.count(entries, &(&1.status == :completed))
    failed = Enum.count(entries, &(&1.status == :failed))

    success_rate =
      if completed + failed > 0 do
        round(completed / (completed + failed) * 100)
      else
        100
      end

    %{
      total: total,
      pending: pending,
      executing: executing,
      completed: completed,
      failed: failed,
      success_rate: success_rate
    }
  end

  defp calculate_target_queue_counts(entries) do
    Enum.reduce(entries, %{}, fn entry, acc ->
      if entry.status in [:pending, :executing] do
        Map.update(acc, entry.target_id, 1, &(&1 + 1))
      else
        acc
      end
    end)
  end

  defp calculate_status_breakdown(entries, total) do
    if total == 0 do
      []
    else
      statuses = [
        %{status: :pending, name: "Pending", color: "var(--badge-pending)"},
        %{status: :executing, name: "Executing", color: "var(--glow-cyan)"},
        %{status: :completed, name: "Completed", color: "var(--status-success)"},
        %{status: :failed, name: "Failed", color: "var(--status-critical)"},
        %{status: :cancelled, name: "Cancelled", color: "var(--neutral-text)"}
      ]

      Enum.map(statuses, fn s ->
        count = Enum.count(entries, &(&1.status == s.status))
        percentage = count / total * 100

        %{
          name: s.name,
          count: count,
          percentage: percentage,
          color: s.color
        }
      end)
      |> Enum.filter(&(&1.count > 0))
    end
  end

  defp calculate_alarm_counts(alarms) do
    %{
      critical: Enum.count(alarms, &(&1.severity == :critical)),
      warning: Enum.count(alarms, &(&1.severity == :warning)),
      info: Enum.count(alarms, &(&1.severity == :info))
    }
  end

  defp calculate_fleet_health(targets) do
    total = length(targets)

    if total == 0 do
      %{healthy: 0, degraded: 0, offline: 0, total: 0, percentage: 100}
    else
      healthy = Enum.count(targets, &(&1.status in [:nominal, :active, :online]))
      degraded = Enum.count(targets, &(&1.status in [:degraded, :warning, :standby]))
      offline = total - healthy - degraded

      %{
        healthy: healthy,
        degraded: degraded,
        offline: offline,
        total: total,
        percentage: round(healthy / total * 100)
      }
    end
  end

  defp build_context_queue_entries(mission_id, targets) do
    entries =
      Commands.list_queue_entries(mission_id,
        status: [:pending, :executing],
        limit: 50
      )

    attach_targets_to_queue_entries(entries, targets)
  end

  defp attach_targets_to_queue_entries(queue_entries, targets) do
    targets_by_id = Map.new(targets, &{&1.id, &1})

    Enum.map(queue_entries, fn entry ->
      target = Map.get(targets_by_id, entry.target_id)

      entry
      |> Map.from_struct()
      |> Map.put(:target, target)
    end)
  end

  defp load_paused_targets(mission_id, targets) do
    targets
    |> Enum.filter(fn target ->
      try do
        Commands.target_paused?(mission_id, target.id)
      rescue
        # TargetDispatcher not running yet
        _ -> false
      catch
        :exit, _ -> false
      end
    end)
    |> MapSet.new(& &1.id)
  end
end
