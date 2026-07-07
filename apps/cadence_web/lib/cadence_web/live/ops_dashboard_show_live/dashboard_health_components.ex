defmodule CadenceWeb.OpsDashboardShowLive.DashboardHealthComponents do
  @moduledoc false
  use CadenceWeb, :html

  alias CadenceWeb.OpsDashboardShowLive.EvidenceQuery

  attr :health, :map, required: true

  def dashboard_health_strip(assigns) do
    assigns =
      assign(
        assigns,
        :evidence_attrs,
        dashboard_health_evidence_attrs(assigns.health)
      )

    ~H"""
    <div
      :if={dashboard_health_visible?(@health)}
      id="dashboard-health-rollup"
      data-dashboard-health-rollup
      data-dashboard-health-snapshot-id={dashboard_health_value(@health, :snapshot_id)}
      data-dashboard-health-state={dashboard_health_value(@health, :state_text)}
      data-dashboard-health-severity={dashboard_health_value(@health, :severity_text)}
      data-dashboard-health-widgets={dashboard_health_value(@health, :widget_count)}
      data-dashboard-health-ready={dashboard_health_value(@health, :ready_count)}
      data-dashboard-health-degraded={dashboard_health_value(@health, :degraded_count)}
      data-dashboard-health-stale={dashboard_health_value(@health, :stale_count)}
      data-dashboard-health-blocked={dashboard_health_value(@health, :blocked_count)}
      data-dashboard-health-affected={dashboard_health_value(@health, :affected_count)}
      data-dashboard-health-states={dashboard_health_value(@health, :states)}
      data-dashboard-health-affected-placements={dashboard_health_value(@health, :affected_placements)}
      data-dashboard-health-blocked-placements={dashboard_health_value(@health, :blocked_placements)}
      data-dashboard-health-stale-placements={dashboard_health_value(@health, :stale_placements)}
      data-dashboard-health-degraded-placements={dashboard_health_value(@health, :degraded_placements)}
      class={[
        "shrink-0 flex flex-wrap items-center gap-2 px-2 py-1 border-b text-xs",
        dashboard_health_strip_class(@health)
      ]}
    >
      <span class="hud-label">Dashboard health</span>
      <span class={["badge badge-xs", dashboard_health_badge_class(@health)]}>
        {dashboard_health_value(@health, :label)}
      </span>
      <span class="text-base-content/70">
        {dashboard_health_summary(@health)}
      </span>
      <div class="ml-auto flex items-center gap-1">
        <button
          id="dashboard-health-snapshot-copy"
          type="button"
          phx-hook="ClipboardButton"
          data-clipboard-text={dashboard_health_snapshot_json(@health)}
          class="btn btn-ghost btn-xs btn-square"
          title="Copy dashboard health snapshot"
          aria-label="Copy dashboard health snapshot"
          data-dashboard-health-snapshot-copy
          data-dashboard-health-snapshot-schema={dashboard_health_value(@health, :snapshot_schema)}
          data-dashboard-health-snapshot-id={dashboard_health_value(@health, :snapshot_id)}
        >
          <.icon name="hero-clipboard-document" class="h-3.5 w-3.5" />
        </button>
        <button
          type="button"
          phx-click="open_evidence"
          {@evidence_attrs}
          class="btn btn-ghost btn-xs btn-square"
          title="Open dashboard health evidence"
          aria-label="Open dashboard health evidence"
          data-dashboard-health-evidence-open
        >
          <.icon name="hero-link" class="h-3.5 w-3.5" />
        </button>
        <button
          id="dashboard-health-snapshot-capture"
          type="button"
          phx-click="capture_dashboard_health_snapshot"
          phx-value-snapshot={dashboard_health_snapshot_json(@health)}
          class="btn btn-ghost btn-xs btn-square"
          title="Capture dashboard health snapshot"
          aria-label="Capture dashboard health snapshot"
          data-dashboard-health-snapshot-capture
          data-dashboard-health-snapshot-schema={dashboard_health_value(@health, :snapshot_schema)}
          data-dashboard-health-snapshot-id={dashboard_health_value(@health, :snapshot_id)}
        >
          <.icon name="hero-bookmark-square" class="h-3.5 w-3.5" />
        </button>
        <details
          :for={group <- dashboard_health_groups(@health)}
          class="dropdown dropdown-end"
          data-dashboard-health-group={group.key}
          data-dashboard-health-group-count={group.count}
          data-dashboard-health-group-placements={group.placement_ids}
        >
          <summary
            class={["badge badge-xs cursor-pointer gap-1", dashboard_health_group_class(group)]}
            data-dashboard-health-badge={group.key}
            data-dashboard-health-badge-count={group.count}
            data-dashboard-health-badge-placements={group.placement_ids}
            title={"#{group.label}: #{group.count}"}
          >
            <.icon name={dashboard_health_group_icon(group)} class="h-3 w-3" />
            <span>{group.label}</span>
            <span class="font-mono">{group.count}</span>
          </summary>
          <div class="dropdown-content z-[var(--z-popover)] mt-1 w-80 rounded border border-base-300 bg-base-100 p-2 text-xs shadow-lg">
            <div class="font-semibold text-base-content">{group.label} widgets</div>
            <div class="mt-2 space-y-1">
              <a
                :for={item <- group.items}
                href={"#widget-#{item.placement_id}"}
                class="grid grid-cols-[minmax(0,1fr)_auto] gap-2 rounded px-2 py-1 hover:bg-base-200"
                data-dashboard-health-item={item.placement_id}
                data-dashboard-health-item-state={item.state_text}
                data-dashboard-health-item-lifecycle={item.lifecycle_state_text}
                data-dashboard-health-item-source={item.source_state_text}
                data-dashboard-health-item-warnings={item.warning_codes_text}
                data-dashboard-health-item-reason={item.reason}
              >
                <span class="min-w-0 truncate">{item.title}</span>
                <span class="font-mono text-base-content/60">{item.reason}</span>
              </a>
            </div>
          </div>
        </details>
      </div>
    </div>
    """
  end

  defp dashboard_health_visible?(health) when is_map(health),
    do: Map.get(health, :visible?) == true

  defp dashboard_health_visible?(_health), do: false

  defp dashboard_health_value(health, key) when is_map(health), do: Map.get(health, key)

  defp dashboard_health_groups(health) when is_map(health), do: Map.get(health, :groups, [])

  defp dashboard_health_summary(health) when is_map(health) do
    [
      "widgets #{Map.get(health, :widget_count, 0)}",
      "affected #{Map.get(health, :affected_count, 0)}",
      "blocked #{Map.get(health, :blocked_count, 0)}",
      "stale #{Map.get(health, :stale_count, 0)}",
      "degraded #{Map.get(health, :degraded_count, 0)}"
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

  defp dashboard_health_evidence_attrs(_health), do: %{}

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
