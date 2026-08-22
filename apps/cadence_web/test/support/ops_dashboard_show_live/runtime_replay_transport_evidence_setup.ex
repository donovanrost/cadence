defmodule CadenceWeb.OpsDashboardShowLive.RuntimeReplayTransportEvidenceSetup do
  @moduledoc false

  @endpoint CadenceWeb.Endpoint

  import ExUnit.Assertions
  import Phoenix.ConnTest
  import Phoenix.LiveViewTest
  use CadenceWeb.OpsDashboardShowLive.ViewTestSupport
  import CadenceWeb.OpsDashboardShowLive.RuntimeReplayEvidenceFixtures
  import CadenceWeb.OpsDashboardShowLive.RuntimeReplaySourceFamilyFixtures

  alias Cadence.Dashboards.Document
  alias CadenceWeb.TestFixtures

  def run do
    replay_run_id = "replay_run_transport_runtime_activity_ops"
    record_at = ~U[2026-06-17 12:01:00Z]
    action_at = ~U[2026-06-17 12:01:30Z]
    timer_at = ~U[2026-06-17 12:02:00Z]

    {conn, org, mission} = signed_in_org_and_mission()
    telemetry_replay_source = persist_dashboard_realm!(mission, :replay)
    replay_sources = persist_replay_event_and_operational_sources!(mission)
    persist_replay_run!(mission, replay_run_id)

    telemetry_sample =
      persist_replay_command_verifier_telemetry_sample!(
        org,
        mission,
        replay_run_id,
        telemetry_replay_source,
        DateTime.add(action_at, 10, :second)
      )

    release_attempt = persist_transport_command_release_attempt!(org, mission, action_at)

    verifier_instance =
      persist_transport_command_verifier_instance!(org, mission, release_attempt, action_at)

    failed_verifier_instance =
      persist_transport_command_verifier_instance!(
        org,
        mission,
        release_attempt,
        DateTime.add(action_at, 5, :second),
        command_verifier_instance_id: "verifier-instance-failed",
        verifier_name: "Transport action rejected",
        lifecycle_state: :failed,
        failure_reason: "failure_criteria_matched"
      )

    telemetry_verifier_instance =
      persist_transport_command_verifier_instance!(
        org,
        mission,
        release_attempt,
        DateTime.add(action_at, 10, :second),
        command_verifier_instance_id: "verifier-instance-telemetry-satisfied",
        verifier_id: "telemetry-verifier-1",
        verifier_name: "Telemetry release confirmation",
        matched_record_kind: :telemetry_sample,
        matched_record_id: telemetry_sample.sample_id
      )

    capability_verifier_instance =
      persist_transport_command_verifier_instance!(
        org,
        mission,
        release_attempt,
        DateTime.add(action_at, 15, :second),
        command_verifier_instance_id: "verifier-instance-capability-satisfied",
        verifier_id: "capability-verifier-1",
        verifier_name: "Transport capability confirmation",
        matched_record_kind: :transport_capability_record,
        matched_record_id: "transport-runtime-record-1"
      )

    timed_out_verifier_instance =
      persist_transport_command_verifier_instance!(
        org,
        mission,
        release_attempt,
        DateTime.add(action_at, 60, :second),
        command_verifier_instance_id: "verifier-instance-timed-out",
        verifier_name: "Transport completion timed out",
        lifecycle_state: :timed_out,
        matched_record_kind: nil,
        matched_record_id: nil,
        failure_reason: "timed_out"
      )

    transport_events =
      persist_replay_transport_runtime_events!(
        org,
        mission,
        replay_run_id,
        record_at,
        action_at,
        timer_at
      )

    action_event =
      Enum.find(transport_events, &(&1.kind == :transport_action_requested))

    record_event =
      Enum.find(transport_events, &(&1.kind == :transport_control_input_handled))

    assert Map.get(action_event.payload, "request_document") == %{
             "command_request_id" => "command-request-1",
             "frame_count" => 1
           }

    assert Map.get(record_event.payload, "record_metadata") == %{
             "action_request_ids" => ["transport-action-request-1"],
             "emitted_record_refs" => ["uplink-frame-1"]
           }

    assert {:ok, fetched_release_attempt} =
             Cadence.Commanding.fetch_command_release_attempt(
               org.organization_id,
               mission.mission_id,
               release_attempt.command_release_attempt_id
             )

    assert fetched_release_attempt.command_release_attempt_id ==
             release_attempt.command_release_attempt_id

    assert fetched_release_attempt.command_request_id == "command-request-1"
    assert fetched_release_attempt.verification_state == :failed

    assert {:ok, fetched_command_request} =
             Cadence.Commanding.fetch_command_request(
               org.organization_id,
               mission.mission_id,
               release_attempt.command_request_id
             )

    assert fetched_command_request.verification_state == :failed

    assert {:ok, fetched_verifier_instance} =
             Cadence.Commanding.fetch_command_verifier_instance(
               org.organization_id,
               mission.mission_id,
               verifier_instance.command_verifier_instance_id
             )

    assert fetched_verifier_instance.lifecycle_state == :satisfied
    assert fetched_verifier_instance.matched_record_id == "transport-action-request-1"

    assert {:ok, fetched_telemetry_verifier_instance} =
             Cadence.Commanding.fetch_command_verifier_instance(
               org.organization_id,
               mission.mission_id,
               telemetry_verifier_instance.command_verifier_instance_id
             )

    assert fetched_telemetry_verifier_instance.lifecycle_state == :satisfied
    assert fetched_telemetry_verifier_instance.matched_record_kind == :telemetry_sample
    assert fetched_telemetry_verifier_instance.matched_record_id == telemetry_sample.sample_id

    assert {:ok, fetched_capability_verifier_instance} =
             Cadence.Commanding.fetch_command_verifier_instance(
               org.organization_id,
               mission.mission_id,
               capability_verifier_instance.command_verifier_instance_id
             )

    assert fetched_capability_verifier_instance.lifecycle_state == :satisfied

    assert fetched_capability_verifier_instance.matched_record_kind ==
             :transport_capability_record

    assert fetched_capability_verifier_instance.matched_record_id == "transport-runtime-record-1"

    assert {:ok, fetched_failed_verifier_instance} =
             Cadence.Commanding.fetch_command_verifier_instance(
               org.organization_id,
               mission.mission_id,
               failed_verifier_instance.command_verifier_instance_id
             )

    assert fetched_failed_verifier_instance.lifecycle_state == :failed
    assert fetched_failed_verifier_instance.failure_reason == "failure_criteria_matched"

    assert {:ok, fetched_timed_out_verifier_instance} =
             Cadence.Commanding.fetch_command_verifier_instance(
               org.organization_id,
               mission.mission_id,
               timed_out_verifier_instance.command_verifier_instance_id
             )

    assert fetched_timed_out_verifier_instance.lifecycle_state == :timed_out
    assert fetched_timed_out_verifier_instance.failure_reason == "timed_out"

    dashboard =
      TestFixtures.persist_dashboard_document!(mission,
        name: "Replay Transport Runtime Evidence",
        widgets: [
          %{
            type: :state_timeline,
            title: "Replay Transport Runtime",
            binding: %{
              source: :operational_observables,
              observables: ["runtime.transport_activity"]
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

    timeline_widget = render_item_by_title(document, "Replay Transport Runtime").widget
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
               ~s([data-state-timeline-observable="runtime.transport_activity"][data-state-timeline-state="Transport control input handled"][data-state-timeline-realm="replay"][data-state-timeline-data-source-id="#{replay_sources.operational_data_source_id}"][data-state-timeline-source-binding-id="#{replay_sources.operational_binding_id}"][data-state-timeline-replay-run-id="#{replay_run_id}"][data-state-timeline-dataset="operational_observables_replay"])
           )

    assert has_element?(
             view,
             action_row_selector <>
               ~s([data-state-timeline-observable="runtime.transport_activity"][data-state-timeline-state="Transport action requested"][data-state-timeline-realm="replay"])
           )

    assert has_element?(
             view,
             timer_row_selector <>
               ~s([data-state-timeline-observable="runtime.transport_activity"][data-state-timeline-state="Transport timer fired"][data-state-timeline-realm="replay"])
           )

    assert has_element?(
             view,
             action_row_selector <>
               ~s( [data-state-timeline-row-evidence="#{action_row_id}"][data-state-timeline-row-evidence-observable="runtime.transport_activity"][phx-value-replay-run-id="#{replay_run_id}"][phx-value-source-binding-id="#{replay_sources.operational_binding_id}"][phx-value-data-source-id="#{replay_sources.operational_data_source_id}"])
           )

    view
    |> element(action_row_selector <> ~s( [data-state-timeline-row-evidence]))
    |> render_click()

    evidence_path = assert_patch(view)
    assert evidence_path =~ "panel=evidence"
    assert evidence_path =~ "selected_evidence_kind=frame"
    assert evidence_path =~ "selected_placement=#{URI.encode_www_form(timeline_widget_id)}"
    assert evidence_path =~ "selected_observable=runtime.transport_activity"
    assert evidence_path =~ "selected_data_source=#{replay_sources.operational_data_source_id}"
    assert evidence_path =~ "selected_source_binding=#{replay_sources.operational_binding_id}"
    assert evidence_path =~ "replay_run_id=#{replay_run_id}"
    assert evidence_path =~ "time_mode=replay_run"

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
             ~s(#dashboard-evidence-inspector [data-evidence-ref-kind="command release attempt"][data-evidence-ref-id="#{release_attempt.command_release_attempt_id}"][data-evidence-ref-link-target="command_release_attempt"])
           )

    assert has_element?(
             view,
             ~s(#dashboard-evidence-inspector [data-evidence-ref-kind="transport action request"][data-evidence-ref-id="transport-action-request-1"][data-evidence-ref-link-target="transport_action_request"])
           )

    assert has_element?(
             view,
             ~s(#dashboard-evidence-inspector [data-evidence-ref-kind="telemetry sample"][data-evidence-ref-id="#{telemetry_sample.sample_id}"][data-evidence-ref-link-target="telemetry_sample"])
           )

    assert has_element?(
             view,
             ~s(#dashboard-evidence-inspector [data-evidence-ref-kind="transport capability record"][data-evidence-ref-id="transport-runtime-record-1"][data-evidence-ref-link-target="transport_capability_record"])
           )

    assert has_element?(
             view,
             ~s(#dashboard-evidence-inspector [data-evidence-ref-kind="command verifier instance"][data-evidence-ref-id="#{verifier_instance.command_verifier_instance_id}"])
           )

    assert has_element?(
             view,
             ~s(#dashboard-evidence-inspector [data-evidence-ref-kind="command verifier instance"][data-evidence-ref-id="#{telemetry_verifier_instance.command_verifier_instance_id}"])
           )

    assert has_element?(
             view,
             ~s(#dashboard-evidence-inspector [data-evidence-ref-kind="command verifier instance"][data-evidence-ref-id="#{capability_verifier_instance.command_verifier_instance_id}"])
           )

    assert has_element?(
             view,
             ~s(#dashboard-evidence-inspector [data-evidence-ref-kind="command verifier instance"][data-evidence-ref-id="#{failed_verifier_instance.command_verifier_instance_id}"][data-evidence-ref-link-target="command_verifier_instance"])
           )

    assert has_element?(
             view,
             ~s(#dashboard-evidence-inspector [data-evidence-ref-kind="command verifier instance"][data-evidence-ref-id="#{timed_out_verifier_instance.command_verifier_instance_id}"])
           )

    assert has_element?(
             view,
             ~s(#dashboard-evidence-copy-link[data-clipboard-text*="panel=evidence"][data-clipboard-text*="selected_evidence_kind=frame"][data-clipboard-text*="selected_observable=#{URI.encode_www_form("runtime.transport_activity")}"][data-clipboard-text*="selected_data_source=#{replay_sources.operational_data_source_id}"][data-clipboard-text*="selected_source_binding=#{replay_sources.operational_binding_id}"][data-clipboard-text*="replay_run_id=#{replay_run_id}"])
           )

    %{
      action_at: action_at,
      action_event: action_event,
      action_row_selector: action_row_selector,
      capability_verifier_instance: capability_verifier_instance,
      conn: conn,
      failed_verifier_instance: failed_verifier_instance,
      record_at: record_at,
      record_event: record_event,
      release_attempt: release_attempt,
      replay_run_id: replay_run_id,
      replay_sources: replay_sources,
      telemetry_sample: telemetry_sample,
      telemetry_verifier_instance: telemetry_verifier_instance,
      timer_at: timer_at,
      transport_events: transport_events,
      verifier_instance: verifier_instance,
      view: view
    }
  end
end
