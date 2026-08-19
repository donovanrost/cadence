defmodule CadenceWeb.OpsDashboardShowLive.RuntimeTransportEvidenceLiveTest do
  use CadenceWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  use CadenceWeb.OpsDashboardShowLive.ViewTestSupport
  import CadenceWeb.OpsDashboardShowLive.RuntimeReplaySourceFamilyFixtures
  import CadenceWeb.OpsDashboardShowLive.RuntimeReplayEvidenceFixtures

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias Cadence.Dashboards.Document

  alias CadenceWeb.OpsDashboardShowLive.RuntimeReplayTransportEvidenceScenario,
    as: ReplayTransportRuntimeEvidenceScenario

  alias CadenceWeb.TestFixtures

  defp assert_data_link_field(view, field) do
    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="#{field}"])
           )
  end

  defp assert_data_link_field(view, field, value) do
    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="#{field}"]),
             value
           )
  end

  test "opens live transport runtime capability-record operational-event copied route from frame evidence" do
    record_at = ~U[2026-06-17 12:01:00Z]
    action_at = ~U[2026-06-17 12:01:30Z]
    timer_at = ~U[2026-06-17 12:02:00Z]

    {conn, org, mission} = signed_in_org_and_mission()

    transport_events =
      persist_live_transport_runtime_events!(
        org,
        mission,
        record_at,
        action_at,
        timer_at
      )

    record_event =
      Enum.find(transport_events, &(&1.kind == :transport_control_input_handled))

    assert Map.get(record_event.payload, "record_metadata") == %{
             "action_request_ids" => ["transport-action-request-live-1"],
             "emitted_record_refs" => ["uplink-frame-live-1"]
           }

    dashboard =
      TestFixtures.persist_dashboard_document!(mission,
        name: "Live Transport Capability Evidence",
        widgets: [
          %{
            type: :state_timeline,
            title: "Live Transport Capability",
            binding: %{
              source: :operational_observables,
              observables: ["runtime.transport_activity"]
            }
          }
        ]
      )

    document = fetch_dashboard_document!(org, mission, dashboard)
    timeline_widget = render_item_by_title(document, "Live Transport Capability").widget
    timeline_widget_id = timeline_widget.widget_id

    {:ok, view, _html} =
      live(
        conn,
        show_path(mission, dashboard) <>
          "?scope_kind=mission&scope_id=#{mission.mission_id}"
      )

    render_dashboard_async(view)

    assert has_element?(
             view,
             ~s(#ops-dashboard-show-page[data-dashboard-time-mode="live"][data-engine-time-mode="live"])
           )

    record_row_id =
      "state:runtime.transport_activity:#{DateTime.to_unix(record_at, :millisecond)}:0"

    record_row_selector =
      ~s(#widget-#{timeline_widget_id} [data-state-timeline-row="#{record_row_id}"])

    assert has_element?(
             view,
             record_row_selector <>
               ~s([data-state-timeline-observable="runtime.transport_activity"][data-state-timeline-state="Transport control input handled"][data-state-timeline-realm="flight"][data-state-timeline-data-source-id="managed_operational_observables"][data-state-timeline-source-binding-id="default_flight_operational_observables"])
           )

    assert has_element?(
             view,
             record_row_selector <>
               ~s( [data-state-timeline-row-evidence="#{record_row_id}"][data-state-timeline-row-evidence-observable="runtime.transport_activity"][phx-value-source-binding-id="default_flight_operational_observables"][phx-value-data-source-id="managed_operational_observables"])
           )

    view
    |> element(record_row_selector <> ~s( [data-state-timeline-row-evidence]))
    |> render_click()

    evidence_path = assert_patch(view)
    assert evidence_path =~ "panel=evidence"
    assert evidence_path =~ "selected_evidence_kind=frame"
    assert evidence_path =~ "selected_placement=#{URI.encode_www_form(timeline_widget_id)}"
    assert evidence_path =~ "selected_observable=runtime.transport_activity"
    assert evidence_path =~ "selected_data_source=managed_operational_observables"
    assert evidence_path =~ "selected_source_binding=default_flight_operational_observables"
    assert evidence_path =~ "selected_realm=flight"

    assert has_element?(
             view,
             ~s(#dashboard-evidence-inspector[data-evidence-kind="frame"][data-evidence-status="resolved"])
           )

    for transport_event <- transport_events do
      assert has_element?(
               view,
               ~s(#dashboard-evidence-inspector [data-evidence-ref-kind="operational event"][data-evidence-ref-id="#{transport_event.event_id}"])
             )
    end

    record_event_selector =
      ~s(#dashboard-evidence-inspector [data-evidence-ref-kind="operational event"][data-evidence-ref-id="#{record_event.event_id}"])

    record_event_id = record_event.event_id
    record_event_route_id = URI.encode_www_form(record_event_id)
    record_event_at_ms = DateTime.to_unix(record_at, :millisecond)

    record_event_evidence =
      view
      |> render()
      |> LazyHTML.from_fragment()
      |> LazyHTML.query(record_event_selector)

    assert ["operational_event"] =
             LazyHTML.attribute(record_event_evidence, "phx-value-target")

    assert [^record_event_id] =
             LazyHTML.attribute(record_event_evidence, "phx-value-target-id")

    assert ["evidence-ref:operational_event:" <> _] =
             LazyHTML.attribute(record_event_evidence, "phx-value-link-id")

    view
    |> element(record_event_selector)
    |> render_click(%{
      "link-id" => "evidence-ref:operational_event:#{record_event_id}",
      "target" => "operational_event",
      "target-id" => record_event_id,
      "timestamp-ms" => record_event_at_ms,
      "realm" => "flight",
      "time-mode" => "live",
      "data-source-id" => "managed_operational_observables",
      "source-binding-id" => "default_flight_operational_observables"
    })

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="operational_event"][data-data-link-target-id="#{record_event_id}"][data-data-link-status="resolved"][data-data-link-selected-data-source-id="managed_operational_observables"][data-data-link-selected-source-binding-id="default_flight_operational_observables"])
           )

    record_event_path = assert_patch(view)
    assert record_event_path =~ "panel=data_link"
    assert record_event_path =~ "selected_target=operational_event"
    assert record_event_path =~ "selected_id=#{record_event_route_id}"
    assert record_event_path =~ "selected_time=#{record_event_at_ms}"
    assert record_event_path =~ "time_mode=live"

    assert has_element?(
             view,
             ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=operational_event"][data-clipboard-text*="selected_id=#{record_event_route_id}"][data-clipboard-text*="selected_time=#{record_event_at_ms}"][data-clipboard-text*="data_source_id=managed_operational_observables"][data-clipboard-text*="source_binding_id=default_flight_operational_observables"])
           )

    record_event_copied_path =
      view
      |> render()
      |> element_attribute("#dashboard-data-link-copy-link", "data-clipboard-text")

    assert record_event_copied_path =~ "panel=data_link"
    assert record_event_copied_path =~ "selected_target=operational_event"
    assert record_event_copied_path =~ "selected_id=#{record_event_route_id}"
    assert record_event_copied_path =~ "selected_time=#{record_event_at_ms}"
    assert record_event_copied_path =~ "time_mode=live"
    assert record_event_copied_path =~ "data_source_id=managed_operational_observables"

    assert record_event_copied_path =~
             "source_binding_id=default_flight_operational_observables"

    {:ok, reopened_record_event_view, _html} = live(conn, record_event_copied_path)

    assert has_element?(
             reopened_record_event_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="operational_event"][data-data-link-target-id="#{record_event_id}"][data-data-link-status="resolved"][data-data-link-selected-data-source-id="managed_operational_observables"][data-data-link-selected-source-binding-id="default_flight_operational_observables"])
           )

    assert has_element?(
             reopened_record_event_view,
             ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=operational_event"][data-clipboard-text*="selected_id=#{record_event_route_id}"][data-clipboard-text*="selected_time=#{record_event_at_ms}"])
           )

    assert_live_transport_capability_runtime_context!(reopened_record_event_view)

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Transport capability record"])
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Event kind"])
           )

    stop_dashboard_view(reopened_record_event_view)
    stop_dashboard_view(view)
  end

  test "opens live transport runtime action-request operational-event copied route from frame evidence" do
    record_at = ~U[2026-06-17 12:01:00Z]
    action_at = ~U[2026-06-17 12:01:30Z]
    timer_at = ~U[2026-06-17 12:02:00Z]

    {conn, org, mission} = signed_in_org_and_mission()

    transport_events =
      persist_live_transport_runtime_events!(
        org,
        mission,
        record_at,
        action_at,
        timer_at
      )

    action_event =
      Enum.find(transport_events, &(&1.kind == :transport_action_requested))

    assert Map.get(action_event.payload, "request_document") == %{
             "command_request_id" => "command-request-live-1",
             "frame_count" => 1
           }

    dashboard =
      TestFixtures.persist_dashboard_document!(mission,
        name: "Live Transport Runtime Evidence",
        widgets: [
          %{
            type: :state_timeline,
            title: "Live Transport Runtime",
            binding: %{
              source: :operational_observables,
              observables: ["runtime.transport_activity"]
            }
          }
        ]
      )

    document = fetch_dashboard_document!(org, mission, dashboard)
    timeline_widget = render_item_by_title(document, "Live Transport Runtime").widget
    timeline_widget_id = timeline_widget.widget_id

    {:ok, view, _html} =
      live(
        conn,
        show_path(mission, dashboard) <>
          "?scope_kind=mission&scope_id=#{mission.mission_id}"
      )

    render_dashboard_async(view)

    assert has_element?(
             view,
             ~s(#ops-dashboard-show-page[data-dashboard-time-mode="live"][data-engine-time-mode="live"])
           )

    record_row_id =
      "state:runtime.transport_activity:#{DateTime.to_unix(record_at, :millisecond)}:0"

    action_row_id =
      "state:runtime.transport_activity:#{DateTime.to_unix(action_at, :millisecond)}:1"

    timer_row_id =
      "state:runtime.transport_activity:#{DateTime.to_unix(timer_at, :millisecond)}:2"

    record_row_selector =
      ~s(#widget-#{timeline_widget_id} [data-state-timeline-row="#{record_row_id}"])

    action_row_selector =
      ~s(#widget-#{timeline_widget_id} [data-state-timeline-row="#{action_row_id}"])

    timer_row_selector =
      ~s(#widget-#{timeline_widget_id} [data-state-timeline-row="#{timer_row_id}"])

    assert has_element?(
             view,
             record_row_selector <>
               ~s([data-state-timeline-observable="runtime.transport_activity"][data-state-timeline-state="Transport control input handled"][data-state-timeline-realm="flight"][data-state-timeline-data-source-id="managed_operational_observables"][data-state-timeline-source-binding-id="default_flight_operational_observables"])
           )

    assert has_element?(
             view,
             action_row_selector <>
               ~s([data-state-timeline-observable="runtime.transport_activity"][data-state-timeline-state="Transport action requested"][data-state-timeline-realm="flight"])
           )

    assert has_element?(
             view,
             timer_row_selector <>
               ~s([data-state-timeline-observable="runtime.transport_activity"][data-state-timeline-state="Transport timer fired"][data-state-timeline-realm="flight"])
           )

    assert has_element?(
             view,
             action_row_selector <>
               ~s( [data-state-timeline-row-evidence="#{action_row_id}"][data-state-timeline-row-evidence-observable="runtime.transport_activity"][phx-value-source-binding-id="default_flight_operational_observables"][phx-value-data-source-id="managed_operational_observables"])
           )

    view
    |> element(action_row_selector <> ~s( [data-state-timeline-row-evidence]))
    |> render_click()

    evidence_path = assert_patch(view)
    assert evidence_path =~ "panel=evidence"
    assert evidence_path =~ "selected_evidence_kind=frame"
    assert evidence_path =~ "selected_placement=#{URI.encode_www_form(timeline_widget_id)}"
    assert evidence_path =~ "selected_observable=runtime.transport_activity"
    assert evidence_path =~ "selected_data_source=managed_operational_observables"
    assert evidence_path =~ "selected_source_binding=default_flight_operational_observables"
    assert evidence_path =~ "selected_realm=flight"

    assert has_element?(
             view,
             ~s(#dashboard-evidence-inspector[data-evidence-kind="frame"][data-evidence-status="resolved"])
           )

    for transport_event <- transport_events do
      assert has_element?(
               view,
               ~s(#dashboard-evidence-inspector [data-evidence-ref-kind="operational event"][data-evidence-ref-id="#{transport_event.event_id}"])
             )
    end

    assert has_element?(
             view,
             ~s(#dashboard-evidence-copy-link[data-clipboard-text*="panel=evidence"][data-clipboard-text*="selected_evidence_kind=frame"][data-clipboard-text*="selected_observable=#{URI.encode_www_form("runtime.transport_activity")}"][data-clipboard-text*="selected_data_source=managed_operational_observables"][data-clipboard-text*="selected_source_binding=default_flight_operational_observables"])
           )

    action_event_selector =
      ~s(#dashboard-evidence-inspector [data-evidence-ref-kind="operational event"][data-evidence-ref-id="#{action_event.event_id}"])

    action_event_id = action_event.event_id
    action_event_route_id = URI.encode_www_form(action_event_id)
    action_event_at_ms = DateTime.to_unix(action_at, :millisecond)

    action_event_evidence =
      view
      |> render()
      |> LazyHTML.from_fragment()
      |> LazyHTML.query(action_event_selector)

    assert ["operational_event"] =
             LazyHTML.attribute(action_event_evidence, "phx-value-target")

    assert [^action_event_id] =
             LazyHTML.attribute(action_event_evidence, "phx-value-target-id")

    assert ["evidence-ref:operational_event:" <> _] =
             LazyHTML.attribute(action_event_evidence, "phx-value-link-id")

    view
    |> element(action_event_selector)
    |> render_click(%{
      "link-id" => "evidence-ref:operational_event:#{action_event_id}",
      "target" => "operational_event",
      "target-id" => action_event_id,
      "timestamp-ms" => action_event_at_ms,
      "realm" => "flight",
      "time-mode" => "live",
      "data-source-id" => "managed_operational_observables",
      "source-binding-id" => "default_flight_operational_observables"
    })

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="operational_event"][data-data-link-target-id="#{action_event_id}"][data-data-link-status="resolved"][data-data-link-selected-data-source-id="managed_operational_observables"][data-data-link-selected-source-binding-id="default_flight_operational_observables"])
           )

    action_event_path = assert_patch(view)
    assert action_event_path =~ "panel=data_link"
    assert action_event_path =~ "selected_target=operational_event"
    assert action_event_path =~ "selected_id=#{action_event_route_id}"
    assert action_event_path =~ "selected_time=#{action_event_at_ms}"
    assert action_event_path =~ "time_mode=live"

    assert has_element?(
             view,
             ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=operational_event"][data-clipboard-text*="selected_id=#{action_event_route_id}"][data-clipboard-text*="selected_time=#{action_event_at_ms}"][data-clipboard-text*="data_source_id=managed_operational_observables"][data-clipboard-text*="source_binding_id=default_flight_operational_observables"])
           )

    action_event_copied_path =
      view
      |> render()
      |> element_attribute("#dashboard-data-link-copy-link", "data-clipboard-text")

    assert action_event_copied_path =~ "panel=data_link"
    assert action_event_copied_path =~ "selected_target=operational_event"
    assert action_event_copied_path =~ "selected_id=#{action_event_route_id}"
    assert action_event_copied_path =~ "selected_time=#{action_event_at_ms}"
    assert action_event_copied_path =~ "time_mode=live"
    assert action_event_copied_path =~ "data_source_id=managed_operational_observables"

    assert action_event_copied_path =~
             "source_binding_id=default_flight_operational_observables"

    {:ok, reopened_action_event_view, _html} = live(conn, action_event_copied_path)

    assert has_element?(
             reopened_action_event_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="operational_event"][data-data-link-target-id="#{action_event_id}"][data-data-link-status="resolved"][data-data-link-selected-data-source-id="managed_operational_observables"][data-data-link-selected-source-binding-id="default_flight_operational_observables"])
           )

    assert has_element?(
             reopened_action_event_view,
             ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=operational_event"][data-clipboard-text*="selected_id=#{action_event_route_id}"][data-clipboard-text*="selected_time=#{action_event_at_ms}"])
           )

    assert_live_transport_action_runtime_context!(reopened_action_event_view)

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Transport action request"])
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Action kind"])
           )

    stop_dashboard_view(reopened_action_event_view)
    stop_dashboard_view(view)
  end

  test "opens live transport runtime timer operational-event copied route from frame evidence" do
    record_at = ~U[2026-06-17 12:01:00Z]
    action_at = ~U[2026-06-17 12:01:30Z]
    timer_at = ~U[2026-06-17 12:02:00Z]

    {conn, org, mission} = signed_in_org_and_mission()

    transport_events =
      persist_live_transport_runtime_events!(
        org,
        mission,
        record_at,
        action_at,
        timer_at
      )

    timer_event =
      Enum.find(transport_events, &(&1.kind == :transport_timer_fired))

    assert Map.get(timer_event.payload, "timer_metadata") == %{
             "action_request_id" => "transport-action-request-live-1"
           }

    dashboard =
      TestFixtures.persist_dashboard_document!(mission,
        name: "Live Transport Timer Evidence",
        widgets: [
          %{
            type: :state_timeline,
            title: "Live Transport Timer",
            binding: %{
              source: :operational_observables,
              observables: ["runtime.transport_activity"]
            }
          }
        ]
      )

    document = fetch_dashboard_document!(org, mission, dashboard)
    timeline_widget = render_item_by_title(document, "Live Transport Timer").widget
    timeline_widget_id = timeline_widget.widget_id

    {:ok, view, _html} =
      live(
        conn,
        show_path(mission, dashboard) <>
          "?scope_kind=mission&scope_id=#{mission.mission_id}"
      )

    render_dashboard_async(view)

    assert has_element?(
             view,
             ~s(#ops-dashboard-show-page[data-dashboard-time-mode="live"][data-engine-time-mode="live"])
           )

    timer_row_id =
      "state:runtime.transport_activity:#{DateTime.to_unix(timer_at, :millisecond)}:2"

    timer_row_selector =
      ~s(#widget-#{timeline_widget_id} [data-state-timeline-row="#{timer_row_id}"])

    assert has_element?(
             view,
             timer_row_selector <>
               ~s([data-state-timeline-observable="runtime.transport_activity"][data-state-timeline-state="Transport timer fired"][data-state-timeline-realm="flight"][data-state-timeline-data-source-id="managed_operational_observables"][data-state-timeline-source-binding-id="default_flight_operational_observables"])
           )

    assert has_element?(
             view,
             timer_row_selector <>
               ~s( [data-state-timeline-row-evidence="#{timer_row_id}"][data-state-timeline-row-evidence-observable="runtime.transport_activity"][phx-value-source-binding-id="default_flight_operational_observables"][phx-value-data-source-id="managed_operational_observables"])
           )

    view
    |> element(timer_row_selector <> ~s( [data-state-timeline-row-evidence]))
    |> render_click()

    evidence_path = assert_patch(view)
    assert evidence_path =~ "panel=evidence"
    assert evidence_path =~ "selected_evidence_kind=frame"
    assert evidence_path =~ "selected_placement=#{URI.encode_www_form(timeline_widget_id)}"
    assert evidence_path =~ "selected_observable=runtime.transport_activity"
    assert evidence_path =~ "selected_data_source=managed_operational_observables"
    assert evidence_path =~ "selected_source_binding=default_flight_operational_observables"
    assert evidence_path =~ "selected_realm=flight"

    assert has_element?(
             view,
             ~s(#dashboard-evidence-inspector[data-evidence-kind="frame"][data-evidence-status="resolved"])
           )

    for transport_event <- transport_events do
      assert has_element?(
               view,
               ~s(#dashboard-evidence-inspector [data-evidence-ref-kind="operational event"][data-evidence-ref-id="#{transport_event.event_id}"])
             )
    end

    timer_event_selector =
      ~s(#dashboard-evidence-inspector [data-evidence-ref-kind="operational event"][data-evidence-ref-id="#{timer_event.event_id}"])

    timer_event_id = timer_event.event_id
    timer_event_route_id = URI.encode_www_form(timer_event_id)
    timer_event_at_ms = DateTime.to_unix(timer_at, :millisecond)

    timer_event_evidence =
      view
      |> render()
      |> LazyHTML.from_fragment()
      |> LazyHTML.query(timer_event_selector)

    assert ["operational_event"] =
             LazyHTML.attribute(timer_event_evidence, "phx-value-target")

    assert [^timer_event_id] =
             LazyHTML.attribute(timer_event_evidence, "phx-value-target-id")

    assert ["evidence-ref:operational_event:" <> _] =
             LazyHTML.attribute(timer_event_evidence, "phx-value-link-id")

    view
    |> element(timer_event_selector)
    |> render_click(%{
      "link-id" => "evidence-ref:operational_event:#{timer_event_id}",
      "target" => "operational_event",
      "target-id" => timer_event_id,
      "timestamp-ms" => timer_event_at_ms,
      "realm" => "flight",
      "time-mode" => "live",
      "data-source-id" => "managed_operational_observables",
      "source-binding-id" => "default_flight_operational_observables"
    })

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="operational_event"][data-data-link-target-id="#{timer_event_id}"][data-data-link-status="resolved"][data-data-link-selected-data-source-id="managed_operational_observables"][data-data-link-selected-source-binding-id="default_flight_operational_observables"])
           )

    timer_event_path = assert_patch(view)
    assert timer_event_path =~ "panel=data_link"
    assert timer_event_path =~ "selected_target=operational_event"
    assert timer_event_path =~ "selected_id=#{timer_event_route_id}"
    assert timer_event_path =~ "selected_time=#{timer_event_at_ms}"
    assert timer_event_path =~ "time_mode=live"

    assert has_element?(
             view,
             ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=operational_event"][data-clipboard-text*="selected_id=#{timer_event_route_id}"][data-clipboard-text*="selected_time=#{timer_event_at_ms}"][data-clipboard-text*="data_source_id=managed_operational_observables"][data-clipboard-text*="source_binding_id=default_flight_operational_observables"])
           )

    timer_event_copied_path =
      view
      |> render()
      |> element_attribute("#dashboard-data-link-copy-link", "data-clipboard-text")

    assert timer_event_copied_path =~ "panel=data_link"
    assert timer_event_copied_path =~ "selected_target=operational_event"
    assert timer_event_copied_path =~ "selected_id=#{timer_event_route_id}"
    assert timer_event_copied_path =~ "selected_time=#{timer_event_at_ms}"
    assert timer_event_copied_path =~ "time_mode=live"
    assert timer_event_copied_path =~ "data_source_id=managed_operational_observables"

    assert timer_event_copied_path =~
             "source_binding_id=default_flight_operational_observables"

    {:ok, reopened_timer_event_view, _html} = live(conn, timer_event_copied_path)

    assert has_element?(
             reopened_timer_event_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="operational_event"][data-data-link-target-id="#{timer_event_id}"][data-data-link-status="resolved"][data-data-link-selected-data-source-id="managed_operational_observables"][data-data-link-selected-source-binding-id="default_flight_operational_observables"])
           )

    assert has_element?(
             reopened_timer_event_view,
             ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=operational_event"][data-clipboard-text*="selected_id=#{timer_event_route_id}"][data-clipboard-text*="selected_time=#{timer_event_at_ms}"])
           )

    assert_live_transport_timer_runtime_context!(reopened_timer_event_view)

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Transport timer event"])
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Timer metadata"])
           )

    stop_dashboard_view(reopened_timer_event_view)
    stop_dashboard_view(view)
  end

  test "opens replay managed capability record lifecycle evidence from rendered operational observable frame panel" do
    replay_run_id = "replay_run_managed_capability_record_ops"
    initialized_at = ~U[2026-06-17 12:00:30Z]
    record_at = ~U[2026-06-17 12:01:30Z]
    timer_at = ~U[2026-06-17 12:02:30Z]

    {conn, org, mission} = signed_in_org_and_mission()
    _telemetry_replay_source = persist_dashboard_realm!(mission, :replay)
    replay_sources = persist_replay_event_and_operational_sources!(mission)
    persist_replay_run!(mission, replay_run_id)

    capability_events =
      persist_replay_managed_capability_record_events!(
        org,
        mission,
        replay_run_id,
        initialized_at,
        record_at,
        timer_at
      )

    record_event =
      Enum.find(capability_events, &(&1.kind == :managed_capability_record_handled))

    assert Map.get(record_event.payload, "record_metadata") == %{
             "action_request_ids" => ["managed-action-request-2"],
             "emitted_record_refs" => ["limit-state-1", "derived-metric-1"]
           }

    dashboard =
      TestFixtures.persist_dashboard_document!(mission,
        name: "Replay Managed Capability Evidence",
        widgets: [
          %{
            type: :state_timeline,
            title: "Replay Managed Capability",
            binding: %{
              source: :operational_observables,
              observables: ["runtime.managed_activity"]
            }
          }
        ]
      )

    document =
      org
      |> fetch_dashboard_document!(mission, dashboard)
      |> then(fn %Document{} = document ->
        %Document{
          document
          | defaults: %{
              "data" => %{
                "realm" => "replay",
                "source_mode" => "specific",
                "source_contexts" => %{
                  "operational_observables" => %{
                    "source_binding_id" => replay_sources.operational_binding_id
                  }
                }
              }
            }
        }
      end)
      |> then(&replace_dashboard_row_document!(org, mission, &1))

    timeline_widget = render_item_by_title(document, "Replay Managed Capability").widget
    timeline_widget_id = timeline_widget.widget_id

    {:ok, view, _html} =
      live(
        conn,
        show_path(mission, dashboard) <>
          "?time_mode=replay_run&replay_run_id=#{replay_run_id}&scope_kind=mission&scope_id=#{mission.mission_id}"
      )

    render_dashboard_async(view)

    assert has_element?(
             view,
             ~s(#ops-dashboard-show-page[data-dashboard-time-mode="replay_run"][data-engine-time-mode="replay_run"][data-engine-replay-run-id="#{replay_run_id}"])
           )

    initialized_row_id =
      "state:runtime.managed_activity:#{DateTime.to_unix(initialized_at, :millisecond)}:0"

    record_row_id =
      "state:runtime.managed_activity:#{DateTime.to_unix(record_at, :millisecond)}:1"

    timer_row_id =
      "state:runtime.managed_activity:#{DateTime.to_unix(timer_at, :millisecond)}:2"

    initialized_row_selector =
      ~s(#widget-#{timeline_widget_id} [data-state-timeline-row="#{initialized_row_id}"])

    record_row_selector =
      ~s(#widget-#{timeline_widget_id} [data-state-timeline-row="#{record_row_id}"])

    timer_row_selector =
      ~s(#widget-#{timeline_widget_id} [data-state-timeline-row="#{timer_row_id}"])

    assert has_element?(
             view,
             initialized_row_selector <>
               ~s([data-state-timeline-observable="runtime.managed_activity"][data-state-timeline-state="Managed capability initialized"][data-state-timeline-realm="replay"][data-state-timeline-data-source-id="#{replay_sources.operational_data_source_id}"][data-state-timeline-source-binding-id="#{replay_sources.operational_binding_id}"][data-state-timeline-replay-run-id="#{replay_run_id}"][data-state-timeline-dataset="operational_observables_replay"])
           )

    assert has_element?(
             view,
             record_row_selector <>
               ~s([data-state-timeline-observable="runtime.managed_activity"][data-state-timeline-state="Managed capability record handled"][data-state-timeline-realm="replay"])
           )

    assert has_element?(
             view,
             timer_row_selector <>
               ~s([data-state-timeline-observable="runtime.managed_activity"][data-state-timeline-state="Managed capability timer handled"][data-state-timeline-realm="replay"])
           )

    assert has_element?(
             view,
             timer_row_selector <>
               ~s( [data-state-timeline-row-evidence="#{timer_row_id}"][data-state-timeline-row-evidence-observable="runtime.managed_activity"][phx-value-replay-run-id="#{replay_run_id}"][phx-value-source-binding-id="#{replay_sources.operational_binding_id}"][phx-value-data-source-id="#{replay_sources.operational_data_source_id}"])
           )

    view
    |> element(timer_row_selector <> ~s( [data-state-timeline-row-evidence]))
    |> render_click()

    evidence_path = assert_patch(view)
    assert evidence_path =~ "panel=evidence"
    assert evidence_path =~ "selected_evidence_kind=frame"
    assert evidence_path =~ "selected_placement=#{URI.encode_www_form(timeline_widget_id)}"
    assert evidence_path =~ "selected_observable=runtime.managed_activity"
    assert evidence_path =~ "selected_data_source=#{replay_sources.operational_data_source_id}"
    assert evidence_path =~ "selected_source_binding=#{replay_sources.operational_binding_id}"
    assert evidence_path =~ "replay_run_id=#{replay_run_id}"
    assert evidence_path =~ "time_mode=replay_run"

    assert has_element?(
             view,
             ~s(#dashboard-evidence-inspector[data-evidence-kind="frame"][data-evidence-status="resolved"])
           )

    for capability_event <- capability_events do
      assert has_element?(
               view,
               ~s(#dashboard-evidence-inspector [data-evidence-ref-kind="operational event"][data-evidence-ref-id="#{capability_event.event_id}"])
             )
    end

    assert has_element?(
             view,
             ~s(#dashboard-evidence-copy-link[data-clipboard-text*="panel=evidence"][data-clipboard-text*="selected_evidence_kind=frame"][data-clipboard-text*="selected_observable=#{URI.encode_www_form("runtime.managed_activity")}"][data-clipboard-text*="selected_data_source=#{replay_sources.operational_data_source_id}"][data-clipboard-text*="selected_source_binding=#{replay_sources.operational_binding_id}"][data-clipboard-text*="replay_run_id=#{replay_run_id}"])
           )

    record_event_selector =
      ~s(#dashboard-evidence-inspector [data-evidence-ref-kind="operational event"][data-evidence-ref-id="#{record_event.event_id}"])

    record_event_id = record_event.event_id
    record_event_route_id = URI.encode_www_form(record_event_id)
    record_event_at_ms = DateTime.to_unix(record_at, :millisecond)

    record_event_evidence =
      view
      |> render()
      |> LazyHTML.from_fragment()
      |> LazyHTML.query(record_event_selector)

    assert ["operational_event"] =
             LazyHTML.attribute(record_event_evidence, "phx-value-target")

    assert [^record_event_id] =
             LazyHTML.attribute(record_event_evidence, "phx-value-target-id")

    assert ["evidence-ref:operational_event:" <> _] =
             LazyHTML.attribute(record_event_evidence, "phx-value-link-id")

    view
    |> element(record_event_selector)
    |> render_click(%{
      "link-id" => "evidence-ref:operational_event:#{record_event_id}",
      "target" => "operational_event",
      "target-id" => record_event_id,
      "timestamp-ms" => record_event_at_ms,
      "realm" => "replay",
      "time-mode" => "replay_run",
      "replay-run-id" => replay_run_id,
      "data-source-id" => replay_sources.operational_data_source_id,
      "source-binding-id" => replay_sources.operational_binding_id
    })

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="operational_event"][data-data-link-target-id="#{record_event_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    record_event_path = assert_patch(view)
    assert record_event_path =~ "panel=data_link"
    assert record_event_path =~ "selected_target=operational_event"
    assert record_event_path =~ "selected_id=#{record_event_route_id}"
    assert record_event_path =~ "selected_time=#{record_event_at_ms}"
    assert record_event_path =~ "replay_run_id=#{replay_run_id}"

    assert has_element?(
             view,
             ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=operational_event"][data-clipboard-text*="selected_id=#{record_event_route_id}"][data-clipboard-text*="replay_run_id=#{replay_run_id}"][data-clipboard-text*="data_source_id=#{replay_sources.operational_data_source_id}"][data-clipboard-text*="source_binding_id=#{replay_sources.operational_binding_id}"])
           )

    record_event_copied_path =
      view
      |> render()
      |> element_attribute("#dashboard-data-link-copy-link", "data-clipboard-text")

    assert record_event_copied_path =~ "panel=data_link"
    assert record_event_copied_path =~ "selected_target=operational_event"
    assert record_event_copied_path =~ "selected_id=#{record_event_route_id}"
    assert record_event_copied_path =~ "selected_time=#{record_event_at_ms}"
    assert record_event_copied_path =~ "replay_run_id=#{replay_run_id}"

    assert record_event_copied_path =~
             "data_source_id=#{replay_sources.operational_data_source_id}"

    assert record_event_copied_path =~
             "source_binding_id=#{replay_sources.operational_binding_id}"

    {:ok, reopened_record_event_view, _html} = live(conn, record_event_copied_path)

    assert has_element?(
             reopened_record_event_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="operational_event"][data-data-link-target-id="#{record_event_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    assert has_element?(
             reopened_record_event_view,
             ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=operational_event"][data-clipboard-text*="selected_id=#{record_event_route_id}"][data-clipboard-text*="selected_time=#{record_event_at_ms}"][data-clipboard-text*="replay_run_id=#{replay_run_id}"])
           )

    assert_data_link_field(
      reopened_record_event_view,
      "Managed capability record",
      "managed-capability-record-handled-1"
    )

    assert_data_link_field(reopened_record_event_view, "Event kind", "record_handled")

    assert_data_link_field(
      reopened_record_event_view,
      "Capability instance",
      "managed-capability-alpha"
    )

    assert_data_link_field(reopened_record_event_view, "Family", "packet_counter")
    assert_data_link_field(reopened_record_event_view, "Binding set", "managed-binding-set-alpha")
    assert_data_link_field(reopened_record_event_view, "Binding set version", "1")
    assert_data_link_field(reopened_record_event_view, "Activation", "managed-activation-alpha")
    assert_data_link_field(reopened_record_event_view, "Partition affinity", "spacecraft")
    assert_data_link_field(reopened_record_event_view, "Partition value", "spacecraft-alpha")
    assert_data_link_field(reopened_record_event_view, "Packet", "managed-packet-alpha")
    assert_data_link_field(reopened_record_event_view, "Evidence", "managed-evidence-alpha")
    assert_data_link_field(reopened_record_event_view, "Emitted record kinds", "derived_metric")
    assert_data_link_field(reopened_record_event_view, "Emitted record count", "2")
    assert_data_link_field(reopened_record_event_view, "Action request count", "1")
    assert_data_link_field(reopened_record_event_view, "State snapshot", "heartbeat_count")

    assert_data_link_field(
      reopened_record_event_view,
      "Record metadata",
      "managed-action-request-2"
    )

    assert_data_link_field(reopened_record_event_view, "Record metadata", "limit-state-1")
    assert_data_link_field(reopened_record_event_view, "Record metadata", "derived-metric-1")
    assert_data_link_field(reopened_record_event_view, "Recorded")
    assert_data_link_field(reopened_record_event_view, "Replay run", replay_run_id)
    assert_data_link_field(view, "Managed capability record")
    assert_data_link_field(view, "Event kind")
    assert_data_link_field(view, "Replay run")

    stop_dashboard_view(reopened_record_event_view)
    stop_dashboard_view(view)
  end

  test "opens replay transport runtime action evidence from rendered operational observable frame panel" do
    ReplayTransportRuntimeEvidenceScenario.run()
  end
end
