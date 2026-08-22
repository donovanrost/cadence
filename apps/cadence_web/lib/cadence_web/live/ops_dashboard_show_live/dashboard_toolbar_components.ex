defmodule CadenceWeb.OpsDashboardShowLive.DashboardToolbarComponents do
  @moduledoc false
  use CadenceWeb, :html

  alias Cadence.Dashboards.{ComparisonReviewQueue, Document, TimeRange}
  alias CadenceWeb.OpsDashboardShowLive.DashboardRuntimeContextComponents
  alias CadenceWeb.OpsDashboardShowLive.DashboardRuntimeControlsComponents
  alias CadenceWeb.OpsDashboardShowLive.DashboardTimePickerComponents
  alias CadenceWeb.OpsDashboardShowLive.WidgetWarningComponents

  @data_source_issue_codes [
    :missing_source_binding,
    :partial_data,
    :retention_gap,
    :source_binding_segment_merge_unsupported,
    :source_connection_failed,
    :source_degraded,
    :source_execution_failed,
    :source_health_degraded,
    :source_unavailable,
    :stale_data,
    :unsupported_observable_scope,
    :unsupported_source_adapter,
    :unsupported_source_capability,
    :watermark_unknown
  ]

  attr :dashboard_document, :any, required: true
  attr :dashboard_lifecycle_status, :any, required: true
  attr :dashboard_lifecycle_events, :list, default: []
  attr :dashboard_comparison_review_queue, :map, default: nil
  attr :dashboard_publish_readiness, :map, default: nil
  attr :edit_mode?, :boolean, required: true
  attr :editor_route?, :boolean, default: false
  attr :editor_dirty?, :boolean, default: false
  attr :editor_conflict, :map, default: nil
  attr :dashboard_author?, :boolean, default: false
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
  attr :hidden_marker_categories, :list, default: []
  attr :selected_data_ref, :any, default: nil
  attr :time_quick_query, :string, default: ""
  attr :time_recent_ranges, :list, default: []
  attr :query, :string, required: true
  attr :dashboard_warnings, :list, default: []
  attr :dashboard_degraded?, :boolean, default: false
  attr :dashboard_health, :map, default: %{}
  attr :comparison_available?, :boolean, default: false
  attr :comparison_open?, :boolean, default: false
  attr :comparison_open_count, :integer, default: 0

  def dashboard_toolbar(assigns) do
    assigns =
      assigns
      |> assign(:data_issue_count, data_issue_count(assigns))
      |> assign(:data_issue_status, data_issue_status(assigns))
      |> assign(:mission_id, map_value(assigns.current_mission, :mission_id))
      |> assign(:dashboard_id, map_value(assigns.dashboard_document, :dashboard_id))
      |> assign(:historical_request_path, historical_request_path(assigns))
      |> assign(:dashboard_edit_path, dashboard_path(assigns, :edit))
      |> assign(:dashboard_activity_path, dashboard_path(assigns, :activity))
      |> assign(:dashboard_diagnostics_path, dashboard_path(assigns, :diagnostics))
      |> assign(:dashboard_settings_path, dashboard_path(assigns, :settings))
      |> assign(:dashboard_share_path, dashboard_share_path(assigns))
      |> assign(:data_query_label, data_query_label(assigns))
      |> assign(:data_query_overrides?, data_query_overrides?(assigns))
      |> assign(:comparison_toolbar_visible?, comparison_toolbar_visible?(assigns))
      |> then(&assign(&1, :data_issue_action, data_issue_action(&1)))

    ~H"""
    <div
      id="dashboard-telemetry-toolbar"
      class="min-h-10 shrink-0 flex items-center gap-2 border-b border-base-300/50 bg-base-200/35 px-3 py-1"
      data-dashboard-viewer-toolbar={to_string(not @edit_mode?)}
    >
      <div class="min-w-0 flex-1">
        <h1
          class="break-words text-sm font-semibold leading-tight tracking-tight"
          title={@dashboard_document.description}
        >
          {@dashboard_document.name}
        </h1>
      </div>

      <div
        :if={not @edit_mode?}
        id="runtime-context-controls"
        class="cadence-dashboard-query-strip"
      >
        <.popover
          id="dashboard-data-controls"
          trigger_id="dashboard-data-controls-toggle"
          panel_id="dashboard-data-controls-panel"
          label="Dashboard operational scope"
          placement={:bottom_start}
          width={:lg}
          trigger_class="cadence-dashboard-query-trigger"
          data-dashboard-primary-control="scope"
          data-query-overrides={to_string(@data_query_overrides?)}
        >
          <:trigger>
            <span class="cadence-dashboard-query-trigger-label">Scope</span>
            <span class="cadence-dashboard-query-trigger-value hidden max-w-36 sm:inline">
              {runtime_scope_label(@current_mission, @spacecraft, @context_scope_kind, @context_scope_id, @context_scope_ids)}
            </span>
            <span
              :if={@data_query_overrides?}
              class="cadence-dashboard-context-override hidden max-w-40 md:inline-flex"
              data-dashboard-data-override
            >
              {@data_query_label}
            </span>
            <.icon name="hero-chevron-down" class="h-3 w-3 shrink-0 text-base-content/40" />
          </:trigger>
          <div class="cadence-dashboard-query-panel-header">
            <.icon name="hero-viewfinder-circle" class="mt-0.5 h-4 w-4 text-primary" />
            <div>
              <p class="text-xs font-semibold text-base-content/85">Operational scope</p>
              <p class="mt-0.5 text-[0.68rem] text-base-content/50">
                Focus every widget without leaving the dashboard.
              </p>
            </div>
          </div>
          <div class="cadence-dashboard-query-panel-body">
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
            <details
              id="dashboard-query-options"
              open={@data_query_overrides?}
              class="cadence-dashboard-context-advanced"
              data-query-overrides={to_string(@data_query_overrides?)}
            >
              <summary
                id="dashboard-query-options-toggle"
                class="cadence-dashboard-context-advanced-summary"
                aria-label="Dashboard data options"
              >
                <span class="flex min-w-0 items-center gap-2">
                  <.icon name="hero-circle-stack" class="h-4 w-4 shrink-0 text-primary" />
                  <span class="min-w-0">
                    <span class="block text-xs font-semibold text-base-content/85">
                      Data provenance & semantics
                    </span>
                    <span class="block truncate text-[0.68rem] text-base-content/50">
                      {if @data_query_overrides?, do: @data_query_label, else: "Flight · Canonical · Observed limits"}
                    </span>
                  </span>
                </span>
                <.icon name="hero-chevron-right" class="h-3.5 w-3.5 shrink-0 text-base-content/45 transition-transform" />
              </summary>
              <div id="dashboard-query-options-panel" class="pt-3">
                <DashboardRuntimeControlsComponents.runtime_context_controls
                  section={:data}
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
                  hidden_marker_categories={@hidden_marker_categories}
                  selected_data_ref={@selected_data_ref}
                  time_axis={@time_axis}
                />
              </div>
            </details>
          </div>
        </.popover>

        <DashboardTimePickerComponents.time_toolbar_cluster
          time_mode={@time_mode}
          time_axis={@time_axis}
          time_from={@time_from}
          time_to={@time_to}
          replay_run_id={@replay_run_id}
          time_validation={@time_validation}
          data_realm={@data_realm}
          data_view={@data_view}
          compare_data_view={@compare_data_view}
          source_binding_id={@source_binding_id}
          limit_mode={@limit_mode}
          replay_runs={@replay_runs}
          selected_replay_run={@selected_replay_run}
          selected_data_ref={@selected_data_ref}
          quick_query={@time_quick_query}
          recent_ranges={@time_recent_ranges}
        />
      </div>

      <button
        :if={not @edit_mode? and @comparison_toolbar_visible?}
        id="dashboard-comparison-toggle"
        type="button"
        phx-click="toggle_comparison_inspector"
        aria-expanded={to_string(@comparison_open?)}
        aria-controls="dashboard-comparison-inspector"
        data-dashboard-comparison-toggle
        class={[
          "btn btn-ghost btn-xs h-7 gap-1.5 border px-2 font-normal",
          if(@comparison_open?,
            do: "border-info/45 bg-info/10 text-info",
            else: "border-base-300/70 bg-base-100/50"
          )
        ]}
      >
        <.icon name="hero-scale" class="h-3.5 w-3.5" />
        <span class="hidden sm:inline">Compare</span>
        <span
          :if={@comparison_open_count > 0}
          class="badge badge-warning badge-xs"
          data-dashboard-comparison-open-count={@comparison_open_count}
        >
          {@comparison_open_count}
        </span>
      </button>

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
          <.link
            id="dashboard-data-issues-open"
            navigate={@data_issue_action.path}
            class="btn btn-outline btn-xs mt-3 w-full justify-start"
            data-dashboard-data-issue-action={@data_issue_action.kind}
          >
            <.icon name={@data_issue_action.icon} class="h-3.5 w-3.5" />
            {@data_issue_action.label}
          </.link>
          <.link
            :if={@data_issue_action.kind == "data_sources"}
            id="dashboard-data-issues-diagnostics"
            navigate={@dashboard_diagnostics_path}
            class="btn btn-ghost btn-xs mt-1 w-full justify-start"
          >
            <.icon name="hero-wrench-screwdriver" class="h-3.5 w-3.5" />
            Dashboard diagnostics
          </.link>
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
        :if={@edit_mode? and not @editor_route?}
        id="edit-layout-toggle"
        variant={:primary}
        size={:xs}
        phx-click="toggle_edit"
      >
        <.icon name="hero-arrows-pointing-out" class="h-3.5 w-3.5" />
        Done
      </.button>
      <span
        :if={@editor_route?}
        id="dashboard-editor-save-state"
        class={[
          "font-mono text-[0.65rem] uppercase tracking-wider",
          if(@editor_dirty?, do: "text-warning", else: "text-success")
        ]}
        data-editor-dirty={to_string(@editor_dirty?)}
      >
        {if @editor_dirty?, do: "Unsaved changes", else: "Saved"}
      </span>
      <.button
        :if={@editor_route?}
        id="dashboard-editor-discard"
        variant={:ghost}
        size={:xs}
        phx-click="discard_editor"
        data-editor-discard
      >
        Discard
      </.button>
      <.button
        :if={@editor_route?}
        id="dashboard-editor-save"
        variant={:primary}
        size={:xs}
        phx-click="save_editor"
        disabled={not @editor_dirty? or not is_nil(@editor_conflict)}
      >
        <.icon name="hero-check" class="h-3.5 w-3.5" /> Save
      </.button>
      <.button
        :if={@editor_route?}
        id="dashboard-editor-review"
        variant={:ghost}
        size={:xs}
        phx-click="review_editor"
        disabled={not is_nil(@editor_conflict)}
      >
        Review & Publish
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
      <.button
        :if={@edit_mode?}
        id="manage-dashboard-sections"
        variant={:ghost}
        size={:xs}
        phx-click="open_dashboard_sections"
      >
        <.icon name="hero-rectangle-group" class="h-3.5 w-3.5" /> Sections
      </.button>
      <.action_menu id="dashboard-menu">
        <:action :if={not @edit_mode? and not is_nil(@mission_id) and not is_nil(@dashboard_id)}>
          <.link id="dashboard-investigate-telemetry" navigate={telemetry_explore_path(assigns)}>
            <.icon name="hero-chart-bar-square" class="h-4 w-4" /> Explore telemetry
          </.link>
        </:action>
        <:action :if={not @edit_mode? and not is_nil(@mission_id) and not is_nil(@dashboard_id)}>
          <.link
            id="dashboard-investigate-sources"
            navigate={~p"/missions/#{@mission_id}/ops/data-sources?source_dashboard_id=#{@dashboard_id}"}
          >
            <.icon name="hero-circle-stack" class="h-4 w-4" /> Data Sources
          </.link>
        </:action>
        <:action :if={not @edit_mode? and not is_nil(@mission_id)}>
          <.link id="dashboard-investigate-contacts" navigate={~p"/missions/#{@mission_id}/ops/contacts"}>
            <.icon name="hero-signal" class="h-4 w-4" /> Contacts
          </.link>
        </:action>
        <:action :if={not @edit_mode? and @dashboard_author?}>
          <.link
            id="dashboard-edit-link"
            navigate={@dashboard_edit_path}
          >
            <.icon name="hero-pencil-square" class="h-4 w-4" /> Edit Dashboard
          </.link>
        </:action>
        <:action>
          <.link
            id="dashboard-versions-button"
            navigate={@dashboard_activity_path}
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
          </.link>
        </:action>
        <:action>
          <.link
            id="dashboard-historical-workflow-request-button"
            navigate={@historical_request_path}
          >
            <.icon name="hero-document-plus" class="h-4 w-4" /> Request historical data
          </.link>
        </:action>
        <:action>
          <.link
            id="dashboard-diagnostics-button"
            navigate={@dashboard_diagnostics_path}
          >
            <.icon name="hero-chart-bar-square" class="h-4 w-4" /> Diagnostics
          </.link>
        </:action>
        <:action :if={@dashboard_author?}>
          <.link
            id="dashboard-share-button"
            navigate={@dashboard_share_path}
          >
            <.icon name="hero-share" class="h-4 w-4" /> Share current context
          </.link>
        </:action>
        <:action :if={@dashboard_author?}>
          <.link
            id="dashboard-settings-button"
            navigate={@dashboard_settings_path}
          >
            <.icon name="hero-cog-6-tooth" class="h-4 w-4" /> Settings
          </.link>
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

  defp data_query_label(assigns) do
    base = "#{query_value_label(assigns.data_realm)} · #{query_value_label(assigns.data_view)}"

    case assigns.compare_data_view do
      value when is_binary(value) and value != "" ->
        "#{base} ↔ #{query_value_label(value)}"

      _none ->
        base
    end
  end

  defp data_query_overrides?(assigns) do
    assigns.data_realm != "flight" or
      assigns.data_view != "canonical" or
      present_text?(assigns.compare_data_view) or
      assigns.limit_mode != "observed" or
      assigns.time_axis != "generation_time"
  end

  defp comparison_toolbar_visible?(assigns) do
    assigns.comparison_available? and
      (assigns.comparison_open? or assigns.comparison_open_count > 0 or
         present_text?(assigns.compare_data_view))
  end

  defp query_value_label(value) when is_binary(value) do
    value
    |> String.replace("_", " ")
    |> String.capitalize()
  end

  defp query_value_label(_value), do: "Default"

  defp telemetry_explore_path(assigns) do
    {from_value, to_value} =
      TimeRange.frozen_bounds(assigns.time_from, assigns.time_to, DateTime.utc_now())

    query =
      %{
        "source_dashboard_id" => assigns.dashboard_id,
        "spacecraft_id" => assigns.context_spacecraft_id,
        "scope_kind" => assigns.context_scope_kind,
        "scope_id" => assigns.context_scope_id,
        "time_mode" => explore_time_mode(assigns.time_mode),
        "from" => from_value,
        "to" => to_value,
        "time_axis" => assigns.time_axis,
        "replay_run_id" => assigns.replay_run_id,
        "realm" => assigns.data_realm,
        "selection_view" => assigns.data_view,
        "data_source_id" => assigns.data_source_id,
        "source_binding_id" => assigns.source_binding_id,
        "limit_mode" => assigns.limit_mode
      }
      |> Enum.reject(fn {_key, value} -> value in [nil, ""] end)
      |> Map.new()

    ~p"/missions/#{assigns.mission_id}/ops/explore?#{query}"
  end

  defp explore_time_mode("live"), do: "latest"
  defp explore_time_mode(mode), do: mode

  defp data_issue_count(assigns) do
    warning_count = length(assigns.dashboard_warnings)
    affected_count = map_value(assigns.dashboard_health, :affected_count) || 0
    degraded_count = if assigns.dashboard_degraded?, do: 1, else: 0

    Enum.max([warning_count, affected_count, degraded_count])
  end

  defp data_issue_action(assigns) do
    if data_source_issue?(assigns.dashboard_warnings) and
         dashboard_identity?(assigns.mission_id, assigns.dashboard_id) do
      %{
        kind: "data_sources",
        label: "Open Data Sources",
        icon: "hero-circle-stack",
        path:
          ~p"/missions/#{assigns.mission_id}/ops/data-sources?source_dashboard_id=#{assigns.dashboard_id}"
      }
    else
      %{
        kind: "diagnostics",
        label: "Open diagnostics",
        icon: "hero-wrench-screwdriver",
        path: assigns.dashboard_diagnostics_path
      }
    end
  end

  defp data_source_issue?(warnings) when is_list(warnings) do
    Enum.any?(warnings, fn warning ->
      warning
      |> map_value(:code)
      |> normalize_issue_code()
      |> then(&(&1 in @data_source_issue_codes))
    end)
  end

  defp normalize_issue_code(code) when is_atom(code), do: code

  defp normalize_issue_code(code) when is_binary(code) do
    Enum.find(@data_source_issue_codes, &(Atom.to_string(&1) == code))
  end

  defp normalize_issue_code(_code), do: nil

  defp historical_request_query(assigns) do
    point_id =
      map_value(assigns.selected_data_ref, :point_id) ||
        map_value(assigns.selected_data_ref, :observable_id)

    {source_from, source_to} =
      TimeRange.frozen_bounds(assigns.time_from, assigns.time_to, DateTime.utc_now())

    %{
      "realm" => assigns.data_realm,
      "data_source_id" => assigns.data_source_id,
      "source_binding_id" => assigns.source_binding_id,
      "observable_id" => point_id,
      "point_id" => point_id,
      "point_ids" => point_id,
      "source_from" => source_from,
      "source_to" => source_to,
      "dashboard_id" => map_value(assigns.dashboard_document, :dashboard_id),
      "dashboard_version" => dashboard_version(assigns.dashboard_document),
      "dashboard_time_mode" => assigns.time_mode,
      "dashboard_replay_run_id" => assigns.replay_run_id,
      "dashboard_data_view" => assigns.data_view,
      "dashboard_limit_mode" => assigns.limit_mode,
      "reason" => "dashboard_historical_data_gap"
    }
    |> Enum.reject(fn {_key, value} -> value in [nil, ""] end)
    |> Map.new()
  end

  defp historical_request_path(assigns) do
    case map_value(assigns.current_mission, :mission_id) do
      mission_id when is_binary(mission_id) and mission_id != "" ->
        ~p"/missions/#{mission_id}/ops/data-operations?#{historical_request_query(assigns)}"

      _missing_mission ->
        "#"
    end
  end

  defp dashboard_path(assigns, page) do
    mission_id = map_value(assigns.current_mission, :mission_id)
    dashboard_id = map_value(assigns.dashboard_document, :dashboard_id)

    if dashboard_identity?(mission_id, dashboard_id),
      do: dashboard_page_path(page, mission_id, dashboard_id, assigns),
      else: "#"
  end

  defp dashboard_page_path(:edit, mission_id, dashboard_id, _assigns),
    do: ~p"/missions/#{mission_id}/ops/dashboards/#{dashboard_id}/edit"

  defp dashboard_page_path(:activity, mission_id, dashboard_id, _assigns),
    do: ~p"/missions/#{mission_id}/ops/dashboards/#{dashboard_id}/activity"

  defp dashboard_page_path(:diagnostics, mission_id, dashboard_id, assigns),
    do:
      ~p"/missions/#{mission_id}/ops/dashboards/#{dashboard_id}/diagnostics?#{runtime_context_query(assigns)}"

  defp dashboard_page_path(:settings, mission_id, dashboard_id, assigns),
    do:
      ~p"/missions/#{mission_id}/ops/dashboards/#{dashboard_id}/settings?#{runtime_context_query(assigns)}"

  defp dashboard_page_path(_page, _mission_id, _dashboard_id, _assigns), do: "#"

  defp dashboard_identity?(mission_id, dashboard_id),
    do: present_text?(mission_id) and present_text?(dashboard_id)

  defp runtime_context_query(assigns) do
    selected_id =
      map_value(assigns.selected_data_ref, :sample_id) ||
        map_value(assigns.selected_data_ref, :point_id) ||
        map_value(assigns.selected_data_ref, :observable_id)

    %{
      "spacecraft_id" => assigns.context_spacecraft_id,
      "scope_kind" => assigns.context_scope_kind,
      "scope_id" => assigns.context_scope_id,
      "time_mode" => assigns.time_mode,
      "time_axis" => assigns.time_axis,
      "from" => assigns.time_from,
      "to" => assigns.time_to,
      "replay_run_id" => assigns.replay_run_id,
      "realm" => assigns.data_realm,
      "data_view" => assigns.data_view,
      "data_source_id" => assigns.data_source_id,
      "source_binding_id" => assigns.source_binding_id,
      "limit_mode" => assigns.limit_mode,
      "selected_id" => selected_id
    }
    |> Enum.reject(fn {_key, value} -> value in [nil, ""] end)
    |> Map.new()
  end

  defp dashboard_share_path(assigns) do
    case dashboard_path(assigns, :settings) do
      "#" -> "#"
      path -> path <> "#dashboard-sharing"
    end
  end

  defp dashboard_version(%Document{} = document), do: Document.version(document)
  defp dashboard_version(_document), do: nil

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
