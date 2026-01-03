defmodule CadenceWeb.WidgetComponents do
  @moduledoc """
  Shared UI components for dashboard widgets.

  These components provide consistent styling and behavior for widgets
  that can be used in both Phoenix LiveComponents and referenced by
  JavaScript widget hooks that use the same CSS classes.

  ## Design Principles

  1. **CSS Class Consistency** - Components output the same CSS classes that
     JavaScript widgets use, enabling shared styling via `widget-components.css`

  2. **Composability** - Small, focused components that can be combined
     to build complex widget UIs

  3. **Status Semantics** - Consistent severity/status mapping across all widgets
     (critical, warning, info, nominal/success)
  """
  use Phoenix.Component

  alias Phoenix.LiveView.JS

  # =============================================================================
  # Widget Container Components
  # =============================================================================

  @doc """
  Renders a widget container with optional header and config button.

  This is the base wrapper for all widgets, providing consistent padding,
  borders, and header layout.

  ## Examples

      <.widget id="my-widget" title="Telemetry Value">
        Widget content here
      </.widget>

      <.widget id="alarm-1" title="Alarms" on_configure={JS.push("open_config")}>
        <:header_actions>
          <button class="btn btn-ghost btn-xs">ACK ALL</button>
        </:header_actions>
        Alarm list here
      </.widget>
  """
  attr :id, :string, required: true
  attr :title, :string, default: nil
  attr :class, :string, default: nil
  attr :on_configure, JS, default: nil, doc: "JS command to run when config button clicked"
  slot :header_actions, doc: "additional buttons/controls in the header"
  slot :inner_block, required: true

  def widget(assigns) do
    ~H"""
    <div id={@id} class={["widget-container flex flex-col h-full", @class]}>
      <div :if={@title || @header_actions != [] || @on_configure} class="widget-header">
        <span :if={@title} class="widget-title">{@title}</span>
        <div class="flex items-center gap-1 ml-auto">
          {render_slot(@header_actions)}
          <button
            :if={@on_configure}
            type="button"
            class="btn btn-ghost btn-xs btn-square opacity-60 hover:opacity-100"
            phx-click={@on_configure}
            title="Configure widget"
          >
            <.icon name="hero-cog-6-tooth" class="w-3.5 h-3.5" />
          </button>
        </div>
      </div>
      <div class="widget-content">
        {render_slot(@inner_block)}
      </div>
    </div>
    """
  end

  # =============================================================================
  # Status & Severity Indicators
  # =============================================================================

  @doc """
  Renders a severity indicator dot with optional pulse animation.

  Maps severity levels to appropriate colors.

  ## Examples

      <.severity_dot severity={:critical} />
      <.severity_dot severity={:warning} pulse={true} />
      <.severity_dot severity="info" size="lg" />
  """
  attr :severity, :any,
    required: true,
    doc: "Severity level: :critical, :warning, :info, :nominal, or string equivalents"

  attr :pulse, :boolean, default: false, doc: "animate with pulse effect"
  attr :size, :string, default: "md", values: ~w(sm md lg)
  attr :class, :string, default: nil

  def severity_dot(assigns) do
    severity = normalize_severity(assigns.severity)

    color_class =
      case severity do
        :critical -> "bg-error"
        :warning -> "bg-warning"
        :info -> "bg-info"
        :nominal -> "bg-success"
        _ -> "bg-base-content/30"
      end

    size_class =
      case assigns.size do
        "sm" -> "w-1.5 h-1.5"
        "md" -> "w-2 h-2"
        "lg" -> "w-2.5 h-2.5"
      end

    assigns =
      assigns
      |> assign(:color_class, color_class)
      |> assign(:size_class, size_class)

    ~H"""
    <span class={[
      "rounded-full flex-shrink-0",
      @color_class,
      @size_class,
      @pulse && "animate-pulse",
      @class
    ]}>
    </span>
    """
  end

  @doc """
  Renders a status indicator with dot and label.

  ## Examples

      <.status_indicator status={:nominal} label="Ready" />
      <.status_indicator status={:pending} label="Sending..." pulse={true} />
  """
  attr :status, :any, required: true
  attr :label, :string, required: true
  attr :pulse, :boolean, default: false
  attr :class, :string, default: nil

  def status_indicator(assigns) do
    status = normalize_severity(assigns.status)

    text_class =
      case status do
        :critical -> "text-error"
        :warning -> "text-warning"
        :info -> "text-info"
        :nominal -> "text-success"
        :pending -> "text-info"
        _ -> "text-base-content/50"
      end

    assigns = assign(assigns, :text_class, text_class)

    ~H"""
    <div class={["flex items-center gap-2", @class]}>
      <.severity_dot severity={@status} pulse={@pulse} />
      <span class={["text-xs", @text_class]}>{@label}</span>
    </div>
    """
  end

  @doc """
  Renders an alarm/severity count badge.

  Used in summary headers to show counts by severity level.

  ## Examples

      <.severity_count severity={:critical} count={3} />
      <.severity_count severity={:warning} count={12} />
  """
  attr :severity, :any, required: true
  attr :count, :integer, required: true
  attr :pulse, :boolean, default: false, doc: "pulse animation for critical"
  attr :class, :string, default: nil

  def severity_count(assigns) do
    severity = normalize_severity(assigns.severity)

    text_class =
      case severity do
        :critical -> "text-error"
        :warning -> "text-warning"
        :info -> "text-info"
        :nominal -> "text-success"
        _ -> "text-base-content/50"
      end

    assigns = assign(assigns, :text_class, text_class)

    ~H"""
    <div :if={@count > 0} class={["flex items-center gap-1", @pulse && "status-critical-pulse", @class]}>
      <.severity_dot severity={@severity} />
      <span class={["text-xs font-bold", @text_class]}>{@count}</span>
    </div>
    """
  end

  # =============================================================================
  # Telemetry Display Components
  # =============================================================================

  @doc """
  Renders a limits state badge.

  Maps telemetry limits states to appropriate badge variants.

  ## Examples

      <.limits_badge state="green" />
      <.limits_badge state="yellow_high" />
      <.limits_badge state={:red} />
  """
  attr :state, :any, required: true, doc: "Limits state from telemetry"
  attr :size, :string, default: "sm", values: ~w(xs sm md)
  attr :class, :string, default: nil

  def limits_badge(assigns) do
    state = to_string(assigns.state)

    {badge_class, label} =
      case state do
        "green" -> {"badge-success", "Normal"}
        "yellow" -> {"badge-warning", "Warning"}
        "yellow_low" -> {"badge-warning", "Low Warning"}
        "yellow_high" -> {"badge-warning", "High Warning"}
        "red" -> {"badge-error", "Critical"}
        "red_low" -> {"badge-error", "Low Critical"}
        "red_high" -> {"badge-error", "High Critical"}
        "blue" -> {"badge-info", "Stale"}
        _ -> {"badge-neutral", "Unknown"}
      end

    size_class =
      case assigns.size do
        "xs" -> "badge-xs"
        "sm" -> "badge-sm"
        "md" -> ""
      end

    assigns =
      assigns
      |> assign(:badge_class, badge_class)
      |> assign(:size_class, size_class)
      |> assign(:label, label)

    ~H"""
    <span class={["badge", @badge_class, @size_class, @class]}>{@label}</span>
    """
  end

  @doc """
  Renders a trend indicator arrow.

  Shows directional trend of a value (up, down, or stable).

  ## Examples

      <.trend_indicator trend={:up} />
      <.trend_indicator trend="down" />
      <.trend_indicator trend={nil} />
  """
  attr :trend, :any, default: nil, doc: ":up, :down, :stable, or nil"
  attr :class, :string, default: nil

  def trend_indicator(assigns) do
    trend = normalize_trend(assigns.trend)

    {icon, color_class} =
      case trend do
        :up -> {"↑", "text-success"}
        :down -> {"↓", "text-error"}
        :stable -> {"•", "text-base-content/40"}
        _ -> {nil, nil}
      end

    assigns =
      assigns
      |> assign(:icon, icon)
      |> assign(:color_class, color_class)

    ~H"""
    <span :if={@icon} class={["text-lg", @color_class, @class]}>{@icon}</span>
    """
  end

  @doc """
  Renders a telemetry value display with formatting.

  Shows value with optional unit, limits coloring, and trend.

  ## Examples

      <.telemetry_value value={123.45} unit="km/s" limits_state="green" trend={:up} />
      <.telemetry_value value={nil} placeholder="--" />
  """
  attr :value, :any, default: nil
  attr :unit, :string, default: nil
  attr :limits_state, :any, default: nil
  attr :trend, :any, default: nil
  attr :precision, :integer, default: 2
  attr :placeholder, :string, default: "--"
  attr :size, :string, default: "lg", values: ~w(sm md lg xl)
  attr :class, :string, default: nil

  def telemetry_value(assigns) do
    formatted_value = format_telemetry_value(assigns.value, assigns.precision, assigns.placeholder)

    limits_color =
      case to_string(assigns.limits_state) do
        "green" -> "text-success"
        s when s in ~w(yellow yellow_low yellow_high) -> "text-warning"
        s when s in ~w(red red_low red_high) -> "text-error"
        "blue" -> "text-info"
        _ -> ""
      end

    size_class =
      case assigns.size do
        "sm" -> "text-lg"
        "md" -> "text-2xl"
        "lg" -> "text-4xl"
        "xl" -> "text-5xl"
      end

    assigns =
      assigns
      |> assign(:formatted_value, formatted_value)
      |> assign(:limits_color, limits_color)
      |> assign(:size_class, size_class)

    ~H"""
    <div class={["flex items-baseline gap-2", @class]}>
      <span class={["font-mono font-bold", @size_class, @limits_color]}>
        {@formatted_value}
      </span>
      <span :if={@unit} class="text-lg text-base-content/70">{@unit}</span>
      <.trend_indicator :if={@trend} trend={@trend} />
    </div>
    """
  end

  # =============================================================================
  # Action Components
  # =============================================================================

  @doc """
  Renders a small action button for widgets.

  Consistent styling for alarm actions, command buttons, etc.

  ## Variants

  - `default` - Cyan/primary colored
  - `success` - Green, used for acknowledge
  - `danger` - Red, used for clear/delete
  - `ghost` - Minimal styling

  ## Examples

      <.widget_action_btn phx-click="acknowledge" variant="success">ACK</.widget_action_btn>
      <.widget_action_btn phx-click="clear" variant="danger">CLEAR</.widget_action_btn>
  """
  attr :variant, :string, default: "default", values: ~w(default success danger ghost)
  attr :disabled, :boolean, default: false
  attr :class, :string, default: nil
  attr :rest, :global, include: ~w(phx-click phx-value-id title)
  slot :inner_block, required: true

  def widget_action_btn(assigns) do
    variant_class =
      case assigns.variant do
        "success" -> "alarm-btn-ack"
        "danger" -> "alarm-btn-clear"
        "ghost" -> "alarm-btn-ghost"
        _ -> ""
      end

    assigns = assign(assigns, :variant_class, variant_class)

    ~H"""
    <button
      type="button"
      class={["alarm-btn", @variant_class, @disabled && "opacity-50 cursor-not-allowed", @class]}
      disabled={@disabled}
      {@rest}
    >
      {render_slot(@inner_block)}
    </button>
    """
  end

  @doc """
  Renders a command execution button with status styling.

  Used by CommandWidget for the main action button.

  ## Examples

      <.command_btn status={:idle} hazardous={false}>EXECUTE</.command_btn>
      <.command_btn status={:pending} hazardous={true}>ABORT</.command_btn>
  """
  attr :status, :atom,
    default: :idle,
    values: [:idle, :confirming, :pending, :sent, :verified, :failed]

  attr :hazardous, :boolean, default: false
  attr :disabled, :boolean, default: false
  attr :class, :string, default: nil
  attr :rest, :global, include: ~w(phx-click id)
  slot :inner_block, required: true

  def command_btn(assigns) do
    button_class =
      cond do
        assigns.hazardous -> "btn-error"
        assigns.status == :pending -> "btn-info"
        true -> "btn-primary"
      end

    assigns = assign(assigns, :button_class, button_class)

    ~H"""
    <button
      type="button"
      class={[
        "command-btn btn btn-lg w-full max-w-48",
        @button_class,
        @disabled && "btn-disabled",
        @class
      ]}
      disabled={@disabled || @status == :pending}
      {@rest}
    >
      <span :if={@status == :pending} class="loading loading-spinner loading-sm"></span>
      <span :if={@status == :confirming} class="text-warning">CONFIRM?</span>
      <span :if={@status not in [:pending, :confirming]}>{render_slot(@inner_block)}</span>
    </button>
    """
  end

  # =============================================================================
  # Alarm Components
  # =============================================================================

  @doc """
  Renders an alarm item with severity styling and actions.

  ## Examples

      <.alarm_item
        alarm={%{id: "1", severity: :critical, message: "High temp", triggered_at: ~U[...]}}
        acknowledged={false}
        on_acknowledge={JS.push("ack_alarm")}
        on_clear={JS.push("clear_alarm")}
      />
  """
  attr :alarm, :map, required: true
  attr :acknowledged, :boolean, default: false
  attr :new, :boolean, default: false, doc: "show new alarm animation"
  attr :on_acknowledge, JS, default: nil
  attr :on_shelve, JS, default: nil
  attr :on_clear, JS, default: nil
  attr :on_details, JS, default: nil
  attr :class, :string, default: nil

  def alarm_item(assigns) do
    severity = normalize_severity(assigns.alarm[:severity] || :info)

    severity_class =
      case severity do
        :critical -> "alarm-item-critical"
        :warning -> "alarm-item-warning"
        _ -> "alarm-item-info"
      end

    assigns =
      assigns
      |> assign(:severity, severity)
      |> assign(:severity_class, severity_class)

    ~H"""
    <div class={[
      "alarm-item",
      @severity_class,
      @new && "alarm-new",
      @acknowledged && "opacity-60",
      @class
    ]}>
      <div class="alarm-item-header flex items-start justify-between gap-2">
        <div class="flex items-center gap-2 min-w-0 flex-1">
          <.severity_dot severity={@severity} />
          <span class="alarm-source text-xs font-medium truncate">
            {@alarm[:target_name] || "Unknown"}
          </span>
        </div>
        <span class="alarm-time text-xs text-base-content/40 flex-shrink-0">
          {format_time(@alarm[:triggered_at])}
        </span>
      </div>

      <div class={["alarm-message text-sm mt-1", @severity == :critical && "font-medium"]}>
        {@alarm[:message] || @alarm[:name] || "Alarm"}
      </div>

      <div class="alarm-actions flex items-center gap-1 mt-2">
        <.widget_action_btn
          :if={@on_acknowledge && !@acknowledged}
          variant="success"
          phx-click={@on_acknowledge}
          phx-value-id={@alarm[:id]}
        >
          ACK
        </.widget_action_btn>
        <span :if={@acknowledged} class="text-xs text-base-content/40">Acknowledged</span>

        <.widget_action_btn :if={@on_shelve} phx-click={@on_shelve} phx-value-id={@alarm[:id]}>
          SHELVE
        </.widget_action_btn>

        <.widget_action_btn
          :if={@on_clear}
          variant="danger"
          phx-click={@on_clear}
          phx-value-id={@alarm[:id]}
        >
          CLEAR
        </.widget_action_btn>

        <.widget_action_btn
          :if={@on_details}
          class="ml-auto"
          phx-click={@on_details}
          phx-value-id={@alarm[:id]}
        >
          <.icon name="hero-information-circle" class="w-3 h-3" />
        </.widget_action_btn>
      </div>
    </div>
    """
  end

  @doc """
  Renders an alarm summary header with severity counts.

  ## Examples

      <.alarm_summary critical={3} warning={5} info={2} />
      <.alarm_summary critical={0} warning={0} info={0} />
  """
  attr :critical, :integer, default: 0
  attr :warning, :integer, default: 0
  attr :info, :integer, default: 0
  attr :on_acknowledge_all, JS, default: nil
  attr :class, :string, default: nil

  def alarm_summary(assigns) do
    all_clear = assigns.critical == 0 && assigns.warning == 0 && assigns.info == 0
    assigns = assign(assigns, :all_clear, all_clear)

    ~H"""
    <div class={["alarm-summary flex items-center justify-between", @class]}>
      <div class="flex items-center gap-3">
        <.severity_count severity={:critical} count={@critical} pulse={@critical > 0} />
        <.severity_count severity={:warning} count={@warning} />
        <.severity_count severity={:info} count={@info} />
        <.status_indicator :if={@all_clear} status={:nominal} label="All clear" />
      </div>
      <button
        :if={@on_acknowledge_all && !@all_clear}
        type="button"
        class="btn btn-ghost btn-xs"
        phx-click={@on_acknowledge_all}
        title="Acknowledge All"
      >
        <.icon name="hero-check" class="w-3 h-3" />
      </button>
    </div>
    """
  end

  # =============================================================================
  # Empty State
  # =============================================================================

  @doc """
  Renders an empty state placeholder for widgets.

  ## Examples

      <.widget_empty icon="hero-bell-slash" message="No alarms" />
      <.widget_empty icon="hero-chart-bar" message="No data available" />
  """
  attr :icon, :string, default: "hero-inbox"
  attr :message, :string, default: "No items"
  attr :class, :string, default: nil

  def widget_empty(assigns) do
    ~H"""
    <div class={["text-center py-8 text-base-content/40", @class]}>
      <.icon name={@icon} class="w-8 h-8 mx-auto mb-2 opacity-50" />
      <p class="text-xs">{@message}</p>
    </div>
    """
  end

  # =============================================================================
  # Icons (delegating to CoreComponents pattern)
  # =============================================================================

  attr :name, :string, required: true
  attr :class, :string, default: "size-4"

  defp icon(%{name: "hero-" <> _} = assigns) do
    ~H"""
    <span class={[@name, @class]} />
    """
  end

  # =============================================================================
  # Private Helpers
  # =============================================================================

  defp normalize_severity(severity) when is_atom(severity), do: severity

  defp normalize_severity(severity) when is_binary(severity) do
    case severity do
      "critical" -> :critical
      "warning" -> :warning
      "info" -> :info
      "nominal" -> :nominal
      "success" -> :nominal
      "pending" -> :pending
      "idle" -> :idle
      "sent" -> :nominal
      "verified" -> :nominal
      "failed" -> :critical
      _ -> :unknown
    end
  end

  defp normalize_severity(_), do: :unknown

  defp normalize_trend(trend) when is_atom(trend), do: trend

  defp normalize_trend(trend) when is_binary(trend) do
    case trend do
      "up" -> :up
      "down" -> :down
      "stable" -> :stable
      _ -> nil
    end
  end

  defp normalize_trend(_), do: nil

  defp format_telemetry_value(nil, _precision, placeholder), do: placeholder
  defp format_telemetry_value(value, _precision, _placeholder) when is_binary(value), do: value

  defp format_telemetry_value(value, precision, _placeholder) when is_number(value) do
    if value == trunc(value) do
      Integer.to_string(trunc(value))
    else
      :erlang.float_to_binary(value * 1.0, decimals: precision)
    end
  end

  defp format_telemetry_value(value, _precision, _placeholder), do: inspect(value)

  defp format_time(nil), do: "--:--"

  defp format_time(%DateTime{} = dt) do
    Calendar.strftime(dt, "%H:%M:%S")
  end

  defp format_time(%NaiveDateTime{} = dt) do
    Calendar.strftime(dt, "%H:%M:%S")
  end

  defp format_time(timestamp) when is_binary(timestamp) do
    case DateTime.from_iso8601(timestamp) do
      {:ok, dt, _} -> format_time(dt)
      _ -> timestamp
    end
  end

  defp format_time(_), do: "--:--"
end
