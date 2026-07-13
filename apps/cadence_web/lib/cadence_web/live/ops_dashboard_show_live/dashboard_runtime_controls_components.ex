defmodule CadenceWeb.OpsDashboardShowLive.DashboardRuntimeControlsComponents do
  @moduledoc false
  use CadenceWeb, :html

  alias Cadence.Dashboards.DataBinding
  alias CadenceWeb.OpsDashboardShowLive.SelectedDataRef

  attr :time_mode, :string, required: true
  attr :time_axis, :string, default: "generation_time"
  attr :time_from, :string, default: nil
  attr :time_to, :string, default: nil
  attr :replay_run_id, :string, default: nil
  attr :time_validation, :string, default: "ok"
  attr :data_realm, :string, required: true
  attr :data_realms, :list, required: true
  attr :data_view, :string, required: true
  attr :compare_data_view, :string, default: nil
  attr :data_source_id, :string, default: nil
  attr :source_binding_id, :string, default: nil
  attr :data_bindings, :list, required: true
  attr :replay_runs, :list, default: []
  attr :selected_replay_run, :any, default: nil
  attr :limit_mode, :string, required: true
  attr :limit_mode_fallback, :map, default: nil
  attr :selected_data_ref, :any, default: nil

  def runtime_context_controls(assigns) do
    ~H"""
    <div id="runtime-context-controls" class="flex flex-wrap items-center gap-1">
      <form
        id="runtime-context-form"
        phx-change="set_runtime_context"
        class="flex flex-wrap items-center gap-1"
      >
        <input
          :if={@time_mode != "replay_run"}
          id="dashboard-replay-run-id"
          type="hidden"
          name="replay_run_id"
          value={@replay_run_id || ""}
        />
        <.input
          id="dashboard-time-mode"
          name="time_mode"
          type="select"
          value={@time_mode}
          options={[{"Live", "live"}, {"Archive", "archive"}, {"Replay", "replay_run"}]}
          compact
          class="select-xs w-24"
        />
        <.input
          id="dashboard-time-axis"
          name="time_axis"
          type="select"
          value={@time_axis}
          options={time_axis_options()}
          compact
          class="select-xs w-36"
        />
        <.input
          id="dashboard-time-from"
          name="from"
          type="text"
          value={@time_from}
          placeholder="From UTC"
          compact
          class="input-xs w-36 font-mono"
        />
        <.input
          id="dashboard-time-to"
          name="to"
          type="text"
          value={@time_to}
          placeholder="To UTC"
          compact
          class="input-xs w-36 font-mono"
        />
        <.input
          :if={@time_mode == "replay_run"}
          id="dashboard-replay-run-selector"
          name="replay_run_id"
          type="select"
          value={@replay_run_id || ""}
          options={replay_run_options(@replay_runs, @replay_run_id)}
          compact
          class="select-xs w-44 font-mono"
        />
        <.input
          id="dashboard-data-realm"
          name="realm"
          type="select"
          value={@data_realm}
          options={realm_options(@data_realms)}
          compact
          class="select-xs w-28"
        />
        <.input
          id="dashboard-source-binding"
          name="source_binding_id"
          type="select"
          value={@source_binding_id || ""}
          options={source_binding_options(@data_bindings, @data_realm)}
          compact
          class="select-xs w-52 font-mono"
        />
        <.input
          id="dashboard-data-view"
          name="data_view"
          type="select"
          value={@data_view}
          options={data_view_options()}
          compact
          class="select-xs w-32"
        />
        <.input
          id="dashboard-compare-data-view"
          name="compare_data_view"
          type="select"
          value={@compare_data_view || ""}
          options={compare_data_view_options(@data_view)}
          compact
          class="select-xs w-36"
        />
        <.input
          id="dashboard-limit-mode"
          name="limit_mode"
          type="select"
          value={@limit_mode}
          options={limit_mode_options()}
          compact
          class="select-xs w-32"
        />
        <span
          :if={limit_mode_fallback?(@limit_mode_fallback)}
          id="dashboard-limit-mode-fallback"
          data-requested-limit-mode={limit_mode_fallback_value(@limit_mode_fallback, "requested_mode")}
          data-applied-limit-mode={limit_mode_fallback_value(@limit_mode_fallback, "applied_mode")}
          data-limit-mode-fallback-reason={limit_mode_fallback_value(@limit_mode_fallback, "reason")}
          class="badge badge-warning badge-xs gap-1"
          title={limit_mode_fallback_title(@limit_mode_fallback)}
        >
          <.icon name="hero-exclamation-triangle" class="h-3 w-3" /> Observed only
        </span>
      </form>
      <span
        id="dashboard-active-source"
        data-dashboard-active-data-source={@data_source_id}
        data-dashboard-active-source-binding={@source_binding_id}
        class={[
          "badge badge-xs max-w-64 truncate font-mono",
          if(@source_binding_id, do: "badge-primary badge-outline", else: "badge-ghost")
        ]}
        title={source_context_label(@data_source_id, @source_binding_id)}
      >
        {source_context_label(@data_source_id, @source_binding_id)}
      </span>
      <span
        :if={@time_mode == "replay_run"}
        id="dashboard-replay-progress-clock"
        data-dashboard-replay-run-id={@replay_run_id || ""}
        data-dashboard-replay-run-known={replay_run_known_text(@selected_replay_run)}
        data-dashboard-replay-run-status={replay_run_attr(@selected_replay_run, :status)}
        data-dashboard-replay-run-started-at={replay_run_datetime(@selected_replay_run, :started_at)}
        data-dashboard-replay-run-completed-at={
          replay_run_datetime(@selected_replay_run, :completed_at)
        }
        data-dashboard-replay-run-sample-count={
          replay_run_integer(@selected_replay_run, :replayed_sample_count)
        }
        data-dashboard-replay-window-from={@time_from || ""}
        data-dashboard-replay-window-to={@time_to || ""}
        data-dashboard-replay-window-bounded={replay_window_bounded_text(@time_from, @time_to)}
        class="badge badge-info badge-outline badge-xs max-w-80 truncate font-mono"
        title={replay_clock_title(@selected_replay_run, @replay_run_id, @time_from, @time_to)}
      >
        <.icon name="hero-forward" class="h-3 w-3" />
        {replay_clock_label(@selected_replay_run, @replay_run_id, @time_from, @time_to)}
      </span>
      <span
        :if={@time_mode == "replay_run" and present_text?(@replay_run_id) and is_nil(@selected_replay_run)}
        id="dashboard-replay-metadata-warning"
        data-dashboard-replay-run-id={@replay_run_id}
        class="badge badge-warning badge-xs max-w-64 truncate font-mono"
        title="This replay run is not present in the persisted mission replay-run inventory."
      >
        <.icon name="hero-exclamation-triangle" class="h-3 w-3" /> Unlisted replay
      </span>
      <div id="dashboard-time-presets" class="join">
        <button
          id="dashboard-time-preset-live"
          type="button"
          class={["btn btn-xs join-item", if(@time_mode == "live", do: "btn-secondary", else: "btn-ghost")]}
          phx-click="set_time_preset"
          phx-value-preset="live"
          disabled={@time_mode == "live"}
          title="Return to live dashboard time"
        >
          <.icon name="hero-play" class="h-3.5 w-3.5" /> Live
        </button>
        <button
          id="dashboard-time-preset-last-5m"
          type="button"
          class="btn btn-xs join-item btn-ghost"
          phx-click="set_time_preset"
          phx-value-preset="last_5m"
          title="Show the last five minutes as a snapshot"
        >
          5m
        </button>
        <button
          id="dashboard-time-preset-last-15m"
          type="button"
          class="btn btn-xs join-item btn-ghost"
          phx-click="set_time_preset"
          phx-value-preset="last_15m"
          title="Show the last fifteen minutes as a snapshot"
        >
          15m
        </button>
        <button
          id="dashboard-time-preset-last-1h"
          type="button"
          class="btn btn-xs join-item btn-ghost"
          phx-click="set_time_preset"
          phx-value-preset="last_1h"
          title="Show the last hour as a snapshot"
        >
          1h
        </button>
      </div>
      <span
        :if={@time_validation != "ok"}
        id="dashboard-time-validation"
        data-time-validation={@time_validation}
        class="badge badge-warning badge-xs"
      >
        Time reset
      </span>
      <.button
        id="dashboard-resume-live"
        variant={if @time_mode == "live", do: :secondary, else: :ghost}
        size={:xs}
        phx-click="resume_live"
        disabled={@time_mode == "live"}
        title="Return to live dashboard time"
      >
        <.icon name="hero-play" class="h-3.5 w-3.5" /> Live
      </.button>
      <.button
        id="dashboard-pause-at-selection"
        variant={:ghost}
        size={:xs}
        phx-click="pause_at_selected_time"
        disabled={not selected_timestamp?(@selected_data_ref)}
        title="Pause dashboard time around the selected datum"
      >
        <.icon name="hero-pause" class="h-3.5 w-3.5" /> Pause
      </.button>
      <.button
        :if={@time_mode == "replay_run"}
        id="dashboard-replay-scrub-to-selection"
        variant={:ghost}
        size={:xs}
        phx-click="scrub_replay_to_selection"
        disabled={not replay_scrub_available?(@replay_run_id, @selected_data_ref)}
        data-dashboard-replay-scrub-available={
          replay_scrub_available_text(@replay_run_id, @selected_data_ref)
        }
        title="Move replay time around the selected datum"
      >
        <.icon name="hero-arrows-right-left" class="h-3.5 w-3.5" /> Scrub
      </.button>
      <.button
        id="dashboard-clear-selection"
        variant={:ghost}
        size={:xs}
        phx-click="clear_data_selection"
        disabled={not SelectedDataRef.present?(@selected_data_ref)}
        title="Clear the selected dashboard datum"
      >
        <.icon name="hero-x-mark" class="h-3.5 w-3.5" /> Clear
      </.button>
    </div>
    """
  end

  defp selected_timestamp?(selected_data_ref),
    do: match?({:ok, _from_iso, _to_iso}, SelectedDataRef.archive_range(selected_data_ref))

  defp replay_clock_label(selected_replay_run, replay_run_id, from, to) do
    run_label = replay_run_label(selected_replay_run, replay_run_id)

    if replay_window_bounded?(from, to) do
      "#{run_label} / #{from} -> #{to}"
    else
      "#{run_label} / full run"
    end
  end

  defp replay_clock_title(selected_replay_run, replay_run_id, from, to) do
    run_label = replay_run_title(selected_replay_run, replay_run_id)

    if replay_window_bounded?(from, to) do
      "Replay #{run_label}, generation window #{from} to #{to}"
    else
      "Replay #{run_label}, full available run"
    end
  end

  defp replay_run_options(replay_runs, replay_run_id) do
    current_id = present_text(replay_run_id)

    options =
      replay_runs
      |> Enum.sort_by(&replay_run_sort_key/1)
      |> Enum.map(fn replay_run ->
        {replay_run_option_label(replay_run), replay_run_attr(replay_run, :replay_run_id)}
      end)

    options =
      if current_id && not Enum.any?(options, fn {_label, id} -> id == current_id end) do
        [{"Unlisted replay / #{current_id}", current_id} | options]
      else
        options
      end

    [{"Select replay run", ""} | options]
  end

  defp replay_run_option_label(replay_run) do
    replay_run
    |> replay_run_label(replay_run_attr(replay_run, :replay_run_id))
    |> then(fn label ->
      case replay_run_integer(replay_run, :replayed_sample_count) do
        "" -> label
        count -> "#{label} / #{count} samples"
      end
    end)
  end

  defp replay_run_label(nil, replay_run_id),
    do: present_text(replay_run_id) || "unselected replay"

  defp replay_run_label(replay_run, replay_run_id) do
    status = replay_run_attr(replay_run, :status)

    run_id =
      present_text(replay_run_attr(replay_run, :replay_run_id)) || present_text(replay_run_id)

    [status, run_id]
    |> Enum.filter(&present_text?/1)
    |> case do
      [] -> "unselected replay"
      parts -> Enum.join(parts, " ")
    end
  end

  defp replay_run_title(nil, replay_run_id) do
    present_text(replay_run_id) || "No replay run selected"
  end

  defp replay_run_title(replay_run, replay_run_id) do
    label = replay_run_label(replay_run, replay_run_id)
    started_at = replay_run_datetime(replay_run, :started_at)
    completed_at = replay_run_datetime(replay_run, :completed_at)

    cond do
      present_text?(started_at) and present_text?(completed_at) ->
        "#{label}, started #{started_at}, completed #{completed_at}"

      present_text?(started_at) ->
        "#{label}, started #{started_at}"

      true ->
        label
    end
  end

  defp replay_run_known_text(nil), do: "false"
  defp replay_run_known_text(_replay_run), do: "true"

  defp replay_run_attr(nil, _field), do: ""

  defp replay_run_attr(replay_run, field) when is_map(replay_run) do
    replay_run
    |> Map.get(field, Map.get(replay_run, Atom.to_string(field)))
    |> replay_run_value_text()
  end

  defp replay_run_datetime(replay_run, field) do
    case replay_run_value(replay_run, field) do
      %DateTime{} = datetime -> DateTime.to_iso8601(datetime)
      value -> replay_run_value_text(value)
    end
  end

  defp replay_run_integer(replay_run, field) do
    case replay_run_value(replay_run, field) do
      value when is_integer(value) -> Integer.to_string(value)
      value -> replay_run_value_text(value)
    end
  end

  defp replay_run_value(nil, _field), do: nil

  defp replay_run_value(replay_run, field) when is_map(replay_run) do
    Map.get(replay_run, field, Map.get(replay_run, Atom.to_string(field)))
  end

  defp replay_run_value_text(value) when is_atom(value), do: Atom.to_string(value)
  defp replay_run_value_text(value) when is_binary(value), do: value
  defp replay_run_value_text(value) when is_integer(value), do: Integer.to_string(value)
  defp replay_run_value_text(_value), do: ""

  defp replay_run_sort_key(replay_run) do
    started_at =
      case replay_run_value(replay_run, :started_at) do
        %DateTime{} = datetime -> DateTime.to_unix(datetime, :microsecond)
        _value -> 0
      end

    {-started_at, replay_run_attr(replay_run, :replay_run_id)}
  end

  defp replay_window_bounded?(from, to), do: present_text?(from) and present_text?(to)

  defp replay_window_bounded_text(from, to) do
    if replay_window_bounded?(from, to), do: "true", else: "false"
  end

  defp replay_scrub_available?(replay_run_id, selected_data_ref) do
    present_text?(replay_run_id) and selected_timestamp?(selected_data_ref)
  end

  defp replay_scrub_available_text(replay_run_id, selected_data_ref) do
    if replay_scrub_available?(replay_run_id, selected_data_ref), do: "true", else: "false"
  end

  defp limit_mode_options do
    [
      {"Observed", "observed"},
      {"Current", "current"},
      {"Recomputed", "recomputed"},
      {"Compare", "compare"}
    ]
  end

  defp time_axis_options do
    [
      {"Generation", "generation_time"},
      {"Receipt", "receipt_time"}
    ]
  end

  defp limit_mode_fallback?(fallback) when is_map(fallback),
    do: present_text(Map.get(fallback, "requested_mode")) != nil

  defp limit_mode_fallback?(_fallback), do: false

  defp limit_mode_fallback_value(fallback, key) when is_map(fallback),
    do: present_text(Map.get(fallback, key))

  defp limit_mode_fallback_value(_fallback, _key), do: nil

  defp limit_mode_fallback_title(fallback) do
    requested = limit_mode_fallback_value(fallback, "requested_mode") || "requested"
    applied = limit_mode_fallback_value(fallback, "applied_mode") || "observed"

    "Requested #{requested} limit semantics; using #{applied}."
  end

  defp data_view_options do
    [
      {"Canonical", "canonical"},
      {"As recorded", "as_recorded"},
      {"All revisions", "all_revisions"},
      {"Recomputed", "recomputed"}
    ]
  end

  defp compare_data_view_options(active_data_view) do
    [
      {"No compare", ""}
      | Enum.reject(data_view_options(), fn {_label, view} -> view == active_data_view end)
    ]
  end

  defp present_text?(value), do: not is_nil(present_text(value))

  defp present_text(value) when is_binary(value) do
    value
    |> String.trim()
    |> case do
      "" -> nil
      value -> value
    end
  end

  defp present_text(_value), do: nil

  defp realm_options(realms) do
    Enum.map(realms, fn realm -> {String.capitalize(to_string(realm)), realm} end)
  end

  defp source_binding_options(bindings, realm) do
    options =
      bindings
      |> Enum.filter(&telemetry_binding_for_realm?(&1, realm))
      |> Enum.sort_by(&{&1.priority, &1.binding_id})
      |> Enum.map(fn binding -> {source_binding_option_label(binding), binding.binding_id} end)

    [{"Primary source", ""} | options]
  end

  defp telemetry_binding_for_realm?(binding, realm) do
    binding.logical_source == :telemetry and normalize_realm(binding.realm) == realm and
      DataBinding.active?(binding)
  end

  defp source_binding_option_label(binding) do
    "#{binding.binding_id} / #{binding.data_source_id}"
  end

  defp source_context_label(nil, nil), do: "Primary source"
  defp source_context_label(nil, ""), do: "Primary source"
  defp source_context_label("", ""), do: "Primary source"
  defp source_context_label(data_source_id, nil), do: data_source_id
  defp source_context_label(data_source_id, ""), do: data_source_id
  defp source_context_label(_data_source_id, source_binding_id), do: source_binding_id

  defp normalize_realm(realm) when is_atom(realm), do: Atom.to_string(realm)
  defp normalize_realm(realm) when is_binary(realm), do: realm
  defp normalize_realm(_realm), do: nil
end
