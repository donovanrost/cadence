defmodule CadenceWeb.OpsDashboardShowLive.DashboardTimePickerComponents do
  @moduledoc """
  Grafana-style dashboard time range picker.

  Toolbar cluster: shift back / picker popover / shift forward / zoom out /
  (inactive) refresh interval. The popover pairs an absolute From/To form and
  recently used ranges with a searchable quick-range list; quick ranges keep
  the dashboard live with a sliding window, absolute bounds freeze it into
  archive mode.
  """
  use CadenceWeb, :html

  alias Cadence.Dashboards.TimeRange
  alias CadenceWeb.OpsDashboardShowLive.DashboardTimeReplayComponents

  attr :time_mode, :string, required: true
  attr :time_axis, :string, default: "generation_time"
  attr :time_from, :string, default: nil
  attr :time_to, :string, default: nil
  attr :replay_run_id, :string, default: nil
  attr :time_validation, :string, default: "ok"
  attr :data_realm, :string, required: true
  attr :data_view, :string, required: true
  attr :compare_data_view, :string, default: nil
  attr :source_binding_id, :string, default: nil
  attr :limit_mode, :string, required: true
  attr :replay_runs, :list, default: []
  attr :selected_replay_run, :any, default: nil
  attr :selected_data_ref, :any, default: nil
  attr :quick_query, :string, default: ""
  attr :recent_ranges, :list, default: []

  def time_toolbar_cluster(assigns) do
    assigns =
      assigns
      |> assign(:time_query_label, time_query_label(assigns))
      |> assign(:range_bounded?, range_bounded?(assigns))

    ~H"""
    <.shift_button id="dashboard-time-shift-back" direction="back" disabled={not @range_bounded?} />
    <.popover
      id="dashboard-time-controls"
      trigger_id="dashboard-time-controls-toggle"
      panel_id="dashboard-time-controls-panel"
      label="Dashboard time range"
      placement={:bottom_end}
      width={:lg}
      trigger_class="cadence-dashboard-query-trigger"
      data-query-state={@time_mode}
    >
      <:trigger>
        <span class="cadence-dashboard-query-dot"></span>
        <span
          id="dashboard-active-time-range"
          class="cadence-dashboard-query-trigger-value max-w-48"
          data-dashboard-time-mode={@time_mode}
          data-dashboard-time-summary={@time_mode}
        >
          {@time_query_label}
        </span>
        <.icon name="hero-chevron-down" class="h-3 w-3 shrink-0 text-base-content/40" />
      </:trigger>
      <div class="cadence-dashboard-query-panel-header">
        <.icon name="hero-clock" class="mt-0.5 h-4 w-4 text-primary" />
        <div>
          <p class="text-xs font-semibold text-base-content/85">Dashboard time</p>
          <p class="mt-0.5 text-[0.68rem] text-base-content/50">
            Follow live telemetry, inspect history, or select a replay run.
          </p>
        </div>
      </div>
      <div class="cadence-dashboard-query-panel-body">
        <div id="dashboard-time-query-controls" data-dashboard-query-control-section="time" class="min-w-0">
          <.time_picker_panel
            time_mode={@time_mode}
            time_from={@time_from}
            time_to={@time_to}
            time_validation={@time_validation}
            quick_query={@quick_query}
            recent_ranges={@recent_ranges}
          />
          <DashboardTimeReplayComponents.replay_section
            time_mode={@time_mode}
            time_axis={@time_axis}
            time_from={@time_from}
            time_to={@time_to}
            replay_run_id={@replay_run_id}
            data_realm={@data_realm}
            data_view={@data_view}
            compare_data_view={@compare_data_view}
            source_binding_id={@source_binding_id}
            limit_mode={@limit_mode}
            replay_runs={@replay_runs}
            selected_replay_run={@selected_replay_run}
          />
          <DashboardTimeReplayComponents.selected_datum_section
            time_mode={@time_mode}
            replay_run_id={@replay_run_id}
            selected_data_ref={@selected_data_ref}
          />
        </div>
      </div>
    </.popover>
    <.shift_button id="dashboard-time-shift-forward" direction="forward" disabled={not @range_bounded?} />
    <.button
      id="dashboard-time-zoom-out"
      variant={:ghost}
      size={:xs}
      phx-click="zoom_out_time_range"
      disabled={not @range_bounded?}
      aria-label="Zoom out time range"
      title="Zoom out time range"
    >
      <.icon name="hero-magnifying-glass-minus" class="h-3.5 w-3.5" />
    </.button>
    <span title="Auto-refresh interval selection coming soon. Live dashboards stream continuously.">
      <.input
        id="dashboard-refresh-interval"
        name="refresh_interval"
        type="select"
        value=""
        options={refresh_interval_options()}
        disabled
        compact
        class="select-xs"
        aria-label="Auto-refresh interval (coming soon)"
        data-dashboard-refresh-interval-inactive="true"
      />
    </span>
    """
  end

  attr :id, :string, required: true
  attr :direction, :string, required: true
  attr :disabled, :boolean, required: true

  defp shift_button(assigns) do
    assigns = assign(assigns, :label, "Move time range #{assigns.direction}wards")

    ~H"""
    <.button
      id={@id}
      variant={:ghost}
      size={:xs}
      phx-click="shift_time_range"
      phx-value-direction={@direction}
      disabled={@disabled}
      aria-label={@label}
      title={@label}
    >
      <.icon
        name={if @direction == "back", do: "hero-chevron-left", else: "hero-chevron-right"}
        class="h-3.5 w-3.5"
      />
    </.button>
    """
  end

  attr :time_mode, :string, required: true
  attr :time_from, :string, default: nil
  attr :time_to, :string, default: nil
  attr :time_validation, :string, default: "ok"
  attr :quick_query, :string, default: ""
  attr :recent_ranges, :list, default: []

  defp time_picker_panel(assigns) do
    ~H"""
    <div class="flex gap-3">
      <.absolute_range_pane
        time_from={@time_from}
        time_to={@time_to}
        time_validation={@time_validation}
        recent_ranges={@recent_ranges}
      />
      <.quick_range_list
        time_mode={@time_mode}
        time_from={@time_from}
        time_to={@time_to}
        quick_query={@quick_query}
      />
    </div>
    """
  end

  attr :time_from, :string, default: nil
  attr :time_to, :string, default: nil
  attr :time_validation, :string, default: "ok"
  attr :recent_ranges, :list, default: []

  defp absolute_range_pane(assigns) do
    assigns =
      assign(
        assigns,
        :range_form,
        to_form(%{"from" => assigns.time_from || "", "to" => assigns.time_to || ""})
      )

    ~H"""
    <div class="min-w-0 flex-1">
      <p id="dashboard-range-heading" class="text-xs font-semibold text-base-content/85">
        Absolute time range
      </p>
      <.form
        for={@range_form}
        id="dashboard-custom-range-form"
        phx-submit="set_chart_time_range"
        class="mt-2"
      >
        <.input
          field={@range_form[:from]}
          id="dashboard-time-from"
          type="text"
          label="From"
          placeholder="now-6h or 2026-08-01T16:30:00Z"
          compact
          class="input-xs font-mono"
        />
        <div class="mt-2">
          <.input
            field={@range_form[:to]}
            id="dashboard-time-to"
            type="text"
            label="To"
            placeholder="now"
            compact
            class="input-xs font-mono"
          />
        </div>
        <.button id="dashboard-apply-time-range" type="submit" variant={:primary} size={:xs} class="mt-2">
          Apply time range
        </.button>
      </.form>
      <span
        :if={@time_validation != "ok"}
        id="dashboard-time-validation"
        data-time-validation={@time_validation}
        class="badge badge-warning badge-xs mt-2"
      >
        Time reset
      </span>
      <.recent_ranges_section recent_ranges={@recent_ranges} />
    </div>
    """
  end

  attr :recent_ranges, :list, default: []

  defp recent_ranges_section(assigns) do
    ~H"""
    <div id="dashboard-time-recents" phx-hook="TimeRangeRecents" class="mt-3 border-t border-base-300/60 pt-2">
      <p class="text-xs font-semibold text-base-content/85">Recently used absolute ranges</p>
      <p :if={@recent_ranges == []} class="mt-1 text-[0.68rem] text-base-content/60">
        Apply an absolute range and it will appear here for quick reuse.
      </p>
      <ul :if={@recent_ranges != []} class="mt-1" role="presentation">
        <li :for={range <- @recent_ranges}>
          <button
            type="button"
            phx-click="set_chart_time_range"
            phx-value-from={range.from}
            phx-value-to={range.to}
            data-dashboard-time-recent-range
            class="w-full truncate px-1 py-0.5 text-left font-mono text-[0.68rem] text-base-content/70 hover:bg-base-300/40 hover:text-base-content"
            title={"Apply #{range.from} to #{range.to}"}
          >
            {TimeRange.label(range.from, range.to) || "#{range.from} to #{range.to}"}
          </button>
        </li>
      </ul>
    </div>
    """
  end

  attr :time_mode, :string, required: true
  attr :time_from, :string, default: nil
  attr :time_to, :string, default: nil
  attr :quick_query, :string, default: ""

  defp quick_range_list(assigns) do
    assigns =
      assigns
      |> assign(:search_form, to_form(%{"query" => assigns.quick_query}))
      |> assign(:visible_ranges, filter_quick_ranges(assigns.quick_query))
      |> assign(:live_selected?, assigns.time_mode == "live" and is_nil(assigns.time_from))
      |> assign(:live_visible?, quick_match?("Live", assigns.quick_query))

    ~H"""
    <div class="w-44 shrink-0 border-l border-base-300/60 pl-3">
      <.form
        for={@search_form}
        id="dashboard-time-quick-search-form"
        phx-change="time_quick_search"
        onsubmit="return false"
      >
        <.input
          field={@search_form[:query]}
          id="dashboard-time-quick-search"
          type="search"
          placeholder="Search quick ranges"
          compact
          phx-debounce="150"
        />
      </.form>
      <ul
        id="dashboard-time-presets"
        role="presentation"
        aria-label="Quick time ranges"
        class="mt-2 max-h-56 overflow-y-auto"
      >
        <li :if={@live_visible?}>
          <.quick_range_button
            id="dashboard-time-preset-live"
            preset="live"
            label="Live"
            selected?={@live_selected?}
            disabled={@live_selected?}
            title="Return to live dashboard time"
          />
        </li>
        <li :for={range <- @visible_ranges}>
          <.quick_range_button
            id={"dashboard-time-preset-#{String.replace(range.key, "_", "-")}"}
            preset={range.key}
            label={range.label}
            selected?={quick_range_selected?(range, @time_mode, @time_from, @time_to)}
            disabled={false}
            title={"Follow the #{String.downcase(range.label)} as a sliding window"}
          />
        </li>
      </ul>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :preset, :string, required: true
  attr :label, :string, required: true
  attr :selected?, :boolean, required: true
  attr :disabled, :boolean, required: true
  attr :title, :string, required: true

  defp quick_range_button(assigns) do
    ~H"""
    <button
      id={@id}
      type="button"
      phx-click="set_time_preset"
      phx-value-preset={@preset}
      disabled={@disabled}
      aria-current={to_string(@selected?)}
      title={@title}
      class={[
        "flex w-full items-center gap-1.5 px-2 py-1 text-left text-xs",
        if(@selected?,
          do: "bg-primary/10 font-semibold text-primary",
          else: "text-base-content/80 hover:bg-base-300/40 hover:text-base-content"
        )
      ]}
    >
      <span :if={@preset == "live"} class="h-1.5 w-1.5 rounded-full bg-success"></span>
      {@label}
    </button>
    """
  end

  def time_query_label(%{time_mode: "live"} = assigns) do
    TimeRange.label(assigns.time_from, assigns.time_to) || "Live"
  end

  def time_query_label(%{time_mode: "replay_run"} = assigns) do
    case assigns.replay_run_id do
      value when is_binary(value) and value != "" -> "Replay · #{value}"
      _missing -> "Replay"
    end
  end

  def time_query_label(assigns) do
    case {short_timestamp(assigns.time_from), short_timestamp(assigns.time_to)} do
      {nil, nil} -> "Selected historical range"
      {from_text, to_text} -> "#{from_text || "…"} → #{to_text || "…"}"
    end
  end

  defp short_timestamp(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, timestamp, _offset} -> Calendar.strftime(timestamp, "%b %-d %H:%M UTC")
      _invalid -> value
    end
  end

  defp short_timestamp(_value), do: nil

  defp range_bounded?(assigns) do
    assigns.time_mode in ["live", "archive"] and
      match?(
        {:ok, _resolution},
        TimeRange.resolve(assigns.time_from, assigns.time_to, DateTime.utc_now())
      )
  end

  defp quick_range_selected?(range, "live", time_from, time_to),
    do: range.from == time_from and range.to == time_to

  defp quick_range_selected?(_range, _mode, _from, _to), do: false

  defp filter_quick_ranges(query) do
    Enum.filter(TimeRange.quick_ranges(), &quick_match?(&1.label, query))
  end

  defp refresh_interval_options,
    do: [{"Off", ""}, {"5s", "5s"}, {"10s", "10s"}, {"30s", "30s"}, {"1m", "1m"}]

  defp quick_match?(_label, query) when query in [nil, ""], do: true

  defp quick_match?(label, query) do
    haystack = String.downcase(label)

    query
    |> String.downcase()
    |> String.split(~r/\s+/, trim: true)
    |> Enum.all?(&String.contains?(haystack, &1))
  end
end
