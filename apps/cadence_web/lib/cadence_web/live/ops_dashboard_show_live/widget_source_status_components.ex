defmodule CadenceWeb.OpsDashboardShowLive.WidgetSourceStatusComponents do
  @moduledoc false
  use CadenceWeb, :html

  alias Cadence.Dashboards.SourceActions
  alias CadenceWeb.OpsDashboardShowLive.EvidenceAttrs
  alias CadenceWeb.OpsDashboardShowLive.EvidenceQuery

  @source_status_states [
    :fresh,
    :no_data,
    :partial,
    :degraded,
    :stale,
    :unknown,
    :retention_gap,
    :unavailable
  ]
  @source_status_state_by_text Map.new(@source_status_states, &{Atom.to_string(&1), &1})

  attr :widget, :any, required: true
  attr :placement_id, :string, required: true
  attr :data, :any, required: true
  attr :data_view, :string, default: nil
  attr :compare_data_view, :string, default: nil
  attr :warnings, :list, default: []

  def widget_query_diagnostics(assigns) do
    assigns =
      assigns
      |> assign(
        :rows,
        widget_query_diagnostic_rows(
          assigns.widget,
          assigns.data,
          assigns.data_view,
          assigns.compare_data_view
        )
      )
      |> assign(:source_status, source_status(assigns.data))
      |> assign(
        :evidence_attrs,
        widget_query_evidence_attrs(
          assigns.placement_id,
          assigns.widget,
          assigns.data,
          assigns.data_view,
          assigns.compare_data_view,
          assigns.warnings
        )
      )

    ~H"""
    <.popover
      id={"widget-query-#{@placement_id}"}
      label="Widget query diagnostics"
      width={:md}
      data-widget-query-diagnostics
      data-widget-query-data-view={query_diagnostic_value(@data_view)}
      data-widget-query-compare-data-view={query_diagnostic_value(@compare_data_view)}
      data-widget-query-binding-source={widget_binding_value(@widget, :source)}
      data-widget-query-binding-mode={widget_binding_value(@widget, :mode)}
      data-widget-query-observables={widget_observable_ids(@widget)}
      data-widget-query-sampling={widget_binding_value(@widget, :sampling)}
      data-widget-query-window-seconds={widget_option_value(@widget, :window_seconds)}
      data-widget-query-source-state={source_status_text(@source_status, :state)}
      data-widget-query-source-data-state={source_status_text(@source_status, :data_state)}
      data-widget-query-source-request-ids={source_status_list_text(@source_status, :source_request_ids)}
      data-widget-query-logical-sources={source_status_list_text(@source_status, :logical_sources)}
      data-widget-query-data-source-ids={source_status_list_text(@source_status, :data_source_ids)}
      data-widget-query-source-binding-ids={source_status_list_text(@source_status, :source_binding_ids)}
      data-widget-query-realms={source_status_list_text(@source_status, :realms)}
      data-widget-query-time-modes={source_status_list_text(@source_status, :time_modes)}
      data-widget-query-time-axes={source_status_list_text(@source_status, :time_axes)}
      data-widget-query-scope-kinds={source_status_list_text(@source_status, :scope_kinds)}
      data-widget-query-scope-ids={source_status_list_text(@source_status, :scope_ids)}
      data-widget-query-contact-ids={source_status_list_text(@source_status, :contact_ids)}
      data-widget-query-source-endpoint-ids={source_status_list_text(@source_status, :source_endpoint_ids)}
      data-widget-query-source-health-states={source_status_list_text(@source_status, :source_health_states)}
      data-widget-query-source-health-reasons={source_status_list_text(@source_status, :source_health_reasons)}
      data-widget-query-source-health-event-ids={source_status_list_text(@source_status, :source_health_event_ids)}
      data-widget-query-empty-reason={source_status_empty_reason_text(@source_status)}
      data-widget-query-warning-codes={warning_codes(@warnings)}
    >
      <:trigger>
        <span class="btn btn-ghost btn-xs btn-square" title={widget_query_diagnostic_title(@rows)} data-widget-query-diagnostics-open>
          <.icon name="hero-adjustments-horizontal" class="h-3.5 w-3.5" />
        </span>
      </:trigger>
      <div class="p-2 text-xs">
        <div class="font-semibold text-base-content">Widget query</div>
        <dl class="mt-2 grid grid-cols-[7.25rem_minmax(0,1fr)] gap-x-2 gap-y-1">
          <%= for row <- @rows do %>
            <dt class="text-base-content/60" data-widget-query-field={row.label}>{row.label}</dt>
            <dd class="font-mono text-base-content break-all" data-widget-query-value={row.key}>
              {row.value}
            </dd>
          <% end %>
        </dl>
        <button
          type="button"
          phx-click="open_evidence"
          {@evidence_attrs}
          class="btn btn-xs btn-outline mt-2 w-full justify-start"
          data-widget-query-evidence-open
        >
          <.icon name="hero-link" class="h-3.5 w-3.5" />
          Open query evidence
        </button>
      </div>
    </.popover>
    """
  end

  attr :source_status, :map, required: true
  attr :mission_id, :string, default: nil

  def source_status_badge(assigns) do
    inventory_query = source_status_inventory_query(assigns.source_status)

    assigns =
      assigns
      |> assign(:evidence_attrs, EvidenceAttrs.source_status(assigns.source_status))
      |> assign(:inventory_query, inventory_query)
      |> assign(:inventory_query_text, source_status_inventory_query_text(inventory_query))
      |> assign(
        :inventory_href,
        source_status_inventory_href(assigns.mission_id, inventory_query)
      )
      |> assign(:actionable?, source_status_evidence?(assigns.source_status))

    ~H"""
    <span :if={@actionable?} class="join">
      <button
        type="button"
        phx-click="open_evidence"
        {@evidence_attrs}
        class={["badge badge-xs gap-1 cursor-pointer join-item", source_status_badge_class(@source_status)]}
        title={source_status_title(@source_status)}
        aria-label={"Inspect #{source_status_label(@source_status)} evidence"}
        data-widget-source-badge={source_status_text(@source_status, :state)}
        data-widget-source-badge-action="open_evidence"
        data-widget-source-badge-inventory-action={source_status_inventory_action(@inventory_query)}
        data-widget-source-badge-inventory-query={@inventory_query_text}
        data-widget-source-badge-inventory-href={@inventory_href || ""}
        data-widget-source-badge-severity={source_status_text(@source_status, :severity)}
        data-widget-source-badge-label={source_status_label(@source_status)}
        data-widget-source-badge-source={source_status_list_text(@source_status, :logical_sources)}
        data-widget-source-badge-data-source={
          source_status_list_text(@source_status, :data_source_ids)
        }
        data-widget-source-badge-binding={
          source_status_list_text(@source_status, :source_binding_ids)
        }
        data-widget-source-badge-time-mode={source_status_list_text(@source_status, :time_modes)}
        data-widget-source-badge-scope-kind={source_status_list_text(@source_status, :scope_kinds)}
        data-widget-source-badge-scope-id={source_status_list_text(@source_status, :scope_ids)}
        data-widget-source-badge-contact-id={source_status_list_text(@source_status, :contact_ids)}
        data-widget-source-badge-source-endpoint-id={
          source_status_list_text(@source_status, :source_endpoint_ids)
        }
        data-widget-source-badge-health-state={
          source_status_list_text(@source_status, :source_health_states)
        }
        data-widget-source-badge-health-reason={
          source_status_list_text(@source_status, :source_health_reasons)
        }
        data-widget-source-badge-health-event-id={
          source_status_list_text(@source_status, :source_health_event_ids)
        }
        data-widget-source-badge-empty-reason={source_status_empty_reason_text(@source_status)}
      >
        <.icon name="hero-signal" class="h-3 w-3" />
        <span>{source_status_label(@source_status)}</span>
      </button>
      <.link
        :if={@inventory_href}
        navigate={@inventory_href}
        class="badge badge-xs badge-outline join-item px-1"
        title="Open source inventory"
        aria-label={"Open #{source_status_label(@source_status)} source inventory"}
        data-widget-source-badge-inventory-open={source_status_text(@source_status, :state)}
        data-widget-source-badge-inventory-query={@inventory_query_text}
      >
        <.icon name="hero-circle-stack" class="h-3 w-3" />
      </.link>
    </span>
    <span
      :if={!@actionable?}
      class={["badge badge-xs gap-1", source_status_badge_class(@source_status)]}
      title={source_status_title(@source_status)}
      data-widget-source-badge={source_status_text(@source_status, :state)}
      data-widget-source-badge-action="none"
      data-widget-source-badge-inventory-action={source_status_inventory_action(@inventory_query)}
      data-widget-source-badge-inventory-query={@inventory_query_text}
      data-widget-source-badge-inventory-href={@inventory_href || ""}
      data-widget-source-badge-severity={source_status_text(@source_status, :severity)}
      data-widget-source-badge-label={source_status_label(@source_status)}
      data-widget-source-badge-source={source_status_list_text(@source_status, :logical_sources)}
      data-widget-source-badge-data-source={
        source_status_list_text(@source_status, :data_source_ids)
      }
      data-widget-source-badge-binding={
        source_status_list_text(@source_status, :source_binding_ids)
      }
      data-widget-source-badge-time-mode={source_status_list_text(@source_status, :time_modes)}
      data-widget-source-badge-scope-kind={source_status_list_text(@source_status, :scope_kinds)}
      data-widget-source-badge-scope-id={source_status_list_text(@source_status, :scope_ids)}
      data-widget-source-badge-contact-id={source_status_list_text(@source_status, :contact_ids)}
      data-widget-source-badge-source-endpoint-id={
        source_status_list_text(@source_status, :source_endpoint_ids)
      }
      data-widget-source-badge-health-state={
        source_status_list_text(@source_status, :source_health_states)
      }
      data-widget-source-badge-health-reason={
        source_status_list_text(@source_status, :source_health_reasons)
      }
      data-widget-source-badge-health-event-id={
        source_status_list_text(@source_status, :source_health_event_ids)
      }
      data-widget-source-badge-empty-reason={source_status_empty_reason_text(@source_status)}
    >
      <.icon name="hero-signal" class="h-3 w-3" />
      <span>{source_status_label(@source_status)}</span>
    </span>
    """
  end

  def source_status(%{source_status: source_status}) when is_map(source_status),
    do: source_status

  def source_status(_data), do: nil

  def source_status_badge?(data) do
    case source_status(data) |> source_status_state() do
      state
      when state in [
             :no_data,
             :partial,
             :degraded,
             :stale,
             :unknown,
             :retention_gap,
             :unavailable
           ] ->
        true

      _state ->
        false
    end
  end

  def widget_query_diagnostics?(widget, data, data_view, compare_data_view) do
    widget_query_diagnostic_rows(widget, data, data_view, compare_data_view) != []
  end

  defp widget_query_evidence_attrs(
         placement_id,
         widget,
         data,
         data_view,
         compare_data_view,
         warnings
       ) do
    source_status = source_status(data)

    EvidenceQuery.phx_value_attrs(%{
      "kind" => "query",
      "placement-id" => placement_id,
      "widget-title" => map_value(widget, :title),
      "requested-data-view" => data_view,
      "compare-data-view" => compare_data_view,
      "binding-source" => widget_binding_value(widget, :source),
      "binding-mode" => widget_binding_value(widget, :mode),
      "observables" => widget_observable_ids(widget),
      "sampling" => widget_binding_value(widget, :sampling),
      "window-seconds" => widget_option_value(widget, :window_seconds),
      "source-evidence-state" => source_status_text(source_status, :state),
      "data-state" => source_status_text(source_status, :data_state),
      "source-request-id" => source_status_first_value(source_status, :source_request_ids),
      "logical-source" => source_status_first_value(source_status, :logical_sources),
      "realm" => source_status_first_value(source_status, :realms),
      "data-source-id" => source_status_first_value(source_status, :data_source_ids),
      "source-binding-id" => source_status_first_value(source_status, :source_binding_ids),
      "time-mode" => source_status_first_value(source_status, :time_modes),
      "time-axis" => source_status_first_value(source_status, :time_axes),
      "replay-run-id" => source_status_first_value(source_status, :replay_run_ids),
      "scope-kind" => source_status_first_value(source_status, :scope_kinds),
      "scope-id" => source_status_first_value(source_status, :scope_ids),
      "scope-ids" => source_status_list_text(source_status, :scope_ids),
      "contact-id" => source_status_first_value(source_status, :contact_ids),
      "contact-ids" => source_status_list_text(source_status, :contact_ids),
      "source-endpoint-id" => source_status_first_value(source_status, :source_endpoint_ids),
      "source-health-state" => source_status_first_value(source_status, :source_health_states),
      "source-health-reason" => source_status_first_value(source_status, :source_health_reasons),
      "source-health-event-id" =>
        source_status_first_value(source_status, :source_health_event_ids),
      "source-empty-reason" => source_status_empty_reason_text(source_status),
      "widget-warning-codes" => warning_codes(warnings)
    })
  end

  defp widget_query_diagnostic_rows(widget, data, data_view, compare_data_view) do
    source_status = source_status(data)

    [
      query_diagnostic_row("data_view", "Data view", data_view),
      query_diagnostic_row("compare_data_view", "Compare view", compare_data_view),
      query_diagnostic_row(
        "binding_source",
        "Requested source",
        widget_binding_value(widget, :source)
      ),
      query_diagnostic_row("binding_mode", "Binding mode", widget_binding_value(widget, :mode)),
      query_diagnostic_row("observables", "Observables", widget_observable_ids(widget)),
      query_diagnostic_row("sampling", "Sampling", widget_binding_value(widget, :sampling)),
      query_diagnostic_row(
        "window_seconds",
        "Window seconds",
        widget_option_value(widget, :window_seconds)
      ),
      query_diagnostic_row(
        "source_state",
        "Source state",
        source_status_text(source_status, :state)
      ),
      query_diagnostic_row(
        "data_state",
        "Data state",
        source_status_text(source_status, :data_state)
      ),
      query_diagnostic_row(
        "source_requests",
        "Source requests",
        source_status_list_text(source_status, :source_request_ids)
      ),
      query_diagnostic_row(
        "logical_sources",
        "Logical sources",
        source_status_list_text(source_status, :logical_sources)
      ),
      query_diagnostic_row(
        "data_sources",
        "Data sources",
        source_status_list_text(source_status, :data_source_ids)
      ),
      query_diagnostic_row(
        "source_bindings",
        "Source bindings",
        source_status_list_text(source_status, :source_binding_ids)
      ),
      query_diagnostic_row("realms", "Realms", source_status_list_text(source_status, :realms)),
      query_diagnostic_row("time", "Time", source_status_time_text(source_status)),
      query_diagnostic_row("scope", "Scope", source_status_scope_text(source_status)),
      query_diagnostic_row(
        "contacts",
        "Contacts",
        source_status_list_text(source_status, :contact_ids)
      ),
      query_diagnostic_row(
        "source_endpoints",
        "Source endpoints",
        source_status_list_text(source_status, :source_endpoint_ids)
      ),
      query_diagnostic_row(
        "source_health",
        "Source health",
        source_status_list_text(source_status, :source_health_states)
      ),
      query_diagnostic_row(
        "source_health_reasons",
        "Health reasons",
        source_status_list_text(source_status, :source_health_reasons)
      ),
      query_diagnostic_row(
        "source_health_events",
        "Health events",
        source_status_list_text(source_status, :source_health_event_ids)
      ),
      query_diagnostic_row(
        "empty_reason",
        "Empty reason",
        source_status_empty_reason_text(source_status)
      ),
      query_diagnostic_row(
        "warning_codes",
        "Warnings",
        source_status_list_text(source_status, :warning_codes)
      )
    ]
    |> Enum.reject(&is_nil/1)
  end

  defp query_diagnostic_row(key, label, value) do
    case query_diagnostic_value(value) do
      "" -> nil
      value -> %{key: key, label: label, value: value}
    end
  end

  defp widget_query_diagnostic_title(rows) when is_list(rows) do
    rows
    |> Enum.take(3)
    |> Enum.map_join(" | ", fn row -> "#{row.label}: #{row.value}" end)
    |> case do
      "" -> "Widget query"
      summary -> "Widget query | #{summary}"
    end
  end

  defp query_diagnostic_value(nil), do: ""
  defp query_diagnostic_value(""), do: ""
  defp query_diagnostic_value(value) when is_boolean(value), do: to_string(value)
  defp query_diagnostic_value(value) when is_atom(value), do: Atom.to_string(value)
  defp query_diagnostic_value(value) when is_binary(value), do: value
  defp query_diagnostic_value(value) when is_integer(value), do: Integer.to_string(value)
  defp query_diagnostic_value(value) when is_float(value), do: Float.to_string(value)

  defp query_diagnostic_value(value) when is_list(value) do
    value
    |> Enum.map(&query_diagnostic_value/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
    |> Enum.join(",")
  end

  defp query_diagnostic_value(_value), do: ""

  defp widget_binding_value(widget, key) do
    widget
    |> widget_binding()
    |> map_value(key)
    |> query_diagnostic_value()
  end

  defp widget_observable_ids(widget) do
    binding = widget_binding(widget)

    [
      map_value(binding, :point_id),
      map_value(binding, :point_ids),
      map_value(binding, :observables)
    ]
    |> List.flatten()
    |> query_diagnostic_value()
  end

  defp widget_option_value(widget, key) do
    widget
    |> map_value(:options)
    |> map_value(key)
    |> query_diagnostic_value()
  end

  defp widget_binding(widget), do: map_value(widget, :binding) || %{}

  defp map_value(map, key) when is_map(map) and is_atom(key),
    do: Map.get(map, key, Map.get(map, Atom.to_string(key)))

  defp map_value(_map, _key), do: nil

  defp source_status_evidence?(source_status) when is_map(source_status) do
    Enum.any?(
      [
        :source_request_ids,
        :logical_sources,
        :data_source_ids,
        :source_binding_ids,
        :realms,
        :scope_ids,
        :contact_ids,
        :source_endpoint_ids,
        :source_health_event_ids,
        :source_health_reasons
      ],
      &(source_status_list_text(source_status, &1) != "")
    )
  end

  defp source_status_evidence?(_source_status), do: false

  defp source_status_inventory_query(source_status) when is_map(source_status) do
    source_status
    |> source_status_inventory_context()
    |> SourceActions.source_inventory_action(source: :widget_source_status)
    |> case do
      %{query: query} when is_map(query) -> query
      _action -> %{}
    end
  end

  defp source_status_inventory_query(_source_status), do: %{}

  defp source_status_inventory_context(source_status) do
    %{
      data_source_id: source_status_first_value(source_status, :data_source_ids),
      source_binding_id: source_status_first_value(source_status, :source_binding_ids),
      logical_source: source_status_first_value(source_status, :logical_sources),
      realm: source_status_first_value(source_status, :realms),
      scope_kind: source_status_first_value(source_status, :scope_kinds),
      scope_id: source_status_first_value(source_status, :scope_ids),
      contact_id: source_status_first_value(source_status, :contact_ids),
      source_endpoint_id: source_status_first_value(source_status, :source_endpoint_ids),
      source_empty_reason: source_status_empty_reason_text(source_status)
    }
    |> Enum.reject(fn {_key, value} -> value in [nil, ""] end)
    |> Map.new()
  end

  defp source_status_inventory_action(query) when is_map(query) and map_size(query) > 0,
    do: "source_inventory"

  defp source_status_inventory_action(_query), do: "none"

  defp source_status_inventory_query_text(query) when is_map(query) and map_size(query) > 0 do
    query
    |> Enum.sort_by(fn {key, _value} -> to_string(key) end)
    |> Enum.map_join("&", fn {key, value} -> "#{key}=#{value}" end)
  end

  defp source_status_inventory_query_text(_query), do: ""

  defp source_status_inventory_href(mission_id, query)
       when is_binary(mission_id) and mission_id != "" and is_map(query) and map_size(query) > 0 do
    ~p"/missions/#{mission_id}/ops/data-sources?#{query}"
  end

  defp source_status_inventory_href(_mission_id, _query), do: nil

  defp source_status_first_value(source_status, key) when is_map(source_status) do
    source_status
    |> Map.get(key, [])
    |> List.wrap()
    |> List.first()
    |> source_status_value_text()
  end

  defp source_status_first_value(_source_status, _key), do: ""

  defp source_status_badge_class(source_status) do
    case source_status_state(source_status) do
      :unavailable -> "badge-error"
      :retention_gap -> "badge-error badge-outline"
      :degraded -> "badge-warning"
      :partial -> "badge-warning badge-outline"
      :stale -> "badge-warning"
      :unknown -> "badge-warning badge-outline"
      :no_data -> "badge-ghost"
      _state -> "badge-info"
    end
  end

  defp source_status_label(source_status) do
    case source_status_state(source_status) do
      :unavailable -> "Source down"
      :retention_gap -> "Retention gap"
      :degraded -> "Source degraded"
      :partial -> "Source partial"
      :stale -> "Source stale"
      :unknown -> "Source unknown"
      :no_data -> "No source"
      state -> source_status_state_label(state)
    end
  end

  defp source_status_title(source_status) do
    [
      source_status_label(source_status),
      source_status_title_part(
        "source",
        source_status_list_text(source_status, :logical_sources)
      ),
      source_status_title_part(
        "data source",
        source_status_list_text(source_status, :data_source_ids)
      ),
      source_status_title_part(
        "binding",
        source_status_list_text(source_status, :source_binding_ids)
      ),
      source_status_title_part("realm", source_status_list_text(source_status, :realms)),
      source_status_title_part("time", source_status_time_text(source_status)),
      source_status_title_part("scope", source_status_scope_text(source_status)),
      source_status_title_part(
        "source endpoint",
        source_status_list_text(source_status, :source_endpoint_ids)
      ),
      source_status_title_part(
        "health",
        source_status_list_text(source_status, :source_health_states)
      ),
      source_status_title_part(
        "health reason",
        source_status_list_text(source_status, :source_health_reasons)
      ),
      source_status_title_part(
        "health event",
        source_status_list_text(source_status, :source_health_event_ids)
      ),
      source_status_title_part("reason", source_status_empty_reason_text(source_status))
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" | ")
  end

  defp source_status_title_part(_label, ""), do: nil
  defp source_status_title_part(label, value), do: "#{label}: #{value}"

  defp source_status_time_text(source_status) do
    case {
      source_status_list_text(source_status, :time_modes),
      source_status_list_text(source_status, :time_axes)
    } do
      {"", ""} -> ""
      {mode, ""} -> mode
      {"", axis} -> axis
      {mode, axis} -> "#{mode}/#{axis}"
    end
  end

  defp source_status_scope_text(source_status) do
    case {
      source_status_list_text(source_status, :scope_kinds),
      source_status_list_text(source_status, :scope_ids)
    } do
      {"", ""} -> ""
      {kind, ""} -> kind
      {"", id} -> id
      {kind, id} -> "#{kind}/#{id}"
    end
  end

  defp source_status_text(source_status, key) when is_map(source_status) do
    source_status
    |> Map.get(key)
    |> source_status_value_text()
  end

  defp source_status_text(_source_status, _key), do: ""

  defp source_status_list_text(source_status, key) when is_map(source_status) do
    source_status
    |> Map.get(key, [])
    |> List.wrap()
    |> Enum.map(&source_status_value_text/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
    |> Enum.join(",")
  end

  defp source_status_list_text(_source_status, _key), do: ""

  defp source_status_state(source_status) when is_map(source_status) do
    source_status
    |> Map.get(:state)
    |> normalize_source_status_state()
  end

  defp source_status_state(_source_status), do: nil

  defp normalize_source_status_state(state) when state in @source_status_states,
    do: state

  defp normalize_source_status_state(state) when is_binary(state),
    do: Map.get(@source_status_state_by_text, state)

  defp normalize_source_status_state(_state), do: nil

  defp source_status_state_label(nil), do: "Source"

  defp source_status_state_label(state) when is_atom(state) do
    state
    |> Atom.to_string()
    |> String.replace("_", " ")
    |> String.capitalize()
  end

  defp source_status_value_text(value) when is_atom(value), do: Atom.to_string(value)
  defp source_status_value_text(value) when is_binary(value), do: value
  defp source_status_value_text(_value), do: ""

  defp source_status_empty_reason_text(source_status) when is_map(source_status) do
    case map_value(source_status, :empty_reason) do
      nil -> ""
      value -> source_status_value_text(value)
    end
  end

  defp source_status_empty_reason_text(_source_status), do: ""

  defp warning_codes(warnings) do
    Enum.map_join(warnings, ",", & &1.code_text)
  end
end
