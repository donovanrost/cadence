defmodule CadenceWeb.OpsDashboardShowLive.Components do
  @moduledoc false
  use CadenceWeb, :html

  alias CadenceWeb.OpsDashboardShowLive.ComparisonRollupComponents
  alias CadenceWeb.OpsDashboardShowLive.DashboardHealthComponents
  alias CadenceWeb.OpsDashboardShowLive.DashboardToolbarComponents
  alias CadenceWeb.OpsDashboardShowLive.EvidenceAttrs
  alias CadenceWeb.OpsDashboardShowLive.SourceHealthComponents
  alias CadenceWeb.OpsDashboardShowLive.SourceSelectionComponents
  alias CadenceWeb.OpsDashboardShowLive.WidgetComparisonSummary
  alias CadenceWeb.OpsDashboardShowLive.WidgetDataLinkComponents
  alias CadenceWeb.OpsDashboardShowLive.WidgetDataManagementComponents
  alias CadenceWeb.OpsDashboardShowLive.WidgetLifecycleAttrs
  alias CadenceWeb.OpsDashboardShowLive.WidgetPointComponents
  alias CadenceWeb.OpsDashboardShowLive.WidgetRowComponents
  alias CadenceWeb.OpsDashboardShowLive.WidgetSourceStatusComponents
  alias CadenceWeb.OpsDashboardShowLive.WidgetWarningComponents
  alias Phoenix.LiveView.JS

  attr :dashboard_document, :any, required: true
  attr :dashboard_lifecycle_status, :any, required: true
  attr :dashboard_lifecycle_events, :list, default: []
  attr :dashboard_comparison_review_queue, :map, default: nil
  attr :dashboard_publish_readiness, :map, default: nil
  attr :edit_mode?, :boolean, required: true
  attr :show_context?, :boolean, required: true
  attr :current_mission, :any, default: nil
  attr :spacecraft, :list, required: true
  attr :scheduled_contacts, :list, default: []
  attr :realized_contacts, :list, default: []
  attr :context_spacecraft_id, :string, required: true
  attr :context_scope_kind, :string, default: nil
  attr :context_scope_id, :string, default: nil
  attr :context_scope_ids, :list, default: []
  attr :time_mode, :string, required: true
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
    DashboardToolbarComponents.dashboard_toolbar(assigns)
  end

  attr :warnings, :list, required: true
  attr :degraded?, :boolean, required: true

  def dashboard_warnings(assigns) do
    ~H"""
    <div
      :if={@degraded? or @warnings != []}
      id="dashboard-engine-warnings"
      data-engine-degraded={if @degraded?, do: "true", else: "false"}
      data-warning-codes={WidgetWarningComponents.warning_codes(@warnings)}
      class="shrink-0 flex items-center gap-2 px-2 py-1 border-b border-warning/30 bg-warning/10 text-xs"
    >
      <span class="font-semibold text-warning">Dashboard degraded</span>
      <span :if={@warnings == []} class="text-base-content/70">
        One or more sources returned degraded data.
      </span>
      <WidgetWarningComponents.engine_warning_badge
        :for={{warning, index} <- Enum.with_index(@warnings)}
        id={"dashboard-engine-warning-#{index}"}
        warning={warning}
      />
    </div>
    """
  end

  attr :health, :map, required: true

  def dashboard_health_strip(assigns) do
    DashboardHealthComponents.dashboard_health_strip(assigns)
  end

  attr :health, :list, required: true

  def source_health_strip(assigns) do
    SourceHealthComponents.source_health_strip(assigns)
  end

  attr :selections, :list, required: true
  attr :mission_id, :string, default: nil

  def source_selection_strip(assigns) do
    SourceSelectionComponents.source_selection_strip(assigns)
  end

  attr :rollup, :map, required: true
  attr :preset, :map, default: nil
  attr :open_review_summary, :map, default: %{}
  attr :saved_presets, :list, default: []

  def comparison_rollup_strip(assigns) do
    ComparisonRollupComponents.comparison_rollup_strip(assigns)
  end

  attr :widget, :any, required: true
  attr :placement_id, :string, required: true
  attr :mission_id, :string, default: nil
  attr :data, :any, required: true
  attr :compare_data, :any, default: nil
  attr :point, :any, required: true
  attr :spacecraft, :list, required: true
  attr :backfill, :any, required: true
  attr :compare_backfill, :any, default: nil
  attr :limit_markers, :list, required: true
  attr :event_markers, :list, required: true
  attr :selected_data_ref, :any, default: nil
  attr :time_mode, :string, default: nil
  attr :time_axis, :string, default: nil
  attr :window_seconds, :integer, default: nil
  attr :replay_run_id, :string, default: nil
  attr :data_realm, :string, default: nil
  attr :data_view, :string, default: nil
  attr :compare_data_view, :string, default: nil
  attr :data_source_id, :string, default: nil
  attr :source_binding_id, :string, default: nil
  attr :comparison_summary, :any, default: nil
  attr :context_spacecraft_id, :string, required: true
  attr :chart_epoch, :integer, required: true
  attr :edit_mode?, :boolean, required: true
  attr :warnings, :list, default: []

  def widget(assigns) do
    ~H"""
    <.widget_header
      widget={@widget}
      placement_id={@placement_id}
      mission_id={@mission_id}
      data={@data}
      compare_data={@compare_data}
      backfill={@backfill}
      compare_backfill={@compare_backfill}
      data_view={@data_view}
      compare_data_view={@compare_data_view}
      comparison_summary={@comparison_summary}
      spacecraft={@spacecraft}
      edit_mode?={@edit_mode?}
      warnings={@warnings}
    />
    <.widget_body
      widget={@widget}
      placement_id={@placement_id}
      data={@data}
      compare_data={@compare_data}
      point={@point}
      backfill={@backfill}
      compare_backfill={@compare_backfill}
      limit_markers={@limit_markers}
      event_markers={@event_markers}
      selected_data_ref={@selected_data_ref}
      time_mode={@time_mode}
      time_axis={@time_axis}
      window_seconds={@window_seconds}
      replay_run_id={@replay_run_id}
      data_realm={@data_realm}
      data_view={@data_view}
      compare_data_view={@compare_data_view}
      data_source_id={@data_source_id}
      source_binding_id={@source_binding_id}
      context_spacecraft_id={@context_spacecraft_id}
      chart_epoch={@chart_epoch}
      edit_mode?={@edit_mode?}
    />
    """
  end

  attr :widget, :any, required: true
  attr :placement_id, :string, required: true
  attr :data, :any, required: true
  attr :compare_data, :any, default: nil
  attr :point, :any, required: true
  attr :backfill, :any, required: true
  attr :compare_backfill, :any, default: nil
  attr :limit_markers, :list, required: true
  attr :event_markers, :list, required: true
  attr :selected_data_ref, :any, default: nil
  attr :time_mode, :string, default: nil
  attr :time_axis, :string, default: nil
  attr :window_seconds, :integer, default: nil
  attr :replay_run_id, :string, default: nil
  attr :data_realm, :string, default: nil
  attr :data_view, :string, default: nil
  attr :compare_data_view, :string, default: nil
  attr :data_source_id, :string, default: nil
  attr :source_binding_id, :string, default: nil
  attr :context_spacecraft_id, :string, required: true
  attr :chart_epoch, :integer, required: true
  attr :edit_mode?, :boolean, required: true

  defp widget_body(%{widget: %{type: :value_tile}} = assigns) do
    ~H"""
    <div
      class="flex-1 min-h-0 p-2 flex flex-col justify-center overflow-hidden"
      data-engine-backed={if engine_backed?(@data), do: "true"}
    >
      <%= cond do %>
        <% @data == nil or @data.unresolved? -> %>
          <.widget_notice notice={unresolved_notice(@widget)} />
        <% @data.sample == nil -> %>
          <.widget_lifecycle_notice data={@data} default="No data received for this point yet." />
        <% true -> %>
          <WidgetPointComponents.value_tile
            widget={@widget}
            data={@data}
            compare_data={@compare_data}
            point={@point}
            compare_data_view={@compare_data_view}
          />
      <% end %>
    </div>
    """
  end

  defp widget_body(%{widget: %{type: :time_series}} = assigns) do
    ~H"""
    <div class={[
      "cadence-time-series-panel-body",
      "flex min-h-0 flex-1 flex-col overflow-hidden"
    ]}>
      <%= cond do %>
        <% @data == nil or @data.unresolved? -> %>
          <.widget_notice notice={unresolved_notice(@widget)} state={:unresolved} />
        <% lifecycle_blocking?(@data) and WidgetPointComponents.chart_payload_empty?(@backfill) -> %>
          <.widget_lifecycle_notice data={@data} />
        <% lifecycle_state(@data) == :no_data and WidgetPointComponents.chart_payload_empty?(@backfill) -> %>
          <.widget_lifecycle_notice
            data={@data}
            default="No historical samples in this time range."
          />
        <% true -> %>
          <.widget_lifecycle_notice
            :if={lifecycle_blocking?(@data) or lifecycle_body_notice?(@data)}
            data={@data}
            compact
          />
          <WidgetPointComponents.time_series_chart
            widget={@widget}
            placement_id={@placement_id}
            data={@data}
            compare_data={@compare_data}
            point={@point}
            backfill={@backfill}
            compare_backfill={@compare_backfill}
            limit_markers={@limit_markers}
            event_markers={@event_markers}
            selected_data_ref={@selected_data_ref}
            time_mode={@time_mode}
            time_axis={@time_axis}
            window_seconds={@window_seconds}
            replay_run_id={@replay_run_id}
            data_realm={@data_realm}
            data_view={@data_view}
            compare_data_view={@compare_data_view}
            data_source_id={@data_source_id}
            source_binding_id={@source_binding_id}
            context_spacecraft_id={@context_spacecraft_id}
            chart_epoch={@chart_epoch}
            edit_mode?={@edit_mode?}
          />
      <% end %>
    </div>
    """
  end

  defp widget_body(%{widget: %{type: :status_matrix}} = assigns) do
    ~H"""
    <div
      class="flex-1 min-h-0 overflow-auto p-2"
      data-status-matrix
      data-engine-backed={if engine_backed?(@data), do: "true"}
    >
      <%= cond do %>
        <% @data == nil or @data.unresolved? -> %>
          <.widget_notice notice={unresolved_notice(@widget)} state={:unresolved} />
        <% lifecycle_blocking?(@data) -> %>
          <.widget_lifecycle_notice data={@data} />
        <% @data.rows == [] -> %>
          <.widget_lifecycle_notice data={@data} default="No current rows." />
        <% true -> %>
          <WidgetRowComponents.status_matrix_table
            data={@data}
            widget={@widget}
            placement_id={@placement_id}
          />
      <% end %>
    </div>
    """
  end

  defp widget_body(%{widget: %{type: :data_table}} = assigns) do
    ~H"""
    <div
      class="flex-1 min-h-0 overflow-auto p-2"
      data-data-table
      data-engine-backed={if engine_backed?(@data), do: "true"}
    >
      <%= cond do %>
        <% @data == nil or @data.unresolved? -> %>
          <.widget_notice notice={unresolved_notice(@widget)} state={:unresolved} />
        <% lifecycle_blocking?(@data) -> %>
          <.widget_lifecycle_notice data={@data} />
        <% @data.rows == [] -> %>
          <.widget_lifecycle_notice data={@data} default="No rows for this table." />
        <% true -> %>
          <WidgetRowComponents.data_table
            data={@data}
            widget={@widget}
            placement_id={@placement_id}
          />
      <% end %>
    </div>
    """
  end

  defp widget_body(%{widget: %{type: :state_timeline}} = assigns) do
    ~H"""
    <div
      class="flex-1 min-h-0 overflow-auto p-2"
      data-state-timeline
      data-engine-backed={if engine_backed?(@data), do: "true"}
    >
      <%= cond do %>
        <% @data == nil or @data.unresolved? -> %>
          <.widget_notice notice={unresolved_notice(@widget)} state={:unresolved} />
        <% lifecycle_blocking?(@data) -> %>
          <.widget_lifecycle_notice data={@data} />
        <% @data.rows == [] -> %>
          <.widget_lifecycle_notice
            data={@data}
            default="No state transitions in this time range."
          />
        <% true -> %>
          <WidgetRowComponents.state_timeline data={@data} placement_id={@placement_id} />
      <% end %>
    </div>
    """
  end

  defp widget_body(%{widget: %{type: :event_timeline}} = assigns) do
    ~H"""
    <div
      class="flex-1 min-h-0 overflow-auto p-2"
      data-event-timeline
      data-engine-backed={if engine_backed?(@data), do: "true"}
    >
      <%= cond do %>
        <% @data == nil or @data.unresolved? -> %>
          <.widget_notice notice={unresolved_notice(@widget)} state={:unresolved} />
        <% lifecycle_blocking?(@data) -> %>
          <.widget_lifecycle_notice data={@data} />
        <% @data.rows == [] -> %>
          <.widget_lifecycle_notice data={@data} default="No events in this time range." />
        <% true -> %>
          <WidgetRowComponents.event_timeline data={@data} placement_id={@placement_id} />
      <% end %>
    </div>
    """
  end

  defp widget_body(%{widget: %{type: :constellation_health}} = assigns) do
    ~H"""
    <div
      class="flex-1 min-h-0 p-2 overflow-y-auto"
      data-engine-backed={if engine_backed?(@data), do: "true"}
    >
      <%= cond do %>
        <% @data == nil -> %>
          <.widget_notice notice="Waiting for the first rollup." state={:no_data} />
        <% lifecycle_blocking?(@data) -> %>
          <.widget_lifecycle_notice data={@data} />
        <% true -> %>
        <WidgetPointComponents.constellation_health data={@data} />
      <% end %>
    </div>
    """
  end

  attr :widget, :any, required: true
  attr :placement_id, :string, required: true
  attr :mission_id, :string, default: nil
  attr :data, :any, required: true
  attr :compare_data, :any, default: nil
  attr :backfill, :any, default: nil
  attr :compare_backfill, :any, default: nil
  attr :data_view, :string, default: nil
  attr :compare_data_view, :string, default: nil
  attr :comparison_summary, :any, default: nil
  attr :spacecraft, :list, required: true
  attr :edit_mode?, :boolean, required: true
  attr :warnings, :list, default: []

  defp widget_header(assigns) do
    assigns =
      assign(
        assigns,
        :comparison_summary,
        assigns.comparison_summary || WidgetComparisonSummary.summary(assigns)
      )

    ~H"""
    <div
      class={[
        "cadence-dashboard-widget-header",
        "flex shrink-0 items-center gap-1.5 px-2.5 py-1"
      ]}
      {WidgetLifecycleAttrs.attrs(@data, @warnings)}
      data-dashboard-widget-header
      data-dashboard-widget-type={@widget.type}
      data-warning-codes={WidgetWarningComponents.warning_codes(@warnings)}
      data-data-management-badges={
        WidgetDataManagementComponents.data_management_badge_codes(@data)
      }
      data-widget-comparison-state={comparison_summary_value(@comparison_summary, :state)}
      data-widget-comparison-primary-count={comparison_summary_value(@comparison_summary, :primary_count)}
      data-widget-comparison-compare-count={comparison_summary_value(@comparison_summary, :compare_count)}
    >
      <h3 class={[
        "min-w-0 flex-1 truncate",
        "text-[0.8rem] font-semibold leading-4 text-base-content/85"
      ]}>
        {@widget.title}
      </h3>
      <div class={[
        "cadence-dashboard-widget-actions",
        "ml-auto flex shrink-0 items-center gap-1"
      ]}>
        <.severity_badge
          :if={point_data?(@data) && actionable_limit_event?(@data.limit_event)}
          severity={normalized_severity(@data.limit_event.normalized_state)}
          label={state_label(@data.limit_event.normalized_state)}
        />
        <span
          :if={@comparison_summary}
          class={[
            "badge badge-xs font-mono",
            comparison_summary_badge_class(@comparison_summary)
          ]}
          data-widget-comparison-summary
          data-widget-comparison-state={@comparison_summary.state}
          data-widget-comparison-primary-view={@comparison_summary.primary_view}
          data-widget-comparison-compare-view={@comparison_summary.compare_view}
          data-widget-comparison-primary-count={@comparison_summary.primary_count}
          data-widget-comparison-compare-count={@comparison_summary.compare_count}
          data-widget-comparison-delta={Map.get(@comparison_summary, :delta)}
          title={@comparison_summary.title}
        >
          {@comparison_summary.label}
        </span>
        <.status_badge
          :if={point_data?(@data) && quality_status(@data)}
          status={quality_status(@data)}
          label={quality_label(@data)}
        />
        <span
          :if={lifecycle_body_notice?(@data)}
          class={["inline-flex", lifecycle_indicator_class(@data)]}
          title={lifecycle_notice(@data, "Data is incomplete.")}
          aria-label={lifecycle_notice(@data, "Data is incomplete.")}
          data-widget-lifecycle-indicator={lifecycle_state(@data)}
        >
          <.icon name={lifecycle_indicator_icon(@data)} class="h-3.5 w-3.5" />
        </span>
        <.popover
          id={"widget-details-#{@placement_id}"}
          label={"#{@widget.title} widget details"}
          width={:md}
          data-widget-details
        >
          <:trigger>
            <span
              class="btn btn-ghost btn-xs btn-square text-base-content/55 hover:text-base-content"
              title="Widget details"
              data-widget-details-toggle
            >
              <.icon name="hero-ellipsis-vertical" class="h-4 w-4" />
            </span>
          </:trigger>
          <div class="p-3 text-xs">
            <div class="border-b border-base-300/60 pb-2">
              <p class="font-semibold text-base-content">{@widget.title}</p>
              <p class="mt-0.5 break-all font-mono text-[0.65rem] text-base-content/55">
                {binding_caption(@widget, @data, @spacecraft)}
              </p>
            </div>
            <div class="mt-2 flex flex-wrap items-center gap-1" data-widget-detail-indicators>
              <.status_badge
                :if={lifecycle_status(@data)}
                status={lifecycle_status(@data)}
                label={lifecycle_label(@data)}
              />
              <WidgetSourceStatusComponents.source_status_badge
                :if={WidgetSourceStatusComponents.source_status_badge?(@data)}
                source_status={WidgetSourceStatusComponents.source_status(@data)}
                mission_id={@mission_id}
              />
              <WidgetDataManagementComponents.data_management_badge
                :for={badge <- WidgetDataManagementComponents.data_management_badges(@data)}
                badge={badge}
              />
              <WidgetWarningComponents.engine_warning_badge
                :for={{warning, index} <- Enum.with_index(@warnings)}
                id={"widget-#{@placement_id}-engine-warning-#{index}"}
                warning={warning}
                placement_id={@placement_id}
              />
            </div>
            <div
              class="mt-2 flex items-center gap-1 border-t border-base-300/60 pt-2"
              data-widget-detail-actions
            >
              <WidgetSourceStatusComponents.widget_query_diagnostics
                :if={
                  WidgetSourceStatusComponents.widget_query_diagnostics?(
                    @widget,
                    @data,
                    @data_view,
                    @compare_data_view
                  )
                }
                widget={@widget}
                placement_id={@placement_id}
                data={@data}
                data_view={@data_view}
                compare_data_view={@compare_data_view}
                warnings={@warnings}
              />
              <button
                :if={frame_evidence?(@data)}
                type="button"
                phx-click="open_evidence"
                {EvidenceAttrs.widget_frame(@placement_id, widget_evidence_observable(@data), @data)}
                class="btn btn-ghost btn-xs btn-square"
                title="Inspect frame evidence"
                aria-label="Inspect frame evidence"
                data-widget-frame-evidence
              >
                <.icon name="hero-document-magnifying-glass" class="h-3.5 w-3.5" />
              </button>
              <WidgetDataLinkComponents.widget_data_link_menu
                :if={widget_links(@data) != []}
                links={widget_links(@data)}
                placement_id={@placement_id}
              />
              <button
                :if={@widget.type == :time_series}
                type="button"
                phx-click="open_widget_inspector"
                phx-value-placement-id={@placement_id}
                class="btn btn-ghost btn-xs btn-square"
                title="Inspect data"
                aria-label="Inspect data"
                data-widget-inspect-data
              >
                <.icon name="hero-table-cells" class="h-3.5 w-3.5" />
              </button>
            </div>
          </div>
        </.popover>
        <.button
          :if={@edit_mode?}
          variant={:ghost}
          size={:xs}
          phx-click="open_widget_config"
          phx-value-widget-id={@widget.widget_id}
          aria-label={"Configure #{@widget.title}"}
        >
          <.icon name="hero-cog-6-tooth" class="h-3.5 w-3.5" />
        </.button>
        <.button
          :if={@edit_mode?}
          variant={:ghost}
          size={:xs}
          phx-click="remove_widget"
          phx-value-widget-id={@widget.widget_id}
          aria-label={"Remove #{@widget.title}"}
          data-confirm="Remove this widget?"
        >
          <.icon name="hero-x-mark" class="h-3.5 w-3.5" />
        </.button>
      </div>
    </div>
    """
  end

  attr :notice, :string, required: true
  attr :status, :atom, default: :info
  attr :state, :atom, default: nil
  attr :compact, :boolean, default: false

  defp widget_notice(assigns) do
    ~H"""
    <div
      class={[
        "rounded border font-mono text-[0.68rem] leading-snug",
        if(@compact, do: "mt-1 px-2 py-1", else: "px-2 py-1.5"),
        widget_notice_class(@status)
      ]}
      data-widget-body-notice={notice_state(@state)}
    >
      {@notice}
    </div>
    """
  end

  attr :data, :any, required: true
  attr :default, :string, default: nil
  attr :compact, :boolean, default: false

  defp widget_lifecycle_notice(assigns) do
    assigns =
      assigns
      |> assign(:state, lifecycle_state(assigns.data))
      |> assign(:status, lifecycle_status(assigns.data) || :info)
      |> assign(
        :notice,
        actionable_lifecycle_notice(assigns.data, assigns.default || "No data available.")
      )
      |> assign(:actions?, not assigns.compact and lifecycle_actionable?(assigns.data))

    ~H"""
    <div
      class={[
        "rounded border font-mono text-[0.68rem] leading-snug",
        if(@compact, do: "mt-1 px-2 py-1", else: "px-2 py-1.5"),
        widget_notice_class(@status)
      ]}
      data-widget-body-notice={notice_state(@state)}
      data-widget-empty-actionable={to_string(@actions?)}
    >
      <p>{@notice}</p>
      <div :if={@actions?} class="mt-2 flex flex-wrap gap-1.5 font-sans">
        <button
          type="button"
          phx-click={JS.dispatch("click", to: "#dashboard-data-controls-toggle")}
          class="btn btn-xs btn-outline"
          data-widget-empty-adjust-context
        >
          <.icon name="hero-adjustments-horizontal" class="h-3.5 w-3.5" /> Adjust scope & time
        </button>
        <button
          type="button"
          phx-click={JS.dispatch("click", to: "#dashboard-investigate-toggle")}
          class="btn btn-xs btn-ghost"
          data-widget-empty-investigate
        >
          <.icon name="hero-magnifying-glass" class="h-3.5 w-3.5" /> Investigate
        </button>
      </div>
    </div>
    """
  end

  defp widget_links(%{links: links}) when is_list(links), do: links
  defp widget_links(_data), do: []

  defp lifecycle_blocking?(%{lifecycle_state: state})
       when state in [:error, :unsupported, :retention_gap],
       do: true

  defp lifecycle_blocking?(_data), do: false

  defp lifecycle_body_notice?(%{lifecycle_state: state}) when state in [:stale, :partial],
    do: true

  defp lifecycle_body_notice?(_data), do: false

  defp lifecycle_indicator_icon(%{lifecycle_state: :stale}), do: "hero-clock"
  defp lifecycle_indicator_icon(%{lifecycle_state: :partial}), do: "hero-chart-pie"

  defp lifecycle_indicator_class(%{lifecycle_state: :stale}), do: "text-warning"
  defp lifecycle_indicator_class(%{lifecycle_state: :partial}), do: "text-warning"

  defp lifecycle_state(%{lifecycle_state: state}) when is_atom(state), do: state
  defp lifecycle_state(nil), do: :no_data
  defp lifecycle_state(_data), do: :ready

  defp lifecycle_notice(
         %{lifecycle_state: :unsupported, lifecycle: %{warning_codes: warning_codes}},
         _default
       )
       when is_list(warning_codes) do
    if :unsupported_observable_scope in warning_codes do
      "This widget does not support the selected context."
    else
      "This widget requests data the selected source cannot provide."
    end
  end

  defp lifecycle_notice(%{lifecycle_state: :unsupported}, _default),
    do: "This widget requests data the selected source cannot provide."

  defp lifecycle_notice(%{lifecycle_state: :error}, _default),
    do: "This widget cannot load because its source failed."

  defp lifecycle_notice(%{lifecycle_state: :retention_gap}, _default),
    do:
      "This widget cannot load because the selected time range is outside available source retention."

  defp lifecycle_notice(%{lifecycle_state: :partial}, _default),
    do: "This widget is showing partial data; source coverage is incomplete."

  defp lifecycle_notice(%{lifecycle_state: :stale}, _default),
    do: "This widget is showing stale or freshness-unknown data."

  defp lifecycle_notice(%{lifecycle_state: :no_data}, default), do: default
  defp lifecycle_notice(_data, default), do: default

  defp actionable_lifecycle_notice(data, default) do
    if lifecycle_state(data) == :no_data do
      scoped_no_data_notice(data, default)
    else
      lifecycle_notice(data, default)
    end
  end

  defp scoped_no_data_notice(data, default) do
    source_status = WidgetSourceStatusComponents.source_status(data)

    case source_status && Map.get(source_status, :empty_reason) do
      :contact_scope_no_data ->
        "Source responded, but no rows matched this contact and source-endpoint scope in the selected time range."

      :source_endpoint_scope_no_data ->
        "Source responded, but no rows matched this source endpoint in the selected time range."

      :scope_no_data ->
        "Source responded, but no rows matched the active dashboard scope in the selected time range."

      _reason ->
        lifecycle_notice(data, default)
    end
  end

  defp lifecycle_actionable?(%{lifecycle_state: state})
       when state in [:no_data, :unsupported, :error, :retention_gap],
       do: true

  defp lifecycle_actionable?(_data), do: false

  defp lifecycle_status(%{lifecycle_state: :stale}), do: :attention
  defp lifecycle_status(%{lifecycle_state: :partial}), do: :attention
  defp lifecycle_status(%{lifecycle_state: :retention_gap}), do: :blocked
  defp lifecycle_status(%{lifecycle_state: :error}), do: :blocked
  defp lifecycle_status(%{lifecycle_state: :unsupported}), do: :blocked
  defp lifecycle_status(%{lifecycle_state: :no_data}), do: :info
  defp lifecycle_status(nil), do: :info
  defp lifecycle_status(_data), do: nil

  defp lifecycle_label(%{lifecycle_state: :stale}), do: "Stale"
  defp lifecycle_label(%{lifecycle_state: :partial}), do: "Partial"
  defp lifecycle_label(%{lifecycle_state: :retention_gap}), do: "Retention Gap"
  defp lifecycle_label(%{lifecycle_state: :error}), do: "Source Error"
  defp lifecycle_label(%{lifecycle_state: :unsupported}), do: "Unsupported"
  defp lifecycle_label(%{lifecycle_state: :no_data}), do: "No Data"
  defp lifecycle_label(nil), do: "No Data"

  defp widget_notice_class(:blocked), do: "border-error/40 bg-error/10 text-error"
  defp widget_notice_class(:error), do: "border-error/40 bg-error/10 text-error"
  defp widget_notice_class(:attention), do: "border-warning/40 bg-warning/10 text-warning"
  defp widget_notice_class(:warning), do: "border-warning/40 bg-warning/10 text-warning"
  defp widget_notice_class(_status), do: "border-base-300/70 bg-base-100/70 text-base-content/70"

  defp notice_state(nil), do: nil
  defp notice_state(state) when is_atom(state), do: Atom.to_string(state)
  defp notice_state(state) when is_binary(state), do: state
  defp notice_state(_state), do: nil

  defp unresolved_notice(%{binding: %{mode: :context}}) do
    "Pick a spacecraft context to resolve this widget."
  end

  defp unresolved_notice(_widget), do: "This widget's point is not in the active catalog."

  defp binding_caption(widget, data, spacecraft) do
    case widget.binding do
      %{mode: :constellation} ->
        "All spacecraft"

      %{mode: :fixed, spacecraft_id: spacecraft_id, point_id: point_id} ->
        "#{spacecraft_name(spacecraft, spacecraft_id)} · #{point_id}"

      %{mode: :context, point_id: point_id} ->
        case data do
          %{spacecraft_id: spacecraft_id} when is_binary(spacecraft_id) ->
            "#{spacecraft_name(spacecraft, spacecraft_id)} · #{point_id}"

          _unresolved ->
            point_id
        end
    end
  end

  defp spacecraft_name(spacecraft, spacecraft_id) do
    case Enum.find(spacecraft, &(&1.spacecraft_id == spacecraft_id)) do
      nil -> spacecraft_id
      found -> found.display_name
    end
  end

  defp comparison_summary_badge_class(%{state: "increased"}), do: "badge-info badge-outline"
  defp comparison_summary_badge_class(%{state: "decreased"}), do: "badge-info badge-outline"
  defp comparison_summary_badge_class(%{state: "unchanged"}), do: "badge-success badge-outline"
  defp comparison_summary_badge_class(%{state: "available"}), do: "badge-info badge-outline"
  defp comparison_summary_badge_class(%{state: "missing"}), do: "badge-warning badge-outline"
  defp comparison_summary_badge_class(_summary), do: "badge-ghost"

  defp comparison_summary_value(nil, _key), do: nil
  defp comparison_summary_value(summary, key), do: Map.get(summary, key)

  defp point_data?(%{kind: :point}), do: true
  defp point_data?(_data), do: false

  defp actionable_limit_event?(%{normalized_state: state}) when state in [:red, :yellow, :blue],
    do: true

  defp actionable_limit_event?(_limit_event), do: false

  defp engine_backed?(%{engine_backed?: true}), do: true
  defp engine_backed?(_data), do: false

  defp frame_evidence?(%{engine_backed?: true, links: links}) when is_list(links), do: links != []
  defp frame_evidence?(_data), do: false

  defp widget_evidence_observable(%{observable_id: observable_id})
       when is_binary(observable_id) and observable_id != "",
       do: observable_id

  defp widget_evidence_observable(%{links: links}) when is_list(links) do
    Enum.find_value(links, fn
      %{target: :telemetry_point, target_id: target_id} when is_binary(target_id) -> target_id
      %{target: "telemetry_point", target_id: target_id} when is_binary(target_id) -> target_id
      _other -> nil
    end)
  end

  defp normalized_severity(:red), do: :critical
  defp normalized_severity(:yellow), do: :warning
  defp normalized_severity(:blue), do: :info

  defp state_label(:red), do: "Red"
  defp state_label(:yellow), do: "Yellow"
  defp state_label(:blue), do: "Blue"

  defp quality_status(%{sample: %{quality_state: :suspect}}), do: :attention
  defp quality_status(%{sample: %{quality_state: :bad}}), do: :blocked
  defp quality_status(_data), do: nil

  defp quality_label(%{sample: %{quality_state: quality_state}}) do
    quality_state |> Atom.to_string() |> String.capitalize()
  end
end
