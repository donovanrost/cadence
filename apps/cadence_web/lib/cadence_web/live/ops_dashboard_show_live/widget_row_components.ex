defmodule CadenceWeb.OpsDashboardShowLive.WidgetRowComponents do
  @moduledoc false
  use CadenceWeb, :html

  alias CadenceWeb.OpsDashboardShowLive.WidgetDataLinkComponents
  alias CadenceWeb.OpsDashboardShowLive.WidgetDataManagementComponents

  attr(:data, :map, required: true)
  attr(:widget, :map, required: true)
  attr(:placement_id, :string, required: true)

  def status_matrix_table(assigns) do
    assigns =
      assign(
        assigns,
        :presentation,
        status_matrix_presentation(assigns.data, assigns.widget, assigns.placement_id)
      )

    ~H"""
    <.vue
      id={@presentation.component_id}
      v-component="WidgetRows"
      presentation={@presentation}
      v-ssr={false}
      class="contents"
    />
    """
  end

  attr(:data, :map, required: true)
  attr(:widget, :map, required: true)
  attr(:placement_id, :string, required: true)

  def data_table(assigns) do
    assigns =
      assign(
        assigns,
        :presentation,
        data_table_presentation(assigns.data, assigns.widget, assigns.placement_id)
      )

    ~H"""
    <.vue
      id={@presentation.component_id}
      v-component="WidgetRows"
      presentation={@presentation}
      v-ssr={false}
      class="contents"
    />
    """
  end

  attr(:data, :map, required: true)
  attr(:placement_id, :string, required: true)

  def state_timeline(assigns) do
    assigns =
      assign(
        assigns,
        :presentation,
        state_timeline_presentation(assigns.data, assigns.placement_id)
      )

    ~H"""
    <.vue
      id={@presentation.component_id}
      v-component="WidgetRows"
      presentation={@presentation}
      v-ssr={false}
      class="contents"
    />
    """
  end

  attr(:data, :map, required: true)
  attr(:placement_id, :string, required: true)

  def event_timeline(assigns) do
    assigns =
      assign(
        assigns,
        :presentation,
        event_timeline_presentation(assigns.data, assigns.placement_id)
      )

    ~H"""
    <.vue
      id={@presentation.component_id}
      v-component="WidgetRows"
      presentation={@presentation}
      v-ssr={false}
      class="contents"
    />
    """
  end

  def status_matrix_presentation(data, widget, placement_id) do
    %{
      kind: "status_matrix",
      component_id: "widget-rows-status-matrix-#{placement_id}-component",
      root: %{class: "table table-xs w-full"},
      head: %{
        class: "sticky top-0 z-[var(--z-sticky)] bg-base-100",
        row_class: "border-base-300/70 text-[0.62rem] uppercase text-base-content/55",
        cells: [
          table_heading("observable", "w-[34%] px-1 py-1 font-semibold", "Observable"),
          table_heading(
            "value",
            "px-1 py-1 text-right font-semibold",
            status_matrix_value_heading(data)
          ),
          table_heading(
            "quality",
            "px-1 py-1 font-semibold",
            status_matrix_quality_heading(data)
          ),
          table_heading(
            "state",
            "px-1 py-1 font-semibold",
            status_matrix_state_heading(data)
          ),
          table_heading(
            "time",
            "px-1 py-1 text-right font-semibold",
            status_matrix_time_heading(data)
          ),
          table_heading("inspect", "w-7 px-1 py-1 text-right font-semibold", "Inspect", "sr-only")
        ]
      },
      rows:
        data.rows
        |> Enum.with_index()
        |> Enum.map(fn {row, index} ->
          %{
            key: row_key("status-matrix", placement_id, index, row.observable_id),
            class: "border-base-300/50",
            attrs: status_matrix_row_attrs(row),
            cells: status_matrix_cells(row, widget.options.precision, placement_id)
          }
        end)
    }
  end

  defp status_matrix_row_attrs(row) do
    compact_attrs(%{
      "data-status-matrix-row" => direct_attr_value(row.observable_id),
      "data-status-matrix-source" => direct_attr_value(row_source(row)),
      "data-status-matrix-status-policy" => direct_attr_value(row_status_policy(row)),
      "data-status-matrix-contact-id" => direct_attr_value(Map.get(row, :contact_id)),
      "data-status-matrix-contact-kind" => direct_attr_value(Map.get(row, :contact_kind)),
      "data-status-matrix-phase" => direct_attr_value(Map.get(row, :phase)),
      "data-status-matrix-resource-id" => direct_attr_value(Map.get(row, :resource_id)),
      "data-status-matrix-scope-kind" => direct_attr_value(Map.get(row, :scope_kind)),
      "data-status-matrix-link-id" => direct_attr_value(Map.get(row, :link_id)),
      "data-status-matrix-transport-id" => direct_attr_value(Map.get(row, :transport_id)),
      "data-status-matrix-source-endpoint-id" =>
        direct_attr_value(Map.get(row, :source_endpoint_id)),
      "data-status-matrix-ground-station-id" =>
        direct_attr_value(Map.get(row, :ground_station_id)),
      "data-status-matrix-spacecraft-id" => direct_attr_value(Map.get(row, :spacecraft_id)),
      "data-status-matrix-connection-state" => direct_attr_value(Map.get(row, :connection_state)),
      "data-status-matrix-frame-observable-id" =>
        direct_attr_value(row_context_attr(row, :frame_observable_id)),
      "data-status-matrix-product-family" =>
        direct_attr_value(row_context_attr(row, :product_family)),
      "data-status-matrix-supported-capability" =>
        direct_attr_value(row_context_attr(row, :supported_capability)),
      "data-status-matrix-source-request-id" =>
        direct_attr_value(row_context_attr(row, :source_request_id)),
      "data-status-matrix-logical-source" =>
        direct_attr_value(row_context_attr(row, :logical_source)),
      "data-status-matrix-realm" => direct_attr_value(row_context_attr(row, :realm)),
      "data-status-matrix-data-source-id" =>
        direct_attr_value(row_context_attr(row, :data_source_id)),
      "data-status-matrix-source-binding-id" =>
        direct_attr_value(row_context_attr(row, :source_binding_id)),
      "data-status-matrix-replay-run-id" =>
        direct_attr_value(row_context_attr(row, :replay_run_id)),
      "data-status-matrix-dataset" => direct_attr_value(row_context_attr(row, :dataset)),
      "data-status-matrix-query-scope-kind" =>
        direct_attr_value(row_context_attr(row, :query_scope_kind)),
      "data-status-matrix-query-scope-id" =>
        direct_attr_value(row_context_attr(row, :query_scope_id)),
      "data-status-matrix-query-scope-ids" =>
        direct_attr_value(row_context_attr(row, :query_scope_ids)),
      "data-data-management-badges" =>
        direct_attr_value(WidgetDataManagementComponents.data_management_badge_codes(row)),
      "data-data-management-warning-codes" =>
        direct_attr_value(WidgetDataManagementComponents.data_management_warning_codes(row))
    })
  end

  defp status_matrix_cells(row, precision, placement_id) do
    [
      table_text_cell(
        "observable",
        "max-w-0 truncate px-1 py-1 font-mono text-[0.72rem]",
        %{
          "title" => direct_attr_value(row.observable_id),
          "data-status-matrix-field" => "observable"
        },
        row.label
      ),
      table_text_cell(
        "value",
        "px-1 py-1 text-right font-mono text-[0.72rem] tabular-nums",
        %{"data-status-matrix-field" => "value"},
        format_matrix_value(row.value, precision)
      ),
      table_badge_cell(
        "quality",
        "px-1 py-1",
        %{"data-status-matrix-field" => "quality"},
        [basic_badge(matrix_quality_label(row), matrix_quality_badge_class(row))] ++
          data_management_badge_presentations(row)
      ),
      table_badge_cell(
        "limit",
        "px-1 py-1",
        %{"data-status-matrix-field" => "limit"},
        [basic_badge(matrix_limit_label(row), matrix_limit_badge_class(row))]
      ),
      table_text_cell(
        "time",
        "px-1 py-1 text-right font-mono text-[0.68rem] text-base-content/65",
        %{"data-status-matrix-field" => "time"},
        matrix_time_value(row)
      ),
      table_link_cell(
        "actions",
        "px-1 py-1 text-right",
        if(matrix_row_inspectable?(row),
          do:
            WidgetDataLinkComponents.status_matrix_row_link_presentation(
              row,
              matrix_row_links(row),
              placement_id
            )
        )
      )
    ]
  end

  def data_table_presentation(data, widget, placement_id) do
    %{
      kind: "data_table",
      component_id: "widget-rows-data-table-#{placement_id}-component",
      root: %{class: "table table-xs w-full"},
      head: %{
        class: "sticky top-0 z-[var(--z-sticky)] bg-base-100",
        row_class: "border-base-300/70 text-[0.62rem] uppercase text-base-content/55",
        cells: [
          table_heading("observable", "w-[28%] px-1 py-1 font-semibold", "Observable"),
          table_heading("source", "px-1 py-1 font-semibold", "Source"),
          table_heading("value", "px-1 py-1 text-right font-semibold", "Value"),
          table_heading("unit", "px-1 py-1 font-semibold", "Unit"),
          table_heading("quality", "px-1 py-1 font-semibold", "Quality"),
          table_heading("state", "px-1 py-1 font-semibold", "State"),
          table_heading("time", "px-1 py-1 text-right font-semibold", "Observed"),
          table_heading("inspect", "w-7 px-1 py-1 text-right font-semibold", "Inspect", "sr-only")
        ]
      },
      rows:
        data.rows
        |> Enum.with_index()
        |> Enum.map(fn {row, index} ->
          %{
            key: row_key("data-table", placement_id, index, row.observable_id),
            class: "border-base-300/50",
            attrs: data_table_row_attrs(row),
            cells: data_table_cells(row, widget.options.precision, placement_id)
          }
        end)
    }
  end

  defp data_table_row_attrs(row) do
    compact_attrs(%{
      "data-data-table-row" => direct_attr_value(row.observable_id),
      "data-data-table-source" => direct_attr_value(row_source(row)),
      "data-data-table-status-policy" => direct_attr_value(row_status_policy(row)),
      "data-data-table-resource-id" => direct_attr_value(Map.get(row, :resource_id)),
      "data-data-table-scope-kind" => direct_attr_value(Map.get(row, :scope_kind)),
      "data-data-table-transport-id" => direct_attr_value(Map.get(row, :transport_id)),
      "data-data-table-source-endpoint-id" =>
        direct_attr_value(Map.get(row, :source_endpoint_id)),
      "data-data-table-ground-station-id" => direct_attr_value(Map.get(row, :ground_station_id)),
      "data-data-table-link-id" => direct_attr_value(Map.get(row, :link_id)),
      "data-data-table-contact-id" => direct_attr_value(Map.get(row, :contact_id)),
      "data-data-table-spacecraft-id" => direct_attr_value(Map.get(row, :spacecraft_id)),
      "data-data-table-frame-observable-id" =>
        direct_attr_value(row_context_attr(row, :frame_observable_id)),
      "data-data-table-product-family" =>
        direct_attr_value(row_context_attr(row, :product_family)),
      "data-data-table-supported-capability" =>
        direct_attr_value(row_context_attr(row, :supported_capability)),
      "data-data-table-source-request-id" =>
        direct_attr_value(row_context_attr(row, :source_request_id)),
      "data-data-table-logical-source" =>
        direct_attr_value(row_context_attr(row, :logical_source)),
      "data-data-table-realm" => direct_attr_value(row_context_attr(row, :realm)),
      "data-data-table-data-source-id" =>
        direct_attr_value(row_context_attr(row, :data_source_id)),
      "data-data-table-source-binding-id" =>
        direct_attr_value(row_context_attr(row, :source_binding_id)),
      "data-data-table-replay-run-id" => direct_attr_value(row_context_attr(row, :replay_run_id)),
      "data-data-table-dataset" => direct_attr_value(row_context_attr(row, :dataset)),
      "data-data-table-query-scope-kind" =>
        direct_attr_value(row_context_attr(row, :query_scope_kind)),
      "data-data-table-query-scope-id" =>
        direct_attr_value(row_context_attr(row, :query_scope_id)),
      "data-data-table-query-scope-ids" =>
        direct_attr_value(row_context_attr(row, :query_scope_ids)),
      "data-data-management-badges" =>
        direct_attr_value(WidgetDataManagementComponents.data_management_badge_codes(row)),
      "data-data-management-warning-codes" =>
        direct_attr_value(WidgetDataManagementComponents.data_management_warning_codes(row))
    })
  end

  defp data_table_cells(row, precision, placement_id) do
    [
      table_text_cell(
        "observable",
        "max-w-0 truncate px-1 py-1 font-mono text-[0.72rem]",
        %{
          "title" => direct_attr_value(row.observable_id),
          "data-data-table-field" => "observable"
        },
        row.label || row.observable_id
      ),
      table_text_cell(
        "source",
        "px-1 py-1 font-mono text-[0.68rem]",
        %{"data-data-table-field" => "source"},
        row_source(row)
      ),
      table_text_cell(
        "value",
        "px-1 py-1 text-right font-mono text-[0.72rem] tabular-nums",
        %{"data-data-table-field" => "value"},
        format_matrix_value(row.value, precision)
      ),
      table_text_cell(
        "unit",
        "px-1 py-1 font-mono text-[0.68rem]",
        %{"data-data-table-field" => "unit"},
        Map.get(row, :unit) || "-"
      ),
      table_badge_cell(
        "quality",
        "px-1 py-1",
        %{"data-data-table-field" => "quality"},
        [basic_badge(matrix_quality_label(row), matrix_quality_badge_class(row))] ++
          data_management_badge_presentations(row)
      ),
      table_badge_cell(
        "state",
        "px-1 py-1",
        %{"data-data-table-field" => "state"},
        [basic_badge(matrix_limit_label(row), matrix_limit_badge_class(row))]
      ),
      table_text_cell(
        "time",
        "px-1 py-1 text-right font-mono text-[0.68rem] text-base-content/65",
        %{"data-data-table-field" => "time"},
        format_matrix_time(Map.get(row, :receipt_time))
      ),
      table_link_cell(
        "actions",
        "px-1 py-1 text-right",
        if(matrix_row_inspectable?(row),
          do:
            WidgetDataLinkComponents.data_table_row_link_presentation(
              row,
              matrix_row_links(row),
              placement_id
            )
        )
      )
    ]
  end

  def state_timeline_presentation(data, placement_id) do
    lanes = Map.get(data, :lanes, [%{lane_key: "default", label: "State", rows: data.rows}])

    %{
      kind: "state_timeline",
      component_id: "widget-rows-state-timeline-#{placement_id}-component",
      root: %{class: "space-y-3"},
      lanes:
        lanes
        |> Enum.with_index()
        |> Enum.map(fn {lane, lane_index} ->
          %{
            key: row_key("state-lane", placement_id, lane_index, lane.lane_key),
            class: "space-y-1.5",
            attrs:
              compact_attrs(%{
                "data-state-timeline-lane" => direct_attr_value(lane.lane_key),
                "data-state-timeline-lane-source" => direct_attr_value(Map.get(lane, :source)),
                "data-state-timeline-lane-resource" =>
                  direct_attr_value(Map.get(lane, :resource_id))
              }),
            heading: state_timeline_lane_heading(lane),
            rows_class: "space-y-1.5",
            rows:
              lane.rows
              |> Enum.with_index()
              |> Enum.map(fn {row, row_index} ->
                state_timeline_row_presentation(
                  row,
                  lane,
                  placement_id,
                  lane_index,
                  row_index
                )
              end)
          }
        end)
    }
  end

  defp state_timeline_lane_heading(lane) do
    %{
      class: "flex min-w-0 items-center justify-between gap-2 border-b border-base-300/60 pb-1",
      label_container_class: "min-w-0",
      label: %{
        class: "truncate font-mono text-[0.68rem] font-semibold text-base-content/75",
        attrs: %{"data-state-timeline-lane-label" => direct_attr_value(lane.lane_key)},
        text: rendered_body(lane.label)
      },
      metadata_class:
        "mt-0.5 flex flex-wrap gap-x-2 gap-y-0.5 font-mono text-[0.62rem] text-base-content/45",
      metadata:
        [rendered_body(Map.get(lane, :observable_id))]
        |> append_if(Map.get(lane, :scope_kind), Map.get(lane, :scope_kind)),
      count: %{
        class: "shrink-0 font-mono text-[0.62rem] text-base-content/45",
        text: state_timeline_lane_count(lane)
      }
    }
  end

  defp state_timeline_row_presentation(
         row,
         lane,
         placement_id,
         lane_index,
         row_index
       ) do
    links = Map.get(row, :links, [])

    %{
      key: row_key("state-row-#{lane_index}", placement_id, row_index, row.row_id),
      class:
        "grid grid-cols-[minmax(0,1fr)_auto] gap-2 rounded border border-base-300/60 bg-base-100/70 px-2 py-1.5",
      attrs: state_timeline_row_attrs(row, lane),
      content_class: "min-w-0",
      heading_class: "flex flex-wrap items-center gap-1.5",
      title: %{
        class: "truncate font-mono text-[0.68rem] text-base-content/60",
        text: rendered_body(state_timeline_title(row))
      },
      badges:
        [basic_badge(state_timeline_label(row), state_timeline_badge_class(row))]
        |> append_violation_badge(Map.get(row, :violation?))
        |> Kernel.++(data_management_badge_presentations(row)),
      bar: %{
        class: "mt-1 h-2 overflow-hidden rounded bg-base-300/70",
        fill_class: "h-full rounded #{state_timeline_bar_class(row)}"
      },
      metadata_class:
        "mt-1 flex flex-wrap gap-x-2 gap-y-0.5 font-mono text-[0.66rem] text-base-content/55",
      metadata: state_timeline_metadata(row),
      actions_class: "self-start text-right",
      link_menu:
        if(links != [],
          do:
            WidgetDataLinkComponents.state_timeline_row_link_presentation(
              row,
              links,
              placement_id
            )
        )
    }
  end

  defp state_timeline_row_attrs(row, lane) do
    compact_attrs(%{
      "data-state-timeline-row" => direct_attr_value(row.row_id),
      "data-state-timeline-observable" => direct_attr_value(row.observable_id),
      "data-state-timeline-state" =>
        direct_attr_value(state_timeline_text(Map.get(row, :normalized_state))),
      "data-state-timeline-limit-event-id" => direct_attr_value(Map.get(row, :limit_event_id)),
      "data-state-timeline-lane-row" => direct_attr_value(lane.lane_key),
      "data-state-timeline-source-request-id" =>
        direct_attr_value(row_context_attr(row, :source_request_id)),
      "data-state-timeline-logical-source" =>
        direct_attr_value(row_context_attr(row, :logical_source)),
      "data-state-timeline-realm" => direct_attr_value(row_context_attr(row, :realm)),
      "data-state-timeline-data-source-id" =>
        direct_attr_value(row_context_attr(row, :data_source_id)),
      "data-state-timeline-source-binding-id" =>
        direct_attr_value(row_context_attr(row, :source_binding_id)),
      "data-state-timeline-replay-run-id" =>
        direct_attr_value(row_context_attr(row, :replay_run_id)),
      "data-state-timeline-dataset" => direct_attr_value(row_context_attr(row, :dataset)),
      "data-state-timeline-query-scope-kind" =>
        direct_attr_value(row_context_attr(row, :query_scope_kind)),
      "data-state-timeline-query-scope-id" =>
        direct_attr_value(row_context_attr(row, :query_scope_id)),
      "data-state-timeline-query-scope-ids" =>
        direct_attr_value(row_context_attr(row, :query_scope_ids)),
      "data-data-management-badges" =>
        direct_attr_value(WidgetDataManagementComponents.data_management_badge_codes(row))
    })
  end

  defp state_timeline_metadata(row) do
    [state_timeline_range(row)]
    |> append_if(state_timeline_duration(row), state_timeline_duration(row))
    |> append_if(Map.get(row, :sample_id), Map.get(row, :sample_id))
    |> append_if(state_timeline_resource_id(row), state_timeline_resource_id(row))
    |> append_if(
      Map.get(row, :limit_definition_id),
      state_timeline_definition_label(row)
    )
  end

  def event_timeline_presentation(data, placement_id) do
    %{
      kind: "event_timeline",
      component_id: "widget-rows-event-timeline-#{placement_id}-component",
      root: %{class: "space-y-1"},
      rows:
        data.rows
        |> Enum.with_index()
        |> Enum.map(fn {row, index} ->
          event_timeline_row_presentation(row, placement_id, index)
        end)
    }
  end

  defp event_timeline_row_presentation(row, placement_id, index) do
    links = Map.get(row, :links, [])

    %{
      key: row_key("event-row", placement_id, index, row.row_id),
      class:
        "grid grid-cols-[auto_minmax(0,1fr)_auto] gap-2 rounded border border-base-300/60 bg-base-100/70 px-2 py-1.5",
      attrs: event_timeline_row_attrs(row),
      marker: %{
        container_class: "pt-0.5",
        class: "block h-2.5 w-2.5 rounded-full #{event_timeline_dot_class(row)}"
      },
      content_class: "min-w-0",
      heading_class: "flex flex-wrap items-center gap-1.5",
      category: %{
        class: "font-mono text-[0.66rem] uppercase text-base-content/55",
        text: event_timeline_text(Map.get(row, :category))
      },
      badges:
        [basic_badge(event_timeline_badge_label(row), event_timeline_badge_class(row))] ++
          data_management_badge_presentations(row),
      time: %{
        class: "font-mono text-[0.66rem] text-base-content/50",
        text: format_event_timeline_time(row)
      },
      title: %{
        class: "truncate text-sm font-medium",
        attrs:
          compact_attrs(%{
            "title" => direct_attr_value(Map.get(row, :title)),
            "data-event-timeline-title" => direct_attr_value(true)
          }),
        text: rendered_body(Map.get(row, :title))
      },
      metadata_class:
        "mt-0.5 flex flex-wrap gap-x-2 gap-y-0.5 font-mono text-[0.66rem] text-base-content/55",
      metadata: event_timeline_metadata(row),
      actions_class: "self-start text-right",
      link_menu:
        if(links != [],
          do:
            WidgetDataLinkComponents.event_timeline_row_link_presentation(
              row,
              links,
              placement_id
            )
        )
    }
  end

  defp event_timeline_row_attrs(row) do
    compact_attrs(%{
      "data-event-timeline-row" => direct_attr_value(row.row_id),
      "data-event-timeline-source-request-id" =>
        direct_attr_value(row_context_attr(row, :source_request_id)),
      "data-event-timeline-logical-source" =>
        direct_attr_value(row_context_attr(row, :logical_source)),
      "data-event-timeline-realm" => direct_attr_value(row_context_attr(row, :realm)),
      "data-event-timeline-data-source-id" =>
        direct_attr_value(row_context_attr(row, :data_source_id)),
      "data-event-timeline-source-binding-id" =>
        direct_attr_value(row_context_attr(row, :source_binding_id)),
      "data-event-timeline-replay-run-id" =>
        direct_attr_value(row_context_attr(row, :replay_run_id)),
      "data-event-timeline-dataset" => direct_attr_value(row_context_attr(row, :dataset)),
      "data-event-timeline-category" =>
        direct_attr_value(event_timeline_text(Map.get(row, :category))),
      "data-event-timeline-kind" => direct_attr_value(event_timeline_text(Map.get(row, :kind))),
      "data-event-timeline-severity" =>
        direct_attr_value(event_timeline_text(Map.get(row, :severity))),
      "data-event-timeline-record-id" => direct_attr_value(Map.get(row, :source_record_id)),
      "data-event-timeline-target" =>
        direct_attr_value(event_timeline_text(Map.get(row, :target))),
      "data-event-timeline-target-id" => direct_attr_value(Map.get(row, :target_id)),
      "data-event-timeline-complete-through" =>
        direct_attr_value(event_timeline_datetime_attr(Map.get(row, :complete_through))),
      "data-event-timeline-latest-receipt-time" =>
        direct_attr_value(event_timeline_datetime_attr(Map.get(row, :latest_receipt_time))),
      "data-event-timeline-confidence" =>
        direct_attr_value(event_timeline_text(Map.get(row, :confidence))),
      "data-event-timeline-reason" =>
        direct_attr_value(event_timeline_text(Map.get(row, :reason))),
      "data-data-management-badges" =>
        direct_attr_value(WidgetDataManagementComponents.data_management_badge_codes(row))
    })
  end

  defp event_timeline_metadata(row) do
    []
    |> append_if(Map.get(row, :source_record_id), Map.get(row, :source_record_id))
    |> append_if(
      Map.get(row, :logical_source),
      event_timeline_text(Map.get(row, :logical_source))
    )
    |> append_if(Map.get(row, :data_source_id), Map.get(row, :data_source_id))
    |> append_if(Map.get(row, :source_binding_id), Map.get(row, :source_binding_id))
    |> append_if(Map.get(row, :realm), event_timeline_text(Map.get(row, :realm)))
    |> append_if(Map.get(row, :dataset), Map.get(row, :dataset))
    |> append_if(event_timeline_duration(row), event_timeline_duration(row))
    |> append_if(
      Map.get(row, :complete_through),
      "complete #{format_event_timeline_time(%{occurred_at: Map.get(row, :complete_through)})}"
    )
    |> append_if(
      Map.get(row, :latest_receipt_time),
      "latest #{format_event_timeline_time(%{occurred_at: Map.get(row, :latest_receipt_time)})}"
    )
    |> append_if(Map.get(row, :confidence), event_timeline_text(Map.get(row, :confidence)))
    |> append_if(Map.get(row, :reason), event_timeline_text(Map.get(row, :reason)))
  end

  defp table_heading(key, class, text, text_class \\ nil) do
    %{key: key, class: class, text: rendered_body(text), text_class: text_class}
  end

  defp table_text_cell(key, class, attrs, text) do
    %{
      key: key,
      class: class,
      attrs: compact_attrs(attrs),
      text: rendered_body(text),
      badges: [],
      link_menu: nil
    }
  end

  defp table_badge_cell(key, class, attrs, badges) do
    %{
      key: key,
      class: class,
      attrs: compact_attrs(attrs),
      text: nil,
      badges: add_badge_keys(badges, key),
      link_menu: nil
    }
  end

  defp table_link_cell(key, class, link_menu) do
    %{key: key, class: class, attrs: %{}, text: nil, badges: [], link_menu: link_menu}
  end

  defp basic_badge(text, variant_class) do
    %{
      tag: "span",
      class: "badge badge-xs #{variant_class}",
      attrs: %{},
      text: rendered_body(text)
    }
  end

  defp data_management_badge_presentations(row) do
    row
    |> WidgetDataManagementComponents.data_management_badges()
    |> Enum.map(&WidgetDataManagementComponents.data_management_badge_presentation(&1, "ml-1"))
  end

  defp add_badge_keys(badges, prefix) do
    badges
    |> Enum.with_index()
    |> Enum.map(fn {badge, index} -> Map.put(badge, :key, "#{prefix}-badge-#{index}") end)
  end

  defp append_violation_badge(badges, value) when value in [nil, false], do: badges

  defp append_violation_badge(badges, _value) do
    badges ++
      [
        %{
          tag: "span",
          class: "badge badge-error badge-xs",
          attrs: %{},
          text: "Violation"
        }
      ]
  end

  defp append_if(values, condition, _text) when condition in [nil, false], do: values
  defp append_if(values, _condition, text), do: values ++ [rendered_body(text)]

  defp row_key(kind, placement_id, index, identity) do
    "#{kind}-#{placement_id}-#{index}-#{rendered_body(identity)}"
  end

  # Direct HEEx attributes omit nil/false, render true without a value, and
  # stringify all other scalar values. Keeping that conversion on the server
  # prevents JavaScript truthiness from changing the rendered contract.
  defp direct_attr_value(value) when value in [nil, false], do: nil
  defp direct_attr_value(true), do: ""
  defp direct_attr_value(value), do: rendered_body(value)

  defp compact_attrs(attrs) do
    attrs
    |> Enum.reject(fn {_name, value} -> is_nil(value) end)
    |> Map.new()
  end

  defp rendered_body(value), do: to_string(value)

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
