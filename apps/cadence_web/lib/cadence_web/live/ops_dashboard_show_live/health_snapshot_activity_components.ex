defmodule CadenceWeb.OpsDashboardShowLive.HealthSnapshotActivityComponents do
  @moduledoc false
  use CadenceWeb, :html

  alias CadenceWeb.OpsDashboardShowLive.HealthSnapshotActivity

  alias Cadence.Dashboards.LifecycleEvent

  attr :event, LifecycleEvent, required: true

  def event_details(assigns) do
    assigns =
      assign(
        assigns,
        :health_snapshot,
        HealthSnapshotActivity.build(assigns.event)
      )

    ~H"""
    <div
      :if={@health_snapshot.present?}
      class="mt-3 space-y-3 border-t border-base-300/70 pt-3 text-xs"
      data-dashboard-health-snapshot-event={@event.dashboard_lifecycle_event_id}
      data-dashboard-health-snapshot-capture-schema={@health_snapshot.capture_schema}
      data-dashboard-health-snapshot-schema={@health_snapshot.snapshot_schema}
      data-dashboard-health-snapshot-id={@health_snapshot.snapshot_id}
      data-dashboard-health-snapshot-state={@health_snapshot.state}
      data-dashboard-health-snapshot-severity={@health_snapshot.severity}
      data-dashboard-health-snapshot-source={@health_snapshot.source}
      data-dashboard-health-snapshot-reason={@health_snapshot.captured_reason}
    >
      <div class="flex items-start justify-between gap-2">
        <dl class="grid min-w-0 grid-cols-[5rem_1fr] gap-x-2 gap-y-1">
          <dt class="hud-label">Snapshot</dt>
          <dd data-activity-field="Health snapshot" class="truncate font-mono text-base-content/70">
            {@health_snapshot.snapshot_id}
          </dd>
          <dt class="hud-label">State</dt>
          <dd data-activity-field="Health state" class="font-mono text-base-content/70">
            {@health_snapshot.state}
          </dd>
          <dt class="hud-label">Severity</dt>
          <dd data-activity-field="Health severity" class="font-mono text-base-content/70">
            {@health_snapshot.severity}
          </dd>
        </dl>

        <button
          id={"dashboard-health-snapshot-event-copy-#{@event.dashboard_lifecycle_event_id}"}
          type="button"
          phx-hook="ClipboardButton"
          data-clipboard-text={@health_snapshot.snapshot_json}
          data-dashboard-health-snapshot-event-copy={@event.dashboard_lifecycle_event_id}
          data-dashboard-health-snapshot-id={@health_snapshot.snapshot_id}
          data-dashboard-health-snapshot-schema={@health_snapshot.snapshot_schema}
          class="btn btn-ghost btn-xs shrink-0"
        >
          <.icon name="hero-clipboard-document" class="h-3.5 w-3.5" /> Copy
        </button>
      </div>

      <div class="grid grid-cols-2 gap-2">
        <div
          :for={count <- @health_snapshot.counts}
          class="border border-base-300/70 bg-base-100/50 px-2 py-1.5"
          data-dashboard-health-snapshot-count={count.key}
          data-dashboard-health-snapshot-count-value={count.value}
        >
          <div class="hud-label">{count.label}</div>
          <div class="font-mono text-base-content/80">{count.value}</div>
        </div>
      </div>

      <dl
        :if={@health_snapshot.placements != []}
        class="grid grid-cols-[5rem_1fr] gap-x-2 gap-y-1"
      >
        <%= for placement <- @health_snapshot.placements do %>
          <dt class="hud-label">{placement.label}</dt>
          <dd
            data-dashboard-health-snapshot-placements={placement.key}
            data-dashboard-health-snapshot-placement-ids={placement.ids_attr}
            class="font-mono text-base-content/70"
          >
            {placement.ids_text}
          </dd>
        <% end %>
      </dl>
    </div>
    """
  end
end
