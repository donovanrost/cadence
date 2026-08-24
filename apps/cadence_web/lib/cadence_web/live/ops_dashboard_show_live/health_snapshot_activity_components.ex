defmodule CadenceWeb.OpsDashboardShowLive.HealthSnapshotActivityComponents do
  @moduledoc false
  use CadenceWeb, :html

  alias CadenceWeb.OpsDashboardShowLive.HealthSnapshotActivity

  alias Cadence.Dashboards.LifecycleEvent

  attr :event, LifecycleEvent, required: true

  def event_details(assigns) do
    health_snapshot = HealthSnapshotActivity.build(assigns.event)

    if health_snapshot.present? do
      event_id = assigns.event.dashboard_lifecycle_event_id

      assigns =
        assigns
        |> assign(
          :island_id,
          "dashboard-health-snapshot-event-#{rendered_body(event_id)}-component"
        )
        |> assign(:presentation, health_snapshot_activity_dto(event_id, health_snapshot))

      ~H"""
      <.vue
        id={@island_id}
        v-component="HealthSnapshotActivity"
        presentation={@presentation}
        v-ssr={false}
        class="contents"
      />
      """
    else
      ~H""
    end
  end

  defp health_snapshot_activity_dto(event_id, health_snapshot) do
    event_id_text = rendered_body(event_id)

    %{
      root: %{
        class: "mt-3 space-y-3 border-t border-base-300/70 pt-3 text-xs",
        attrs:
          raw_attributes(%{
            "data-dashboard-health-snapshot-event" => event_id,
            "data-dashboard-health-snapshot-capture-schema" => health_snapshot.capture_schema,
            "data-dashboard-health-snapshot-schema" => health_snapshot.snapshot_schema,
            "data-dashboard-health-snapshot-id" => health_snapshot.snapshot_id,
            "data-dashboard-health-snapshot-state" => health_snapshot.state,
            "data-dashboard-health-snapshot-severity" => health_snapshot.severity,
            "data-dashboard-health-snapshot-source" => health_snapshot.source,
            "data-dashboard-health-snapshot-reason" => health_snapshot.captured_reason
          })
      },
      summary: %{
        class: "flex items-start justify-between gap-2",
        rows_class: "grid min-w-0 grid-cols-[5rem_1fr] gap-x-2 gap-y-1",
        rows: [
          summary_row(
            "snapshot",
            0,
            "Snapshot",
            "Health snapshot",
            "truncate font-mono text-base-content/70",
            health_snapshot.snapshot_id
          ),
          summary_row(
            "state",
            1,
            "State",
            "Health state",
            "font-mono text-base-content/70",
            health_snapshot.state
          ),
          summary_row(
            "severity",
            2,
            "Severity",
            "Health severity",
            "font-mono text-base-content/70",
            health_snapshot.severity
          )
        ]
      },
      copy_host: %{
        id: "dashboard-health-snapshot-event-copy-#{event_id_text}-component",
        class: "contents"
      },
      copy_props: %{
        button_id: "dashboard-health-snapshot-event-copy-#{event_id_text}",
        clipboard_text: health_snapshot.snapshot_json,
        button_class: "btn btn-ghost btn-xs shrink-0",
        icon: "hero-clipboard-document",
        icon_class: "h-3.5 w-3.5",
        label: "Copy",
        data_attrs:
          raw_attributes(%{
            "data-dashboard-health-snapshot-event-copy" => event_id,
            "data-dashboard-health-snapshot-id" => health_snapshot.snapshot_id,
            "data-dashboard-health-snapshot-schema" => health_snapshot.snapshot_schema
          })
      },
      counts: %{
        class: "grid grid-cols-2 gap-2",
        rows:
          health_snapshot.counts
          |> Enum.with_index()
          |> Enum.map(fn {count, index} -> count_row(count, index) end)
      },
      placements: %{
        visible: health_snapshot.placements != [],
        class: "grid grid-cols-[5rem_1fr] gap-x-2 gap-y-1",
        rows:
          health_snapshot.placements
          |> Enum.with_index()
          |> Enum.map(fn {placement, index} -> placement_row(placement, index) end)
      }
    }
  end

  defp summary_row(key, order, label, data_label, value_class, value) do
    %{
      key: key,
      order: order,
      label: %{class: "hud-label", text: rendered_body(label)},
      value: %{
        class: value_class,
        attrs: raw_attributes(%{"data-activity-field" => data_label}),
        text: rendered_body(value)
      }
    }
  end

  defp count_row(count, order) do
    %{
      key: rendered_body(count.key),
      order: order,
      class: "border border-base-300/70 bg-base-100/50 px-2 py-1.5",
      attrs:
        raw_attributes(%{
          "data-dashboard-health-snapshot-count" => count.key,
          "data-dashboard-health-snapshot-count-value" => count.value
        }),
      label: %{class: "hud-label", text: rendered_body(count.label)},
      value: %{class: "font-mono text-base-content/80", text: rendered_body(count.value)}
    }
  end

  defp placement_row(placement, order) do
    %{
      key: rendered_body(placement.key),
      order: order,
      label: %{class: "hud-label", text: rendered_body(placement.label)},
      value: %{
        class: "font-mono text-base-content/70",
        attrs:
          raw_attributes(%{
            "data-dashboard-health-snapshot-placements" => placement.key,
            "data-dashboard-health-snapshot-placement-ids" => placement.ids_attr
          }),
        text: rendered_body(placement.ids_text)
      }
    }
  end

  defp raw_attributes(attributes) do
    Enum.reduce(attributes, %{}, fn
      {_key, value}, rendered when value in [nil, false] ->
        rendered

      {key, true}, rendered ->
        Map.put(rendered, to_string(key), "")

      {key, value}, rendered ->
        Map.put(rendered, to_string(key), rendered_body(value))
    end)
  end

  defp rendered_body(nil), do: ""
  defp rendered_body(value), do: to_string(value)
end
