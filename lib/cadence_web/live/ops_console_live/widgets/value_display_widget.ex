defmodule CadenceWeb.OpsConsoleLive.Widgets.ValueDisplayWidget do
  @moduledoc """
  Phoenix LiveComponent for displaying a single telemetry value.

  Shows the current value with:
  - Limits state coloring (green/yellow/red)
  - Trend indicator (up/down/stable)
  - Unit display
  - Item label

  Real-time updates are handled by a JavaScript hook that subscribes
  to the TelemetryStore for high-frequency updates without LiveView
  round-trips.

  ## Usage

      <.live_component
        module={ValueDisplayWidget}
        id="value-widget-1"
        widget_id="widget-123"
        config={%{
          "telemetry_item" => %{
            "target" => "SAT-1",
            "packet" => "HEALTH",
            "item" => "CPU_TEMP"
          },
          "unit" => "°C",
          "precision" => 2,
          "show_trend" => true
        }}
        on_configure={JS.push("open_widget_config")}
      />
  """
  use CadenceWeb, :live_component

  import CadenceWeb.WidgetComponents

  alias Phoenix.LiveView.JS

  @impl true
  def mount(socket) do
    {:ok, assign(socket, current_value: nil, limits_state: :unknown, trend: nil)}
  end

  @impl true
  def update(assigns, socket) do
    socket =
      socket
      |> assign(assigns)
      |> assign_telemetry_key()

    {:ok, socket}
  end

  defp assign_telemetry_key(socket) do
    config = socket.assigns[:config] || %{}
    item = config["telemetry_item"] || %{}

    telemetry_key =
      case {item["target"], item["packet"], item["item"]} do
        {t, p, i} when is_binary(t) and is_binary(p) and is_binary(i) ->
          "#{t}:#{p}:#{i}"

        _ ->
          nil
      end

    assign(socket, :telemetry_key, telemetry_key)
  end

  @impl true
  def render(assigns) do
    config = assigns[:config] || %{}
    item = config["telemetry_item"] || %{}
    unit = config["unit"] || ""
    show_trend = Map.get(config, "show_trend", true)
    title = config["title"] || item["item"] || "Value"

    assigns =
      assigns
      |> assign(:unit, unit)
      |> assign(:show_trend, show_trend)
      |> assign(:title, title)
      |> assign(:item, item)

    ~H"""
    <.widget
      id={@widget_id}
      title={@title}
      on_configure={@on_configure && JS.push("open_widget_config", value: widget_config_value(@widget_id, "value_display", @config))}
    >
      <div
        id={"#{@widget_id}-content"}
        class="value-display"
        phx-hook="ValueDisplayWidget"
        phx-update="ignore"
        data-telemetry-key={@telemetry_key}
        data-unit={@unit}
        data-precision={@config["precision"] || 2}
        data-show-trend={to_string(@show_trend)}
      >
        <div class="value-container">
          <span class="value text-4xl font-mono font-bold" data-value>--</span>
          <span :if={@unit != ""} class="unit text-lg text-base-content/70">{@unit}</span>
          <span :if={@show_trend} class="trend text-2xl" data-trend></span>
        </div>
        <div class="limits-state mt-2" data-limits-state>
          <.limits_badge state={:unknown} />
        </div>
        <div :if={@item["target"]} class="item-label text-sm text-base-content/50 mt-2">
          {@item["target"]}/{@item["packet"]}/{@item["item"]}
        </div>
      </div>
    </.widget>
    """
  end

  defp widget_config_value(widget_id, widget_type, config) do
    %{
      widget_id: widget_id,
      widget_type: widget_type,
      config: config
    }
  end
end
