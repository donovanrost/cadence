defmodule CadenceWeb.OpsDashboardShowLive.RuntimeManagedEvidenceLiveTest do
  use CadenceWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import CadenceWeb.OpsDashboardShowLive.ViewTestSupport
  import CadenceWeb.OpsDashboardShowLive.RuntimeReplaySourceFamilyFixtures
  import CadenceWeb.OpsDashboardShowLive.RuntimeReplayEvidenceFixtures

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias Cadence.Dashboards.Document
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

  defp persist_live_managed_runtime_dashboard!(org, mission) do
    dashboard =
      TestFixtures.persist_dashboard_document!(mission,
        name: "Live Managed Runtime Evidence",
        widgets: [
          %{
            type: :state_timeline,
            title: "Live Managed Runtime",
            binding: %{
              source: :operational_observables,
              observables: ["runtime.managed_activity"]
            }
          }
        ]
      )

    document = fetch_dashboard_document!(org, mission, dashboard)
    timeline_widget = render_item_by_title(document, "Live Managed Runtime").widget

    {dashboard, timeline_widget.widget_id}
  end

  defp assert_replay_managed_action_event_route(
         conn,
         evidence_path,
         action_event,
         action_at,
         replay_run_id,
         replay_sources
       ) do
    {:ok, action_evidence_view, _html} = live(conn, evidence_path)

    action_event_selector =
      ~s(#dashboard-evidence-inspector [data-evidence-ref-kind="operational event"][data-evidence-ref-id="#{action_event.event_id}"])

    action_event_id = action_event.event_id
    action_event_route_id = URI.encode_www_form(action_event_id)
    action_event_at_ms = DateTime.to_unix(action_at, :millisecond)

    action_event_evidence =
      action_evidence_view
      |> render()
      |> LazyHTML.from_fragment()
      |> LazyHTML.query(action_event_selector)

    assert ["operational_event"] =
             LazyHTML.attribute(action_event_evidence, "phx-value-target")

    assert [^action_event_id] =
             LazyHTML.attribute(action_event_evidence, "phx-value-target-id")

    assert ["evidence-ref:operational_event:" <> _] =
             LazyHTML.attribute(action_event_evidence, "phx-value-link-id")

    action_evidence_view
    |> element(action_event_selector)
    |> render_click(%{
      "link-id" => "evidence-ref:operational_event:#{action_event_id}",
      "target" => "operational_event",
      "target-id" => action_event_id,
      "timestamp-ms" => action_event_at_ms,
      "realm" => "replay",
      "time-mode" => "replay_run",
      "replay-run-id" => replay_run_id,
      "data-source-id" => replay_sources.operational_data_source_id,
      "source-binding-id" => replay_sources.operational_binding_id
    })

    assert has_element?(
             action_evidence_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="operational_event"][data-data-link-target-id="#{action_event_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    action_event_path = assert_patch(action_evidence_view)
    assert action_event_path =~ "panel=data_link"
    assert action_event_path =~ "selected_target=operational_event"
    assert action_event_path =~ "selected_id=#{action_event_route_id}"
    assert action_event_path =~ "selected_time=#{action_event_at_ms}"
    assert action_event_path =~ "replay_run_id=#{replay_run_id}"

    assert has_element?(
             action_evidence_view,
             ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=operational_event"][data-clipboard-text*="selected_id=#{action_event_route_id}"][data-clipboard-text*="replay_run_id=#{replay_run_id}"][data-clipboard-text*="data_source_id=#{replay_sources.operational_data_source_id}"][data-clipboard-text*="source_binding_id=#{replay_sources.operational_binding_id}"])
           )

    action_event_copied_path =
      action_evidence_view
      |> render()
      |> element_attribute("#dashboard-data-link-copy-link", "data-clipboard-text")

    assert action_event_copied_path =~ "panel=data_link"
    assert action_event_copied_path =~ "selected_target=operational_event"
    assert action_event_copied_path =~ "selected_id=#{action_event_route_id}"
    assert action_event_copied_path =~ "selected_time=#{action_event_at_ms}"
    assert action_event_copied_path =~ "replay_run_id=#{replay_run_id}"

    assert action_event_copied_path =~
             "data_source_id=#{replay_sources.operational_data_source_id}"

    assert action_event_copied_path =~
             "source_binding_id=#{replay_sources.operational_binding_id}"

    {:ok, reopened_action_event_view, _html} = live(conn, action_event_copied_path)

    assert has_element?(
             reopened_action_event_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="operational_event"][data-data-link-target-id="#{action_event_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    assert has_element?(
             reopened_action_event_view,
             ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=operational_event"][data-clipboard-text*="selected_id=#{action_event_route_id}"][data-clipboard-text*="selected_time=#{action_event_at_ms}"][data-clipboard-text*="replay_run_id=#{replay_run_id}"])
           )

    assert has_element?(
             reopened_action_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Managed action request"]),
             "managed-action-request-1"
           )

    assert has_element?(
             reopened_action_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Action kind"]),
             "schedule_timer"
           )

    assert has_element?(
             reopened_action_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Request document"]),
             "timer_key"
           )

    assert has_element?(
             reopened_action_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Capability instance"]),
             "managed-capability-alpha"
           )

    assert has_element?(
             reopened_action_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Family"]),
             "packet_counter"
           )

    assert has_element?(
             reopened_action_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Binding set"]),
             "managed-binding-set-alpha"
           )

    assert has_element?(
             reopened_action_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Binding set version"]),
             "1"
           )

    assert has_element?(
             reopened_action_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Activation"]),
             "managed-activation-alpha"
           )

    assert has_element?(
             reopened_action_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Partition affinity"]),
             "spacecraft"
           )

    assert has_element?(
             reopened_action_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Partition value"]),
             "spacecraft-alpha"
           )

    assert has_element?(
             reopened_action_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Packet"]),
             "managed-packet-alpha"
           )

    assert has_element?(
             reopened_action_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Evidence"]),
             "managed-evidence-alpha"
           )

    assert has_element?(
             reopened_action_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Requested"])
           )

    assert has_element?(
             reopened_action_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Replay run"]),
             replay_run_id
           )

    assert_data_link_field(action_evidence_view, "Managed action request")
    assert_data_link_field(action_evidence_view, "Action kind")
    assert_data_link_field(action_evidence_view, "Replay run")

    stop_dashboard_view(action_evidence_view)
  end

  test "opens replay managed runtime action and timer evidence from rendered operational observable frame panel" do
    replay_run_id = "replay_run_managed_runtime_ops"
    action_at = ~U[2026-06-17 12:01:30Z]
    timer_at = ~U[2026-06-17 12:02:30Z]

    enable_dashboard_engine_inline_resolves!()

    {conn, org, mission} = signed_in_org_and_mission()
    _telemetry_replay_source = persist_dashboard_realm!(mission, :replay)
    replay_sources = persist_replay_event_and_operational_sources!(mission)
    persist_replay_run!(mission, replay_run_id)

    {action_event, timer_event} =
      persist_replay_managed_runtime_events!(
        org,
        mission,
        replay_run_id,
        action_at,
        timer_at
      )

    assert Map.get(action_event.payload, "request_document") == %{
             "delay_ms" => 1_000,
             "timer_key" => "flush"
           }

    dashboard =
      TestFixtures.persist_dashboard_document!(mission,
        name: "Replay Managed Runtime Evidence",
        widgets: [
          %{
            type: :state_timeline,
            title: "Replay Managed Runtime",
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

    timeline_widget = render_item_by_title(document, "Replay Managed Runtime").widget
    timeline_widget_id = timeline_widget.widget_id

    {:ok, view, _html} =
      live(
        conn,
        show_path(mission, dashboard) <>
          "?time_mode=replay_run&replay_run_id=#{replay_run_id}&scope_kind=mission&scope_id=#{mission.mission_id}"
      )

    render_dashboard_async(view)

    root_selector =
      ~s(#ops-dashboard-show-page[data-dashboard-time-mode="replay_run"][data-engine-time-mode="replay_run"][data-engine-replay-run-id="#{replay_run_id}"])

    assert has_element?(view, root_selector)

    action_row_id =
      "state:runtime.managed_activity:#{DateTime.to_unix(action_at, :millisecond)}:0"

    action_row_selector =
      ~s(#widget-#{timeline_widget_id} [data-state-timeline-row="#{action_row_id}"])

    assert has_element?(
             view,
             action_row_selector <>
               ~s([data-state-timeline-observable="runtime.managed_activity"][data-state-timeline-state="Managed action requested"][data-state-timeline-realm="replay"][data-state-timeline-data-source-id="#{replay_sources.operational_data_source_id}"][data-state-timeline-source-binding-id="#{replay_sources.operational_binding_id}"][data-state-timeline-replay-run-id="#{replay_run_id}"][data-state-timeline-dataset="operational_observables_replay"])
           )

    timer_row_id =
      "state:runtime.managed_activity:#{DateTime.to_unix(timer_at, :millisecond)}:1"

    timer_row_selector =
      ~s(#widget-#{timeline_widget_id} [data-state-timeline-row="#{timer_row_id}"])

    assert has_element?(
             view,
             timer_row_selector <>
               ~s([data-state-timeline-observable="runtime.managed_activity"][data-state-timeline-state="Managed timer fired"][data-state-timeline-realm="replay"][data-state-timeline-data-source-id="#{replay_sources.operational_data_source_id}"][data-state-timeline-source-binding-id="#{replay_sources.operational_binding_id}"][data-state-timeline-replay-run-id="#{replay_run_id}"][data-state-timeline-dataset="operational_observables_replay"])
           )

    assert has_element?(
             view,
             action_row_selector <>
               ~s( [data-state-timeline-row-evidence="#{action_row_id}"][data-state-timeline-row-evidence-observable="runtime.managed_activity"][phx-value-replay-run-id="#{replay_run_id}"][phx-value-source-binding-id="#{replay_sources.operational_binding_id}"][phx-value-data-source-id="#{replay_sources.operational_data_source_id}"])
           )

    view
    |> element(action_row_selector <> ~s( [data-state-timeline-row-evidence]))
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

    assert has_element?(
             view,
             ~s(#dashboard-evidence-inspector [data-evidence-ref-kind="operational event"][data-evidence-ref-id="#{action_event.event_id}"])
           )

    assert has_element?(
             view,
             ~s(#dashboard-evidence-inspector [data-evidence-ref-kind="operational event"][data-evidence-ref-id="#{timer_event.event_id}"])
           )

    assert has_element?(
             view,
             ~s(#dashboard-evidence-copy-link[data-clipboard-text*="panel=evidence"][data-clipboard-text*="selected_evidence_kind=frame"][data-clipboard-text*="selected_observable=#{URI.encode_www_form("runtime.managed_activity")}"][data-clipboard-text*="selected_data_source=#{replay_sources.operational_data_source_id}"][data-clipboard-text*="selected_source_binding=#{replay_sources.operational_binding_id}"][data-clipboard-text*="replay_run_id=#{replay_run_id}"])
           )

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
      "realm" => "replay",
      "time-mode" => "replay_run",
      "replay-run-id" => replay_run_id,
      "data-source-id" => replay_sources.operational_data_source_id,
      "source-binding-id" => replay_sources.operational_binding_id
    })

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="operational_event"][data-data-link-target-id="#{timer_event_id}"])
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="operational_event"][data-data-link-target-id="#{timer_event_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    timer_event_path = assert_patch(view)
    assert timer_event_path =~ "panel=data_link"
    assert timer_event_path =~ "selected_target=operational_event"
    assert timer_event_path =~ "selected_id=#{timer_event_route_id}"
    assert timer_event_path =~ "selected_time=#{timer_event_at_ms}"
    assert timer_event_path =~ "replay_run_id=#{replay_run_id}"

    assert has_element?(
             view,
             ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=operational_event"][data-clipboard-text*="selected_id=#{timer_event_route_id}"][data-clipboard-text*="replay_run_id=#{replay_run_id}"][data-clipboard-text*="data_source_id=#{replay_sources.operational_data_source_id}"][data-clipboard-text*="source_binding_id=#{replay_sources.operational_binding_id}"])
           )

    timer_event_copied_path =
      view
      |> render()
      |> element_attribute("#dashboard-data-link-copy-link", "data-clipboard-text")

    assert timer_event_copied_path =~ "panel=data_link"
    assert timer_event_copied_path =~ "selected_target=operational_event"
    assert timer_event_copied_path =~ "selected_id=#{timer_event_route_id}"
    assert timer_event_copied_path =~ "selected_time=#{timer_event_at_ms}"
    assert timer_event_copied_path =~ "replay_run_id=#{replay_run_id}"

    assert timer_event_copied_path =~
             "data_source_id=#{replay_sources.operational_data_source_id}"

    assert timer_event_copied_path =~
             "source_binding_id=#{replay_sources.operational_binding_id}"

    {:ok, reopened_timer_event_view, _html} = live(conn, timer_event_copied_path)

    assert has_element?(
             reopened_timer_event_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="operational_event"][data-data-link-target-id="#{timer_event_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    assert has_element?(
             reopened_timer_event_view,
             ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=operational_event"][data-clipboard-text*="selected_id=#{timer_event_route_id}"][data-clipboard-text*="selected_time=#{timer_event_at_ms}"][data-clipboard-text*="replay_run_id=#{replay_run_id}"])
           )

    assert_managed_timer_runtime_context!(reopened_timer_event_view, replay_run_id)

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Managed timer event"])
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Timer"])
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Replay run"])
           )

    assert_replay_managed_action_event_route(
      conn,
      evidence_path,
      action_event,
      action_at,
      replay_run_id,
      replay_sources
    )

    stop_dashboard_view(view)
  end

  test "opens live managed runtime action and timer operational-event copied routes from frame evidence" do
    action_at = ~U[2026-06-17 12:01:30Z]
    timer_at = ~U[2026-06-17 12:02:30Z]

    enable_dashboard_engine_inline_resolves!()

    {conn, org, mission} = signed_in_org_and_mission()

    {action_event, timer_event} =
      persist_live_managed_runtime_events!(org, mission, action_at, timer_at)

    {dashboard, timeline_widget_id} =
      persist_live_managed_runtime_dashboard!(org, mission)

    {:ok, view, _html} =
      live(
        conn,
        show_path(mission, dashboard) <>
          "?scope_kind=mission&scope_id=#{mission.mission_id}"
      )

    render_dashboard_async(view)

    root_selector =
      ~s(#ops-dashboard-show-page[data-dashboard-time-mode="live"][data-engine-time-mode="live"])

    assert has_element?(view, root_selector)

    action_row_id =
      "state:runtime.managed_activity:#{DateTime.to_unix(action_at, :millisecond)}:0"

    action_row_selector =
      ~s(#widget-#{timeline_widget_id} [data-state-timeline-row="#{action_row_id}"])

    assert has_element?(
             view,
             action_row_selector <>
               ~s([data-state-timeline-observable="runtime.managed_activity"][data-state-timeline-state="Managed action requested"][data-state-timeline-realm="flight"][data-state-timeline-data-source-id="managed_operational_observables"][data-state-timeline-source-binding-id="default_flight_operational_observables"])
           )

    timer_row_id =
      "state:runtime.managed_activity:#{DateTime.to_unix(timer_at, :millisecond)}:1"

    timer_row_selector =
      ~s(#widget-#{timeline_widget_id} [data-state-timeline-row="#{timer_row_id}"])

    assert has_element?(
             view,
             timer_row_selector <>
               ~s([data-state-timeline-observable="runtime.managed_activity"][data-state-timeline-state="Managed timer fired"][data-state-timeline-realm="flight"][data-state-timeline-data-source-id="managed_operational_observables"][data-state-timeline-source-binding-id="default_flight_operational_observables"])
           )

    assert has_element?(
             view,
             action_row_selector <>
               ~s( [data-state-timeline-row-evidence="#{action_row_id}"][data-state-timeline-row-evidence-observable="runtime.managed_activity"][phx-value-source-binding-id="default_flight_operational_observables"][phx-value-data-source-id="managed_operational_observables"])
           )

    view
    |> element(action_row_selector <> ~s( [data-state-timeline-row-evidence]))
    |> render_click()

    evidence_path = assert_patch(view)
    assert evidence_path =~ "panel=evidence"
    assert evidence_path =~ "selected_evidence_kind=frame"
    assert evidence_path =~ "selected_placement=#{URI.encode_www_form(timeline_widget_id)}"
    assert evidence_path =~ "selected_observable=runtime.managed_activity"
    assert evidence_path =~ "selected_data_source=managed_operational_observables"
    assert evidence_path =~ "selected_source_binding=default_flight_operational_observables"
    assert evidence_path =~ "selected_realm=flight"

    assert has_element?(
             view,
             ~s(#dashboard-evidence-inspector[data-evidence-kind="frame"][data-evidence-status="resolved"])
           )

    assert has_element?(
             view,
             ~s(#dashboard-evidence-inspector [data-evidence-ref-kind="operational event"][data-evidence-ref-id="#{action_event.event_id}"])
           )

    assert has_element?(
             view,
             ~s(#dashboard-evidence-inspector [data-evidence-ref-kind="operational event"][data-evidence-ref-id="#{timer_event.event_id}"])
           )

    assert has_element?(
             view,
             ~s(#dashboard-evidence-copy-link[data-clipboard-text*="panel=evidence"][data-clipboard-text*="selected_evidence_kind=frame"][data-clipboard-text*="selected_observable=#{URI.encode_www_form("runtime.managed_activity")}"][data-clipboard-text*="selected_data_source=managed_operational_observables"][data-clipboard-text*="selected_source_binding=default_flight_operational_observables"])
           )

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

    assert_live_managed_timer_runtime_context!(reopened_timer_event_view)

    {:ok, action_evidence_view, _html} = live(conn, evidence_path)

    action_event_selector =
      ~s(#dashboard-evidence-inspector [data-evidence-ref-kind="operational event"][data-evidence-ref-id="#{action_event.event_id}"])

    action_event_id = action_event.event_id
    action_event_route_id = URI.encode_www_form(action_event_id)
    action_event_at_ms = DateTime.to_unix(action_at, :millisecond)

    action_event_evidence =
      action_evidence_view
      |> render()
      |> LazyHTML.from_fragment()
      |> LazyHTML.query(action_event_selector)

    assert ["operational_event"] =
             LazyHTML.attribute(action_event_evidence, "phx-value-target")

    assert [^action_event_id] =
             LazyHTML.attribute(action_event_evidence, "phx-value-target-id")

    assert ["evidence-ref:operational_event:" <> _] =
             LazyHTML.attribute(action_event_evidence, "phx-value-link-id")

    action_evidence_view
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
             action_evidence_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="operational_event"][data-data-link-target-id="#{action_event_id}"][data-data-link-status="resolved"][data-data-link-selected-data-source-id="managed_operational_observables"][data-data-link-selected-source-binding-id="default_flight_operational_observables"])
           )

    action_event_path = assert_patch(action_evidence_view)
    assert action_event_path =~ "panel=data_link"
    assert action_event_path =~ "selected_target=operational_event"
    assert action_event_path =~ "selected_id=#{action_event_route_id}"
    assert action_event_path =~ "selected_time=#{action_event_at_ms}"
    assert action_event_path =~ "time_mode=live"

    assert has_element?(
             action_evidence_view,
             ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=operational_event"][data-clipboard-text*="selected_id=#{action_event_route_id}"][data-clipboard-text*="data_source_id=managed_operational_observables"][data-clipboard-text*="source_binding_id=default_flight_operational_observables"])
           )

    action_event_copied_path =
      action_evidence_view
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

    assert_data_link_field(
      reopened_action_event_view,
      "Managed action request",
      "managed-action-request-live-1"
    )

    assert_data_link_field(reopened_action_event_view, "Action kind", "schedule_timer")
    assert_data_link_field(reopened_action_event_view, "Request document", "timer_key")

    assert_data_link_field(
      reopened_action_event_view,
      "Capability instance",
      "managed-capability-live-alpha"
    )

    assert_data_link_field(reopened_action_event_view, "Family", "packet_counter")

    assert_data_link_field(
      reopened_action_event_view,
      "Binding set",
      "managed-binding-set-live-alpha"
    )

    assert_data_link_field(reopened_action_event_view, "Binding set version", "1")

    assert_data_link_field(
      reopened_action_event_view,
      "Activation",
      "managed-activation-live-alpha"
    )

    assert_data_link_field(reopened_action_event_view, "Partition affinity", "spacecraft")
    assert_data_link_field(reopened_action_event_view, "Partition value", "spacecraft-alpha")
    assert_data_link_field(reopened_action_event_view, "Packet", "managed-packet-live-alpha")
    assert_data_link_field(reopened_action_event_view, "Evidence", "managed-evidence-live-alpha")
    assert_data_link_field(reopened_action_event_view, "Requested")

    stop_dashboard_view(action_evidence_view)
    stop_dashboard_view(reopened_action_event_view)
    stop_dashboard_view(reopened_timer_event_view)
    stop_dashboard_view(view)
  end

  test "opens live managed capability-record operational-event copied route from frame evidence" do
    initialized_at = ~U[2026-06-17 12:00:30Z]
    record_at = ~U[2026-06-17 12:01:30Z]
    timer_at = ~U[2026-06-17 12:02:30Z]

    enable_dashboard_engine_inline_resolves!()

    {conn, org, mission} = signed_in_org_and_mission()

    capability_events =
      persist_live_managed_capability_record_events!(
        org,
        mission,
        initialized_at,
        record_at,
        timer_at
      )

    record_event =
      Enum.find(capability_events, &(&1.kind == :managed_capability_record_handled))

    assert Map.get(record_event.payload, "record_metadata") == %{
             "action_request_ids" => ["managed-action-request-live-2"],
             "emitted_record_refs" => ["limit-state-live-1", "derived-metric-live-1"]
           }

    dashboard =
      TestFixtures.persist_dashboard_document!(mission,
        name: "Live Managed Capability Evidence",
        widgets: [
          %{
            type: :state_timeline,
            title: "Live Managed Capability",
            binding: %{
              source: :operational_observables,
              observables: ["runtime.managed_activity"]
            }
          }
        ]
      )

    document = fetch_dashboard_document!(org, mission, dashboard)
    timeline_widget = render_item_by_title(document, "Live Managed Capability").widget
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
               ~s([data-state-timeline-observable="runtime.managed_activity"][data-state-timeline-state="Managed capability initialized"][data-state-timeline-realm="flight"][data-state-timeline-data-source-id="managed_operational_observables"][data-state-timeline-source-binding-id="default_flight_operational_observables"])
           )

    assert has_element?(
             view,
             record_row_selector <>
               ~s([data-state-timeline-observable="runtime.managed_activity"][data-state-timeline-state="Managed capability record handled"][data-state-timeline-realm="flight"])
           )

    assert has_element?(
             view,
             timer_row_selector <>
               ~s([data-state-timeline-observable="runtime.managed_activity"][data-state-timeline-state="Managed capability timer handled"][data-state-timeline-realm="flight"])
           )

    assert has_element?(
             view,
             timer_row_selector <>
               ~s( [data-state-timeline-row-evidence="#{timer_row_id}"][data-state-timeline-row-evidence-observable="runtime.managed_activity"][phx-value-source-binding-id="default_flight_operational_observables"][phx-value-data-source-id="managed_operational_observables"])
           )

    view
    |> element(timer_row_selector <> ~s( [data-state-timeline-row-evidence]))
    |> render_click()

    evidence_path = assert_patch(view)
    assert evidence_path =~ "panel=evidence"
    assert evidence_path =~ "selected_evidence_kind=frame"
    assert evidence_path =~ "selected_placement=#{URI.encode_www_form(timeline_widget_id)}"
    assert evidence_path =~ "selected_observable=runtime.managed_activity"
    assert evidence_path =~ "selected_data_source=managed_operational_observables"
    assert evidence_path =~ "selected_source_binding=default_flight_operational_observables"
    assert evidence_path =~ "selected_realm=flight"

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
             ~s(#dashboard-evidence-copy-link[data-clipboard-text*="panel=evidence"][data-clipboard-text*="selected_evidence_kind=frame"][data-clipboard-text*="selected_observable=#{URI.encode_www_form("runtime.managed_activity")}"][data-clipboard-text*="selected_data_source=managed_operational_observables"][data-clipboard-text*="selected_source_binding=default_flight_operational_observables"])
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

    assert_data_link_field(
      reopened_record_event_view,
      "Managed capability record",
      "managed-capability-record-live-handled-1"
    )

    assert_data_link_field(reopened_record_event_view, "Event kind", "record_handled")

    assert_data_link_field(
      reopened_record_event_view,
      "Capability instance",
      "managed-capability-live-alpha"
    )

    assert_data_link_field(reopened_record_event_view, "Family", "packet_counter")

    assert_data_link_field(
      reopened_record_event_view,
      "Binding set",
      "managed-binding-set-live-alpha"
    )

    assert_data_link_field(reopened_record_event_view, "Binding set version", "1")

    assert_data_link_field(
      reopened_record_event_view,
      "Activation",
      "managed-activation-live-alpha"
    )

    assert_data_link_field(reopened_record_event_view, "Partition affinity", "spacecraft")
    assert_data_link_field(reopened_record_event_view, "Partition value", "spacecraft-alpha")
    assert_data_link_field(reopened_record_event_view, "Packet", "managed-packet-live-alpha")
    assert_data_link_field(reopened_record_event_view, "Evidence", "managed-evidence-live-alpha")
    assert_data_link_field(reopened_record_event_view, "Emitted record kinds", "derived_metric")
    assert_data_link_field(reopened_record_event_view, "Emitted record count", "2")
    assert_data_link_field(reopened_record_event_view, "Action request count", "1")
    assert_data_link_field(reopened_record_event_view, "State snapshot", "heartbeat_count")

    assert_data_link_field(
      reopened_record_event_view,
      "Record metadata",
      "managed-action-request-live-2"
    )

    assert_data_link_field(reopened_record_event_view, "Record metadata", "limit-state-live-1")
    assert_data_link_field(reopened_record_event_view, "Record metadata", "derived-metric-live-1")
    assert_data_link_field(reopened_record_event_view, "Recorded")
    assert_data_link_field(view, "Managed capability record")
    assert_data_link_field(view, "Event kind")

    stop_dashboard_view(reopened_record_event_view)
    stop_dashboard_view(view)
  end
end
