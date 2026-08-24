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
    assigns =
      assign(
        assigns,
        :presentation,
        dashboard_warnings_presentation(assigns.warnings, assigns.degraded?)
      )

    ~H"""
    <.vue
      :if={@presentation}
      id="dashboard-engine-warnings-component"
      v-component="DashboardWarnings"
      presentation={@presentation}
      v-ssr={false}
      class="contents"
    />
    """
  end

  defp dashboard_warnings_presentation([], false), do: nil

  defp dashboard_warnings_presentation(warnings, degraded?) do
    %{
      root: %{
        id: "dashboard-engine-warnings",
        class:
          "shrink-0 flex items-center gap-2 px-2 py-1 border-b border-warning/30 bg-warning/10 text-xs",
        attrs: %{
          "data-engine-degraded" => if(degraded?, do: "true", else: "false"),
          "data-warning-codes" => WidgetWarningComponents.warning_codes(warnings)
        }
      },
      label: %{class: "font-semibold text-warning", text: "Dashboard degraded"},
      fallback: %{
        visible: warnings == [],
        class: "text-base-content/70",
        text: "One or more sources returned degraded data."
      },
      warnings:
        warnings
        |> Enum.with_index()
        |> Enum.map(fn {warning, index} ->
          WidgetWarningComponents.warning_presentation(
            "dashboard-engine-warning-#{index}",
            warning,
            nil
          )
        end)
    }
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
  attr :annotations, :list, default: []
  attr :selected_data_ref, :any, default: nil
  attr :time_mode, :string, default: nil
  attr :time_from, :string, default: nil
  attr :time_to, :string, default: nil
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
      annotations={@annotations}
      selected_data_ref={@selected_data_ref}
      time_mode={@time_mode}
      time_from={@time_from}
      time_to={@time_to}
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
  attr :annotations, :list, default: []
  attr :selected_data_ref, :any, default: nil
  attr :time_mode, :string, default: nil
  attr :time_from, :string, default: nil
  attr :time_to, :string, default: nil
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
            placement_id={@placement_id}
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
            annotations={@annotations}
            selected_data_ref={@selected_data_ref}
            time_mode={@time_mode}
            time_from={@time_from}
            time_to={@time_to}
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
        <WidgetPointComponents.constellation_health
          placement_id={@placement_id}
          data={@data}
        />
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
    presentation = widget_header_presentation(assigns)
    assigns = assign(assigns, :presentation, presentation)

    ~H"""
    <.vue
      id={@presentation.component_id}
      v-component="DashboardWidgetHeader"
      presentation={@presentation}
      v-ssr={false}
      class="contents"
    />
    """
  end

  def widget_header_presentation(assigns) do
    comparison_summary =
      Map.get(assigns, :comparison_summary) || WidgetComparisonSummary.summary(assigns)

    widget = assigns.widget
    data = assigns.data
    warnings = Map.get(assigns, :warnings, [])
    placement_id = assigns.placement_id
    data_view = Map.get(assigns, :data_view)
    compare_data_view = Map.get(assigns, :compare_data_view)
    links = widget_links(data)
    source_status = WidgetSourceStatusComponents.source_status(data)

    %{
      component_id: "dashboard-widget-header-#{placement_id}-component",
      root: %{
        class: [
          "cadence-dashboard-widget-header",
          "flex shrink-0 items-center gap-1.5 px-2.5 py-1"
        ],
        attrs:
          data
          |> WidgetLifecycleAttrs.attrs(warnings)
          |> Map.merge(%{
            "data-dashboard-widget-header" => "",
            "data-dashboard-widget-type" => widget_header_attr_value(widget.type),
            "data-warning-codes" => WidgetWarningComponents.warning_codes(warnings),
            "data-data-management-badges" =>
              WidgetDataManagementComponents.data_management_badge_codes(data),
            "data-widget-comparison-state" =>
              widget_header_attr_value(comparison_summary_value(comparison_summary, :state)),
            "data-widget-comparison-primary-count" =>
              widget_header_attr_value(
                comparison_summary_value(comparison_summary, :primary_count)
              ),
            "data-widget-comparison-compare-count" =>
              widget_header_attr_value(
                comparison_summary_value(comparison_summary, :compare_count)
              )
          })
          |> compact_widget_header_attrs()
      },
      title: %{
        class: [
          "min-w-0 flex-1 truncate",
          "text-[0.8rem] font-semibold leading-4 text-base-content/85"
        ],
        text: widget.title
      },
      status_indicators: %{
        class: "ml-auto flex shrink-0 items-center gap-1",
        attrs: %{"data-widget-status-indicators" => ""},
        limit: widget_header_limit_badge(data),
        comparison: widget_header_comparison_badge(comparison_summary),
        quality: widget_header_quality_badge(data),
        lifecycle: widget_header_lifecycle_indicator(data)
      },
      actions: %{
        class: [
          "cadence-dashboard-widget-actions",
          "flex shrink-0 items-center gap-1"
        ],
        details:
          widget_header_details(
            assigns,
            source_status,
            links,
            warnings,
            data_view,
            compare_data_view
          ),
        edit: widget_header_edit_actions(widget, Map.get(assigns, :edit_mode?, false))
      }
    }
  end

  defp widget_header_limit_badge(%{kind: :point, limit_event: limit_event}) do
    if actionable_limit_event?(limit_event) do
      severity = normalized_severity(limit_event.normalized_state)

      %{
        class: [
          "inline-flex items-center gap-1 px-2 py-0.5 rounded-[2px] text-xs font-medium",
          widget_header_severity_class(severity)
        ],
        dot_class: "w-1.5 h-1.5 rounded-full bg-current",
        label_class: "uppercase text-[0.65rem]",
        text: state_label(limit_event.normalized_state)
      }
    end
  end

  defp widget_header_limit_badge(_data), do: nil

  defp widget_header_comparison_badge(nil), do: nil

  defp widget_header_comparison_badge(summary) do
    %{
      class: ["badge badge-xs font-mono", comparison_summary_badge_class(summary)],
      attrs:
        compact_widget_header_attrs(%{
          "data-widget-comparison-summary" => "",
          "data-widget-comparison-state" => widget_header_attr_value(summary.state),
          "data-widget-comparison-primary-view" => widget_header_attr_value(summary.primary_view),
          "data-widget-comparison-compare-view" => widget_header_attr_value(summary.compare_view),
          "data-widget-comparison-primary-count" =>
            widget_header_attr_value(summary.primary_count),
          "data-widget-comparison-compare-count" =>
            widget_header_attr_value(summary.compare_count),
          "data-widget-comparison-delta" => widget_header_attr_value(Map.get(summary, :delta)),
          "title" => widget_header_attr_value(summary.title)
        }),
      text: summary.label
    }
  end

  defp widget_header_quality_badge(data) do
    if point_data?(data) && quality_status(data) do
      widget_header_status_badge(quality_status(data), quality_label(data))
    end
  end

  defp widget_header_lifecycle_indicator(data) do
    if lifecycle_body_notice?(data) do
      notice = lifecycle_notice(data, "Data is incomplete.")

      %{
        class: ["inline-flex", lifecycle_indicator_class(data)],
        attrs: %{
          "title" => notice,
          "aria-label" => notice,
          "data-widget-lifecycle-indicator" => widget_header_attr_value(lifecycle_state(data))
        },
        icon: %{name: lifecycle_indicator_icon(data), class: "h-3.5 w-3.5"}
      }
    end
  end

  defp widget_header_details(
         assigns,
         source_status,
         links,
         warnings,
         data_view,
         compare_data_view
       ) do
    widget = assigns.widget
    data = assigns.data
    placement_id = assigns.placement_id
    overlay_id = "widget-details-#{placement_id}"
    label = "#{widget.title} widget details"

    %{
      overlay: %{
        id: overlay_id,
        class: "cadence-overlay",
        attrs: %{
          "data-overlay-kind" => "popover",
          "data-overlay-placement" => "bottom-end",
          "data-widget-details" => ""
        }
      },
      trigger: %{
        id: "#{overlay_id}-trigger",
        type: "button",
        class: "cadence-overlay-trigger",
        attrs: %{
          "data-overlay-trigger" => "",
          "aria-haspopup" => "dialog",
          "aria-expanded" => "false",
          "aria-controls" => "#{overlay_id}-panel",
          "aria-label" => label
        },
        content: %{
          class: "btn btn-ghost btn-xs btn-square text-base-content/55 hover:text-base-content",
          attrs: %{"title" => "Widget details", "data-widget-details-toggle" => ""},
          icon: %{name: "hero-ellipsis-vertical", class: "h-4 w-4"}
        }
      },
      panel: %{
        id: "#{overlay_id}-panel",
        class: "cadence-overlay-panel cadence-popover-panel",
        hidden: true,
        attrs: %{
          "data-overlay-panel" => "",
          "data-overlay-width" => "md",
          "aria-label" => label
        }
      },
      body: %{
        class: "p-3 text-xs",
        heading: %{
          class: "border-b border-base-300/60 pb-2",
          title: %{class: "font-semibold text-base-content", text: widget.title},
          binding: %{
            class: "mt-0.5 break-all font-mono text-[0.65rem] text-base-content/55",
            text: binding_caption(widget, data, Map.get(assigns, :spacecraft, []))
          }
        },
        indicators: %{
          class: "mt-2 flex flex-wrap items-center gap-1",
          attrs: %{"data-widget-detail-indicators" => ""},
          lifecycle:
            if(lifecycle_status(data),
              do: widget_header_status_badge(lifecycle_status(data), lifecycle_label(data))
            ),
          source:
            if(WidgetSourceStatusComponents.source_status_badge?(data),
              do:
                WidgetSourceStatusComponents.source_status_badge_presentation(
                  source_status,
                  Map.get(assigns, :mission_id)
                )
            ),
          data_management:
            Enum.map(
              WidgetDataManagementComponents.data_management_badges(data),
              &WidgetDataManagementComponents.data_management_badge_presentation/1
            ),
          warnings:
            warnings
            |> Enum.with_index()
            |> Enum.map(fn {warning, index} ->
              WidgetWarningComponents.warning_presentation(
                "widget-#{placement_id}-engine-warning-#{index}",
                warning,
                placement_id
              )
            end)
        },
        actions: %{
          class: "mt-2 flex items-center gap-1 border-t border-base-300/60 pt-2",
          attrs: %{"data-widget-detail-actions" => ""},
          query:
            if(
              WidgetSourceStatusComponents.widget_query_diagnostics?(
                widget,
                data,
                data_view,
                compare_data_view
              ),
              do:
                WidgetSourceStatusComponents.widget_query_diagnostics_presentation(
                  placement_id,
                  widget,
                  data,
                  data_view,
                  compare_data_view,
                  warnings
                )
            ),
          frame_evidence: widget_header_frame_evidence(data, placement_id),
          data_links:
            if(links != [],
              do: WidgetDataLinkComponents.widget_data_link_presentation(links, placement_id)
            ),
          inspector: widget_header_inspector_action(widget, placement_id)
        }
      }
    }
  end

  defp widget_header_frame_evidence(data, placement_id) do
    if frame_evidence?(data) do
      %{
        type: "button",
        class: "btn btn-ghost btn-xs btn-square",
        attrs:
          placement_id
          |> EvidenceAttrs.widget_frame(widget_evidence_observable(data), data)
          |> Map.merge(%{
            "phx-click" => "open_evidence",
            "title" => "Inspect frame evidence",
            "aria-label" => "Inspect frame evidence",
            "data-widget-frame-evidence" => ""
          }),
        icon: %{name: "hero-document-magnifying-glass", class: "h-3.5 w-3.5"}
      }
    end
  end

  defp widget_header_inspector_action(%{type: :time_series}, placement_id) do
    %{
      type: "button",
      class: "btn btn-ghost btn-xs btn-square",
      attrs: %{
        "phx-click" => "open_widget_inspector",
        "phx-value-placement-id" => placement_id,
        "title" => "Inspect data",
        "aria-label" => "Inspect data",
        "data-widget-inspect-data" => ""
      },
      icon: %{name: "hero-table-cells", class: "h-3.5 w-3.5"}
    }
  end

  defp widget_header_inspector_action(_widget, _placement_id), do: nil

  defp widget_header_edit_actions(_widget, false), do: []

  defp widget_header_edit_actions(widget, true) do
    [
      %{
        key: "configure",
        type: "button",
        class: "btn btn-ghost btn-xs",
        attrs: %{
          "phx-click" => "open_widget_config",
          "phx-value-widget-id" => widget.widget_id,
          "aria-label" => "Configure #{widget.title}"
        },
        icon: %{name: "hero-cog-6-tooth", class: "h-3.5 w-3.5"}
      },
      %{
        key: "remove",
        type: "button",
        class: "btn btn-ghost btn-xs",
        attrs: %{
          "phx-click" => "remove_widget",
          "phx-value-widget-id" => widget.widget_id,
          "aria-label" => "Remove #{widget.title}",
          "data-confirm" => "Remove this widget?"
        },
        icon: %{name: "hero-x-mark", class: "h-3.5 w-3.5"}
      }
    ]
  end

  defp widget_header_status_badge(status, label) do
    %{
      class: [
        "inline-flex rounded-full px-2 py-1 text-[0.65rem] font-semibold uppercase tracking-wide",
        widget_header_status_class(status)
      ],
      text: label
    }
  end

  defp widget_header_status_class(:ready), do: "bg-success/20 text-success"
  defp widget_header_status_class(:attention), do: "bg-warning/20 text-warning"
  defp widget_header_status_class(:blocked), do: "bg-error/20 text-error"
  defp widget_header_status_class(:info), do: "bg-info/20 text-info"

  defp widget_header_severity_class(:critical), do: "bg-error/20 text-error"
  defp widget_header_severity_class(:warning), do: "bg-warning/20 text-warning"
  defp widget_header_severity_class(:info), do: "bg-info/20 text-info"

  defp compact_widget_header_attrs(attrs) do
    attrs
    |> Enum.reject(fn {_name, value} -> is_nil(value) end)
    |> Map.new()
  end

  defp widget_header_attr_value(nil), do: nil
  defp widget_header_attr_value(value) when is_binary(value), do: value
  defp widget_header_attr_value(value) when is_atom(value), do: Atom.to_string(value)
  defp widget_header_attr_value(value), do: to_string(value)

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
          phx-click={JS.dispatch("click", to: "#dashboard-menu-trigger")}
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
