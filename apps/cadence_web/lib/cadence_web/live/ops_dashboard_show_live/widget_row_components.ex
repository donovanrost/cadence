defmodule CadenceWeb.OpsDashboardShowLive.WidgetRowComponents do
  @moduledoc false
  use CadenceWeb, :html

  alias CadenceWeb.OpsDashboardShowLive.WidgetDataLinkComponents
  alias CadenceWeb.OpsDashboardShowLive.WidgetDataManagementComponents

  attr :data, :map, required: true
  attr :widget, :map, required: true
  attr :placement_id, :string, required: true

  def status_matrix_table(assigns) do
    ~H"""
    <table class="table table-xs w-full">
      <thead class="sticky top-0 z-[var(--z-sticky)] bg-base-100">
        <tr class="border-base-300/70 text-[0.62rem] uppercase text-base-content/55">
          <th class="w-[34%] px-1 py-1 font-semibold">Observable</th>
          <th class="px-1 py-1 text-right font-semibold">
            {status_matrix_value_heading(@data)}
          </th>
          <th class="px-1 py-1 font-semibold">{status_matrix_quality_heading(@data)}</th>
          <th class="px-1 py-1 font-semibold">{status_matrix_state_heading(@data)}</th>
          <th class="px-1 py-1 text-right font-semibold">
            {status_matrix_time_heading(@data)}
          </th>
          <th class="w-7 px-1 py-1 text-right font-semibold">
            <span class="sr-only">Inspect</span>
          </th>
        </tr>
      </thead>
      <tbody>
        <tr
          :for={row <- @data.rows}
          class="border-base-300/50"
          data-status-matrix-row={row.observable_id}
          data-status-matrix-source={row_source(row)}
          data-status-matrix-status-policy={row_status_policy(row)}
          data-status-matrix-contact-id={Map.get(row, :contact_id)}
          data-status-matrix-contact-kind={Map.get(row, :contact_kind)}
          data-status-matrix-phase={Map.get(row, :phase)}
          data-status-matrix-resource-id={Map.get(row, :resource_id)}
          data-status-matrix-scope-kind={Map.get(row, :scope_kind)}
          data-status-matrix-link-id={Map.get(row, :link_id)}
          data-status-matrix-transport-id={Map.get(row, :transport_id)}
          data-status-matrix-source-endpoint-id={Map.get(row, :source_endpoint_id)}
          data-status-matrix-ground-station-id={Map.get(row, :ground_station_id)}
          data-status-matrix-spacecraft-id={Map.get(row, :spacecraft_id)}
          data-status-matrix-connection-state={Map.get(row, :connection_state)}
          data-status-matrix-frame-observable-id={row_context_attr(row, :frame_observable_id)}
          data-status-matrix-product-family={row_context_attr(row, :product_family)}
          data-status-matrix-supported-capability={row_context_attr(row, :supported_capability)}
          data-status-matrix-source-request-id={row_context_attr(row, :source_request_id)}
          data-status-matrix-logical-source={row_context_attr(row, :logical_source)}
          data-status-matrix-realm={row_context_attr(row, :realm)}
          data-status-matrix-data-source-id={row_context_attr(row, :data_source_id)}
          data-status-matrix-source-binding-id={row_context_attr(row, :source_binding_id)}
          data-status-matrix-replay-run-id={row_context_attr(row, :replay_run_id)}
          data-status-matrix-dataset={row_context_attr(row, :dataset)}
          data-status-matrix-query-scope-kind={row_context_attr(row, :query_scope_kind)}
          data-status-matrix-query-scope-id={row_context_attr(row, :query_scope_id)}
          data-status-matrix-query-scope-ids={row_context_attr(row, :query_scope_ids)}
          data-data-management-badges={
            WidgetDataManagementComponents.data_management_badge_codes(row)
          }
          data-data-management-warning-codes={
            WidgetDataManagementComponents.data_management_warning_codes(row)
          }
        >
          <td
            class="max-w-0 truncate px-1 py-1 font-mono text-[0.72rem]"
            title={row.observable_id}
            data-status-matrix-field="observable"
          >
            {row.label}
          </td>
          <td
            class="px-1 py-1 text-right font-mono text-[0.72rem] tabular-nums"
            data-status-matrix-field="value"
          >
            {format_matrix_value(row.value, @widget.options.precision)}
          </td>
          <td class="px-1 py-1" data-status-matrix-field="quality">
            <span class={["badge badge-xs", matrix_quality_badge_class(row)]}>
              {matrix_quality_label(row)}
            </span>
            <WidgetDataManagementComponents.data_management_badge
              :for={badge <- WidgetDataManagementComponents.data_management_badges(row)}
              badge={badge}
              class="ml-1"
            />
          </td>
          <td class="px-1 py-1" data-status-matrix-field="limit">
            <span class={["badge badge-xs", matrix_limit_badge_class(row)]}>
              {matrix_limit_label(row)}
            </span>
          </td>
          <td
            class="px-1 py-1 text-right font-mono text-[0.68rem] text-base-content/65"
            data-status-matrix-field="time"
          >
            {matrix_time_value(row)}
          </td>
          <td class="px-1 py-1 text-right">
            <WidgetDataLinkComponents.status_matrix_row_link_menu
              :if={matrix_row_inspectable?(row)}
              row={row}
              links={matrix_row_links(row)}
              placement_id={@placement_id}
            />
          </td>
        </tr>
      </tbody>
    </table>
    """
  end

  attr :data, :map, required: true
  attr :widget, :map, required: true
  attr :placement_id, :string, required: true

  def data_table(assigns) do
    ~H"""
    <table class="table table-xs w-full">
      <thead class="sticky top-0 z-[var(--z-sticky)] bg-base-100">
        <tr class="border-base-300/70 text-[0.62rem] uppercase text-base-content/55">
          <th class="w-[28%] px-1 py-1 font-semibold">Observable</th>
          <th class="px-1 py-1 font-semibold">Source</th>
          <th class="px-1 py-1 text-right font-semibold">Value</th>
          <th class="px-1 py-1 font-semibold">Unit</th>
          <th class="px-1 py-1 font-semibold">Quality</th>
          <th class="px-1 py-1 font-semibold">State</th>
          <th class="px-1 py-1 text-right font-semibold">Observed</th>
          <th class="w-7 px-1 py-1 text-right font-semibold">
            <span class="sr-only">Inspect</span>
          </th>
        </tr>
      </thead>
      <tbody>
        <tr
          :for={row <- @data.rows}
          class="border-base-300/50"
          data-data-table-row={row.observable_id}
          data-data-table-source={row_source(row)}
          data-data-table-status-policy={row_status_policy(row)}
          data-data-table-resource-id={Map.get(row, :resource_id)}
          data-data-table-scope-kind={Map.get(row, :scope_kind)}
          data-data-table-transport-id={Map.get(row, :transport_id)}
          data-data-table-source-endpoint-id={Map.get(row, :source_endpoint_id)}
          data-data-table-ground-station-id={Map.get(row, :ground_station_id)}
          data-data-table-link-id={Map.get(row, :link_id)}
          data-data-table-contact-id={Map.get(row, :contact_id)}
          data-data-table-spacecraft-id={Map.get(row, :spacecraft_id)}
          data-data-table-frame-observable-id={row_context_attr(row, :frame_observable_id)}
          data-data-table-product-family={row_context_attr(row, :product_family)}
          data-data-table-supported-capability={row_context_attr(row, :supported_capability)}
          data-data-table-source-request-id={row_context_attr(row, :source_request_id)}
          data-data-table-logical-source={row_context_attr(row, :logical_source)}
          data-data-table-realm={row_context_attr(row, :realm)}
          data-data-table-data-source-id={row_context_attr(row, :data_source_id)}
          data-data-table-source-binding-id={row_context_attr(row, :source_binding_id)}
          data-data-table-replay-run-id={row_context_attr(row, :replay_run_id)}
          data-data-table-dataset={row_context_attr(row, :dataset)}
          data-data-table-query-scope-kind={row_context_attr(row, :query_scope_kind)}
          data-data-table-query-scope-id={row_context_attr(row, :query_scope_id)}
          data-data-table-query-scope-ids={row_context_attr(row, :query_scope_ids)}
          data-data-management-badges={
            WidgetDataManagementComponents.data_management_badge_codes(row)
          }
          data-data-management-warning-codes={
            WidgetDataManagementComponents.data_management_warning_codes(row)
          }
        >
          <td
            class="max-w-0 truncate px-1 py-1 font-mono text-[0.72rem]"
            title={row.observable_id}
            data-data-table-field="observable"
          >
            {row.label || row.observable_id}
          </td>
          <td class="px-1 py-1 font-mono text-[0.68rem]" data-data-table-field="source">
            {row_source(row)}
          </td>
          <td
            class="px-1 py-1 text-right font-mono text-[0.72rem] tabular-nums"
            data-data-table-field="value"
          >
            {format_matrix_value(row.value, @widget.options.precision)}
          </td>
          <td class="px-1 py-1 font-mono text-[0.68rem]" data-data-table-field="unit">
            {Map.get(row, :unit) || "-"}
          </td>
          <td class="px-1 py-1" data-data-table-field="quality">
            <span class={["badge badge-xs", matrix_quality_badge_class(row)]}>
              {matrix_quality_label(row)}
            </span>
            <WidgetDataManagementComponents.data_management_badge
              :for={badge <- WidgetDataManagementComponents.data_management_badges(row)}
              badge={badge}
              class="ml-1"
            />
          </td>
          <td class="px-1 py-1" data-data-table-field="state">
            <span class={["badge badge-xs", matrix_limit_badge_class(row)]}>
              {matrix_limit_label(row)}
            </span>
          </td>
          <td
            class="px-1 py-1 text-right font-mono text-[0.68rem] text-base-content/65"
            data-data-table-field="time"
          >
            {format_matrix_time(Map.get(row, :receipt_time))}
          </td>
          <td class="px-1 py-1 text-right">
            <WidgetDataLinkComponents.data_table_row_link_menu
              :if={matrix_row_inspectable?(row)}
              row={row}
              links={matrix_row_links(row)}
              placement_id={@placement_id}
            />
          </td>
        </tr>
      </tbody>
    </table>
    """
  end

  attr :data, :map, required: true
  attr :placement_id, :string, required: true

  def state_timeline(assigns) do
    ~H"""
    <div class="space-y-3">
      <div
        :for={lane <- Map.get(@data, :lanes, [%{lane_key: "default", label: "State", rows: @data.rows}])}
        class="space-y-1.5"
        data-state-timeline-lane={lane.lane_key}
        data-state-timeline-lane-source={lane.source}
        data-state-timeline-lane-resource={lane.resource_id}
      >
        <div class="flex min-w-0 items-center justify-between gap-2 border-b border-base-300/60 pb-1">
          <div class="min-w-0">
            <div
              class="truncate font-mono text-[0.68rem] font-semibold text-base-content/75"
              data-state-timeline-lane-label={lane.lane_key}
            >
              {lane.label}
            </div>
            <div class="mt-0.5 flex flex-wrap gap-x-2 gap-y-0.5 font-mono text-[0.62rem] text-base-content/45">
              <span>{Map.get(lane, :observable_id)}</span>
              <span :if={Map.get(lane, :scope_kind)}>{Map.get(lane, :scope_kind)}</span>
            </div>
          </div>
          <span class="shrink-0 font-mono text-[0.62rem] text-base-content/45">
            {state_timeline_lane_count(lane)}
          </span>
        </div>
        <div class="space-y-1.5">
          <div
            :for={row <- lane.rows}
            class="grid grid-cols-[minmax(0,1fr)_auto] gap-2 rounded border border-base-300/60 bg-base-100/70 px-2 py-1.5"
            data-state-timeline-row={row.row_id}
            data-state-timeline-observable={row.observable_id}
            data-state-timeline-state={state_timeline_text(Map.get(row, :normalized_state))}
            data-state-timeline-limit-event-id={Map.get(row, :limit_event_id)}
            data-state-timeline-lane-row={lane.lane_key}
            data-state-timeline-source-request-id={row_context_attr(row, :source_request_id)}
            data-state-timeline-logical-source={row_context_attr(row, :logical_source)}
            data-state-timeline-realm={row_context_attr(row, :realm)}
            data-state-timeline-data-source-id={row_context_attr(row, :data_source_id)}
            data-state-timeline-source-binding-id={row_context_attr(row, :source_binding_id)}
            data-state-timeline-replay-run-id={row_context_attr(row, :replay_run_id)}
            data-state-timeline-dataset={row_context_attr(row, :dataset)}
            data-state-timeline-query-scope-kind={row_context_attr(row, :query_scope_kind)}
            data-state-timeline-query-scope-id={row_context_attr(row, :query_scope_id)}
            data-state-timeline-query-scope-ids={row_context_attr(row, :query_scope_ids)}
            data-data-management-badges={
              WidgetDataManagementComponents.data_management_badge_codes(row)
            }
          >
            <div class="min-w-0">
              <div class="flex flex-wrap items-center gap-1.5">
                <span class="truncate font-mono text-[0.68rem] text-base-content/60">
                  {state_timeline_title(row)}
                </span>
                <span class={["badge badge-xs", state_timeline_badge_class(row)]}>
                  {state_timeline_label(row)}
                </span>
                <span :if={Map.get(row, :violation?)} class="badge badge-error badge-xs">
                  Violation
                </span>
                <WidgetDataManagementComponents.data_management_badge
                  :for={badge <- WidgetDataManagementComponents.data_management_badges(row)}
                  badge={badge}
                  class="ml-1"
                />
              </div>
              <div class="mt-1 h-2 overflow-hidden rounded bg-base-300/70">
                <div class={["h-full rounded", state_timeline_bar_class(row)]}></div>
              </div>
              <div class="mt-1 flex flex-wrap gap-x-2 gap-y-0.5 font-mono text-[0.66rem] text-base-content/55">
                <span>{state_timeline_range(row)}</span>
                <span :if={state_timeline_duration(row)}>{state_timeline_duration(row)}</span>
                <span :if={Map.get(row, :sample_id)}>{Map.get(row, :sample_id)}</span>
                <span :if={state_timeline_resource_id(row)}>
                  {state_timeline_resource_id(row)}
                </span>
                <span :if={Map.get(row, :limit_definition_id)}>
                  {state_timeline_definition_label(row)}
                </span>
              </div>
            </div>
            <div class="self-start text-right">
              <WidgetDataLinkComponents.state_timeline_row_link_menu
                :if={Map.get(row, :links, []) != []}
                row={row}
                links={Map.get(row, :links, [])}
                placement_id={@placement_id}
              />
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  attr :data, :map, required: true
  attr :placement_id, :string, required: true

  def event_timeline(assigns) do
    ~H"""
    <div class="space-y-1">
      <div
        :for={row <- @data.rows}
        class="grid grid-cols-[auto_minmax(0,1fr)_auto] gap-2 rounded border border-base-300/60 bg-base-100/70 px-2 py-1.5"
        data-event-timeline-row={row.row_id}
        data-event-timeline-source-request-id={row_context_attr(row, :source_request_id)}
        data-event-timeline-logical-source={row_context_attr(row, :logical_source)}
        data-event-timeline-realm={row_context_attr(row, :realm)}
        data-event-timeline-data-source-id={row_context_attr(row, :data_source_id)}
        data-event-timeline-source-binding-id={row_context_attr(row, :source_binding_id)}
        data-event-timeline-replay-run-id={row_context_attr(row, :replay_run_id)}
        data-event-timeline-dataset={row_context_attr(row, :dataset)}
        data-event-timeline-category={event_timeline_text(Map.get(row, :category))}
        data-event-timeline-kind={event_timeline_text(Map.get(row, :kind))}
        data-event-timeline-severity={event_timeline_text(Map.get(row, :severity))}
        data-event-timeline-record-id={Map.get(row, :source_record_id)}
        data-event-timeline-target={event_timeline_text(Map.get(row, :target))}
        data-event-timeline-target-id={Map.get(row, :target_id)}
        data-event-timeline-complete-through={
          event_timeline_datetime_attr(Map.get(row, :complete_through))
        }
        data-event-timeline-latest-receipt-time={
          event_timeline_datetime_attr(Map.get(row, :latest_receipt_time))
        }
        data-event-timeline-confidence={event_timeline_text(Map.get(row, :confidence))}
        data-event-timeline-reason={event_timeline_text(Map.get(row, :reason))}
        data-data-management-badges={WidgetDataManagementComponents.data_management_badge_codes(row)}
      >
        <div class="pt-0.5">
          <span class={["block h-2.5 w-2.5 rounded-full", event_timeline_dot_class(row)]}>
          </span>
        </div>
        <div class="min-w-0">
          <div class="flex flex-wrap items-center gap-1.5">
            <span class="font-mono text-[0.66rem] uppercase text-base-content/55">
              {event_timeline_text(Map.get(row, :category))}
            </span>
            <span class={["badge badge-xs", event_timeline_badge_class(row)]}>
              {event_timeline_badge_label(row)}
            </span>
            <WidgetDataManagementComponents.data_management_badge
              :for={badge <- WidgetDataManagementComponents.data_management_badges(row)}
              badge={badge}
              class="ml-1"
            />
            <span class="font-mono text-[0.66rem] text-base-content/50">
              {format_event_timeline_time(row)}
            </span>
          </div>
          <div
            class="truncate text-sm font-medium"
            title={Map.get(row, :title)}
            data-event-timeline-title
          >
            {Map.get(row, :title)}
          </div>
          <div class="mt-0.5 flex flex-wrap gap-x-2 gap-y-0.5 font-mono text-[0.66rem] text-base-content/55">
            <span :if={Map.get(row, :source_record_id)}>
              {Map.get(row, :source_record_id)}
            </span>
            <span :if={Map.get(row, :logical_source)}>
              {event_timeline_text(Map.get(row, :logical_source))}
            </span>
            <span :if={Map.get(row, :data_source_id)}>
              {Map.get(row, :data_source_id)}
            </span>
            <span :if={Map.get(row, :source_binding_id)}>
              {Map.get(row, :source_binding_id)}
            </span>
            <span :if={Map.get(row, :realm)}>
              {event_timeline_text(Map.get(row, :realm))}
            </span>
            <span :if={Map.get(row, :dataset)}>
              {Map.get(row, :dataset)}
            </span>
            <span :if={event_timeline_duration(row)}>
              {event_timeline_duration(row)}
            </span>
            <span :if={Map.get(row, :complete_through)}>
              complete {format_event_timeline_time(%{occurred_at: Map.get(row, :complete_through)})}
            </span>
            <span :if={Map.get(row, :latest_receipt_time)}>
              latest {format_event_timeline_time(%{occurred_at: Map.get(row, :latest_receipt_time)})}
            </span>
            <span :if={Map.get(row, :confidence)}>
              {event_timeline_text(Map.get(row, :confidence))}
            </span>
            <span :if={Map.get(row, :reason)}>
              {event_timeline_text(Map.get(row, :reason))}
            </span>
          </div>
        </div>
        <div class="self-start text-right">
          <WidgetDataLinkComponents.event_timeline_row_link_menu
            :if={Map.get(row, :links, []) != []}
            row={row}
            links={Map.get(row, :links, [])}
            placement_id={@placement_id}
          />
        </div>
      </div>
    </div>
    """
  end

  defp format_matrix_value(value, precision) when is_float(value),
    do: :erlang.float_to_binary(value, decimals: precision)

  defp format_matrix_value(value, _precision) when is_integer(value), do: Integer.to_string(value)
  defp format_matrix_value(value, _precision) when is_binary(value), do: value
  defp format_matrix_value(nil, _precision), do: "-"
  defp format_matrix_value(value, _precision) when is_atom(value), do: matrix_state_label(value)
  defp format_matrix_value(value, _precision), do: inspect(value)

  defp format_matrix_time(%DateTime{} = datetime), do: Calendar.strftime(datetime, "%H:%M:%S")
  defp format_matrix_time(_datetime), do: "-"

  defp state_timeline_range(%{starts_at: %DateTime{} = starts_at, ends_at: %DateTime{} = ends_at}) do
    "#{format_state_timeline_time(starts_at)} - #{format_state_timeline_time(ends_at)}"
  end

  defp state_timeline_range(%{starts_at: %DateTime{} = starts_at}) do
    "#{format_state_timeline_time(starts_at)} - latest"
  end

  defp state_timeline_range(_row), do: "-"

  defp state_timeline_duration(%{
         starts_at: %DateTime{} = starts_at,
         ends_at: %DateTime{} = ends_at
       }) do
    seconds = max(DateTime.diff(ends_at, starts_at, :second), 0)

    cond do
      seconds >= 3600 -> "#{div(seconds, 3600)}h #{div(rem(seconds, 3600), 60)}m"
      seconds >= 60 -> "#{div(seconds, 60)}m"
      true -> "#{seconds}s"
    end
  end

  defp state_timeline_duration(_row), do: nil

  defp format_state_timeline_time(%DateTime{} = datetime),
    do: Calendar.strftime(datetime, "%H:%M:%S")

  defp state_timeline_title(row) do
    Map.get(row, :label) || Map.get(row, :observable_id)
  end

  defp state_timeline_resource_id(row) do
    resource_id = Map.get(row, :resource_id)

    if resource_id && resource_id != Map.get(row, :sample_id) do
      resource_id
    end
  end

  defp state_timeline_lane_count(%{rows: rows}) do
    case length(rows) do
      1 -> "1 transition"
      count -> "#{count} transitions"
    end
  end

  defp state_timeline_label(%{normalized_state: state}), do: state_timeline_text(state)
  defp state_timeline_label(_row), do: "State"

  defp state_timeline_definition_label(row) do
    case Map.get(row, :limit_definition_version) do
      nil -> Map.get(row, :limit_definition_id)
      version -> "#{Map.get(row, :limit_definition_id)} v#{version}"
    end
  end

  defp state_timeline_badge_class(%{normalized_state: state}), do: matrix_limit_badge_class(state)
  defp state_timeline_badge_class(_row), do: "badge-ghost"

  defp state_timeline_bar_class(%{normalized_state: state}) do
    case matrix_limit_badge_class(state) do
      "badge-error" -> "bg-error"
      "badge-warning" -> "bg-warning"
      "badge-success" -> "bg-success"
      "badge-info" -> "bg-info"
      _class -> "bg-base-content/30"
    end
  end

  defp state_timeline_text(nil), do: "-"

  defp state_timeline_text(value) do
    value
    |> to_string()
    |> String.replace("_", " ")
    |> String.capitalize()
  end

  defp format_event_timeline_time(%{occurred_at: %DateTime{} = datetime}) do
    Calendar.strftime(datetime, "%H:%M:%S")
  end

  defp format_event_timeline_time(%{starts_at: %DateTime{} = datetime}) do
    Calendar.strftime(datetime, "%H:%M:%S")
  end

  defp format_event_timeline_time(_row), do: "-"

  defp event_timeline_datetime_attr(%DateTime{} = datetime), do: DateTime.to_iso8601(datetime)
  defp event_timeline_datetime_attr(_datetime), do: nil

  defp event_timeline_duration(%{
         starts_at: %DateTime{} = starts_at,
         ends_at: %DateTime{} = ends_at
       }) do
    seconds = max(DateTime.diff(ends_at, starts_at, :second), 0)

    cond do
      seconds >= 3600 -> "#{div(seconds, 3600)}h #{div(rem(seconds, 3600), 60)}m"
      seconds >= 60 -> "#{div(seconds, 60)}m"
      true -> "#{seconds}s"
    end
  end

  defp event_timeline_duration(_row), do: nil

  defp event_timeline_badge_label(%{status: status}) when not is_nil(status),
    do: event_timeline_text(status)

  defp event_timeline_badge_label(%{kind: kind}) when not is_nil(kind),
    do: event_timeline_text(kind)

  defp event_timeline_badge_label(%{severity: severity}) when not is_nil(severity),
    do: event_timeline_text(severity)

  defp event_timeline_badge_label(_row), do: "Event"

  defp event_timeline_badge_class(%{severity: severity}), do: event_timeline_badge_class(severity)
  defp event_timeline_badge_class(:critical), do: "badge-error"
  defp event_timeline_badge_class("critical"), do: "badge-error"
  defp event_timeline_badge_class(:error), do: "badge-error"
  defp event_timeline_badge_class("error"), do: "badge-error"
  defp event_timeline_badge_class(:warning), do: "badge-warning"
  defp event_timeline_badge_class("warning"), do: "badge-warning"
  defp event_timeline_badge_class(:warn), do: "badge-warning"
  defp event_timeline_badge_class("warn"), do: "badge-warning"
  defp event_timeline_badge_class(:healthy), do: "badge-success"
  defp event_timeline_badge_class("healthy"), do: "badge-success"
  defp event_timeline_badge_class(:info), do: "badge-info"
  defp event_timeline_badge_class("info"), do: "badge-info"
  defp event_timeline_badge_class(_severity), do: "badge-ghost"

  defp event_timeline_dot_class(%{severity: severity}) do
    case event_timeline_badge_class(severity) do
      "badge-error" -> "bg-error"
      "badge-warning" -> "bg-warning"
      "badge-success" -> "bg-success"
      "badge-info" -> "bg-info"
      _class -> "bg-base-content/30"
    end
  end

  defp event_timeline_text(nil), do: "-"

  defp event_timeline_text(value) do
    value
    |> to_string()
    |> String.replace("_", " ")
    |> String.capitalize()
  end

  defp status_matrix_value_heading(data) do
    cond do
      contact_phase_matrix?(data) -> "Phase"
      connection_state_matrix?(data) -> "State"
      metric_value_matrix?(data) -> "Value"
      true -> "Value"
    end
  end

  defp status_matrix_quality_heading(data) do
    cond do
      contact_phase_matrix?(data) -> "Kind"
      connection_state_matrix?(data) -> "Adapter"
      metric_value_matrix?(data) -> "Unit"
      true -> "Quality"
    end
  end

  defp status_matrix_state_heading(data) do
    if operational_status_matrix?(data), do: "Status", else: "Limit"
  end

  defp status_matrix_time_heading(data) do
    cond do
      contact_phase_matrix?(data) -> "Contact"
      connection_state_matrix?(data) -> "Target"
      metric_value_matrix?(data) -> "Observed"
      true -> "Time"
    end
  end

  defp operational_status_matrix?(data) do
    contact_phase_matrix?(data) or connection_state_matrix?(data) or metric_value_matrix?(data)
  end

  defp contact_phase_matrix?(%{rows: rows}) when is_list(rows) do
    Enum.any?(rows, &(Map.get(&1, :status_policy) == :contact_phase))
  end

  defp contact_phase_matrix?(_data), do: false

  defp connection_state_matrix?(%{rows: rows}) when is_list(rows) do
    Enum.any?(rows, &(Map.get(&1, :status_policy) == :connection_state))
  end

  defp connection_state_matrix?(_data), do: false

  defp metric_value_matrix?(%{rows: rows}) when is_list(rows) do
    Enum.any?(rows, &(Map.get(&1, :status_policy) == :metric_value))
  end

  defp metric_value_matrix?(_data), do: false

  defp row_source(row), do: row |> Map.get(:source, :telemetry) |> to_string()

  defp row_status_policy(row), do: row |> Map.get(:status_policy, :limit_state) |> to_string()

  defp matrix_time_value(%{status_policy: :contact_phase, contact_id: contact_id}),
    do: contact_id || "-"

  defp matrix_time_value(%{status_policy: :connection_state, resource_id: resource_id}),
    do: resource_id || "-"

  defp matrix_time_value(row), do: format_matrix_time(Map.get(row, :receipt_time))

  defp matrix_quality_label(%{status_policy: :contact_phase, contact_kind: contact_kind}),
    do: matrix_state_label(contact_kind)

  defp matrix_quality_label(%{status_policy: :connection_state, adapter_key: adapter_key}),
    do: matrix_state_label(adapter_key)

  defp matrix_quality_label(%{status_policy: :metric_value, unit: unit}), do: unit || "-"

  defp matrix_quality_label(row), do: matrix_state_label(Map.get(row, :quality_state))

  defp matrix_limit_label(%{normalized_state: nil, limit_state: nil}), do: "None"
  defp matrix_limit_label(%{normalized_state: state}), do: matrix_state_label(state)
  defp matrix_limit_label(%{limit_state: state}), do: matrix_state_label(state)

  defp matrix_state_label(nil), do: "None"

  defp matrix_state_label(value) do
    value
    |> to_string()
    |> String.replace("_", " ")
    |> String.capitalize()
  end

  defp matrix_limit_badge_class(%{status_policy: :contact_phase, phase: phase}),
    do: contact_phase_badge_class(phase)

  defp matrix_limit_badge_class(%{
         status_policy: :connection_state,
         connection_state: connection_state
       }),
       do: connection_state_badge_class(connection_state)

  defp matrix_limit_badge_class(%{status_policy: :metric_value, normalized_state: state}),
    do: metric_value_badge_class(state)

  defp matrix_limit_badge_class(%{normalized_state: state}), do: matrix_limit_badge_class(state)
  defp matrix_limit_badge_class(%{limit_state: state}), do: matrix_limit_badge_class(state)
  defp matrix_limit_badge_class(:red), do: "badge-error"
  defp matrix_limit_badge_class("red"), do: "badge-error"
  defp matrix_limit_badge_class(:yellow), do: "badge-warning"
  defp matrix_limit_badge_class("yellow"), do: "badge-warning"
  defp matrix_limit_badge_class(:blue), do: "badge-info"
  defp matrix_limit_badge_class("blue"), do: "badge-info"
  defp matrix_limit_badge_class(:green), do: "badge-success"
  defp matrix_limit_badge_class("green"), do: "badge-success"
  defp matrix_limit_badge_class(_state), do: "badge-ghost"

  defp matrix_quality_badge_class(%{status_policy: :contact_phase}), do: "badge-outline"
  defp matrix_quality_badge_class(%{status_policy: :connection_state}), do: "badge-outline"
  defp matrix_quality_badge_class(%{status_policy: :metric_value}), do: "badge-outline"
  defp matrix_quality_badge_class(%{quality_state: state}), do: matrix_quality_badge_class(state)
  defp matrix_quality_badge_class(:bad), do: "badge-error"
  defp matrix_quality_badge_class("bad"), do: "badge-error"
  defp matrix_quality_badge_class(:suspect), do: "badge-warning"
  defp matrix_quality_badge_class("suspect"), do: "badge-warning"
  defp matrix_quality_badge_class(:good), do: "badge-success"
  defp matrix_quality_badge_class("good"), do: "badge-success"
  defp matrix_quality_badge_class(_state), do: "badge-ghost"

  defp contact_phase_badge_class(phase)
       when phase in [:active, "active"],
       do: "badge-success"

  defp contact_phase_badge_class(phase)
       when phase in [:scheduled, "scheduled"],
       do: "badge-info"

  defp contact_phase_badge_class(phase)
       when phase in [:completed, "completed"],
       do: "badge-ghost"

  defp contact_phase_badge_class(phase)
       when phase in [:stopped, "stopped", :expired, "expired", :canceled, "canceled"],
       do: "badge-warning"

  defp contact_phase_badge_class(_phase), do: "badge-ghost"

  defp connection_state_badge_class(state)
       when state in [:connected, "connected"],
       do: "badge-success"

  defp connection_state_badge_class(state)
       when state in [:connecting, "connecting"],
       do: "badge-info"

  defp connection_state_badge_class(state)
       when state in [:degraded, "degraded"],
       do: "badge-warning"

  defp connection_state_badge_class(state)
       when state in [:disconnected, "disconnected"],
       do: "badge-error"

  defp connection_state_badge_class(_state), do: "badge-ghost"

  defp metric_value_badge_class(state) when state in [:observed, "observed"], do: "badge-success"
  defp metric_value_badge_class(state) when state in [:no_data, "no_data"], do: "badge-ghost"
  defp metric_value_badge_class(_state), do: "badge-ghost"

  defp matrix_row_links(%{links: links}) when is_list(links), do: links
  defp matrix_row_links(_row), do: []

  defp matrix_row_inspectable?(row) do
    matrix_row_links(row) != [] or present?(Map.get(row, :frame_observable_id))
  end

  defp row_context_attr(row, key) do
    row
    |> Map.get(key)
    |> context_attr()
  end

  defp context_attr(nil), do: nil
  defp context_attr(values) when is_list(values), do: Enum.map_join(values, ",", &context_attr/1)
  defp context_attr(value) when is_atom(value), do: Atom.to_string(value)
  defp context_attr(value), do: to_string(value)

  defp present?(nil), do: false
  defp present?(""), do: false
  defp present?(_value), do: true
end
