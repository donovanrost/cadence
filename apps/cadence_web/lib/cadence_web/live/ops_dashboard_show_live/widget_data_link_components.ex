defmodule CadenceWeb.OpsDashboardShowLive.WidgetDataLinkComponents do
  @moduledoc false
  use CadenceWeb, :html

  alias CadenceWeb.OpsDashboardShowLive.{DataLinkAttrs, EvidenceAttrs}

  attr :links, :list, required: true
  attr :placement_id, :string, required: true

  def widget_data_link_menu(assigns) do
    ~H"""
    <details class="dropdown dropdown-end" data-widget-data-links>
      <summary
        class="btn btn-ghost btn-xs btn-square"
        aria-label="Inspect widget data"
        title="Inspect widget data"
        data-widget-data-link-menu
      >
        <.icon name="hero-magnifying-glass" class="h-3.5 w-3.5" />
      </summary>
      <div class="dropdown-content z-[var(--z-popover)] mt-1 w-56 rounded border border-base-300 bg-base-100 p-1 text-xs shadow-lg">
        <button
          :for={link <- @links}
          type="button"
          phx-click="open_data_link"
          {DataLinkAttrs.open(link,
            placement_id: @placement_id,
            timestamp_ms: widget_link_timestamp_ms(link)
          )}
          class="flex w-full items-center justify-between gap-2 rounded px-2 py-1 text-left hover:bg-base-200"
          data-widget-data-link-target={link.target_text}
          data-widget-data-link-id={link.target_id || ""}
          data-widget-data-link-ref={link.link_id || ""}
        >
          <span>{link.label || link.target_text}</span>
          <span class="font-mono text-base-content/60 truncate">{link.target_id}</span>
        </button>
      </div>
    </details>
    """
  end

  attr :row, :map, required: true
  attr :links, :list, required: true
  attr :placement_id, :string, required: true

  def status_matrix_row_link_menu(assigns) do
    ~H"""
    <details class="dropdown dropdown-end" data-status-matrix-row-links={@row.observable_id}>
      <summary
        class="btn btn-ghost btn-xs btn-square"
        aria-label={"Inspect #{@row.observable_id}"}
        title={"Inspect #{@row.observable_id}"}
        data-status-matrix-row-link-menu={@row.observable_id}
      >
        <.icon name="hero-magnifying-glass" class="h-3.5 w-3.5" />
      </summary>
      <div class="dropdown-content z-[var(--z-popover)] mt-1 w-56 rounded border border-base-300 bg-base-100 p-1 text-xs shadow-lg">
        <button
          type="button"
          phx-click="open_evidence"
          {EvidenceAttrs.row_frame(@placement_id, @row)}
          class="flex w-full items-center justify-between gap-2 rounded px-2 py-1 text-left hover:bg-base-200"
          data-status-matrix-row-evidence={@row.observable_id}
          data-status-matrix-row-evidence-observable={row_frame_observable_id(@row)}
        >
          <span>Frame evidence</span>
          <.icon name="hero-document-magnifying-glass" class="h-3.5 w-3.5" />
        </button>
        <button
          :for={link <- @links}
          type="button"
          phx-click="open_data_link"
          {DataLinkAttrs.open(link, placement_id: @placement_id)}
          class="grid w-full grid-cols-[minmax(0,1fr)_minmax(0,1fr)] gap-2 rounded px-2 py-1 text-left hover:bg-base-200"
          data-status-matrix-row-link={@row.observable_id}
          data-status-matrix-row-link-target={link.target_text}
          data-status-matrix-row-link-id={link.target_id || ""}
          data-status-matrix-row-link-ref={link.link_id || ""}
        >
          <span class="truncate">{link.label || link.target_text}</span>
          <span class="truncate text-right font-mono text-base-content/60">{link.target_id}</span>
        </button>
      </div>
    </details>
    """
  end

  attr :row, :map, required: true
  attr :links, :list, required: true
  attr :placement_id, :string, required: true

  def data_table_row_link_menu(assigns) do
    ~H"""
    <details class="dropdown dropdown-end" data-data-table-row-links={@row.observable_id}>
      <summary
        class="btn btn-ghost btn-xs btn-square"
        aria-label={"Inspect #{@row.observable_id}"}
        title={"Inspect #{@row.observable_id}"}
        data-data-table-row-link-menu={@row.observable_id}
      >
        <.icon name="hero-magnifying-glass" class="h-3.5 w-3.5" />
      </summary>
      <div class="dropdown-content z-[var(--z-popover)] mt-1 w-56 rounded border border-base-300 bg-base-100 p-1 text-xs shadow-lg">
        <button
          type="button"
          phx-click="open_evidence"
          {EvidenceAttrs.row_frame(@placement_id, @row)}
          class="flex w-full items-center justify-between gap-2 rounded px-2 py-1 text-left hover:bg-base-200"
          data-data-table-row-evidence={@row.observable_id}
          data-data-table-row-evidence-observable={row_frame_observable_id(@row)}
        >
          <span>Frame evidence</span>
          <.icon name="hero-document-magnifying-glass" class="h-3.5 w-3.5" />
        </button>
        <button
          :for={link <- @links}
          type="button"
          phx-click="open_data_link"
          {DataLinkAttrs.open(link, placement_id: @placement_id)}
          class="grid w-full grid-cols-[minmax(0,1fr)_minmax(0,1fr)] gap-2 rounded px-2 py-1 text-left hover:bg-base-200"
          data-data-table-row-link={@row.observable_id}
          data-data-table-row-link-target={link.target_text}
          data-data-table-row-link-id={link.target_id || ""}
          data-data-table-row-link-ref={link.link_id || ""}
        >
          <span class="truncate">{link.label || link.target_text}</span>
          <span class="truncate text-right font-mono text-base-content/60">{link.target_id}</span>
        </button>
      </div>
    </details>
    """
  end

  attr :row, :map, required: true
  attr :links, :list, required: true
  attr :placement_id, :string, required: true

  def state_timeline_row_link_menu(assigns) do
    ~H"""
    <details class="dropdown dropdown-end" data-state-timeline-row-links={@row.row_id}>
      <summary
        class="btn btn-ghost btn-xs btn-square"
        aria-label={"Inspect #{Map.get(@row, :observable_id)} state transition"}
        title={"Inspect #{Map.get(@row, :observable_id)} state transition"}
        data-state-timeline-row-link-menu={@row.row_id}
      >
        <.icon name="hero-magnifying-glass" class="h-3.5 w-3.5" />
      </summary>
      <div class="dropdown-content z-[var(--z-popover)] mt-1 w-60 rounded border border-base-300 bg-base-100 p-1 text-xs shadow-lg">
        <button
          type="button"
          phx-click="open_evidence"
          {EvidenceAttrs.row_frame(@placement_id, @row)}
          class="flex w-full items-center justify-between gap-2 rounded px-2 py-1 text-left hover:bg-base-200"
          data-state-timeline-row-evidence={@row.row_id}
          data-state-timeline-row-evidence-observable={row_frame_observable_id(@row)}
        >
          <span>Frame evidence</span>
          <.icon name="hero-document-magnifying-glass" class="h-3.5 w-3.5" />
        </button>
        <button
          :for={link <- @links}
          type="button"
          phx-click="open_data_link"
          {DataLinkAttrs.open(link,
            placement_id: @placement_id,
            timestamp_ms: state_timeline_link_timestamp_ms(@row)
          )}
          class="grid w-full grid-cols-[minmax(0,1fr)_minmax(0,1fr)] gap-2 rounded px-2 py-1 text-left hover:bg-base-200"
          data-state-timeline-row-link={@row.row_id}
          data-state-timeline-row-link-target={link.target_text}
          data-state-timeline-row-link-id={link.target_id || ""}
          data-state-timeline-row-link-ref={link.link_id || ""}
        >
          <span class="truncate">{link.label || link.target_text}</span>
          <span class="truncate text-right font-mono text-base-content/60">{link.target_id}</span>
        </button>
      </div>
    </details>
    """
  end

  attr :row, :map, required: true
  attr :links, :list, required: true
  attr :placement_id, :string, required: true

  def event_timeline_row_link_menu(assigns) do
    ~H"""
    <details class="dropdown dropdown-end" data-event-timeline-row-links={@row.row_id}>
      <summary
        class="btn btn-ghost btn-xs btn-square"
        aria-label={"Inspect #{Map.get(@row, :title)}"}
        title={"Inspect #{Map.get(@row, :title)}"}
        data-event-timeline-row-link-menu={@row.row_id}
      >
        <.icon name="hero-magnifying-glass" class="h-3.5 w-3.5" />
      </summary>
      <div class="dropdown-content z-[var(--z-popover)] mt-1 w-60 rounded border border-base-300 bg-base-100 p-1 text-xs shadow-lg">
        <button
          :for={link <- @links}
          type="button"
          phx-click="open_data_link"
          {DataLinkAttrs.open(link,
            placement_id: @placement_id,
            timestamp_ms: event_timeline_link_timestamp_ms(@row)
          )}
          class="grid w-full grid-cols-[minmax(0,1fr)_minmax(0,1fr)] gap-2 rounded px-2 py-1 text-left hover:bg-base-200"
          data-event-timeline-row-link={@row.row_id}
          data-event-timeline-row-link-target={link.target_text}
          data-event-timeline-row-link-id={link.target_id || ""}
          data-event-timeline-row-link-ref={link.link_id || ""}
        >
          <span class="truncate">{link.label || link.target_text}</span>
          <span class="truncate text-right font-mono text-base-content/60">{link.target_id}</span>
        </button>
      </div>
    </details>
    """
  end

  defp row_frame_observable_id(row) do
    Map.get(row, :frame_observable_id) || Map.get(row, :observable_id)
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
end
