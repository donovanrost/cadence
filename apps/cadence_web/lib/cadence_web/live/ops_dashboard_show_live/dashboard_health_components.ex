defmodule CadenceWeb.OpsDashboardShowLive.DashboardHealthComponents do
  @moduledoc false
  use CadenceWeb, :html

  alias CadenceWeb.OpsDashboardShowLive.EvidenceQuery

  attr :health, :map, required: true

  def dashboard_health_strip(%{health: %{visible?: true} = health} = assigns) do
    assigns = assign(assigns, :presentation, dashboard_health_dto(health))

    ~H"""
    <.vue
      id="dashboard-health-rollup-component"
      v-component="DashboardHealth"
      presentation={@presentation}
      v-ssr={false}
      class="contents"
    />
    """
  end

  def dashboard_health_strip(assigns), do: ~H""

  defp dashboard_health_dto(health) do
    snapshot_json = dashboard_health_snapshot_json(health)

    %{
      root: %{
        id: "dashboard-health-rollup",
        class:
          "shrink-0 flex flex-wrap items-center gap-2 px-2 py-1 border-b text-xs #{dashboard_health_strip_class(health)}",
        attrs: dashboard_health_root_attrs(health)
      },
      label: %{class: "hud-label", text: "Dashboard health"},
      status: %{
        class: "badge badge-xs #{dashboard_health_badge_class(health)}",
        text: dashboard_health_text(Map.get(health, :label))
      },
      summary: %{
        class: "text-base-content/70",
        text: dashboard_health_summary(health)
      },
      controls_class: "ml-auto flex items-center gap-1",
      copy_host: %{
        id: "dashboard-health-snapshot-copy-component",
        class: "contents"
      },
      copy_props: %{
        button_id: "dashboard-health-snapshot-copy",
        clipboard_text: snapshot_json,
        button_class: "btn btn-ghost btn-xs btn-square",
        icon: "hero-clipboard-document",
        icon_class: "h-3.5 w-3.5",
        label: "",
        title: "Copy dashboard health snapshot",
        aria_label: "Copy dashboard health snapshot",
        data_attrs:
          string_data_attrs(%{
            "data-dashboard-health-snapshot-copy" => "",
            "data-dashboard-health-snapshot-schema" => Map.get(health, :snapshot_schema),
            "data-dashboard-health-snapshot-id" => Map.get(health, :snapshot_id)
          })
      },
      evidence: dashboard_health_evidence_dto(health),
      capture: dashboard_health_capture_dto(health, snapshot_json),
      groups:
        health
        |> dashboard_health_groups()
        |> Enum.with_index()
        |> Enum.map(fn {group, index} -> dashboard_health_group_dto(group, index) end)
    }
  end

  defp dashboard_health_root_attrs(health) do
    string_data_attrs(%{
      "data-dashboard-health-rollup" => "",
      "data-dashboard-health-snapshot-id" => Map.get(health, :snapshot_id),
      "data-dashboard-health-state" => Map.get(health, :state_text),
      "data-dashboard-health-severity" => Map.get(health, :severity_text),
      "data-dashboard-health-widgets" => Map.get(health, :widget_count),
      "data-dashboard-health-ready" => Map.get(health, :ready_count),
      "data-dashboard-health-degraded" => Map.get(health, :degraded_count),
      "data-dashboard-health-stale" => Map.get(health, :stale_count),
      "data-dashboard-health-blocked" => Map.get(health, :blocked_count),
      "data-dashboard-health-affected" => Map.get(health, :affected_count),
      "data-dashboard-health-states" => Map.get(health, :states),
      "data-dashboard-health-affected-placements" => Map.get(health, :affected_placements),
      "data-dashboard-health-blocked-placements" => Map.get(health, :blocked_placements),
      "data-dashboard-health-stale-placements" => Map.get(health, :stale_placements),
      "data-dashboard-health-degraded-placements" => Map.get(health, :degraded_placements)
    })
  end

  defp dashboard_health_evidence_dto(health) do
    %{
      id: nil,
      type: "button",
      class: "btn btn-ghost btn-xs btn-square",
      title: "Open dashboard health evidence",
      aria_label: "Open dashboard health evidence",
      icon: %{name: "hero-link", class: "h-3.5 w-3.5"},
      attrs:
        health
        |> dashboard_health_evidence_attrs()
        |> Map.merge(%{
          "phx-click" => "open_evidence",
          "data-dashboard-health-evidence-open" => ""
        })
        |> string_data_attrs()
    }
  end

  defp dashboard_health_capture_dto(health, snapshot_json) do
    %{
      id: "dashboard-health-snapshot-capture",
      type: "button",
      class: "btn btn-ghost btn-xs btn-square",
      title: "Capture dashboard health snapshot",
      aria_label: "Capture dashboard health snapshot",
      icon: %{name: "hero-bookmark-square", class: "h-3.5 w-3.5"},
      attrs:
        string_data_attrs(%{
          "phx-click" => "capture_dashboard_health_snapshot",
          "phx-value-snapshot" => snapshot_json,
          "data-dashboard-health-snapshot-capture" => "",
          "data-dashboard-health-snapshot-schema" => Map.get(health, :snapshot_schema),
          "data-dashboard-health-snapshot-id" => Map.get(health, :snapshot_id)
        })
    }
  end

  defp dashboard_health_group_dto(group, index) do
    group_key = dashboard_health_text(Map.get(group, :key))
    group_label = dashboard_health_text(Map.get(group, :label))
    group_count = dashboard_health_text(Map.get(group, :count))
    overlay_id = "dashboard-health-group-#{group_key}"
    overlay_label = "#{group_label} widgets"

    %{
      key: "#{overlay_id}-#{index}",
      order: index,
      overlay: %{
        id: overlay_id,
        class: "cadence-overlay",
        open_attr: "",
        attrs:
          string_data_attrs(%{
            "data-overlay-kind" => "popover",
            "data-overlay-placement" => "bottom-end",
            "data-dashboard-health-group" => Map.get(group, :key),
            "data-dashboard-health-group-count" => Map.get(group, :count),
            "data-dashboard-health-group-placements" => Map.get(group, :placement_ids)
          }),
        trigger: %{
          id: "#{overlay_id}-trigger",
          type: "button",
          class: "cadence-overlay-trigger",
          aria_expanded: %{open: "true", closed: "false"},
          attrs:
            string_data_attrs(%{
              "data-overlay-trigger" => "",
              "aria-haspopup" => "dialog",
              "aria-controls" => "#{overlay_id}-panel",
              "aria-label" => overlay_label
            })
        },
        panel: %{
          id: "#{overlay_id}-panel",
          class: "cadence-overlay-panel cadence-popover-panel",
          attrs:
            string_data_attrs(%{
              "data-overlay-panel" => "",
              "data-overlay-width" => "md",
              "aria-label" => overlay_label
            })
        }
      },
      badge: %{
        class: "badge badge-xs cursor-pointer gap-1 #{dashboard_health_group_class(group)}",
        title: "#{group_label}: #{group_count}",
        attrs:
          string_data_attrs(%{
            "data-dashboard-health-badge" => Map.get(group, :key),
            "data-dashboard-health-badge-count" => Map.get(group, :count),
            "data-dashboard-health-badge-placements" => Map.get(group, :placement_ids)
          }),
        icon: %{name: dashboard_health_group_icon(group), class: "h-3 w-3"},
        label: group_label,
        count: group_count,
        count_class: "font-mono"
      },
      details: %{
        class: "p-2 text-xs",
        heading: %{class: "font-semibold text-base-content", text: overlay_label},
        items_class: "mt-2 space-y-1"
      },
      items:
        group
        |> Map.get(:items, [])
        |> Enum.with_index()
        |> Enum.map(fn {item, item_index} ->
          dashboard_health_item_dto(item, group_key, item_index)
        end)
    }
  end

  defp dashboard_health_item_dto(item, group_key, index) do
    placement_id = dashboard_health_text(Map.get(item, :placement_id))

    %{
      key: "dashboard-health-item-#{group_key}-#{index}-#{placement_id}",
      order: index,
      href: "#widget-#{placement_id}",
      class: "grid grid-cols-[minmax(0,1fr)_auto] gap-2 rounded px-2 py-1 hover:bg-base-200",
      attrs:
        string_data_attrs(%{
          "data-dashboard-health-item" => Map.get(item, :placement_id),
          "data-dashboard-health-item-state" => Map.get(item, :state_text),
          "data-dashboard-health-item-lifecycle" => Map.get(item, :lifecycle_state_text),
          "data-dashboard-health-item-source" => Map.get(item, :source_state_text),
          "data-dashboard-health-item-warnings" => Map.get(item, :warning_codes_text),
          "data-dashboard-health-item-reason" => Map.get(item, :reason)
        }),
      title: %{
        class: "min-w-0 truncate",
        text: dashboard_health_text(Map.get(item, :title))
      },
      reason: %{
        class: "font-mono text-base-content/60",
        text: dashboard_health_text(Map.get(item, :reason))
      }
    }
  end

  defp dashboard_health_groups(health) when is_map(health), do: Map.get(health, :groups, [])

  defp dashboard_health_summary(health) when is_map(health) do
    [
      "widgets #{dashboard_health_text(Map.get(health, :widget_count, 0))}",
      "affected #{dashboard_health_text(Map.get(health, :affected_count, 0))}",
      "blocked #{dashboard_health_text(Map.get(health, :blocked_count, 0))}",
      "stale #{dashboard_health_text(Map.get(health, :stale_count, 0))}",
      "degraded #{dashboard_health_text(Map.get(health, :degraded_count, 0))}"
    ]
    |> Enum.join(" / ")
  end

  defp dashboard_health_snapshot_json(health) when is_map(health) do
    health
    |> Map.get(:snapshot, %{"schema" => Map.get(health, :snapshot_schema)})
    |> Jason.encode!()
  end

  defp dashboard_health_evidence_attrs(health) when is_map(health) do
    EvidenceQuery.phx_value_attrs(%{
      "kind" => "dashboard_health",
      "dashboard-health-schema" => Map.get(health, :snapshot_schema),
      "dashboard-health-snapshot-id" => Map.get(health, :snapshot_id),
      "dashboard-health-state" => Map.get(health, :state_text),
      "dashboard-health-severity" => Map.get(health, :severity_text),
      "dashboard-health-widgets" => Map.get(health, :widget_count),
      "dashboard-health-ready" => Map.get(health, :ready_count),
      "dashboard-health-degraded" => Map.get(health, :degraded_count),
      "dashboard-health-stale" => Map.get(health, :stale_count),
      "dashboard-health-blocked" => Map.get(health, :blocked_count),
      "dashboard-health-affected" => Map.get(health, :affected_count),
      "dashboard-health-states" => Map.get(health, :states),
      "dashboard-health-affected-placements" => Map.get(health, :affected_placements),
      "dashboard-health-blocked-placements" => Map.get(health, :blocked_placements),
      "dashboard-health-stale-placements" => Map.get(health, :stale_placements),
      "dashboard-health-degraded-placements" => Map.get(health, :degraded_placements)
    })
  end

  defp string_data_attrs(attrs) do
    Enum.reduce(attrs, %{}, fn
      {_key, nil}, data_attrs ->
        data_attrs

      {key, value}, data_attrs ->
        Map.put(data_attrs, to_string(key), data_attr_value(value))
    end)
  end

  defp data_attr_value(value) when is_binary(value), do: value
  defp data_attr_value(value) when is_boolean(value), do: to_string(value)
  defp data_attr_value(value) when is_number(value), do: to_string(value)
  defp data_attr_value(value) when is_atom(value), do: Atom.to_string(value)
  defp data_attr_value(value), do: inspect(value)

  defp dashboard_health_text(nil), do: ""
  defp dashboard_health_text(value) when is_binary(value), do: value
  defp dashboard_health_text(value) when is_atom(value), do: Atom.to_string(value)
  defp dashboard_health_text(value) when is_number(value), do: to_string(value)
  defp dashboard_health_text(value), do: inspect(value)

  defp dashboard_health_strip_class(%{state: :blocked}), do: "border-error/30 bg-error/10"
  defp dashboard_health_strip_class(%{state: :stale}), do: "border-warning/30 bg-warning/10"
  defp dashboard_health_strip_class(%{state: :degraded}), do: "border-warning/30 bg-warning/10"
  defp dashboard_health_strip_class(_health), do: "border-base-300/60 bg-base-200/30"

  defp dashboard_health_badge_class(%{state: :blocked}), do: "badge-error"
  defp dashboard_health_badge_class(%{state: :stale}), do: "badge-warning"
  defp dashboard_health_badge_class(%{state: :degraded}), do: "badge-warning badge-outline"
  defp dashboard_health_badge_class(_health), do: "badge-success badge-outline"

  defp dashboard_health_group_class(%{state: :blocked}), do: "badge-error"
  defp dashboard_health_group_class(%{state: :stale}), do: "badge-warning"
  defp dashboard_health_group_class(%{state: :degraded}), do: "badge-warning badge-outline"
  defp dashboard_health_group_class(_group), do: "badge-success badge-outline"

  defp dashboard_health_group_icon(%{state: :blocked}), do: "hero-no-symbol"
  defp dashboard_health_group_icon(%{state: :stale}), do: "hero-clock"
  defp dashboard_health_group_icon(%{state: :degraded}), do: "hero-exclamation-triangle"
  defp dashboard_health_group_icon(_group), do: "hero-check-circle"
end
