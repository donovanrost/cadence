defmodule CadenceWeb.OpsDashboardShowLive.WidgetDataLinkComponents do
  @moduledoc false
  use CadenceWeb, :html

  alias CadenceWeb.OpsDashboardShowLive.{DataLinkAttrs, EvidenceAttrs}

  @overlay_class "cadence-overlay"
  @trigger_class "cadence-overlay-trigger"
  @panel_class "cadence-overlay-panel cadence-popover-panel"
  @trigger_content_class "btn btn-ghost btn-xs btn-square"
  @body_class "p-1 text-xs"
  @inspect_icon %{name: "hero-magnifying-glass", class: "h-3.5 w-3.5"}
  @evidence_icon %{
    name: "hero-document-magnifying-glass",
    class: "h-3.5 w-3.5"
  }
  @evidence_item_class "flex w-full items-center justify-between gap-2 rounded px-2 py-1 text-left hover:bg-base-200"
  @widget_link_item_class "flex w-full items-center justify-between gap-2 rounded px-2 py-1 text-left hover:bg-base-200"
  @row_link_item_class "grid w-full grid-cols-[minmax(0,1fr)_minmax(0,1fr)] gap-2 rounded px-2 py-1 text-left hover:bg-base-200"
  @widget_link_secondary_class "font-mono text-base-content/60 truncate"
  @row_link_label_class "truncate"
  @row_link_secondary_class "truncate text-right font-mono text-base-content/60"

  attr(:links, :list, required: true)
  attr(:placement_id, :string, required: true)

  def widget_data_link_menu(assigns) do
    presentation = widget_data_link_presentation(assigns.links, assigns.placement_id)

    assigns = assign(assigns, :presentation, presentation)

    ~H"""
    <.vue
      id={@presentation.component_id}
      v-component="WidgetDataLinks"
      presentation={@presentation}
      v-ssr={false}
      class="contents"
    />
    """
  end

  def widget_data_link_presentation(links, placement_id) do
    overlay_id = "widget-data-links-#{placement_id}"

    popover_presentation(
      "widget",
      overlay_id,
      "Inspect widget data",
      %{"data-widget-data-links" => ""},
      %{"data-widget-data-link-menu" => ""},
      Enum.map(links, &widget_link_item(&1, placement_id))
    )
  end

  attr(:row, :map, required: true)
  attr(:links, :list, required: true)
  attr(:placement_id, :string, required: true)

  def status_matrix_row_link_menu(assigns) do
    presentation =
      status_matrix_row_link_presentation(assigns.row, assigns.links, assigns.placement_id)

    assigns = assign(assigns, :presentation, presentation)

    ~H"""
    <.vue
      id={@presentation.component_id}
      v-component="WidgetDataLinks"
      presentation={@presentation}
      v-ssr={false}
      class="contents"
    />
    """
  end

  def status_matrix_row_link_presentation(row, links, placement_id) do
    observable_id = text_value(row.observable_id)
    observable_attr = direct_attr_value(row.observable_id)
    overlay_id = "status-row-links-#{placement_id}-#{observable_id}"
    label = "Inspect #{observable_id}"

    popover_presentation(
      "status_matrix_row",
      overlay_id,
      label,
      %{"data-status-matrix-row-links" => observable_attr},
      %{"data-status-matrix-row-link-menu" => observable_attr},
      [status_matrix_evidence_item(row, placement_id, observable_attr)] ++
        Enum.map(links, &status_matrix_link_item(&1, placement_id, observable_attr))
    )
  end

  attr(:row, :map, required: true)
  attr(:links, :list, required: true)
  attr(:placement_id, :string, required: true)

  def data_table_row_link_menu(assigns) do
    presentation =
      data_table_row_link_presentation(assigns.row, assigns.links, assigns.placement_id)

    assigns = assign(assigns, :presentation, presentation)

    ~H"""
    <.vue
      id={@presentation.component_id}
      v-component="WidgetDataLinks"
      presentation={@presentation}
      v-ssr={false}
      class="contents"
    />
    """
  end

  def data_table_row_link_presentation(row, links, placement_id) do
    observable_id = text_value(row.observable_id)
    observable_attr = direct_attr_value(row.observable_id)
    overlay_id = "data-row-links-#{placement_id}-#{observable_id}"
    label = "Inspect #{observable_id}"

    popover_presentation(
      "data_table_row",
      overlay_id,
      label,
      %{"data-data-table-row-links" => observable_attr},
      %{"data-data-table-row-link-menu" => observable_attr},
      [data_table_evidence_item(row, placement_id, observable_attr)] ++
        Enum.map(links, &data_table_link_item(&1, placement_id, observable_attr))
    )
  end

  attr(:row, :map, required: true)
  attr(:links, :list, required: true)
  attr(:placement_id, :string, required: true)

  def state_timeline_row_link_menu(assigns) do
    presentation =
      state_timeline_row_link_presentation(assigns.row, assigns.links, assigns.placement_id)

    assigns = assign(assigns, :presentation, presentation)

    ~H"""
    <.vue
      id={@presentation.component_id}
      v-component="WidgetDataLinks"
      presentation={@presentation}
      v-ssr={false}
      class="contents"
    />
    """
  end

  def state_timeline_row_link_presentation(row, links, placement_id) do
    row_id = text_value(row.row_id)
    row_id_attr = direct_attr_value(row.row_id)
    observable_id = text_value(Map.get(row, :observable_id))
    overlay_id = "state-row-links-#{placement_id}-#{row_id}"
    label = "Inspect #{observable_id} state transition"
    timestamp_ms = state_timeline_link_timestamp_ms(row)

    popover_presentation(
      "state_timeline_row",
      overlay_id,
      label,
      %{"data-state-timeline-row-links" => row_id_attr},
      %{"data-state-timeline-row-link-menu" => row_id_attr},
      [state_timeline_evidence_item(row, placement_id, row_id_attr)] ++
        Enum.map(
          links,
          &state_timeline_link_item(&1, placement_id, row_id_attr, timestamp_ms)
        )
    )
  end

  attr(:row, :map, required: true)
  attr(:links, :list, required: true)
  attr(:placement_id, :string, required: true)

  def event_timeline_row_link_menu(assigns) do
    presentation =
      event_timeline_row_link_presentation(assigns.row, assigns.links, assigns.placement_id)

    assigns = assign(assigns, :presentation, presentation)

    ~H"""
    <.vue
      id={@presentation.component_id}
      v-component="WidgetDataLinks"
      presentation={@presentation}
      v-ssr={false}
      class="contents"
    />
    """
  end

  def event_timeline_row_link_presentation(row, links, placement_id) do
    row_id = text_value(row.row_id)
    row_id_attr = direct_attr_value(row.row_id)
    title = text_value(Map.get(row, :title))
    overlay_id = "event-row-links-#{placement_id}-#{row_id}"
    label = "Inspect #{title}"
    timestamp_ms = event_timeline_link_timestamp_ms(row)

    popover_presentation(
      "event_timeline_row",
      overlay_id,
      label,
      %{"data-event-timeline-row-links" => row_id_attr},
      %{"data-event-timeline-row-link-menu" => row_id_attr},
      Enum.map(
        links,
        &event_timeline_link_item(&1, placement_id, row_id_attr, timestamp_ms)
      )
    )
  end

  defp popover_presentation(kind, overlay_id, label, overlay_attrs, trigger_attrs, items) do
    %{
      kind: kind,
      component_id: "#{overlay_id}-component",
      overlay: %{
        id: overlay_id,
        class: @overlay_class,
        attrs:
          Map.merge(
            %{
              "data-overlay-kind" => "popover",
              "data-overlay-placement" => "bottom-end"
            },
            compact_attrs(overlay_attrs)
          )
      },
      trigger: %{
        id: "#{overlay_id}-trigger",
        type: "button",
        class: @trigger_class,
        attrs: %{
          "data-overlay-trigger" => "",
          "aria-haspopup" => "dialog",
          "aria-expanded" => "false",
          "aria-controls" => "#{overlay_id}-panel",
          "aria-label" => label
        },
        content: %{
          class: @trigger_content_class,
          title: label,
          attrs: compact_attrs(trigger_attrs),
          icon: @inspect_icon
        }
      },
      panel: %{
        id: "#{overlay_id}-panel",
        class: @panel_class,
        hidden: true,
        attrs: %{
          "data-overlay-panel" => "",
          "data-overlay-width" => "sm",
          "aria-label" => label
        }
      },
      body: %{class: @body_class},
      items:
        items
        |> Enum.with_index()
        |> Enum.map(fn {item, index} ->
          Map.put(item, :key, "#{overlay_id}-item-#{index}")
        end)
    }
  end

  defp widget_link_item(link, placement_id) do
    data_link_item(
      link,
      placement_id,
      widget_link_timestamp_ms(link),
      @widget_link_item_class,
      nil,
      @widget_link_secondary_class,
      %{
        "data-widget-data-link-target" => direct_attr_value(link.target_text),
        "data-widget-data-link-id" => fallback_empty_attr_value(link.target_id),
        "data-widget-data-link-ref" => fallback_empty_attr_value(link.link_id)
      }
    )
  end

  defp status_matrix_link_item(link, placement_id, observable_id) do
    data_link_item(
      link,
      placement_id,
      nil,
      @row_link_item_class,
      @row_link_label_class,
      @row_link_secondary_class,
      %{
        "data-status-matrix-row-link" => observable_id,
        "data-status-matrix-row-link-target" => direct_attr_value(link.target_text),
        "data-status-matrix-row-link-id" => fallback_empty_attr_value(link.target_id),
        "data-status-matrix-row-link-ref" => fallback_empty_attr_value(link.link_id)
      }
    )
  end

  defp data_table_link_item(link, placement_id, observable_id) do
    data_link_item(
      link,
      placement_id,
      nil,
      @row_link_item_class,
      @row_link_label_class,
      @row_link_secondary_class,
      %{
        "data-data-table-row-link" => observable_id,
        "data-data-table-row-link-target" => direct_attr_value(link.target_text),
        "data-data-table-row-link-id" => fallback_empty_attr_value(link.target_id),
        "data-data-table-row-link-ref" => fallback_empty_attr_value(link.link_id)
      }
    )
  end

  defp state_timeline_link_item(link, placement_id, row_id, timestamp_ms) do
    data_link_item(
      link,
      placement_id,
      timestamp_ms,
      @row_link_item_class,
      @row_link_label_class,
      @row_link_secondary_class,
      %{
        "data-state-timeline-row-link" => row_id,
        "data-state-timeline-row-link-target" => direct_attr_value(link.target_text),
        "data-state-timeline-row-link-id" => fallback_empty_attr_value(link.target_id),
        "data-state-timeline-row-link-ref" => fallback_empty_attr_value(link.link_id)
      }
    )
  end

  defp event_timeline_link_item(link, placement_id, row_id, timestamp_ms) do
    data_link_item(
      link,
      placement_id,
      timestamp_ms,
      @row_link_item_class,
      @row_link_label_class,
      @row_link_secondary_class,
      %{
        "data-event-timeline-row-link" => row_id,
        "data-event-timeline-row-link-target" => direct_attr_value(link.target_text),
        "data-event-timeline-row-link-id" => fallback_empty_attr_value(link.target_id),
        "data-event-timeline-row-link-ref" => fallback_empty_attr_value(link.link_id)
      }
    )
  end

  defp data_link_item(
         link,
         placement_id,
         timestamp_ms,
         class,
         label_class,
         secondary_class,
         data_attrs
       ) do
    event_attrs =
      DataLinkAttrs.open(link,
        placement_id: placement_id,
        timestamp_ms: timestamp_ms
      )

    %{
      kind: "data_link",
      type: "button",
      class: class,
      attrs:
        event_attrs
        |> Map.merge(compact_attrs(data_attrs))
        |> Map.put("phx-click", "open_data_link"),
      label: %{text: text_value(link.label || link.target_text), class: label_class},
      secondary: %{text: text_value(link.target_id), class: secondary_class},
      icon: nil
    }
  end

  defp status_matrix_evidence_item(row, placement_id, observable_id) do
    evidence_item(
      row,
      placement_id,
      %{
        "data-status-matrix-row-evidence" => observable_id,
        "data-status-matrix-row-evidence-observable" => row_frame_observable_id(row)
      }
    )
  end

  defp data_table_evidence_item(row, placement_id, observable_id) do
    evidence_item(
      row,
      placement_id,
      %{
        "data-data-table-row-evidence" => observable_id,
        "data-data-table-row-evidence-observable" => row_frame_observable_id(row)
      }
    )
  end

  defp state_timeline_evidence_item(row, placement_id, row_id) do
    evidence_item(
      row,
      placement_id,
      %{
        "data-state-timeline-row-evidence" => row_id,
        "data-state-timeline-row-evidence-observable" => row_frame_observable_id(row)
      }
    )
  end

  defp evidence_item(row, placement_id, data_attrs) do
    %{
      kind: "evidence",
      type: "button",
      class: @evidence_item_class,
      attrs:
        EvidenceAttrs.row_frame(placement_id, row)
        |> Map.merge(compact_attrs(data_attrs))
        |> Map.put("phx-click", "open_evidence"),
      label: %{text: "Frame evidence", class: nil},
      secondary: nil,
      icon: @evidence_icon
    }
  end

  defp row_frame_observable_id(row) do
    direct_attr_value(Map.get(row, :frame_observable_id) || Map.get(row, :observable_id))
  end

  defp widget_link_timestamp_ms(%{target: target, timestamp_ms: timestamp_ms})
       when target in [:telemetry_sample, "telemetry_sample"] and is_integer(timestamp_ms),
       do: timestamp_ms

  defp widget_link_timestamp_ms(_link), do: nil

  defp event_timeline_link_timestamp_ms(%{occurred_at: %DateTime{} = occurred_at}),
    do: DateTime.to_unix(occurred_at, :millisecond)

  defp event_timeline_link_timestamp_ms(%{starts_at: %DateTime{} = starts_at}),
    do: DateTime.to_unix(starts_at, :millisecond)

  defp event_timeline_link_timestamp_ms(_row), do: nil

  defp state_timeline_link_timestamp_ms(%{starts_at: %DateTime{} = starts_at}),
    do: DateTime.to_unix(starts_at, :millisecond)

  defp state_timeline_link_timestamp_ms(_row), do: nil

  # Old HEEx text bodies and interpolated IDs/labels render nil as empty text and
  # atoms such as false/true as their names.
  defp text_value(value), do: to_string(value)

  # Old direct HEEx attributes omit false/nil and render true with no value.
  # The Vue DTO represents a present valueless attribute as an empty string.
  defp direct_attr_value(value) when value in [nil, false], do: nil
  defp direct_attr_value(true), do: ""
  defp direct_attr_value(value), do: text_value(value)

  # Old `{value || ""}` attributes intentionally turn false/nil into a present
  # empty attribute; true is likewise present without a value.
  defp fallback_empty_attr_value(value) when value in [nil, false, true], do: ""
  defp fallback_empty_attr_value(value), do: text_value(value)

  defp compact_attrs(attrs) do
    attrs
    |> Enum.reject(fn {_name, value} -> is_nil(value) end)
    |> Map.new()
  end
end
