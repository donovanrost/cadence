defmodule CadenceWeb.AdminRuntimeLive do
  @moduledoc false
  use CadenceWeb, :live_view

  @decision_limit 100
  @filter_defaults %{
    "dashboard_id" => "",
    "mission_id" => "",
    "boundary" => "",
    "context_reason" => "",
    "replay_run_id" => "",
    "affected_placement_id" => ""
  }

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Runtime Diagnostics")
     |> assign(:nav_item, :admin_runtime)}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    filters = filter_params(params)
    selected_decision_key = Map.get(params, "decision")
    {:noreply, assign_runtime_diagnostics(socket, filters, selected_decision_key)}
  end

  @impl true
  def handle_event("refresh", _params, socket) do
    {:noreply,
     assign_runtime_diagnostics(
       socket,
       socket.assigns.filter_params,
       socket.assigns.selected_decision_key
     )}
  end

  @impl true
  def handle_event("filter_decisions", %{"runtime_decision_filters" => params}, socket) do
    {:noreply, push_patch(socket, to: ~p"/admin/runtime?#{compact_filter_params(params)}")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div
      id="admin-runtime-page"
      class="space-y-6"
      data-runtime-decision-count={@decision_count}
      data-runtime-decision-status-summary={@status_summary}
      data-runtime-decision-refresh-summary={@refresh_summary}
      data-runtime-decision-source-summary={@source_summary}
      data-runtime-decision-filter-dashboard={@filter_params["dashboard_id"]}
      data-runtime-decision-filter-mission={@filter_params["mission_id"]}
      data-runtime-decision-filter-boundary={@filter_params["boundary"]}
      data-runtime-decision-filter-context-reason={@filter_params["context_reason"]}
      data-runtime-decision-filter-replay-run={@filter_params["replay_run_id"]}
      data-runtime-decision-filter-affected-placement={@filter_params["affected_placement_id"]}
      data-runtime-selected-decision-state={@selected_decision_result_state}
    >
      <.page_header
        title="Runtime Diagnostics"
        subtitle="Process-local runtime health for support workflows, including dashboard invalidation decisions emitted by open dashboards."
        breadcrumbs={[
          {"Platform Admin", ~p"/admin"},
          {"Runtime Diagnostics", nil}
        ]}
      >
        <:title_suffix>{@decision_count} decisions</:title_suffix>
        <:actions>
          <.button id="admin-runtime-refresh" phx-click="refresh" variant={:secondary}>
            <.icon name="hero-arrow-path" class="h-4 w-4" /> Refresh
          </.button>
        </:actions>
      </.page_header>

      <div class="grid gap-3 md:grid-cols-4">
        <.stat_tile id="runtime-decision-count" label="Decisions" value={@decision_count} />
        <.stat_tile id="runtime-refresh-allowed" label="Refresh Allowed" value={@refresh_allowed_count} />
        <.stat_tile
          id="runtime-refresh-suppressed"
          label="Refresh Suppressed"
          value={@refresh_suppressed_count}
        />
        <.stat_tile id="runtime-filtered" label="Filtered" value={@filtered_count} />
      </div>

      <.card
        heading="Decision Filters"
        subtitle="Filter durable decision history and runtime-health fallback rows by dashboard, mission, invalidation boundary, context reason, or impacted placement."
      >
        <.form
          for={@filter_form}
          id="admin-runtime-filter-form"
          phx-change="filter_decisions"
          phx-submit="filter_decisions"
          class="grid gap-3 md:grid-cols-2 xl:grid-cols-6"
        >
          <.input
            field={@filter_form[:dashboard_id]}
            type="text"
            label="Dashboard"
            placeholder="dashboard-id"
            compact
          />
          <.input
            field={@filter_form[:mission_id]}
            type="text"
            label="Mission"
            placeholder="mission-id"
            compact
          />
          <.input
            field={@filter_form[:boundary]}
            type="text"
            label="Boundary"
            placeholder="source_watermark_changed"
            compact
          />
          <.input
            field={@filter_form[:context_reason]}
            type="text"
            label="Context"
            placeholder="replay_run_mismatch"
            compact
          />
          <.input
            field={@filter_form[:replay_run_id]}
            type="text"
            label="Replay Run"
            placeholder="replay-run-id"
            compact
          />
          <.input
            field={@filter_form[:affected_placement_id]}
            type="text"
            label="Placement"
            placeholder="placement-id"
            compact
          />
          <div class="flex items-end gap-2 md:col-span-2 xl:col-span-6">
            <.button id="admin-runtime-apply-filters" type="submit" variant={:secondary}>
              <.icon name="hero-funnel" class="h-4 w-4" /> Apply
            </.button>
            <.button id="admin-runtime-clear-filters" patch={~p"/admin/runtime"} variant={:ghost}>
              <.icon name="hero-x-mark" class="h-4 w-4" /> Clear
            </.button>
          </div>
        </.form>
      </.card>

      <.card heading="Dashboard Invalidation Decisions" padding={:none}>
        <.table
          id="admin-runtime-decisions-table"
          rows={@decisions}
          row_id={&decision_row_id/1}
          row_accent={false}
          class="table-sm"
        >
          <:col :let={decision} label="Dashboard" mono>
            <span class="break-all" data-runtime-decision-field="dashboard">
              {display_value(decision.dashboard_id)}
            </span>
          </:col>
          <:col :let={decision} label="Mission" mono>
            <span class="break-all" data-runtime-decision-field="mission">
              {display_value(decision.mission_id)}
            </span>
          </:col>
          <:col :let={decision} label="Source" mono>
            <span data-runtime-decision-field="source">
              {decision_source(decision)}
            </span>
          </:col>
          <:col :let={decision} label="Boundary" mono>
            <span data-runtime-decision-field="boundary">
              {display_value(decision.boundary)}
            </span>
          </:col>
          <:col :let={decision} label="Status" mono>
            <span data-runtime-decision-field="status">
              {display_value(decision.decision_status)}
            </span>
          </:col>
          <:col :let={decision} label="Context" mono>
            <span data-runtime-decision-field="context">
              {display_value(decision.context_reason)}
            </span>
          </:col>
          <:col :let={decision} label="Replay" mono>
            <span class="break-all" data-runtime-decision-field="replay-run">
              {display_value(replay_run_id(decision))}
            </span>
          </:col>
          <:col :let={decision} label="Refresh" mono>
            <span data-runtime-decision-field="refresh">
              {display_value(decision.refresh_reason)}
            </span>
          </:col>
          <:col :let={decision} label="Artifacts" align={:right} mono>
            <span data-runtime-decision-field="artifacts">
              {display_value(decision.invalidated_artifacts)}
            </span>
          </:col>
          <:col :let={decision} label="Impacted" align={:right} mono>
            <span data-runtime-decision-field="affected-count">
              {display_value(decision.affected_placement_count)}
            </span>
          </:col>
          <:col :let={decision} label="Placements" mono class="max-w-64">
            <span class="break-all" data-runtime-decision-field="affected-placements">
              {display_list(decision.affected_placement_ids)}
            </span>
          </:col>
          <:col :let={decision} label="Impact" mono class="max-w-56">
            <span class="break-all" data-runtime-decision-field="affected-impact">
              {display_list(decision.affected_impact_reasons)}
            </span>
          </:col>
          <:col :let={decision} label="Observed" mono>
            <span data-runtime-decision-field="observed">
              {display_time(decision.decision_observed_at)}
            </span>
          </:col>
          <:col :let={decision} label="" align={:right}>
            <.button
              id={"admin-runtime-inspect-#{dom_value(decision_key(decision))}"}
              patch={runtime_path(@filter_params, decision_key(decision))}
              variant={if(@selected_decision_key == decision_key(decision), do: :secondary, else: :ghost)}
              size={:xs}
            >
              <.icon name="hero-magnifying-glass" class="h-3.5 w-3.5" /> Inspect
            </.button>
          </:col>
          <:empty>
            <div id="admin-runtime-decisions-empty" class="py-6 text-center text-sm text-base-content/70">
              No dashboard runtime invalidation decisions have been recorded.
            </div>
          </:empty>
        </.table>
      </.card>

      <div
        :if={@selected_decision_missing?}
        id="admin-runtime-decision-detail-missing"
        class="rounded border border-warning/40 bg-warning/10 px-4 py-3 text-sm text-warning-content"
      >
        The selected decision could not be found in durable runtime decision history.
      </div>

      <div
        :if={@selected_decision_outside_results?}
        id="admin-runtime-decision-detail-outside-results"
        class="rounded border border-info/40 bg-info/10 px-4 py-3 text-sm text-base-content"
        data-runtime-selected-decision-key={@selected_decision_key}
        data-runtime-selected-decision-context-link={
          selected_decision_context_path(@selected_decision)
        }
      >
        <div class="flex flex-wrap items-center justify-between gap-3">
          <span>
            The selected decision was loaded directly and is outside the current filtered result set.
          </span>
          <.button
            id="admin-runtime-show-selected-context"
            patch={selected_decision_context_path(@selected_decision)}
            variant={:secondary}
            size={:xs}
          >
            <.icon name="hero-funnel" class="h-3.5 w-3.5" /> Show in table context
          </.button>
        </div>
      </div>

      <.card
        :if={@selected_decision}
        id="admin-runtime-decision-detail"
        heading="Decision Detail"
        subtitle={decision_detail_subtitle(@selected_decision)}
      >
        <:actions>
          <.button
            id="admin-runtime-close-detail"
            patch={runtime_path(@filter_params, nil)}
            variant={:ghost}
            size={:xs}
          >
            <.icon name="hero-x-mark" class="h-3.5 w-3.5" /> Close
          </.button>
        </:actions>

        <div
          id="admin-runtime-decision-detail-evidence"
          class="grid gap-x-8 gap-y-6 lg:grid-cols-2 xl:grid-cols-4"
          data-runtime-decision-detail-key={@selected_decision_key}
          data-runtime-decision-detail-source={decision_source(@selected_decision)}
        >
          <div
            :for={{group_label, facts} <- decision_detail_groups(@selected_decision)}
            class="space-y-3 border-t border-base-300 pt-3"
          >
            <p class="hud-label">{group_label}</p>
            <div class="min-w-0">
              <.detail_row :for={{label, value} <- facts} label={label}>
                <span class="break-all" data-runtime-decision-detail-field={dom_value(label)}>
                  {display_detail_value(value)}
                </span>
              </.detail_row>
            </div>
          </div>
        </div>

        <div class="mt-6 grid gap-6 lg:grid-cols-3">
          <div class="min-w-0 border-t border-base-300 pt-3">
            <p class="hud-label">Filters</p>
            <div id="admin-runtime-decision-detail-filters" class="mt-3">
              <.detail_row
                :for={{key, value} <- display_pairs(@selected_decision.filters)}
                label={key}
              >
                <span class="break-all">{value}</span>
              </.detail_row>
              <p
                :if={display_pairs(@selected_decision.filters) == []}
                class="text-sm text-base-content/60"
              >
                No filters recorded.
              </p>
            </div>
          </div>

          <div class="min-w-0 border-t border-base-300 pt-3">
            <p class="hud-label">Measurements</p>
            <div id="admin-runtime-decision-detail-measurements" class="mt-3">
              <.detail_row
                :for={{key, value} <- display_pairs(@selected_decision.measurements)}
                label={key}
              >
                <span class="break-all">{value}</span>
              </.detail_row>
              <p
                :if={display_pairs(@selected_decision.measurements) == []}
                class="text-sm text-base-content/60"
              >
                No measurements recorded.
              </p>
            </div>
          </div>

          <div class="min-w-0 border-t border-base-300 pt-3">
            <p class="hud-label">Decision Payload</p>
            <div id="admin-runtime-decision-detail-decision" class="mt-3">
              <.detail_row
                :for={{key, value} <- display_pairs(@selected_decision.decision)}
                label={key}
              >
                <span class="break-all">{value}</span>
              </.detail_row>
              <p
                :if={display_pairs(@selected_decision.decision) == []}
                class="text-sm text-base-content/60"
              >
                No decision payload recorded.
              </p>
            </div>
          </div>
        </div>
      </.card>
    </div>
    """
  end

  defp assign_runtime_diagnostics(socket, filters, selected_decision_key) do
    decisions =
      filters
      |> decision_filter_opts()
      |> Cadence.dashboard_runtime_invalidation_decisions()

    summary = summarize_decisions(decisions)

    selected_decision_in_results? =
      selected_decision_in_results?(decisions, selected_decision_key)

    selected_decision = selected_decision(decisions, selected_decision_key)

    selected_decision_missing? =
      selected_decision_key not in [nil, ""] and is_nil(selected_decision)

    selected_decision_outside_results? =
      selected_decision_key not in [nil, ""] and
        not is_nil(selected_decision) and
        not selected_decision_in_results?

    socket
    |> assign(:filter_params, filters)
    |> assign(:filter_form, to_form(filters, as: :runtime_decision_filters))
    |> assign(:decisions, decisions)
    |> assign(:selected_decision, selected_decision)
    |> assign(:selected_decision_key, selected_decision_key)
    |> assign(:selected_decision_missing?, selected_decision_missing?)
    |> assign(:selected_decision_outside_results?, selected_decision_outside_results?)
    |> assign(
      :selected_decision_result_state,
      selected_decision_result_state(
        selected_decision_key,
        selected_decision,
        selected_decision_in_results?
      )
    )
    |> assign(:decision_count, length(decisions))
    |> assign(:refresh_allowed_count, summary.refresh_allowed)
    |> assign(:refresh_suppressed_count, summary.refresh_suppressed)
    |> assign(:filtered_count, summary.filtered)
    |> assign(:status_summary, count_summary(summary.statuses))
    |> assign(:refresh_summary, count_summary(summary.refresh_reasons))
    |> assign(:source_summary, count_summary(summary.sources))
  end

  defp summarize_decisions(decisions) do
    Enum.reduce(
      decisions,
      %{
        refresh_allowed: 0,
        refresh_suppressed: 0,
        filtered: 0,
        statuses: %{},
        refresh_reasons: %{},
        sources: %{}
      },
      fn decision, summary ->
        summary
        |> increment_if(:refresh_allowed, decision.refresh_allowed? == true)
        |> increment_if(:refresh_suppressed, decision.refresh_allowed? == false)
        |> increment_if(:filtered, decision.decision_status == :filtered)
        |> count_value(:statuses, decision.decision_status)
        |> count_value(:refresh_reasons, decision.refresh_reason)
        |> count_value(:sources, decision_source(decision))
      end
    )
  end

  defp increment_if(summary, key, true), do: Map.update!(summary, key, &(&1 + 1))
  defp increment_if(summary, _key, false), do: summary

  defp count_value(summary, _key, value) when value in [nil, ""], do: summary

  defp count_value(summary, key, value) do
    Map.update!(summary, key, &Map.update(&1, display_value(value), 1, fn count -> count + 1 end))
  end

  defp count_summary(counts) when map_size(counts) == 0, do: "-"

  defp count_summary(counts) do
    counts
    |> Enum.sort_by(fn {key, _count} -> key end)
    |> Enum.map_join(" ", fn {key, count} -> "#{key}:#{count}" end)
  end

  defp decision_row_id(decision) do
    "admin-runtime-decision-#{dom_value(decision_key(decision))}"
  end

  defp decision_key(decision) do
    decision.dashboard_runtime_invalidation_decision_event_id ||
      decision.invalidation_event_id ||
      [
        decision.dashboard_id,
        decision.boundary,
        display_time(decision.decision_observed_at)
      ]
      |> Enum.map_join(":", &display_value/1)
  end

  defp filter_params(params) when is_map(params) do
    Map.merge(@filter_defaults, Map.take(params, Map.keys(@filter_defaults)))
  end

  defp compact_filter_params(params) when is_map(params) do
    params
    |> Map.take(Map.keys(@filter_defaults))
    |> Enum.reduce(%{}, fn {key, value}, filters ->
      value = value |> to_string() |> String.trim()

      if value == "" do
        filters
      else
        Map.put(filters, key, value)
      end
    end)
  end

  defp decision_filter_opts(filters) do
    filters
    |> compact_filter_params()
    |> Enum.reduce([limit: @decision_limit], fn
      {"dashboard_id", value}, opts -> Keyword.put(opts, :dashboard_id, value)
      {"mission_id", value}, opts -> Keyword.put(opts, :mission_id, value)
      {"boundary", value}, opts -> Keyword.put(opts, :boundary, value)
      {"context_reason", value}, opts -> Keyword.put(opts, :context_reason, value)
      {"replay_run_id", value}, opts -> Keyword.put(opts, :replay_run_id, value)
      {"affected_placement_id", value}, opts -> Keyword.put(opts, :affected_placement_id, value)
    end)
  end

  defp selected_decision(_decisions, selected_decision_key)
       when selected_decision_key in [nil, ""],
       do: nil

  defp selected_decision(decisions, selected_decision_key) do
    selected_decision_from_results(decisions, selected_decision_key) ||
      selected_durable_decision(selected_decision_key)
  end

  defp selected_decision_from_results(_decisions, selected_decision_key)
       when selected_decision_key in [nil, ""],
       do: nil

  defp selected_decision_from_results(decisions, selected_decision_key) do
    Enum.find(decisions, &(decision_key(&1) == selected_decision_key))
  end

  defp selected_decision_in_results?(decisions, selected_decision_key) do
    not is_nil(selected_decision_from_results(decisions, selected_decision_key))
  end

  defp selected_decision_result_state(selected_decision_key, _selected_decision, _in_results?)
       when selected_decision_key in [nil, ""],
       do: "none"

  defp selected_decision_result_state(_selected_decision_key, nil, _in_results?), do: "missing"

  defp selected_decision_result_state(_selected_decision_key, _selected_decision, true),
    do: "visible"

  defp selected_decision_result_state(_selected_decision_key, _selected_decision, false),
    do: "outside_results"

  defp selected_durable_decision(selected_decision_key) do
    selected_decision_by_event_id(selected_decision_key) ||
      selected_decision_by_invalidation_id(selected_decision_key)
  end

  defp selected_decision_by_event_id(selected_decision_key) do
    durable_decision_rows(selected_decision_key,
      dashboard_runtime_invalidation_decision_event_id: selected_decision_key
    )
    |> List.first()
  end

  defp selected_decision_by_invalidation_id(selected_decision_key) do
    durable_decision_rows(selected_decision_key, invalidation_event_id: selected_decision_key)
    |> List.first()
  end

  defp durable_decision_rows(selected_decision_key, opts)
       when is_binary(selected_decision_key) and selected_decision_key != "" do
    Cadence.durable_dashboard_runtime_invalidation_decisions(Keyword.put(opts, :limit, 1))
  end

  defp durable_decision_rows(_selected_decision_key, _opts), do: []

  defp runtime_path(filters, selected_decision_key) do
    ~p"/admin/runtime?#{runtime_query_params(filters, selected_decision_key)}"
  end

  defp runtime_query_params(filters, selected_decision_key)
       when selected_decision_key in [nil, ""] do
    compact_filter_params(filters)
  end

  defp runtime_query_params(filters, selected_decision_key) do
    filters
    |> compact_filter_params()
    |> Map.put("decision", selected_decision_key)
  end

  defp selected_decision_context_path(decision) when is_map(decision) do
    ~p"/admin/runtime?#{selected_decision_context_query(decision)}"
  end

  defp selected_decision_context_path(_decision), do: ~p"/admin/runtime"

  defp selected_decision_context_query(decision) do
    %{
      "dashboard_id" => Map.get(decision, :dashboard_id),
      "mission_id" => Map.get(decision, :mission_id),
      "boundary" => display_value(Map.get(decision, :boundary)),
      "context_reason" => display_value(Map.get(decision, :context_reason)),
      "replay_run_id" => replay_run_id(decision),
      "affected_placement_id" => first_value(Map.get(decision, :affected_placement_ids)),
      "decision" => decision_key(decision)
    }
    |> compact_query_params()
  end

  defp compact_query_params(params) do
    Map.reject(params, fn {_key, value} -> value in [nil, "", "-"] end)
  end

  defp first_value([value | _values]), do: display_value(value)
  defp first_value(_values), do: nil

  defp decision_detail_subtitle(decision) do
    [
      decision_source(decision),
      display_value(decision.decision_status),
      display_time(decision.decision_observed_at)
    ]
    |> Enum.reject(&(&1 in [nil, "", "-"]))
    |> Enum.join(" / ")
  end

  defp decision_detail_groups(decision) do
    [
      {"Identity",
       [
         {"Decision ID", decision.dashboard_runtime_invalidation_decision_event_id},
         {"Invalidation ID", decision.invalidation_event_id},
         {"Dashboard", decision.dashboard_id},
         {"Mission", decision.mission_id},
         {"Organization", decision.organization_id}
       ]},
      {"Invalidation",
       [
         {"Boundary", decision.boundary},
         {"Domain Fact", decision.domain_fact},
         {"Replay Run", replay_run_id(decision)},
         {"Artifacts", decision.invalidated_artifacts},
         {"Occurred", decision.invalidation_occurred_at},
         {"Observed", decision.decision_observed_at}
       ]},
      {"Decision",
       [
         {"Status", decision.decision_status},
         {"Matches", decision.matches?},
         {"Dashboard Matches", decision.dashboard_matches?},
         {"Context Matches", decision.context_matches?},
         {"Refresh Allowed", decision.refresh_allowed?}
       ]},
      {"Impact",
       [
         {"Context Reason", decision.context_reason},
         {"Refresh Reason", decision.refresh_reason},
         {"Impacted Placements", decision.affected_placement_count},
         {"Placement IDs", decision.affected_placement_ids},
         {"Widget Types", decision.affected_widget_type_ids},
         {"Impact Reasons", decision.affected_impact_reasons}
       ]}
    ]
  end

  defp decision_source(%{source_event_present?: true}), do: "durable_projection"
  defp decision_source(_decision), do: "runtime_health"

  defp replay_run_id(decision) do
    decision
    |> Map.get(:filters, %{})
    |> get_map_value(:replay_run_id)
  end

  defp display_value(nil), do: "-"
  defp display_value(""), do: "-"
  defp display_value(value) when is_boolean(value), do: to_string(value)
  defp display_value(value) when is_integer(value), do: Integer.to_string(value)
  defp display_value(value) when is_float(value), do: Float.to_string(value)
  defp display_value(value) when is_atom(value), do: Atom.to_string(value)
  defp display_value(value) when is_binary(value), do: value
  defp display_value(value), do: inspect(value)

  defp display_time(%DateTime{} = datetime), do: DateTime.to_iso8601(datetime)
  defp display_time(value), do: display_value(value)

  defp display_list([]), do: "-"

  defp display_list(values) when is_list(values) do
    Enum.map_join(values, ", ", &display_value/1)
  end

  defp display_list(value), do: display_value(value)

  defp display_detail_value(%DateTime{} = datetime), do: display_time(datetime)
  defp display_detail_value(values) when is_list(values), do: display_list(values)
  defp display_detail_value(value), do: display_value(value)

  defp display_pairs(values) when is_map(values) do
    values
    |> Enum.map(fn {key, value} -> {display_value(key), display_detail_value(value)} end)
    |> Enum.sort_by(fn {key, _value} -> key end)
  end

  defp display_pairs(_values), do: []

  defp get_map_value(values, key) when is_map(values) and is_atom(key) do
    Map.get(values, key, Map.get(values, Atom.to_string(key)))
  end

  defp get_map_value(_values, _key), do: nil

  defp dom_value(value) do
    value
    |> display_value()
    |> String.replace(~r/[^a-zA-Z0-9_-]+/, "-")
  end
end
