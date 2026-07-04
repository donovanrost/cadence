defmodule CadenceWeb.OpsDashboardShowLive.VersionListComponents do
  @moduledoc false
  use CadenceWeb, :html

  attr :version_history, :map, required: true

  def version_overview(assigns) do
    ~H"""
    <div class="space-y-5">
      <div class="grid grid-cols-3 gap-2 text-xs">
        <.pointer_metric
          :for={pointer <- @version_history.pointers}
          label={pointer.label}
          value={pointer.value}
        />
      </div>

      <section class="space-y-2">
        <div class="flex items-center justify-between">
          <h3 class="hud-label">Versions</h3>
          <span class="font-mono text-xs text-base-content/50">{@version_history.count}</span>
        </div>
        <ol id="dashboard-version-list" class="space-y-2">
          <li
            :for={version <- @version_history.versions}
            id={version.dom_id}
            data-version-restore-available={version.restore_action.available_text}
            data-version-restore-reason={version.restore_action.reason_text}
            data-version-publish-available={version.publish_action.available_text}
            data-version-publish-reason={version.publish_action.reason_text}
            data-version-lineage-kind={version.lineage.kind}
            data-version-lineage-source-version={version.lineage.source_version_text}
            class="border border-base-300/70 bg-base-100/40 p-2"
          >
            <div class="flex items-start justify-between gap-3">
              <div class="min-w-0">
                <div class="flex flex-wrap items-center gap-1.5">
                  <span class="font-mono text-sm font-semibold">v{version.version}</span>
                  <span class="badge badge-xs badge-outline">
                    {version.snapshot_label}
                  </span>
                  <span
                    :for={pointer <- version.pointer_labels}
                    data-version-pointer={pointer.label}
                    class={[
                      "badge badge-xs",
                      pointer.badge_class
                    ]}
                  >
                    {pointer.label}
                  </span>
                </div>
                <dl class="mt-2 grid grid-cols-[5.5rem_1fr] gap-x-2 gap-y-1 text-xs">
                  <dt class="hud-label">Saved</dt>
                  <dd class="font-mono text-base-content/70">{version.saved_at}</dd>
                  <dt class="hud-label">Author</dt>
                  <dd data-version-field="Author" class="truncate text-base-content/70">
                    {version.created_by}
                  </dd>
                  <dt class="hud-label">Origin</dt>
                  <dd data-version-field="Origin" class="font-mono text-base-content/70">
                    {version.lineage.label}
                  </dd>
                  <dt class="hud-label">Parent</dt>
                  <dd class="font-mono text-base-content/70">
                    {version.parent_version}
                  </dd>
                  <dt class="hud-label">Based on</dt>
                  <dd class="font-mono text-base-content/70">
                    {version.based_on_version}
                  </dd>
                </dl>
                <p
                  :if={version.change_summary}
                  data-version-field="Summary"
                  class="mt-2 text-xs text-base-content/70"
                >
                  {version.change_summary}
                </p>
              </div>
              <div class="flex shrink-0 flex-col gap-1">
                <.button
                  id={version.publish_button_id}
                  variant={:ghost}
                  size={:xs}
                  phx-click="publish_dashboard_version"
                  phx-value-version={version.version}
                  disabled={not version.publish_action.available}
                  data-version-action="publish"
                  data-version-action-available={version.publish_action.available_text}
                  data-version-action-reason={version.publish_action.reason_text}
                  data-confirm={version.publish_confirm}
                >
                  <.icon name="hero-arrow-up-tray" class="h-3.5 w-3.5" /> Publish
                </.button>
                <.button
                  id={version.restore_button_id}
                  variant={:ghost}
                  size={:xs}
                  phx-click="restore_version_as_draft"
                  phx-value-version={version.version}
                  disabled={not version.restore_action.available}
                  data-version-action="restore"
                  data-version-action-available={version.restore_action.available_text}
                  data-version-action-reason={version.restore_action.reason_text}
                  data-confirm={version.restore_confirm}
                >
                  <.icon name="hero-arrow-uturn-left" class="h-3.5 w-3.5" /> Restore
                </.button>
              </div>
            </div>
          </li>
        </ol>

        <p :if={@version_history.empty} class="text-sm text-base-content/60">
          No saved versions.
        </p>
      </section>
    </div>
    """
  end

  attr :label, :string, required: true
  attr :value, :any, required: true

  defp pointer_metric(assigns) do
    ~H"""
    <div class="border border-base-300/70 bg-base-100/40 px-2 py-1.5">
      <div class="hud-label">{@label}</div>
      <div class="font-mono text-sm">{@value}</div>
    </div>
    """
  end
end
