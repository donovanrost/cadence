defmodule CadenceWeb.OpsConsoleLive.ContextPanelComponent do
  @moduledoc """
  Context panel for OPS Console.

  Displays:
  - Active alarms grouped by severity
  - Command queue summary
  - Quick actions for acknowledging/clearing

  Supports collapsed (rail) and expanded states.
  """

  use CadenceWeb, :live_component

  @impl true
  def update(assigns, socket) do
    socket =
      socket
      |> assign(assigns)
      |> assign_new(:collapsed, fn -> false end)
      |> assign_new(:alarms, fn -> [] end)
      |> assign_new(:collapsed_sections, fn -> MapSet.new() end)

    # Group alarms by severity
    grouped_alarms = group_alarms_by_severity(socket.assigns.alarms)
    socket = assign(socket, :grouped_alarms, grouped_alarms)

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex flex-col h-full">
      <!-- Expanded view (hidden when panel is collapsed) -->
      <div class="context-panel-v2 p-3">
        <!-- Alarms Section -->
        <div class={["context-section", MapSet.member?(@collapsed_sections, :alarms) && "collapsed"]}>
          <button
            type="button"
            class="context-section-header"
            phx-click="toggle_section"
            phx-value-section="alarms"
            phx-target={@myself}
          >
            <div class="flex items-center gap-2">
              <svg class="section-chevron w-3 h-3 transition-transform" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 9l-7 7-7-7"/>
              </svg>
              <span class="mc-label-subsystem text-base-content/40">ACTIVE ALARMS</span>
              <span class="text-xs text-base-content/60">({total_alarms(@alarm_counts)})</span>
            </div>
            <div :if={total_alarms(@alarm_counts) > 0} class="flex items-center gap-1.5">
              <span :if={@alarm_counts.critical > 0} class="w-2 h-2 rounded-full bg-error"></span>
              <span :if={@alarm_counts.warning > 0} class="w-2 h-2 rounded-full bg-warning"></span>
              <span :if={@alarm_counts.info > 0} class="w-2 h-2 rounded-full bg-info"></span>
            </div>
          </button>
          <div class="context-section-content">
            <!-- Critical alarms -->
            <div :if={length(@grouped_alarms.critical) > 0} class="alarm-group mb-3">
              <div class="alarm-group-header alarm-group-critical mb-2">
                <span class="w-2 h-2 rounded-full bg-error"></span>
                <span>CRITICAL ({length(@grouped_alarms.critical)})</span>
              </div>
              <div class="flex flex-col gap-1">
                <.alarm_item :for={alarm <- @grouped_alarms.critical} alarm={alarm} />
              </div>
            </div>

            <!-- Warning alarms -->
            <div :if={length(@grouped_alarms.warning) > 0} class="alarm-group mb-3">
              <div class="alarm-group-header alarm-group-warning mb-2">
                <span class="w-2 h-2 rounded-full bg-warning"></span>
                <span>WARNING ({length(@grouped_alarms.warning)})</span>
              </div>
              <div class="flex flex-col gap-1">
                <.alarm_item :for={alarm <- @grouped_alarms.warning} alarm={alarm} />
              </div>
            </div>

            <!-- Info alarms -->
            <div :if={length(@grouped_alarms.info) > 0} class="alarm-group mb-3">
              <div class="alarm-group-header alarm-group-info mb-2">
                <span class="w-2 h-2 rounded-full bg-info"></span>
                <span>INFO ({length(@grouped_alarms.info)})</span>
              </div>
              <div class="flex flex-col gap-1">
                <.alarm_item :for={alarm <- @grouped_alarms.info} alarm={alarm} />
              </div>
            </div>

            <!-- Empty state -->
            <div :if={total_alarms(@alarm_counts) == 0} class="text-center py-4 text-base-content/40">
              <p class="text-xs">No active alarms</p>
            </div>
          </div>
        </div>

        <!-- Command Queue Section -->
        <div class={[
          "context-section mt-3 pt-3 border-t border-base-300",
          MapSet.member?(@collapsed_sections, :queue) && "collapsed"
        ]}>
          <button
            type="button"
            class="context-section-header"
            phx-click="toggle_section"
            phx-value-section="queue"
            phx-target={@myself}
          >
            <div class="flex items-center gap-2">
              <svg class="section-chevron w-3 h-3 transition-transform" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 9l-7 7-7-7"/>
              </svg>
              <span class="mc-label-subsystem text-base-content/40">COMMAND QUEUE</span>
              <span class="text-xs text-base-content/60">({length(@queue_entries)})</span>
            </div>
            <span
              :if={Enum.any?(@queue_entries, &(&1.status == :executing))}
              class="w-2 h-2 rounded-full bg-warning animate-pulse"
            >
            </span>
          </button>
          <div class="context-section-content cmd-queue-list">
            <.queue_entry_item :for={entry <- Enum.take(@queue_entries, 10)} entry={entry} />
            <p
              :if={@queue_entries == []}
              class="text-xs text-base-content/40 text-center py-4"
            >
              No pending commands
            </p>
          </div>
        </div>
      </div>

      <!-- Rail view (shown when panel is collapsed) -->
      <div class="context-rail hidden flex-col items-center py-2 gap-1">
        <!-- Critical alarms badge -->
        <div
          class={["rail-alarm-badge critical", @alarm_counts.critical > 0 && "has-alarms"]}
          title="Critical Alarms"
        >
          <span class="rail-alarm-count">{@alarm_counts.critical}</span>
          <span class="rail-alarm-label">CRIT</span>
        </div>

        <!-- Warning alarms badge -->
        <div class="rail-alarm-badge warning" title="Warning Alarms">
          <span class="rail-alarm-count">{@alarm_counts.warning}</span>
          <span class="rail-alarm-label">WARN</span>
        </div>

        <!-- Info alarms badge -->
        <div class="rail-alarm-badge info" title="Info Alarms">
          <span class="rail-alarm-count">{@alarm_counts.info}</span>
          <span class="rail-alarm-label">INFO</span>
        </div>

        <div class="rail-divider"></div>

        <!-- Command queue badge -->
        <div
          class={["rail-command-badge", length(@queue_entries) > 0 && "has-commands"]}
          title="Pending Commands"
        >
          <span class="rail-command-count">{length(@queue_entries)}</span>
          <span class="rail-command-label">CMD</span>
        </div>
      </div>
    </div>
    """
  end

  @impl true
  def handle_event("toggle_context_panel", _, socket) do
    send(self(), {:toggle_context_panel})
    {:noreply, socket}
  end

  def handle_event("toggle_section", %{"section" => section}, socket) do
    section_atom = String.to_existing_atom(section)

    collapsed_sections =
      if MapSet.member?(socket.assigns.collapsed_sections, section_atom) do
        MapSet.delete(socket.assigns.collapsed_sections, section_atom)
      else
        MapSet.put(socket.assigns.collapsed_sections, section_atom)
      end

    {:noreply, assign(socket, :collapsed_sections, collapsed_sections)}
  end

  # Alarm item component - matches /ops dashboard structure
  attr :alarm, :map, required: true

  defp alarm_item(assigns) do
    severity_class = alarm_severity_class(assigns.alarm)
    assigns = assign(assigns, :severity_class, severity_class)

    ~H"""
    <div class={"alarm-item #{@severity_class}"} data-id={@alarm.id}>
      <div class="alarm-header">
        <span class="alarm-source">{alarm_source(@alarm)}</span>
        <span class="alarm-time">{format_alarm_time(@alarm.triggered_at)}</span>
      </div>
      <div class="alarm-message">{@alarm.message || @alarm.name || "Alarm"}</div>
      <div class="alarm-actions">
        <button
          type="button"
          class="alarm-btn alarm-btn-ack"
          phx-click="acknowledge_alarm"
          phx-value-id={@alarm.id}
        >
          ACK
        </button>
        <button
          type="button"
          class="alarm-btn alarm-btn-clear"
          phx-click="clear_alarm"
          phx-value-id={@alarm.id}
        >
          CLEAR
        </button>
      </div>
    </div>
    """
  end

  defp alarm_severity_class(%{severity: :critical}), do: "alarm-item-critical"
  defp alarm_severity_class(%{severity: :warning}), do: "alarm-item-warning"
  defp alarm_severity_class(%{severity: :info}), do: "alarm-item-info"
  defp alarm_severity_class(_), do: "alarm-item-info"

  defp alarm_source(%{target_name: name}) when is_binary(name), do: name
  defp alarm_source(%{target: %{name: name}}) when is_binary(name), do: name
  defp alarm_source(_), do: "Unknown"

  defp format_alarm_time(nil), do: "--:--"

  defp format_alarm_time(time) when is_binary(time) do
    case DateTime.from_iso8601(time) do
      {:ok, dt, _} -> format_alarm_time(dt)
      _ -> time
    end
  end

  defp format_alarm_time(%DateTime{} = time) do
    Calendar.strftime(time, "%H:%M:%S")
  end

  defp format_alarm_time(_), do: "--:--"

  # Queue entry item component - matches /ops dashboard structure
  attr :entry, :map, required: true

  defp queue_entry_item(assigns) do
    status = assigns.entry.status || :pending
    status_class = queue_status_class(status)
    priority = Map.get(assigns.entry, :priority, 3)
    priority_class = priority_class(priority)

    status_label =
      case status do
        :pending -> "PEND"
        :held -> "HOLD"
        :executing -> "EXEC"
        :completed -> "DONE"
        :failed -> "FAIL"
        other -> other |> to_string() |> String.upcase() |> String.slice(0, 4)
      end

    assigns =
      assigns
      |> assign(:status_class, status_class)
      |> assign(:priority, priority)
      |> assign(:priority_class, priority_class)
      |> assign(:status_label, status_label)
      |> assign(:is_executing, status == :executing)
      |> assign(:is_failed, status == :failed)

    ~H"""
    <div class={"qe #{@status_class}"} data-id={@entry.id}>
      <div class="qe-meta-row">
        <span class="qe-target">{queue_target_name(@entry)}</span>
        <div class="qe-badges">
          <span class={"qe-priority #{@priority_class}"}>P{@priority}</span>
          <span class="qe-status">{@status_label}</span>
        </div>
      </div>
      <div class="qe-command-row">
        <span :if={@is_executing} class="qe-pulse-inline"></span>
        <svg
          :if={@is_failed}
          class="qe-error-inline"
          fill="none"
          stroke="currentColor"
          viewBox="0 0 24 24"
        >
          <path
            stroke-linecap="round"
            stroke-linejoin="round"
            stroke-width="2"
            d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z"
          />
        </svg>
        <span class="qe-command">{@entry.command_name || "Command"}</span>
      </div>
      <.queue_params_row :if={has_params?(@entry)} entry={@entry} />
    </div>
    """
  end

  defp has_params?(%{parameters: params}) when is_map(params) and map_size(params) > 0, do: true
  defp has_params?(_), do: false

  attr :entry, :map, required: true

  defp queue_params_row(assigns) do
    params = Map.get(assigns.entry, :parameters, %{}) || %{}
    param_items = Enum.take(params, 3)
    assigns = assign(assigns, :param_items, param_items)

    ~H"""
    <div class="qe-params-row">
      <span :for={{key, val} <- @param_items} class="qe-param-item">
        <span class="qe-param-key">{key}</span>
        <span class="qe-param-val">{format_param_value(val)}</span>
      </span>
    </div>
    """
  end

  defp format_param_value(val) when is_binary(val), do: val
  defp format_param_value(val) when is_number(val), do: to_string(val)
  defp format_param_value(val) when is_boolean(val), do: to_string(val)
  defp format_param_value(val) when is_list(val), do: "[...]"
  defp format_param_value(val) when is_map(val), do: "{...}"
  defp format_param_value(nil), do: "null"
  defp format_param_value(_), do: "?"

  defp queue_status_class(:pending), do: "pending"
  defp queue_status_class(:held), do: "held"
  defp queue_status_class(:executing), do: "executing"
  defp queue_status_class(:completed), do: "completed"
  defp queue_status_class(:failed), do: "failed"
  defp queue_status_class(_), do: "pending"

  defp priority_class(p) when p <= 1, do: "priority-high"
  defp priority_class(p) when p >= 4, do: "priority-low"
  defp priority_class(_), do: ""

  defp queue_target_name(%{target: %{name: name}}), do: name
  defp queue_target_name(%{target_name: name}) when is_binary(name), do: name
  defp queue_target_name(_), do: "?"

  # Helper functions
  defp group_alarms_by_severity(alarms) do
    %{
      critical: Enum.filter(alarms, &(&1.severity == :critical)),
      warning: Enum.filter(alarms, &(&1.severity == :warning)),
      info: Enum.filter(alarms, &(&1.severity == :info))
    }
  end

  defp total_alarms(%{critical: c, warning: w, info: i}), do: c + w + i
  defp total_alarms(_), do: 0
end
