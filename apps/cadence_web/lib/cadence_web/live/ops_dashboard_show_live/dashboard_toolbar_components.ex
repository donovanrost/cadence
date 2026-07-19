defmodule CadenceWeb.OpsDashboardShowLive.DashboardToolbarComponents do
  @moduledoc false
  use CadenceWeb, :html

  alias Cadence.Dashboards.ComparisonReviewQueue
  alias CadenceWeb.OpsDashboardShowLive.DashboardRuntimeContextComponents
  alias CadenceWeb.OpsDashboardShowLive.DashboardRuntimeControlsComponents
  alias CadenceWeb.OpsDashboardShowLive.WidgetWarningComponents

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
  attr :dashboard_warnings, :list, default: []
  attr :dashboard_degraded?, :boolean, default: false
  attr :dashboard_health, :map, default: %{}

  def dashboard_toolbar(assigns) do
    assigns =
      assigns
      |> assign(:data_issue_count, data_issue_count(assigns))
      |> assign(:data_issue_status, data_issue_status(assigns))

    ~H"""
    <div
      id="dashboard-telemetry-toolbar"
      class="min-h-11 shrink-0 flex items-center gap-2 border-b border-base-300/60 bg-base-200/45 px-3 py-1.5"
    >
      <div class="min-w-0 flex-1">
        <h1
          class="break-words text-sm font-semibold leading-tight tracking-tight"
          title={@dashboard_document.description}
        >
          {@dashboard_document.name}
        </h1>
        <p class="hidden truncate text-[0.65rem] text-base-content/50 sm:block">
          Telemetry dashboard
        </p>
      </div>

      <.popover
        :if={not @edit_mode?}
        id="dashboard-data-controls"
        trigger_id="dashboard-data-controls-toggle"
        panel_id="dashboard-data-controls-panel"
        label="Dashboard scope and time controls"
        width={:viewport}
      >
        <:trigger>
          <span
          class="btn btn-ghost btn-xs h-7 gap-1.5 border border-base-300/70 bg-base-100/50 px-2 font-normal"
          >
            <.icon name="hero-adjustments-horizontal" class="h-3.5 w-3.5 text-base-content/55" />
            <span class="hidden max-w-36 truncate font-mono text-[0.68rem] sm:inline">
              {runtime_scope_label(@current_mission, @spacecraft, @context_scope_kind, @context_scope_id, @context_scope_ids)}
            </span>
            <span class="text-base-content/35">/</span>
            <span
              class="font-mono text-[0.68rem] font-semibold uppercase tracking-wide"
              data-dashboard-time-summary={@time_mode}
            >
              {time_mode_label(@time_mode)}
            </span>
            <.icon name="hero-chevron-down" class="h-3 w-3 text-base-content/40" />
          </span>
        </:trigger>
        <div class="p-3">
          <div class="mb-3 flex items-center gap-2 border-b border-base-300/60 pb-2">
            <div>
              <p class="hud-label">Scope & time</p>
              <p class="mt-0.5 text-xs text-base-content/55">
                Refine what the telemetry canvas is showing.
              </p>
            </div>
          </div>
          <div class="flex flex-col gap-3">
            <DashboardRuntimeContextComponents.context_selector
              :if={@show_context?}
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
          </div>
        </div>
      </.popover>

      <.popover
        :if={@data_issue_count > 0}
        id="dashboard-data-issues"
        label="Dashboard data health"
        width={:md}
        data-dashboard-data-issue-count={@data_issue_count}
        data-dashboard-data-issue-status={@data_issue_status}
        data-dashboard-data-issue-codes={data_issue_codes(@dashboard_warnings)}
      >
        <:trigger>
          <span
            class={[
              "inline-flex h-7 cursor-pointer items-center gap-1.5 rounded border px-2 text-[0.68rem] font-semibold",
              data_issue_class(@data_issue_status)
            ]}
            title="Open data health summary"
            data-dashboard-data-issues-toggle
          >
            <.icon name="hero-exclamation-triangle" class="h-3.5 w-3.5" />
            <span>{@data_issue_count}</span>
            <span class="hidden sm:inline">
              data {if @data_issue_count == 1, do: "issue", else: "issues"}
            </span>
          </span>
        </:trigger>
        <div class="p-3 text-xs">
          <div class="flex items-start gap-2 border-b border-base-300/60 pb-2">
            <.icon name="hero-signal" class="mt-0.5 h-4 w-4 text-warning" />
            <div class="min-w-0">
              <p class="font-semibold text-base-content">Data health</p>
              <p class="mt-0.5 text-base-content/60">{data_issue_summary(@dashboard_health)}</p>
            </div>
          </div>
          <div :if={@dashboard_warnings != []} class="mt-2 flex flex-wrap gap-1">
            <WidgetWarningComponents.engine_warning_badge
              :for={{warning, index} <- Enum.with_index(@dashboard_warnings)}
              id={"dashboard-data-issue-warning-#{index}"}
              warning={warning}
            />
          </div>
          <p
            :if={@dashboard_degraded? and @dashboard_warnings == []}
            class="mt-2 text-base-content/65"
          >
            One or more sources returned degraded data.
          </p>
          <button
            id="dashboard-data-issues-open"
            type="button"
            phx-click="open_diagnostics"
            class="btn btn-outline btn-xs mt-3 w-full justify-start"
          >
            <.icon name="hero-chart-bar-square" class="h-3.5 w-3.5" />
            Open diagnostics
          </button>
        </div>
      </.popover>

      <button
        :if={@edit_mode? and @dashboard_publish_readiness}
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
        :if={@edit_mode?}
        id="edit-layout-toggle"
        variant={:primary}
        size={:xs}
        phx-click="toggle_edit"
      >
        <.icon name="hero-arrows-pointing-out" class="h-3.5 w-3.5" />
        Done
      </.button>
      <.button
        :if={@edit_mode?}
        id="add-widget-button"
        variant={:ghost}
        size={:xs}
        phx-click="open_add_widget"
      >
        <.icon name="hero-plus" class="h-3.5 w-3.5" /> Widget
      </.button>
      <.action_menu id="dashboard-menu">
        <:action :if={not @edit_mode?}>
          <button id="edit-layout-toggle" phx-click="toggle_edit">
            <.icon name="hero-arrows-pointing-out" class="h-4 w-4" /> Edit layout
          </button>
        </:action>
        <:action :if={not @edit_mode?}>
          <button id="add-widget-button" phx-click="open_add_widget">
            <.icon name="hero-plus" class="h-4 w-4" /> Add widget
          </button>
        </:action>
        <:action>
          <button
            id="dashboard-versions-button"
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
            <.icon name="hero-clock" class="h-4 w-4" /> Versions & activity
            <span
              :if={comparison_review_open_request_count(@dashboard_comparison_review_queue) != "0"}
              class="badge badge-warning badge-xs"
              data-dashboard-comparison-review-open-toolbar-badge
            >
              {comparison_review_open_request_count(@dashboard_comparison_review_queue)}
            </span>
          </button>
        </:action>
        <:action>
          <button
            id="dashboard-historical-workflow-request-button"
            phx-click="open_historical_workflow_request"
          >
            <.icon name="hero-document-plus" class="h-4 w-4" /> Request historical data
          </button>
        </:action>
        <:action>
          <button id="dashboard-diagnostics-button" phx-click="open_diagnostics">
            <.icon name="hero-chart-bar-square" class="h-4 w-4" /> Diagnostics
          </button>
        </:action>
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

  defp runtime_scope_label(_mission, _spacecraft, scope_kind, _scope_id, scope_ids)
       when is_list(scope_ids) and length(scope_ids) > 1 do
    "#{length(scope_ids)} #{scope_kind_label(scope_kind)}"
  end

  defp runtime_scope_label(current_mission, _spacecraft, "mission", _scope_id, _scope_ids) do
    map_value(current_mission, :display_name) || "Mission"
  end

  defp runtime_scope_label(_mission, spacecraft, "spacecraft", scope_id, _scope_ids) do
    spacecraft
    |> Enum.find(&(map_value(&1, :spacecraft_id) == scope_id))
    |> map_value(:display_name)
    |> then(&(&1 || scope_id || "Spacecraft"))
  end

  defp runtime_scope_label(current_mission, _spacecraft, scope_kind, scope_id, _scope_ids) do
    if present_text?(scope_id) do
      "#{scope_kind_label(scope_kind)} · #{scope_id}"
    else
      map_value(current_mission, :display_name) || "Mission"
    end
  end

  defp scope_kind_label(value) when is_binary(value) do
    value
    |> String.replace("_", " ")
    |> String.capitalize()
  end

  defp scope_kind_label(_value), do: "contexts"

  defp time_mode_label("live"), do: "Live"
  defp time_mode_label("archive"), do: "Archive"
  defp time_mode_label("replay_run"), do: "Replay"
  defp time_mode_label(_mode), do: "Time"

  defp data_issue_count(assigns) do
    warning_count = length(assigns.dashboard_warnings)
    affected_count = map_value(assigns.dashboard_health, :affected_count) || 0
    degraded_count = if assigns.dashboard_degraded?, do: 1, else: 0

    Enum.max([warning_count, affected_count, degraded_count])
  end

  defp data_issue_status(assigns) do
    health_state = map_value(assigns.dashboard_health, :state)

    cond do
      health_state == :blocked -> :critical
      Enum.any?(assigns.dashboard_warnings, &(map_value(&1, :severity) == :error)) -> :critical
      data_issue_count(assigns) > 0 -> :warning
      true -> :nominal
    end
  end

  defp data_issue_codes(warnings) do
    warnings
    |> Enum.map(&(map_value(&1, :code_text) || map_value(&1, :code)))
    |> Enum.reject(&is_nil/1)
    |> Enum.map(&to_string/1)
    |> Enum.uniq()
    |> Enum.sort()
    |> Enum.join(",")
  end

  defp data_issue_summary(health) do
    case {map_value(health, :label), map_value(health, :affected_count)} do
      {label, count} when is_binary(label) and is_integer(count) ->
        "#{label}; #{count} affected #{if count == 1, do: "widget", else: "widgets"}."

      {_label, count} when is_integer(count) and count > 0 ->
        "#{count} affected #{if count == 1, do: "widget", else: "widgets"}."

      _other ->
        "Inspect the affected sources and widget evidence."
    end
  end

  defp data_issue_class(:critical), do: "border-error/40 bg-error/10 text-error"
  defp data_issue_class(:warning), do: "border-warning/40 bg-warning/10 text-warning"
  defp data_issue_class(_status), do: "border-base-300 bg-base-100 text-base-content/70"

  defp map_value(nil, _key), do: nil

  defp map_value(map, key) when is_map(map) do
    Map.get(map, key, Map.get(map, Atom.to_string(key)))
  end

  defp map_value(_value, _key), do: nil

  defp present_text?(value), do: is_binary(value) and String.trim(value) != ""

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
