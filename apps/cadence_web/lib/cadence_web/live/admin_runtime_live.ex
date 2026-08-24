defmodule CadenceWeb.AdminRuntimeLive do
  @moduledoc false
  use CadenceWeb, :live_view

  alias Cadence.Projections.DashboardRuntimeInvalidations, as: DashboardRuntimeInvalidations
  alias Phoenix.LiveView.JS

  @decision_limit 100
  @filter_keys [
    "dashboard_id",
    "mission_id",
    "boundary",
    "context_reason",
    "replay_run_id",
    "affected_placement_id"
  ]
  @filter_defaults Map.new(@filter_keys, &{&1, ""})
  @sensitive_pair_key_fragments [
    "api_key",
    "authorization",
    "cookie",
    "credential",
    "password",
    "private_key",
    "secret",
    "session",
    "token"
  ]

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> stream_configure(:decisions, dom_id: &Map.fetch!(&1, :id))
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
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.vue
        id="admin-runtime-component"
        v-component="AdminRuntime"
        summary={@runtime_summary}
        filters={@runtime_filters}
        decisions={@streams.decisions}
        selection={@runtime_selection}
        navigation={@runtime_navigation}
        v-on:refresh={JS.push("refresh")}
        v-on:filter_decisions={JS.push("filter_decisions")}
        v-ssr={false}
        class="contents"
      />
    </Layouts.app>
    """
  end

  defp assign_runtime_diagnostics(socket, filters, selected_decision_key) do
    decisions =
      filters
      |> decision_filter_opts()
      |> DashboardRuntimeInvalidations.list()

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

    selected_decision_result_state =
      selected_decision_result_state(
        selected_decision_key,
        selected_decision,
        selected_decision_in_results?
      )

    decision_rows =
      Enum.map(
        decisions,
        &decision_dto(&1, filters, selected_decision_key)
      )

    socket
    |> assign(:filter_params, filters)
    |> assign(:selected_decision_key, selected_decision_key)
    |> assign(
      :runtime_summary,
      summary_dto(summary, length(decisions), selected_decision_result_state)
    )
    |> assign(:runtime_filters, filters_dto(filters))
    |> assign(
      :runtime_selection,
      selection_dto(
        selected_decision,
        selected_decision_key,
        selected_decision_result_state,
        selected_decision_missing?,
        selected_decision_outside_results?,
        filters
      )
    )
    |> assign(:runtime_navigation, %{admin_href: ~p"/admin"})
    |> stream(:decisions, decision_rows, reset: true)
  end

  defp summary_dto(summary, decision_count, selected_decision_result_state) do
    %{
      decision_count: decision_count,
      status_summary: count_summary(summary.statuses),
      refresh_summary: count_summary(summary.refresh_reasons),
      source_summary: count_summary(summary.sources),
      selected_decision_state: selected_decision_result_state,
      empty_state: %{
        id: "admin-runtime-decisions-empty",
        copy: "No dashboard runtime invalidation decisions have been recorded."
      },
      stats: [
        %{id: "runtime-decision-count", label: "Decisions", value: decision_count},
        %{
          id: "runtime-refresh-allowed",
          label: "Refresh Allowed",
          value: summary.refresh_allowed
        },
        %{
          id: "runtime-refresh-suppressed",
          label: "Refresh Suppressed",
          value: summary.refresh_suppressed
        },
        %{id: "runtime-filtered", label: "Filtered", value: summary.filtered}
      ]
    }
  end

  defp filters_dto(filters) do
    %{
      values: Map.take(filters, @filter_keys),
      fields: [
        filter_field_dto("dashboard_id", "Dashboard", "dashboard-id"),
        filter_field_dto("mission_id", "Mission", "mission-id"),
        filter_field_dto("boundary", "Boundary", "source_watermark_changed"),
        filter_field_dto("context_reason", "Context", "replay_run_mismatch"),
        filter_field_dto("replay_run_id", "Replay Run", "replay-run-id"),
        filter_field_dto("affected_placement_id", "Placement", "placement-id")
      ],
      clear_href: ~p"/admin/runtime"
    }
  end

  defp filter_field_dto(key, label, placeholder) do
    %{
      key: key,
      id: "runtime_decision_filters_#{key}",
      name: "runtime_decision_filters[#{key}]",
      label: label,
      placeholder: placeholder
    }
  end

  defp decision_dto(decision, filters, selected_decision_key) do
    key = decision_key(decision)

    %{
      id: decision_row_id(decision),
      key: key,
      dashboard: display_value(decision.dashboard_id),
      mission: display_value(decision.mission_id),
      source: decision_source(decision),
      boundary: display_value(decision.boundary),
      status: display_value(decision.decision_status),
      context: display_value(decision.context_reason),
      replay_run: display_value(replay_run_id(decision)),
      refresh: display_value(decision.refresh_reason),
      artifacts: display_value(decision.invalidated_artifacts),
      affected_count: display_value(decision.affected_placement_count),
      affected_placements: display_list(decision.affected_placement_ids),
      affected_impact: display_list(decision.affected_impact_reasons),
      observed: display_time(decision.decision_observed_at),
      inspect_action: %{
        id: "admin-runtime-inspect-#{dom_value(key)}",
        href: runtime_path(filters, key),
        selected: selected_decision_key == key
      }
    }
  end

  defp selection_dto(
         selected_decision,
         selected_decision_key,
         selected_decision_result_state,
         selected_decision_missing?,
         selected_decision_outside_results?,
         filters
       ) do
    %{
      state: selected_decision_result_state,
      decision_key: selected_decision_key,
      missing: selected_decision_missing?,
      outside_results: selected_decision_outside_results?,
      context_href: context_href(selected_decision, selected_decision_outside_results?),
      detail: selected_decision_detail_dto(selected_decision, selected_decision_key, filters)
    }
  end

  defp context_href(selected_decision, true),
    do: selected_decision_context_path(selected_decision)

  defp context_href(_selected_decision, false), do: nil

  defp selected_decision_detail_dto(nil, _selected_decision_key, _filters), do: nil

  defp selected_decision_detail_dto(decision, selected_decision_key, filters) do
    %{
      id: "admin-runtime-decision-detail",
      subtitle: decision_detail_subtitle(decision),
      close_action: %{
        id: "admin-runtime-close-detail",
        href: runtime_path(filters, nil)
      },
      evidence: %{
        id: "admin-runtime-decision-detail-evidence",
        decision_key: selected_decision_key,
        source: decision_source(decision),
        groups:
          Enum.map(decision_detail_groups(decision), fn {label, facts} ->
            %{
              key: dom_value(label),
              label: label,
              facts:
                Enum.map(facts, fn {fact_label, value} ->
                  %{
                    key: dom_value(fact_label),
                    label: fact_label,
                    value: display_detail_value(value)
                  }
                end)
            }
          end)
      },
      sections: [
        detail_section_dto(
          "admin-runtime-decision-detail-filters",
          "Filters",
          "No filters recorded.",
          decision.filters
        ),
        detail_section_dto(
          "admin-runtime-decision-detail-measurements",
          "Measurements",
          "No measurements recorded.",
          decision.measurements
        ),
        detail_section_dto(
          "admin-runtime-decision-detail-decision",
          "Decision Payload",
          "No decision payload recorded.",
          decision.decision
        )
      ]
    }
  end

  defp detail_section_dto(id, label, empty_copy, values) do
    %{
      id: id,
      key: dom_value(label),
      label: label,
      empty_copy: empty_copy,
      pairs:
        values
        |> display_pairs()
        |> Enum.with_index()
        |> Enum.map(fn {{key, value}, index} ->
          %{key: "#{dom_value(key)}-#{index}", label: key, value: value}
        end)
    }
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
    Map.merge(@filter_defaults, Map.take(params, @filter_keys))
  end

  defp compact_filter_params(params) when is_map(params) do
    params
    |> Map.take(@filter_keys)
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
    DashboardRuntimeInvalidations.list_durable(Keyword.put(opts, :limit, 1))
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
  defp display_value(_value), do: "-"

  defp display_time(%DateTime{} = datetime), do: DateTime.to_iso8601(datetime)
  defp display_time(value), do: display_value(value)

  defp display_list([]), do: "-"

  defp display_list(values) when is_list(values) do
    if Enum.all?(values, &scalar_value?/1) do
      Enum.map_join(values, ", ", &display_value/1)
    else
      "#{length(values)} entries"
    end
  end

  defp display_list(value), do: display_value(value)

  defp display_detail_value(%DateTime{} = datetime), do: display_time(datetime)
  defp display_detail_value(values) when is_list(values), do: display_list(values)
  defp display_detail_value(value) when is_map(value), do: "#{map_size(value)} fields"
  defp display_detail_value(value), do: display_value(value)

  defp display_pairs(values) when is_map(values) do
    values
    |> Enum.reject(fn {key, _value} -> sensitive_pair_key?(key) end)
    |> Enum.map(fn {key, value} -> {display_value(key), display_detail_value(value)} end)
    |> Enum.sort_by(fn {key, _value} -> key end)
  end

  defp display_pairs(_values), do: []

  defp sensitive_pair_key?(key) do
    normalized_key = key |> display_value() |> String.downcase()
    Enum.any?(@sensitive_pair_key_fragments, &String.contains?(normalized_key, &1))
  end

  defp scalar_value?(value) do
    is_nil(value) or is_boolean(value) or is_number(value) or is_atom(value) or is_binary(value)
  end

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
