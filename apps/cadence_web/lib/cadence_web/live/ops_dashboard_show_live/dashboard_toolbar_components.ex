defmodule CadenceWeb.OpsDashboardShowLive.DashboardToolbarComponents do
  @moduledoc false
  use CadenceWeb, :html

  alias Cadence.Dashboards.ComparisonReviewQueue
  alias CadenceWeb.OpsDashboardShowLive.DashboardRuntimeContextComponents
  alias CadenceWeb.OpsDashboardShowLive.DashboardRuntimeControlsComponents

  attr :dashboard_document, :any, required: true
  attr :dashboard_lifecycle_status, :any, required: true
  attr :dashboard_lifecycle_events, :list, default: []
  attr :dashboard_comparison_review_queue, :map, default: nil
  attr :dashboard_publish_readiness, :map, default: nil
  attr :edit_mode?, :boolean, required: true
  attr :show_context?, :boolean, required: true
  attr :current_mission, :any, default: nil
  attr :spacecraft, :list, required: true
  attr :source_endpoints, :list, default: []
  attr :transports, :list, default: []
  attr :ground_stations, :list, default: []
  attr :link_assignments, :list, default: []
  attr :scheduled_contacts, :list, default: []
  attr :realized_contacts, :list, default: []
  attr :context_spacecraft_id, :string, required: true
  attr :context_scope_kind, :string, default: nil
  attr :context_scope_id, :string, default: nil
  attr :context_scope_ids, :list, default: []
  attr :time_mode, :string, required: true
  attr :time_axis, :string, default: "generation_time"
  attr :time_from, :string, default: nil
  attr :time_to, :string, default: nil
  attr :replay_run_id, :string, default: nil
  attr :time_validation, :string, default: "ok"
  attr :data_realm, :string, required: true
  attr :data_realms, :list, required: true
  attr :data_view, :string, required: true
  attr :compare_data_view, :string, default: nil
  attr :data_source_id, :string, default: nil
  attr :source_binding_id, :string, default: nil
  attr :data_bindings, :list, required: true
  attr :replay_runs, :list, default: []
  attr :selected_replay_run, :any, default: nil
  attr :limit_mode, :string, required: true
  attr :limit_mode_fallback, :map, default: nil
  attr :selected_data_ref, :any, default: nil
  attr :query, :string, required: true

  def dashboard_toolbar(assigns) do
    ~H"""
    <div class="min-h-9 shrink-0 flex flex-wrap items-center gap-2 px-2 py-1 border-b border-base-300/60 bg-base-200/60">
      <h1
        class="min-w-0 flex-1 basis-40 text-sm font-semibold truncate"
        title={@dashboard_document.description}
      >
        {@dashboard_document.name}
      </h1>
      <DashboardRuntimeContextComponents.context_selector
        :if={@show_context? and not @edit_mode?}
        current_mission={@current_mission}
        spacecraft={@spacecraft}
        source_endpoints={@source_endpoints}
        transports={@transports}
        ground_stations={@ground_stations}
        link_assignments={@link_assignments}
        scheduled_contacts={@scheduled_contacts}
        realized_contacts={@realized_contacts}
        context_spacecraft_id={@context_spacecraft_id}
        context_scope_kind={@context_scope_kind}
        context_scope_id={@context_scope_id}
        context_scope_ids={@context_scope_ids}
        query={@query}
      />
      <DashboardRuntimeControlsComponents.runtime_context_controls
        :if={not @edit_mode?}
        time_mode={@time_mode}
        time_from={@time_from}
        time_to={@time_to}
        replay_run_id={@replay_run_id}
        time_validation={@time_validation}
        data_realm={@data_realm}
        data_realms={@data_realms}
        data_view={@data_view}
        compare_data_view={@compare_data_view}
        data_source_id={@data_source_id}
        source_binding_id={@source_binding_id}
        data_bindings={@data_bindings}
        replay_runs={@replay_runs}
        selected_replay_run={@selected_replay_run}
        limit_mode={@limit_mode}
        limit_mode_fallback={@limit_mode_fallback}
        selected_data_ref={@selected_data_ref}
        time_axis={@time_axis}
      />
      <div class="flex-1"></div>
      <button
        :if={@dashboard_publish_readiness}
        id="dashboard-publish-readiness-summary"
        type="button"
        phx-click="open_versions"
        class={[
          "inline-flex h-6 items-center gap-1 rounded border px-2 text-[11px] font-medium",
          publish_readiness_class(@dashboard_publish_readiness.status)
        ]}
        data-dashboard-publish-readiness-status={@dashboard_publish_readiness.status}
        data-dashboard-publish-readiness-issue-count={
          publish_readiness_issue_count(@dashboard_publish_readiness)
        }
      >
        <.icon name={publish_readiness_icon(@dashboard_publish_readiness.status)} class="h-3 w-3" />
        <span>{publish_readiness_label(@dashboard_publish_readiness.status)}</span>
        <span
          :if={publish_readiness_issue_count(@dashboard_publish_readiness) != "0"}
          class="font-mono opacity-80"
        >
          {publish_readiness_issue_count(@dashboard_publish_readiness)}
        </span>
      </button>
      <span :if={@edit_mode?} class="text-xs text-warning" id="edit-paused-note">
        Live updates paused while editing
      </span>
      <.button
        id="edit-layout-toggle"
        variant={if @edit_mode?, do: :primary, else: :ghost}
        size={:xs}
        phx-click="toggle_edit"
      >
        <.icon name="hero-arrows-pointing-out" class="h-3.5 w-3.5" />
        {if @edit_mode?, do: "Done", else: "Edit Layout"}
      </.button>
      <.button id="add-widget-button" variant={:ghost} size={:xs} phx-click="open_add_widget">
        <.icon name="hero-plus" class="h-3.5 w-3.5" /> Widget
      </.button>
      <.button
        id="dashboard-historical-workflow-request-button"
        variant={:ghost}
        size={:xs}
        phx-click="open_historical_workflow_request"
      >
        <.icon name="hero-document-plus" class="h-3.5 w-3.5" /> Data Request
      </.button>
      <.button
        id="dashboard-versions-button"
        variant={:ghost}
        size={:xs}
        phx-click={versions_button_event(@dashboard_comparison_review_queue)}
        data-dashboard-comparison-review-open-count={
          comparison_review_open_request_count(@dashboard_comparison_review_queue)
        }
        data-dashboard-comparison-review-open-requests={
          comparison_review_open_request_ids_attr(@dashboard_comparison_review_queue)
        }
        data-dashboard-comparison-review-open-placements={
          comparison_review_open_placements_attr(@dashboard_comparison_review_queue)
        }
      >
        <.icon name="hero-clock" class="h-3.5 w-3.5" /> Versions
        <span
          :if={comparison_review_open_request_count(@dashboard_comparison_review_queue) != "0"}
          class="badge badge-warning badge-xs"
          data-dashboard-comparison-review-open-toolbar-badge
        >
          {comparison_review_open_request_count(@dashboard_comparison_review_queue)}
        </span>
      </.button>
      <.button
        id="dashboard-diagnostics-button"
        variant={:ghost}
        size={:xs}
        phx-click="open_diagnostics"
      >
        <.icon name="hero-chart-bar-square" class="h-3.5 w-3.5" /> Diagnostics
      </.button>
      <.action_menu id="dashboard-menu">
        <:action>
          <button phx-click="save_runtime_defaults">
            <.icon name="hero-bookmark-square" class="h-4 w-4" /> Save runtime defaults
          </button>
        </:action>
        <:action>
          <button
            phx-click="publish_dashboard"
            disabled={not lifecycle_action_available?(@dashboard_lifecycle_status, :publish)}
            data-dashboard-lifecycle-action="publish"
            data-dashboard-action-available={
              lifecycle_action_available_text(@dashboard_lifecycle_status, :publish)
            }
          >
            <.icon name="hero-arrow-up-tray" class="h-4 w-4" /> Publish latest draft
          </button>
        </:action>
        <:action>
          <button phx-click="open_rename">Rename</button>
        </:action>
        <:action>
          <button
            phx-click="archive_dashboard"
            disabled={not lifecycle_action_available?(@dashboard_lifecycle_status, :archive)}
            data-dashboard-lifecycle-action="archive"
            data-dashboard-action-available={
              lifecycle_action_available_text(@dashboard_lifecycle_status, :archive)
            }
            data-confirm="Archive this dashboard for every operator on the mission?"
          >
            <.icon name="hero-archive-box" class="h-4 w-4" /> Archive
          </button>
        </:action>
      </.action_menu>
    </div>
    """
  end

  defp lifecycle_action_available?(%{publish_available?: available?}, :publish),
    do: available? == true

  defp lifecycle_action_available?(%{archive_available?: available?}, :archive),
    do: available? == true

  defp lifecycle_action_available?(_status, _action), do: false

  defp lifecycle_action_available_text(status, action) do
    if lifecycle_action_available?(status, action), do: "true", else: "false"
  end

  defp publish_readiness_label("blocked"), do: "Publish blocked"
  defp publish_readiness_label("stale"), do: "Re-check publish"
  defp publish_readiness_label("warnings"), do: "Publish warnings"
  defp publish_readiness_label("clean"), do: "Publish ready"
  defp publish_readiness_label(_status), do: "Publish status"

  defp publish_readiness_icon("blocked"), do: "hero-exclamation-triangle"
  defp publish_readiness_icon("stale"), do: "hero-arrow-path"
  defp publish_readiness_icon("warnings"), do: "hero-exclamation-circle"
  defp publish_readiness_icon("clean"), do: "hero-check-circle"
  defp publish_readiness_icon(_status), do: "hero-information-circle"

  defp publish_readiness_class("blocked"), do: "border-error/40 bg-error/10 text-error"
  defp publish_readiness_class("stale"), do: "border-warning/40 bg-warning/10 text-warning"
  defp publish_readiness_class("warnings"), do: "border-warning/40 bg-warning/10 text-warning"
  defp publish_readiness_class("clean"), do: "border-success/40 bg-success/10 text-success"
  defp publish_readiness_class(_status), do: "border-base-300 bg-base-100 text-base-content/70"

  defp publish_readiness_issue_count(%{issues: issues}) when is_list(issues) do
    issues |> length() |> Integer.to_string()
  end

  defp publish_readiness_issue_count(_validation), do: "0"

  defp versions_button_event(open_summary) do
    if comparison_review_open_summary(open_summary).count == 0 do
      "open_versions"
    else
      "open_review_activity"
    end
  end

  defp comparison_review_open_request_count(open_summary) do
    open_summary
    |> comparison_review_open_summary()
    |> Map.fetch!(:count_text)
  end

  defp comparison_review_open_request_ids_attr(open_summary) do
    open_summary
    |> comparison_review_open_summary()
    |> Map.fetch!(:request_ids_attr)
  end

  defp comparison_review_open_placements_attr(open_summary) do
    open_summary
    |> comparison_review_open_summary()
    |> Map.fetch!(:placements_attr)
  end

  defp comparison_review_open_summary(%{count: count, requests: requests} = open_summary)
       when is_integer(count) and is_list(requests) do
    open_summary
  end

  defp comparison_review_open_summary(_open_summary), do: ComparisonReviewQueue.open_summary([])
end
