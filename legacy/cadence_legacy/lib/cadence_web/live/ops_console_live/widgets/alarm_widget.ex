defmodule CadenceWeb.OpsConsoleLive.Widgets.AlarmWidget do
  @moduledoc """
  Phoenix LiveComponent for displaying alarm summaries.

  Shows filtered alarm list with:
  - Severity counts (critical/warning/info)
  - Inline actions (acknowledge, shelve, clear)
  - Configurable filters

  ## Usage

      <.live_component
        module={AlarmWidget}
        id="alarm-widget-1"
        widget_id="widget-789"
        alarms={@active_alarms}
        config={%{
          "severity_filter" => ["critical", "warning"],
          "target_filter" => nil,
          "max_alarms" => 20
        }}
        on_configure={JS.push("open_widget_config")}
        on_acknowledge={JS.push("acknowledge_alarm")}
        on_shelve={JS.push("open_shelve_modal")}
        on_clear={JS.push("clear_alarm")}
      />
  """
  use CadenceWeb, :live_component

  import CadenceWeb.WidgetComponents

  alias Phoenix.LiveView.JS

  @impl true
  def mount(socket) do
    {:ok, assign(socket, acknowledged_ids: MapSet.new())}
  end

  @impl true
  def update(assigns, socket) do
    {:ok, assign(socket, assigns)}
  end

  @impl true
  def render(assigns) do
    config = assigns[:config] || %{}
    alarms = assigns[:alarms] || []
    title = config["title"] || "Alarms"

    # Apply filters
    severity_filter = config["severity_filter"] || []
    target_filter = config["target_filter"]
    max_alarms = config["max_alarms"] || 20
    show_cleared = config["show_cleared"] || false

    filtered_alarms =
      alarms
      |> filter_by_severity(severity_filter)
      |> filter_by_target(target_filter)
      |> filter_cleared(show_cleared)
      |> Enum.take(max_alarms)

    # Calculate counts from unfiltered (but not cleared) alarms
    active_alarms = Enum.reject(alarms, &(&1.status == :cleared))
    counts = calculate_counts(active_alarms)

    has_filters = severity_filter != [] || target_filter != nil

    assigns =
      assigns
      |> assign(:title, title)
      |> assign(:filtered_alarms, filtered_alarms)
      |> assign(:counts, counts)
      |> assign(:has_filters, has_filters)

    ~H"""
    <.widget
      id={@widget_id}
      title={@title}
      on_configure={
        @on_configure &&
          JS.push("open_widget_config", value: widget_config_value(@widget_id, "alarm", @config))
      }
    >
      <div class="alarm-widget">
        <!-- Summary header -->
        <.alarm_summary
          critical={@counts.critical}
          warning={@counts.warning}
          info={@counts.info}
          on_acknowledge_all={
            @on_acknowledge &&
              JS.push("acknowledge_alarms", value: %{alarm_ids: Enum.map(@filtered_alarms, & &1.id)})
          }
        />
        
    <!-- Alarm list -->
        <div class="alarm-list mt-2">
          <.alarm_item
            :for={alarm <- @filtered_alarms}
            alarm={alarm_to_map(alarm)}
            acknowledged={alarm.acknowledged_at != nil || MapSet.member?(@acknowledged_ids, alarm.id)}
            on_acknowledge={@on_acknowledge && JS.push("acknowledge_alarm", value: %{id: alarm.id})}
            on_shelve={@on_shelve && JS.push("open_shelve_modal", value: %{id: alarm.id})}
            on_clear={@on_clear && JS.push("clear_alarm", value: %{id: alarm.id})}
          />

          <.widget_empty
            :if={@filtered_alarms == []}
            icon="hero-check-circle"
            message="No alarms"
          />
        </div>
        
    <!-- Filter indicator -->
        <div :if={@has_filters} class="alarm-filter-info">
          <div class="text-xs text-base-content/40 flex items-center gap-2">
            <.icon name="hero-funnel" class="w-3 h-3" />
            <span>Filtered view</span>
          </div>
        </div>
      </div>
    </.widget>
    """
  end

  defp filter_by_severity(alarms, []), do: alarms

  defp filter_by_severity(alarms, severities) do
    severity_atoms = Enum.map(severities, &String.to_existing_atom/1)
    Enum.filter(alarms, &(&1.severity in severity_atoms))
  end

  defp filter_by_target(alarms, nil), do: alarms

  defp filter_by_target(alarms, target_filter) do
    Enum.filter(alarms, fn alarm ->
      alarm.target_id == target_filter || alarm.target_name == target_filter
    end)
  end

  defp filter_cleared(alarms, true), do: alarms
  defp filter_cleared(alarms, _), do: Enum.reject(alarms, &(&1.status == :cleared))

  defp calculate_counts(alarms) do
    Enum.reduce(alarms, %{critical: 0, warning: 0, info: 0}, fn alarm, acc ->
      case alarm.severity do
        :critical -> Map.update!(acc, :critical, &(&1 + 1))
        :warning -> Map.update!(acc, :warning, &(&1 + 1))
        _ -> Map.update!(acc, :info, &(&1 + 1))
      end
    end)
  end

  defp alarm_to_map(alarm) do
    %{
      id: alarm.id,
      severity: alarm.severity,
      message: alarm.message,
      target_name: Map.get(alarm, :target_name) || Map.get(alarm, :source_id),
      triggered_at: alarm.triggered_at,
      name: Map.get(alarm, :alarm_type)
    }
  end

  defp widget_config_value(widget_id, widget_type, config) do
    %{widget_id: widget_id, widget_type: widget_type, config: config}
  end
end
