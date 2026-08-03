defmodule CadenceWeb.OpsDashboardShowLive.DashboardRuntimeControlsComponents do
  @moduledoc false
  use CadenceWeb, :html

  alias Cadence.Dashboards.DataBinding
  alias CadenceWeb.OpsDashboardShowLive.MarkerCategories

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
  attr :hidden_marker_categories, :list, default: []
  attr :selected_data_ref, :any, default: nil
  attr :section, :atom, values: [:all, :data], default: :all

  def runtime_context_controls(assigns) do
    assigns = assign(assigns, :data_form, to_form(runtime_form_params(assigns)))

    ~H"""
    <div
      id={runtime_controls_id(@section)}
      data-dashboard-query-control-section={@section}
      class="min-w-0"
    >
      <div data-dashboard-data-query-controls>
        <div class="flex items-start justify-between gap-3">
          <div>
            <p class="text-xs font-semibold text-base-content/85">Active telemetry source</p>
            <p class="mt-0.5 text-[0.68rem] text-base-content/50">
              Defaults follow the dashboard definition. Overrides stay in the URL.
            </p>
          </div>
          <span
            id="dashboard-active-source"
            data-dashboard-active-data-source={@data_source_id}
            data-dashboard-active-source-binding={@source_binding_id}
            class="badge badge-primary badge-outline badge-xs max-w-64 truncate font-mono"
            title={source_context_label(@data_source_id, @source_binding_id)}
          >
            {source_context_label(@data_source_id, @source_binding_id)}
          </span>
        </div>

        <.form
          for={@data_form}
          id="runtime-context-form"
          phx-change="set_runtime_context"
          class="mt-3"
        >
          <.input field={@data_form[:time_mode]} id="dashboard-time-mode" type="hidden" compact />
          <.input field={@data_form[:from]} id="dashboard-data-form-from" type="hidden" compact />
          <.input field={@data_form[:to]} id="dashboard-data-form-to" type="hidden" compact />
          <.input field={@data_form[:replay_run_id]} id="dashboard-replay-run-id" type="hidden" compact />

          <section class="cadence-dashboard-query-section" aria-labelledby="dashboard-source-query-heading">
            <p id="dashboard-source-query-heading" class="mb-2 text-xs font-semibold text-base-content/85">
              Source
            </p>
            <div class="grid gap-2 sm:grid-cols-[9rem_minmax(0,1fr)]">
              <.input
                field={@data_form[:realm]}
                id="dashboard-data-realm"
                type="select"
                label="Realm"
                options={realm_options(@data_realms)}
                compact
                class="select-xs"
              />
              <.input
                field={@data_form[:source_binding_id]}
                id="dashboard-source-binding"
                type="select"
                label="Source binding"
                options={source_binding_options(@data_bindings, @data_realm)}
                compact
                class="select-xs font-mono"
              />
            </div>
          </section>

          <section class="cadence-dashboard-query-section" aria-labelledby="dashboard-representation-query-heading">
            <p id="dashboard-representation-query-heading" class="mb-2 text-xs font-semibold text-base-content/85">
              Representation
            </p>
            <div class="grid gap-2 sm:grid-cols-2">
              <.input
                field={@data_form[:data_view]}
                id="dashboard-data-view"
                type="select"
                label="Data view"
                options={data_view_options()}
                compact
                class="select-xs"
              />
              <.input
                field={@data_form[:compare_data_view]}
                id="dashboard-compare-data-view"
                type="select"
                label="Compare against"
                options={compare_data_view_options(@data_view)}
                compact
                class="select-xs"
              />
            </div>
          </section>

          <section class="cadence-dashboard-query-section" aria-labelledby="dashboard-semantics-query-heading">
            <p id="dashboard-semantics-query-heading" class="mb-2 text-xs font-semibold text-base-content/85">
              Operational semantics
            </p>
            <div class="grid gap-2 sm:grid-cols-2">
              <.input
                field={@data_form[:time_axis]}
                id="dashboard-time-axis"
                type="select"
                label="Time basis"
                options={time_axis_options()}
                compact
                class="select-xs"
              />
              <.input
                field={@data_form[:limit_mode]}
                id="dashboard-limit-mode"
                type="select"
                label="Limit semantics"
                options={limit_mode_options()}
                compact
                class="select-xs"
              />
            </div>
            <span
              :if={limit_mode_fallback?(@limit_mode_fallback)}
              id="dashboard-limit-mode-fallback"
              data-requested-limit-mode={limit_mode_fallback_value(@limit_mode_fallback, "requested_mode")}
              data-applied-limit-mode={limit_mode_fallback_value(@limit_mode_fallback, "applied_mode")}
              data-limit-mode-fallback-reason={limit_mode_fallback_value(@limit_mode_fallback, "reason")}
              class="badge badge-warning badge-xs mt-2 gap-1"
              title={limit_mode_fallback_title(@limit_mode_fallback)}
            >
              <.icon name="hero-exclamation-triangle" class="h-3 w-3" /> Observed only
            </span>
          </section>

          <section class="cadence-dashboard-query-section" aria-labelledby="dashboard-markers-query-heading">
            <p id="dashboard-markers-query-heading" class="mb-2 text-xs font-semibold text-base-content/85">
              Chart markers
              <span
                :if={@hidden_marker_categories != []}
                id="dashboard-markers-hidden-count"
                class="badge badge-warning badge-xs ml-1"
              >
                {length(@hidden_marker_categories)} hidden
              </span>
            </p>
            <div id="dashboard-marker-toggles" class="grid gap-1 sm:grid-cols-2">
              <.input
                :for={{label, key} <- MarkerCategories.category_options()}
                type="checkbox"
                id={"dashboard-marker-#{key}"}
                name={"markers[#{key}]"}
                value={to_string(not MarkerCategories.hidden?(@hidden_marker_categories, key))}
                label={label}
                compact
                class="checkbox-xs"
              />
            </div>
          </section>
        </.form>
      </div>
    </div>
    """
  end

  defp runtime_controls_id(:all), do: "runtime-context-controls"
  defp runtime_controls_id(:data), do: "dashboard-data-query-controls"

  defp runtime_form_params(assigns) do
    %{
      "time_mode" => assigns.time_mode,
      "time_axis" => assigns.time_axis,
      "from" => assigns.time_from || "",
      "to" => assigns.time_to || "",
      "replay_run_id" => assigns.replay_run_id || "",
      "realm" => assigns.data_realm,
      "data_view" => assigns.data_view,
      "compare_data_view" => assigns.compare_data_view || "",
      "limit_mode" => assigns.limit_mode,
      "source_binding_id" => assigns.source_binding_id || ""
    }
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
