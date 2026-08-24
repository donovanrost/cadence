defmodule CadenceWeb.OpsDashboardShowLive.DashboardWidgetHeaderComponentsTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest, only: [render_component: 2]

  import CadenceWeb.OpsDashboardShowLive.ViewTestSupport,
    only: [dashboard_widget_presentation: 2, widget_header_presentation: 2]

  alias Cadence.Dashboards.RenderWidget
  alias CadenceWeb.OpsDashboardShowLive.Components

  @widget_types [
    :value_tile,
    :time_series,
    :status_matrix,
    :data_table,
    :state_timeline,
    :event_timeline,
    :constellation_health
  ]

  for type <- @widget_types, {mode, edit_mode?} <- [{:viewer, false}, {:editor, true}] do
    @widget_type type
    @widget_edit_mode? edit_mode?

    test "#{mode} #{type} preserves the single header host and body boundary" do
      type = @widget_type
      placement_id = Atom.to_string(type)
      html = render_widget(type, @widget_edit_mode?)
      widget_presentation = dashboard_widget_presentation(html, placement_id)
      presentation = widget_header_presentation(html, placement_id)

      assert presentation["root"]["attrs"]["data-dashboard-widget-type"] == placement_id
      assert presentation["title"]["text"] == widget_title(type)

      assert length(presentation["actions"]["edit"]) ==
               if(@widget_edit_mode?, do: 2, else: 0)

      document = LazyHTML.from_fragment(html)
      expected_header_id = "dashboard-widget-header-#{placement_id}-component"
      expected_widget_id = "dashboard-widget-#{placement_id}-component"

      assert presentation["component_id"] == expected_header_id
      assert widget_presentation["body"]["kind"] == placement_id

      assert [^expected_widget_id] =
               document
               |> LazyHTML.query("##{expected_widget_id}")
               |> LazyHTML.attribute("id")

      assert ["DashboardWidget"] =
               document
               |> LazyHTML.query(~s([phx-hook="VueHook"]))
               |> LazyHTML.attribute("data-name")

      body_notice_state =
        case widget_presentation["body"]["notice"] do
          nil -> []
          notice -> Map.get(notice["attrs"], "data-widget-body-notice") |> List.wrap()
        end

      assert expected_body_notice(type) == body_notice_state

      assert [] ==
               document
               |> LazyHTML.query(~s([phx-hook="Overlay"][id^="widget-details-"]))
               |> LazyHTML.attribute("id")
    end
  end

  test "root title classes and lifecycle metadata remain server canonical" do
    presentation = presentation(:value_tile, ready_point_data())

    assert presentation.root.class == [
             "cadence-dashboard-widget-header",
             "flex shrink-0 items-center gap-1.5 px-2.5 py-1"
           ]

    assert presentation.title == %{
             class: [
               "min-w-0 flex-1 truncate",
               "text-[0.8rem] font-semibold leading-4 text-base-content/85"
             ],
             text: "Value Tile"
           }

    assert presentation.root.attrs["data-dashboard-widget-header"] == ""
    assert presentation.root.attrs["data-widget-lifecycle-state"] == "ready"
    assert presentation.root.attrs["data-widget-lifecycle-severity"] == "ok"
    assert presentation.root.attrs["data-warning-codes"] == ""
  end

  test "limit and quality status indicator branches preserve labels and classes" do
    for {limit_state, label, class} <- [
          {:red, "Red", "bg-error/20 text-error"},
          {:yellow, "Yellow", "bg-warning/20 text-warning"},
          {:blue, "Blue", "bg-info/20 text-info"}
        ] do
      data = put_in(ready_point_data(), [:limit_event], %{normalized_state: limit_state})
      limit = presentation(:value_tile, data).status_indicators.limit
      assert limit.text == label
      assert class in limit.class
    end

    suspect = put_in(ready_point_data(), [:sample, :quality_state], :suspect)
    bad = put_in(ready_point_data(), [:sample, :quality_state], :bad)

    assert presentation(:value_tile, suspect).status_indicators.quality == %{
             class: [
               "inline-flex rounded-full px-2 py-1 text-[0.65rem] font-semibold uppercase tracking-wide",
               "bg-warning/20 text-warning"
             ],
             text: "Suspect"
           }

    assert presentation(:value_tile, bad).status_indicators.quality.text == "Bad"
    refute presentation(:value_tile, ready_point_data()).status_indicators.limit
  end

  test "comparison summary branches preserve state counts views delta and title" do
    for state <- ["increased", "decreased", "unchanged", "available", "missing"] do
      summary = %{
        state: state,
        label: "Comparison #{state}",
        title: "Comparison title #{state}",
        primary_view: "canonical",
        compare_view: "all_revisions",
        primary_count: 3,
        compare_count: 2,
        delta: "+1"
      }

      presentation = presentation(:value_tile, ready_point_data(), comparison_summary: summary)
      badge = presentation.status_indicators.comparison

      assert badge.attrs["data-widget-comparison-state"] == state
      assert badge.attrs["data-widget-comparison-primary-count"] == "3"
      assert badge.attrs["data-widget-comparison-compare-count"] == "2"
      assert badge.attrs["data-widget-comparison-delta"] == "+1"
      assert badge.attrs["title"] == "Comparison title #{state}"
      assert presentation.root.attrs["data-widget-comparison-state"] == state
    end
  end

  test "lifecycle detail badges and compact header indicators preserve every branch" do
    for {state, detail_text, indicator?} <- [
          {:ready, nil, false},
          {:no_data, "No Data", false},
          {:stale, "Stale", true},
          {:partial, "Partial", true},
          {:retention_gap, "Retention Gap", false},
          {:error, "Source Error", false},
          {:unsupported, "Unsupported", false}
        ] do
      lifecycle = presentation(:value_tile, lifecycle_point_data(state))

      if detail_text do
        assert lifecycle.actions.details.body.indicators.lifecycle.text == detail_text
      else
        refute lifecycle.actions.details.body.indicators.lifecycle
      end

      assert !!lifecycle.status_indicators.lifecycle == indicator?
    end
  end

  test "details binding captions preserve constellation fixed and context resolution branches" do
    spacecraft = [%{spacecraft_id: "spacecraft-1", display_name: "SC Alpha"}]

    assert presentation(:constellation_health, nil).actions.details.body.heading.binding.text ==
             "All spacecraft"

    assert presentation(:value_tile, nil, spacecraft: spacecraft).actions.details.body.heading.binding.text ==
             "SC Alpha · HK.value_tile"

    context_widget =
      widget(:value_tile)
      |> Map.put(:binding, %{mode: :context, source: :telemetry, point_id: "HK.context"})

    unresolved = presentation(context_widget, nil, spacecraft: spacecraft)

    resolved =
      presentation(context_widget, %{spacecraft_id: "spacecraft-1"}, spacecraft: spacecraft)

    assert unresolved.actions.details.body.heading.binding.text == "HK.context"
    assert resolved.actions.details.body.heading.binding.text == "SC Alpha · HK.context"
  end

  test "details popover preserves stable IDs classes hidden state and accessibility" do
    details = presentation(:value_tile, ready_point_data()).actions.details

    assert details.overlay == %{
             id: "widget-details-value_tile",
             class: "cadence-overlay",
             attrs: %{
               "data-overlay-kind" => "popover",
               "data-overlay-placement" => "bottom-end",
               "data-widget-details" => ""
             }
           }

    assert details.trigger.id == "widget-details-value_tile-trigger"
    assert details.trigger.attrs["aria-controls"] == "widget-details-value_tile-panel"
    assert details.trigger.attrs["aria-expanded"] == "false"
    assert details.trigger.attrs["aria-haspopup"] == "dialog"
    assert details.trigger.content.attrs["data-widget-details-toggle"] == ""
    assert details.panel.id == "widget-details-value_tile-panel"
    assert details.panel.hidden
    assert details.panel.attrs["data-overlay-width"] == "md"
  end

  test "source badge preserves evidence payload and inventory navigation contract" do
    source_status = %{
      state: :stale,
      severity: :warning,
      data_state: :ready,
      source_request_ids: ["request-1"],
      logical_sources: [:telemetry],
      data_source_ids: ["questdb-flight"],
      source_binding_ids: ["binding-flight"],
      realms: [:flight],
      scope_kinds: [:contact],
      scope_ids: ["contact-1"],
      contact_ids: ["contact-1"],
      source_endpoint_ids: ["endpoint-1"]
    }

    data = Map.put(lifecycle_point_data(:stale), :source_status, source_status)

    source =
      presentation(:value_tile, data, mission_id: "mission-1").actions.details.body.indicators.source

    assert source.wrapper == %{tag: "span", class: "join"}
    assert source.badge.tag == "button"
    assert source.badge.attrs["phx-click"] == "open_evidence"
    assert source.badge.attrs["phx-value-kind"] == "source"
    assert source.badge.attrs["phx-value-source-request-id"] == "request-1"
    assert source.badge.attrs["data-widget-source-badge"] == "stale"
    assert source.inventory_link.attrs["data-phx-link"] == "redirect"
    assert source.inventory_link.attrs["data-phx-link-state"] == "push"
    assert source.inventory_link.attrs["href"] =~ "/missions/mission-1/ops/data-sources?"
    assert source.inventory_link.attrs["href"] =~ "contact_id=contact-1"

    passive_data =
      lifecycle_point_data(:no_data)
      |> Map.put(:source_status, %{state: :no_data, severity: :info, data_state: :no_data})

    passive = presentation(:value_tile, passive_data).actions.details.body.indicators.source
    refute passive.wrapper
    assert passive.badge.tag == "span"
    assert passive.badge.attrs["data-widget-source-badge-action"] == "none"
    refute Map.has_key?(passive.badge.attrs, "phx-click")
  end

  test "data management badges preserve actionable and passive tags and payloads" do
    actionable = %{
      kind: :backfill,
      value: "backfill_started",
      code: :backfill_started,
      label: "Backfill started",
      status: :warning,
      summary: "Operator requested replay",
      data_link_target: :telemetry_backfill_lifecycle_event,
      data_link_id: "backfill-event-1",
      realm: :replay,
      data_view: :all_revisions
    }

    passive = %{
      kind: :data_view,
      value: "all_revisions",
      code: nil,
      label: "All revisions",
      status: :info,
      summary: "Multiple revisions included"
    }

    data = put_in(ready_point_data(), [:data_management], %{badges: [actionable, passive]})

    [action, label] =
      presentation(:value_tile, data).actions.details.body.indicators.data_management

    assert action.tag == "button"
    assert action.attrs["phx-click"] == "open_data_link"

    assert action.attrs["phx-value-link-id"] ==
             "direct:telemetry_backfill_lifecycle_event:backfill-event-1"

    assert action.attrs["phx-value-target"] == "telemetry_backfill_lifecycle_event"
    assert action.attrs["phx-value-target-id"] == "backfill-event-1"
    assert label.tag == "span"
    refute Map.has_key?(label.attrs, "phx-click")
  end

  test "warning and query presenters are nested as direct component presentations" do
    warning = %{
      code: :source_degraded,
      code_text: "source_degraded",
      label: "Source degraded",
      message: "Telemetry source returned degraded data.",
      severity: :warning,
      details: %{source_request_id: "request-1", logical_source: :telemetry},
      detail_rows: [],
      evidence: [],
      links: []
    }

    header =
      presentation(:value_tile, ready_point_data(), warnings: [warning], data_view: "canonical")

    [warning_presentation] = header.actions.details.body.indicators.warnings
    query = header.actions.details.body.actions.query

    assert warning_presentation.component_id == "widget-value_tile-engine-warning-0-component"
    assert warning_presentation.body.evidence_button.attrs["phx-click"] == "open_evidence"

    assert warning_presentation.body.evidence_button.attrs["phx-value-warning-code"] ==
             "source_degraded"

    assert query.component_id == "widget-query-value_tile-component"
    assert query.body.evidence_button.attrs["phx-click"] == "open_evidence"
    assert query.body.evidence_button.attrs["phx-value-kind"] == "query"
    assert query.body.evidence_button.attrs["phx-value-placement-id"] == "value_tile"
  end

  test "frame data-link inspector configure and remove actions preserve exact events and payloads" do
    link = %{
      link_id: "link-1",
      label: "Sample",
      target: :telemetry_sample,
      target_text: "telemetry_sample",
      target_id: "sample-1",
      source_text: "telemetry"
    }

    data =
      ready_point_data()
      |> Map.put(:observable_id, "HK.value_tile")
      |> Map.put(:links, [link])

    header = presentation(:time_series, data, edit_mode?: true)
    actions = header.actions.details.body.actions

    assert actions.frame_evidence.attrs["phx-click"] == "open_evidence"
    assert actions.frame_evidence.attrs["phx-value-kind"] == "frame"
    assert actions.frame_evidence.attrs["phx-value-placement-id"] == "time_series"
    assert actions.frame_evidence.attrs["phx-value-observable-id"] == "HK.value_tile"

    [data_link] = actions.data_links.items
    assert data_link.attrs["phx-click"] == "open_data_link"
    assert data_link.attrs["phx-value-link-id"] == "link-1"
    assert data_link.attrs["phx-value-target"] == "telemetry_sample"
    assert data_link.attrs["phx-value-target-id"] == "sample-1"

    assert actions.inspector.attrs == %{
             "aria-label" => "Inspect data",
             "data-widget-inspect-data" => "",
             "phx-click" => "open_widget_inspector",
             "phx-value-placement-id" => "time_series",
             "title" => "Inspect data"
           }

    [configure, remove] = header.actions.edit
    assert configure.attrs["phx-click"] == "open_widget_config"
    assert configure.attrs["phx-value-widget-id"] == "time_series"
    assert remove.attrs["phx-click"] == "remove_widget"
    assert remove.attrs["phx-value-widget-id"] == "time_series"
    assert remove.attrs["data-confirm"] == "Remove this widget?"
  end

  defp render_widget(type, edit_mode?) do
    render_component(&Components.widget/1,
      widget: widget(type),
      placement_id: Atom.to_string(type),
      data: nil,
      compare_data: nil,
      point: nil,
      spacecraft: [],
      backfill: nil,
      limit_markers: [],
      event_markers: [],
      selected_data_ref: nil,
      context_spacecraft_id: "spacecraft-1",
      chart_epoch: 1,
      edit_mode?: edit_mode?,
      warnings: []
    )
  end

  defp presentation(type_or_widget, data, overrides \\ []) do
    widget = if is_atom(type_or_widget), do: widget(type_or_widget), else: type_or_widget

    %{
      widget: widget,
      placement_id: Atom.to_string(widget.type),
      mission_id: nil,
      data: data,
      compare_data: nil,
      backfill: nil,
      compare_backfill: nil,
      data_view: nil,
      compare_data_view: nil,
      comparison_summary: nil,
      spacecraft: [],
      edit_mode?: false,
      warnings: []
    }
    |> Map.merge(Map.new(overrides))
    |> Components.widget_header_presentation()
  end

  defp widget(:constellation_health) do
    %RenderWidget{
      widget_id: "constellation_health",
      type: :constellation_health,
      title: widget_title(:constellation_health),
      binding: %{mode: :constellation, source: :telemetry},
      options: %{}
    }
  end

  defp widget(type) do
    %RenderWidget{
      widget_id: Atom.to_string(type),
      type: type,
      title: widget_title(type),
      binding: %{
        mode: :fixed,
        source: :telemetry,
        spacecraft_id: "spacecraft-1",
        point_id: "HK.#{type}"
      },
      options: %{precision: 2, window_seconds: 300}
    }
  end

  defp widget_title(type) do
    type
    |> Atom.to_string()
    |> String.replace("_", " ")
    |> String.split()
    |> Enum.map_join(" ", &String.capitalize/1)
  end

  defp ready_point_data do
    %{
      kind: :point,
      sample: %{
        raw_value: 42,
        engineering_value: 42,
        quality_state: :good,
        receipt_time: ~U[2026-06-17 12:00:00Z],
        generation_time: ~U[2026-06-17 12:00:00Z]
      },
      limit_event: nil,
      links: [],
      data_management: nil,
      stale?: false,
      unresolved?: false,
      engine_backed?: true,
      lifecycle_state: :ready,
      lifecycle: %{
        state: :ready,
        severity: :ok,
        reason_codes: [],
        warning_codes: []
      }
    }
  end

  defp lifecycle_point_data(state) do
    sample =
      if state in [:no_data, :retention_gap, :error, :unsupported],
        do: nil,
        else: ready_point_data().sample

    %{
      ready_point_data()
      | sample: sample,
        stale?: state == :stale,
        lifecycle_state: state,
        lifecycle: %{
          state: state,
          severity: lifecycle_severity(state),
          reason_codes: if(state == :ready, do: [], else: [state]),
          warning_codes: []
        }
    }
  end

  defp lifecycle_severity(:ready), do: :ok
  defp lifecycle_severity(:no_data), do: :info
  defp lifecycle_severity(:stale), do: :warning
  defp lifecycle_severity(:partial), do: :warning
  defp lifecycle_severity(:retention_gap), do: :error
  defp lifecycle_severity(:error), do: :error
  defp lifecycle_severity(:unsupported), do: :error

  defp expected_body_notice(:value_tile), do: []
  defp expected_body_notice(:constellation_health), do: ["no_data"]
  defp expected_body_notice(_type), do: ["unresolved"]
end
