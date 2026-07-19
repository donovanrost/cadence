defmodule CadenceWeb.OpsDashboardShowLive.RuntimeReplayTransportEvidenceScenario do
  @endpoint CadenceWeb.Endpoint

  import ExUnit.Assertions
  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  import CadenceWeb.OpsDashboardShowLive.RuntimeReplayEvidenceFixtures
  import CadenceWeb.OpsDashboardShowLive.RuntimeReplaySourceFamilyFixtures

  alias Cadence.Dashboards.Document
  alias CadenceWeb.TestFixtures

  def run do
    replay_run_id = "replay_run_transport_runtime_activity_ops"
    record_at = ~U[2026-06-17 12:01:00Z]
    action_at = ~U[2026-06-17 12:01:30Z]
    timer_at = ~U[2026-06-17 12:02:00Z]

    enable_dashboard_engine_inline_resolves!()

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
             Cadence.fetch_command_release_attempt(
               org.organization_id,
               mission.mission_id,
               release_attempt.command_release_attempt_id
             )

    assert fetched_release_attempt.command_release_attempt_id ==
             release_attempt.command_release_attempt_id

    assert fetched_release_attempt.command_request_id == "command-request-1"
    assert fetched_release_attempt.verification_state == :failed

    assert {:ok, fetched_command_request} =
             Cadence.fetch_command_request(
               org.organization_id,
               mission.mission_id,
               release_attempt.command_request_id
             )

    assert fetched_command_request.verification_state == :failed

    assert {:ok, fetched_verifier_instance} =
             Cadence.fetch_command_verifier_instance(
               org.organization_id,
               mission.mission_id,
               verifier_instance.command_verifier_instance_id
             )

    assert fetched_verifier_instance.lifecycle_state == :satisfied
    assert fetched_verifier_instance.matched_record_id == "transport-action-request-1"

    assert {:ok, fetched_telemetry_verifier_instance} =
             Cadence.fetch_command_verifier_instance(
               org.organization_id,
               mission.mission_id,
               telemetry_verifier_instance.command_verifier_instance_id
             )

    assert fetched_telemetry_verifier_instance.lifecycle_state == :satisfied
    assert fetched_telemetry_verifier_instance.matched_record_kind == :telemetry_sample
    assert fetched_telemetry_verifier_instance.matched_record_id == telemetry_sample.sample_id

    assert {:ok, fetched_capability_verifier_instance} =
             Cadence.fetch_command_verifier_instance(
               org.organization_id,
               mission.mission_id,
               capability_verifier_instance.command_verifier_instance_id
             )

    assert fetched_capability_verifier_instance.lifecycle_state == :satisfied

    assert fetched_capability_verifier_instance.matched_record_kind ==
             :transport_capability_record

    assert fetched_capability_verifier_instance.matched_record_id == "transport-runtime-record-1"

    assert {:ok, fetched_failed_verifier_instance} =
             Cadence.fetch_command_verifier_instance(
               org.organization_id,
               mission.mission_id,
               failed_verifier_instance.command_verifier_instance_id
             )

    assert fetched_failed_verifier_instance.lifecycle_state == :failed
    assert fetched_failed_verifier_instance.failure_reason == "failure_criteria_matched"

    assert {:ok, fetched_timed_out_verifier_instance} =
             Cadence.fetch_command_verifier_instance(
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

    release_attempt_evidence_selector =
      ~s(#dashboard-evidence-inspector [data-evidence-ref-kind="command release attempt"][data-evidence-ref-id="#{release_attempt.command_release_attempt_id}"])

    release_attempt_id = release_attempt.command_release_attempt_id
    release_attempt_at_ms = DateTime.to_unix(release_attempt.attempted_at, :millisecond)

    release_attempt_evidence =
      view
      |> render()
      |> LazyHTML.from_fragment()
      |> LazyHTML.query(release_attempt_evidence_selector)

    assert ["command_release_attempt"] =
             LazyHTML.attribute(release_attempt_evidence, "phx-value-target")

    assert [^release_attempt_id] =
             LazyHTML.attribute(release_attempt_evidence, "phx-value-target-id")

    assert [release_attempt_at_ms_text] =
             LazyHTML.attribute(release_attempt_evidence, "phx-value-timestamp-ms")

    assert release_attempt_at_ms_text == Integer.to_string(release_attempt_at_ms)

    assert ["evidence-ref:command_release_attempt:" <> _] =
             LazyHTML.attribute(release_attempt_evidence, "phx-value-link-id")

    view
    |> element(release_attempt_evidence_selector)
    |> render_click(%{
      "link-id" => "evidence-ref:command_release_attempt:#{release_attempt_id}",
      "target" => "command_release_attempt",
      "target-id" => release_attempt_id,
      "timestamp-ms" => release_attempt_at_ms,
      "realm" => "replay",
      "time-mode" => "replay_run",
      "replay-run-id" => replay_run_id,
      "data-source-id" => replay_sources.operational_data_source_id,
      "source-binding-id" => replay_sources.operational_binding_id
    })

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="command_release_attempt"][data-data-link-target-id="#{release_attempt_id}"])
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="command_release_attempt"][data-data-link-target-id="#{release_attempt_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    release_attempt_path = assert_patch(view)
    assert release_attempt_path =~ "panel=data_link"
    assert release_attempt_path =~ "selected_target=command_release_attempt"
    assert release_attempt_path =~ "selected_id=#{release_attempt_id}"
    assert release_attempt_path =~ "selected_time=#{release_attempt_at_ms}"
    assert release_attempt_path =~ "replay_run_id=#{replay_run_id}"

    assert has_element?(
             view,
             ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=command_release_attempt"][data-clipboard-text*="selected_id=#{release_attempt_id}"][data-clipboard-text*="replay_run_id=#{replay_run_id}"][data-clipboard-text*="data_source_id=#{replay_sources.operational_data_source_id}"][data-clipboard-text*="source_binding_id=#{replay_sources.operational_binding_id}"])
           )

    release_attempt_copied_path =
      view
      |> render()
      |> element_attribute("#dashboard-data-link-copy-link", "data-clipboard-text")

    assert release_attempt_copied_path =~ "panel=data_link"
    assert release_attempt_copied_path =~ "selected_target=command_release_attempt"
    assert release_attempt_copied_path =~ "selected_id=#{release_attempt_id}"
    assert release_attempt_copied_path =~ "selected_time=#{release_attempt_at_ms}"
    assert release_attempt_copied_path =~ "replay_run_id=#{replay_run_id}"

    assert release_attempt_copied_path =~
             "data_source_id=#{replay_sources.operational_data_source_id}"

    assert release_attempt_copied_path =~
             "source_binding_id=#{replay_sources.operational_binding_id}"

    {:ok, reopened_release_attempt_view, _html} = live(conn, release_attempt_copied_path)

    assert has_element?(
             reopened_release_attempt_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="command_release_attempt"][data-data-link-target-id="#{release_attempt_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    assert has_element?(
             reopened_release_attempt_view,
             ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=command_release_attempt"][data-clipboard-text*="selected_id=#{release_attempt_id}"][data-clipboard-text*="selected_time=#{release_attempt_at_ms}"][data-clipboard-text*="replay_run_id=#{replay_run_id}"])
           )

    assert has_element?(
             reopened_release_attempt_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Command release attempt"]),
             release_attempt_id
           )

    assert has_element?(
             reopened_release_attempt_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Verification state"]),
             "failed"
           )

    assert has_element?(
             reopened_release_attempt_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Command request"]),
             release_attempt.command_request_id
           )

    assert has_element?(
             reopened_release_attempt_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Signal phase"]),
             "start"
           )

    release_attempt_command_request_related_selector =
      ~s(#dashboard-data-link-inspector [data-data-link-related-target="command request"][data-data-link-related-id="#{release_attempt.command_request_id}"])

    release_attempt_command_queue_related_selector =
      ~s(#dashboard-data-link-inspector [data-data-link-related-target="command queue entry"][data-data-link-related-id="#{release_attempt.command_queue_entry_id}"])

    assert has_element?(
             reopened_release_attempt_view,
             release_attempt_command_request_related_selector
           )

    assert has_element?(
             reopened_release_attempt_view,
             release_attempt_command_queue_related_selector
           )

    reopened_release_attempt_view
    |> element(release_attempt_command_request_related_selector)
    |> render_click()

    release_attempt_command_request_path = assert_patch(reopened_release_attempt_view)
    command_request_route_id = URI.encode_www_form(release_attempt.command_request_id)
    assert release_attempt_command_request_path =~ "panel=data_link"
    assert release_attempt_command_request_path =~ "selected_target=command_request"
    assert release_attempt_command_request_path =~ "selected_id=#{command_request_route_id}"
    assert release_attempt_command_request_path =~ "nav_from_target=command_release_attempt"
    assert release_attempt_command_request_path =~ "nav_from_target_id=#{release_attempt_id}"
    assert release_attempt_command_request_path =~ "nav_trail="
    assert release_attempt_command_request_path =~ "replay_run_id=#{replay_run_id}"

    assert release_attempt_command_request_path =~
             "data_source_id=#{replay_sources.operational_data_source_id}"

    assert release_attempt_command_request_path =~
             "source_binding_id=#{replay_sources.operational_binding_id}"

    assert has_element?(
             reopened_release_attempt_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="command_request"][data-data-link-target-id="#{release_attempt.command_request_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    assert has_element?(
             reopened_release_attempt_view,
             ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=command_request"][data-clipboard-text*="selected_id=#{command_request_route_id}"][data-clipboard-text*="nav_from_target=command_release_attempt"][data-clipboard-text*="nav_from_target_id=#{release_attempt_id}"][data-clipboard-text*="replay_run_id=#{replay_run_id}"])
           )

    release_attempt_command_request_copied_path =
      reopened_release_attempt_view
      |> render()
      |> element_attribute("#dashboard-data-link-copy-link", "data-clipboard-text")

    assert release_attempt_command_request_copied_path =~ "panel=data_link"
    assert release_attempt_command_request_copied_path =~ "selected_target=command_request"

    assert release_attempt_command_request_copied_path =~
             "selected_id=#{command_request_route_id}"

    assert release_attempt_command_request_copied_path =~
             "nav_from_target=command_release_attempt"

    assert release_attempt_command_request_copied_path =~
             "nav_from_target_id=#{release_attempt_id}"

    assert release_attempt_command_request_copied_path =~ "replay_run_id=#{replay_run_id}"

    {:ok, reopened_release_attempt_command_request_view, _html} =
      live(conn, release_attempt_command_request_copied_path)

    assert has_element?(
             reopened_release_attempt_command_request_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="command_request"][data-data-link-target-id="#{release_attempt.command_request_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    assert has_element?(
             reopened_release_attempt_command_request_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Command request"]),
             release_attempt.command_request_id
           )

    assert has_element?(
             reopened_release_attempt_command_request_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Command"]),
             release_attempt.command_name
           )

    assert has_element?(
             reopened_release_attempt_command_request_view,
             ~s(#dashboard-data-link-inspector [data-data-link-context="Replay run"]),
             replay_run_id
           )

    stop_dashboard_view(reopened_release_attempt_command_request_view)

    {:ok, reopened_release_attempt_queue_view, _html} = live(conn, release_attempt_copied_path)

    assert has_element?(
             reopened_release_attempt_queue_view,
             release_attempt_command_queue_related_selector
           )

    reopened_release_attempt_queue_view
    |> element(release_attempt_command_queue_related_selector)
    |> render_click()

    release_attempt_command_queue_path = assert_patch(reopened_release_attempt_queue_view)
    command_queue_entry_route_id = URI.encode_www_form(release_attempt.command_queue_entry_id)
    assert release_attempt_command_queue_path =~ "panel=data_link"
    assert release_attempt_command_queue_path =~ "selected_target=command_queue_entry"
    assert release_attempt_command_queue_path =~ "selected_id=#{command_queue_entry_route_id}"
    assert release_attempt_command_queue_path =~ "nav_from_target=command_release_attempt"
    assert release_attempt_command_queue_path =~ "nav_from_target_id=#{release_attempt_id}"
    assert release_attempt_command_queue_path =~ "nav_trail="
    assert release_attempt_command_queue_path =~ "replay_run_id=#{replay_run_id}"

    assert release_attempt_command_queue_path =~
             "data_source_id=#{replay_sources.operational_data_source_id}"

    assert release_attempt_command_queue_path =~
             "source_binding_id=#{replay_sources.operational_binding_id}"

    assert has_element?(
             reopened_release_attempt_queue_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="command_queue_entry"][data-data-link-target-id="#{release_attempt.command_queue_entry_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    assert has_element?(
             reopened_release_attempt_queue_view,
             ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=command_queue_entry"][data-clipboard-text*="selected_id=#{command_queue_entry_route_id}"][data-clipboard-text*="nav_from_target=command_release_attempt"][data-clipboard-text*="nav_from_target_id=#{release_attempt_id}"][data-clipboard-text*="replay_run_id=#{replay_run_id}"])
           )

    release_attempt_command_queue_copied_path =
      reopened_release_attempt_queue_view
      |> render()
      |> element_attribute("#dashboard-data-link-copy-link", "data-clipboard-text")

    assert release_attempt_command_queue_copied_path =~ "panel=data_link"
    assert release_attempt_command_queue_copied_path =~ "selected_target=command_queue_entry"

    assert release_attempt_command_queue_copied_path =~
             "selected_id=#{command_queue_entry_route_id}"

    assert release_attempt_command_queue_copied_path =~
             "nav_from_target=command_release_attempt"

    assert release_attempt_command_queue_copied_path =~
             "nav_from_target_id=#{release_attempt_id}"

    assert release_attempt_command_queue_copied_path =~ "replay_run_id=#{replay_run_id}"

    {:ok, reopened_release_attempt_command_queue_view, _html} =
      live(conn, release_attempt_command_queue_copied_path)

    assert has_element?(
             reopened_release_attempt_command_queue_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="command_queue_entry"][data-data-link-target-id="#{release_attempt.command_queue_entry_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    assert has_element?(
             reopened_release_attempt_command_queue_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Command queue entry"]),
             release_attempt.command_queue_entry_id
           )

    assert has_element?(
             reopened_release_attempt_command_queue_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Command request"]),
             release_attempt.command_request_id
           )

    assert has_element?(
             reopened_release_attempt_command_queue_view,
             ~s(#dashboard-data-link-inspector [data-data-link-context="Replay run"]),
             replay_run_id
           )

    stop_dashboard_view(reopened_release_attempt_command_queue_view)
    stop_dashboard_view(reopened_release_attempt_queue_view)
    stop_dashboard_view(reopened_release_attempt_view)

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Command release attempt"])
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Verification state"])
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Command request"])
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Signal phase"])
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Metadata"])
           )

    failed_verifier_related_selector =
      ~s(#dashboard-data-link-inspector [data-data-link-related-target="command verifier instance"][data-data-link-related-id="#{failed_verifier_instance.command_verifier_instance_id}"])

    assert has_element?(view, failed_verifier_related_selector)

    transport_action_related_selector =
      ~s(#dashboard-data-link-inspector [data-data-link-related-target="transport action request"][data-data-link-related-id="transport-action-request-1"])

    assert has_element?(view, transport_action_related_selector)

    view
    |> element(failed_verifier_related_selector)
    |> render_click()

    failed_related_path = assert_patch(view)
    assert failed_related_path =~ "panel=data_link"
    assert failed_related_path =~ "selected_target=command_verifier_instance"

    assert failed_related_path =~
             "selected_id=#{failed_verifier_instance.command_verifier_instance_id}"

    assert failed_related_path =~ "nav_from_target=command_release_attempt"
    assert failed_related_path =~ "nav_from_target_id=#{release_attempt_id}"
    assert failed_related_path =~ "nav_trail="
    assert failed_related_path =~ "replay_run_id=#{replay_run_id}"
    assert failed_related_path =~ "data_source_id=#{replay_sources.operational_data_source_id}"
    assert failed_related_path =~ "source_binding_id=#{replay_sources.operational_binding_id}"

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="command_verifier_instance"][data-data-link-target-id="#{failed_verifier_instance.command_verifier_instance_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=command_verifier_instance"][data-clipboard-text*="selected_id=#{failed_verifier_instance.command_verifier_instance_id}"][data-clipboard-text*="nav_from_target=command_release_attempt"][data-clipboard-text*="nav_from_target_id=#{release_attempt_id}"][data-clipboard-text*="replay_run_id=#{replay_run_id}"][data-clipboard-text*="data_source_id=#{replay_sources.operational_data_source_id}"][data-clipboard-text*="source_binding_id=#{replay_sources.operational_binding_id}"])
           )

    failed_verifier_copied_path =
      view
      |> render()
      |> element_attribute("#dashboard-data-link-copy-link", "data-clipboard-text")

    assert failed_verifier_copied_path =~ "panel=data_link"
    assert failed_verifier_copied_path =~ "selected_target=command_verifier_instance"

    assert failed_verifier_copied_path =~
             "selected_id=#{failed_verifier_instance.command_verifier_instance_id}"

    assert failed_verifier_copied_path =~ "nav_from_target=command_release_attempt"
    assert failed_verifier_copied_path =~ "nav_from_target_id=#{release_attempt_id}"
    assert failed_verifier_copied_path =~ "replay_run_id=#{replay_run_id}"

    assert failed_verifier_copied_path =~
             "data_source_id=#{replay_sources.operational_data_source_id}"

    assert failed_verifier_copied_path =~
             "source_binding_id=#{replay_sources.operational_binding_id}"

    {:ok, reopened_failed_verifier_view, _html} = live(conn, failed_verifier_copied_path)

    assert has_element?(
             reopened_failed_verifier_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="command_verifier_instance"][data-data-link-target-id="#{failed_verifier_instance.command_verifier_instance_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    assert has_element?(
             reopened_failed_verifier_view,
             ~s(#dashboard-data-link-inspector [data-data-link-navigation] [data-data-link-nav-entry-id="#{release_attempt_id}"][phx-value-target="command_release_attempt"])
           )

    assert has_element?(
             reopened_failed_verifier_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Command verifier instance"]),
             failed_verifier_instance.command_verifier_instance_id
           )

    assert has_element?(
             reopened_failed_verifier_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Failure reason"]),
             "failure_criteria_matched"
           )

    verifier_release_attempt_related_selector =
      ~s(#dashboard-data-link-inspector [data-data-link-related-target="command release attempt"][data-data-link-related-id="#{release_attempt_id}"])

    verifier_command_request_related_selector =
      ~s(#dashboard-data-link-inspector [data-data-link-related-target="command request"][data-data-link-related-id="#{release_attempt.command_request_id}"])

    assert has_element?(
             reopened_failed_verifier_view,
             verifier_release_attempt_related_selector
           )

    assert has_element?(
             reopened_failed_verifier_view,
             verifier_command_request_related_selector
           )

    {:ok, reopened_failed_verifier_command_request_view, _html} =
      live(conn, failed_verifier_copied_path)

    assert has_element?(
             reopened_failed_verifier_command_request_view,
             verifier_command_request_related_selector
           )

    reopened_failed_verifier_command_request_view
    |> element(verifier_command_request_related_selector)
    |> render_click()

    verifier_command_request_path = assert_patch(reopened_failed_verifier_command_request_view)
    verifier_command_request_route_id = URI.encode_www_form(release_attempt.command_request_id)
    assert verifier_command_request_path =~ "panel=data_link"
    assert verifier_command_request_path =~ "selected_target=command_request"
    assert verifier_command_request_path =~ "selected_id=#{verifier_command_request_route_id}"
    assert verifier_command_request_path =~ "nav_from_target=command_verifier_instance"

    assert verifier_command_request_path =~
             "nav_from_target_id=#{failed_verifier_instance.command_verifier_instance_id}"

    assert verifier_command_request_path =~ "nav_trail="
    assert verifier_command_request_path =~ "replay_run_id=#{replay_run_id}"

    assert verifier_command_request_path =~
             "data_source_id=#{replay_sources.operational_data_source_id}"

    assert verifier_command_request_path =~
             "source_binding_id=#{replay_sources.operational_binding_id}"

    assert has_element?(
             reopened_failed_verifier_command_request_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="command_request"][data-data-link-target-id="#{release_attempt.command_request_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    assert has_element?(
             reopened_failed_verifier_command_request_view,
             ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=command_request"][data-clipboard-text*="selected_id=#{verifier_command_request_route_id}"][data-clipboard-text*="nav_from_target=command_verifier_instance"][data-clipboard-text*="nav_from_target_id=#{failed_verifier_instance.command_verifier_instance_id}"][data-clipboard-text*="replay_run_id=#{replay_run_id}"])
           )

    verifier_command_request_copied_path =
      reopened_failed_verifier_command_request_view
      |> render()
      |> element_attribute("#dashboard-data-link-copy-link", "data-clipboard-text")

    assert verifier_command_request_copied_path =~ "panel=data_link"
    assert verifier_command_request_copied_path =~ "selected_target=command_request"

    assert verifier_command_request_copied_path =~
             "selected_id=#{verifier_command_request_route_id}"

    assert verifier_command_request_copied_path =~ "nav_from_target=command_verifier_instance"

    assert verifier_command_request_copied_path =~
             "nav_from_target_id=#{failed_verifier_instance.command_verifier_instance_id}"

    assert verifier_command_request_copied_path =~ "replay_run_id=#{replay_run_id}"

    {:ok, reopened_verifier_command_request_view, _html} =
      live(conn, verifier_command_request_copied_path)

    assert has_element?(
             reopened_verifier_command_request_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="command_request"][data-data-link-target-id="#{release_attempt.command_request_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    assert has_element?(
             reopened_verifier_command_request_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Command request"]),
             release_attempt.command_request_id
           )

    assert has_element?(
             reopened_verifier_command_request_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Command"]),
             release_attempt.command_name
           )

    assert has_element?(
             reopened_verifier_command_request_view,
             ~s(#dashboard-data-link-inspector [data-data-link-context="Replay run"]),
             replay_run_id
           )

    stop_dashboard_view(reopened_verifier_command_request_view)
    stop_dashboard_view(reopened_failed_verifier_command_request_view)

    reopened_failed_verifier_view
    |> element(verifier_release_attempt_related_selector)
    |> render_click()

    verifier_release_attempt_path = assert_patch(reopened_failed_verifier_view)
    assert verifier_release_attempt_path =~ "panel=data_link"
    assert verifier_release_attempt_path =~ "selected_target=command_release_attempt"
    assert verifier_release_attempt_path =~ "selected_id=#{release_attempt_id}"
    assert verifier_release_attempt_path =~ "nav_from_target=command_verifier_instance"

    assert verifier_release_attempt_path =~
             "nav_from_target_id=#{failed_verifier_instance.command_verifier_instance_id}"

    assert verifier_release_attempt_path =~ "nav_trail="
    assert verifier_release_attempt_path =~ "replay_run_id=#{replay_run_id}"

    assert verifier_release_attempt_path =~
             "data_source_id=#{replay_sources.operational_data_source_id}"

    assert verifier_release_attempt_path =~
             "source_binding_id=#{replay_sources.operational_binding_id}"

    assert has_element?(
             reopened_failed_verifier_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="command_release_attempt"][data-data-link-target-id="#{release_attempt_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    assert has_element?(
             reopened_failed_verifier_view,
             ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=command_release_attempt"][data-clipboard-text*="selected_id=#{release_attempt_id}"][data-clipboard-text*="nav_from_target=command_verifier_instance"][data-clipboard-text*="nav_from_target_id=#{failed_verifier_instance.command_verifier_instance_id}"][data-clipboard-text*="replay_run_id=#{replay_run_id}"])
           )

    verifier_release_attempt_copied_path =
      reopened_failed_verifier_view
      |> render()
      |> element_attribute("#dashboard-data-link-copy-link", "data-clipboard-text")

    assert verifier_release_attempt_copied_path =~ "panel=data_link"
    assert verifier_release_attempt_copied_path =~ "selected_target=command_release_attempt"
    assert verifier_release_attempt_copied_path =~ "selected_id=#{release_attempt_id}"
    assert verifier_release_attempt_copied_path =~ "nav_from_target=command_verifier_instance"

    assert verifier_release_attempt_copied_path =~
             "nav_from_target_id=#{failed_verifier_instance.command_verifier_instance_id}"

    assert verifier_release_attempt_copied_path =~ "replay_run_id=#{replay_run_id}"

    {:ok, reopened_verifier_release_attempt_view, _html} =
      live(conn, verifier_release_attempt_copied_path)

    assert has_element?(
             reopened_verifier_release_attempt_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="command_release_attempt"][data-data-link-target-id="#{release_attempt_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    assert has_element?(
             reopened_verifier_release_attempt_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Command release attempt"]),
             release_attempt_id
           )

    assert has_element?(
             reopened_verifier_release_attempt_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Command request"]),
             release_attempt.command_request_id
           )

    assert has_element?(
             reopened_verifier_release_attempt_view,
             ~s(#dashboard-data-link-inspector [data-data-link-context="Replay run"]),
             replay_run_id
           )

    stop_dashboard_view(reopened_verifier_release_attempt_view)

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-navigation] [data-data-link-nav-entry-id="#{release_attempt_id}"][phx-value-target="command_release_attempt"])
           )

    view
    |> element(
      ~s(#dashboard-data-link-inspector [data-data-link-navigation] [data-data-link-nav-entry-id="#{release_attempt_id}"])
    )
    |> render_click()

    release_attempt_back_path = assert_patch(view)
    assert release_attempt_back_path =~ "panel=data_link"
    assert release_attempt_back_path =~ "selected_target=command_release_attempt"
    assert release_attempt_back_path =~ "selected_id=#{release_attempt_id}"
    assert release_attempt_back_path =~ "replay_run_id=#{replay_run_id}"

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="command_release_attempt"][data-data-link-target-id="#{release_attempt_id}"][data-data-link-status="resolved"])
           )

    source_endpoint_related_selector =
      ~s(#dashboard-data-link-inspector [data-data-link-related-target="source endpoint"][data-data-link-related-id="endpoint-alpha"])

    assert has_element?(view, source_endpoint_related_selector)

    view
    |> element(source_endpoint_related_selector)
    |> render_click()

    source_endpoint_related_path = assert_patch(view)
    assert source_endpoint_related_path =~ "panel=data_link"
    assert source_endpoint_related_path =~ "selected_target=source_endpoint"
    assert source_endpoint_related_path =~ "selected_id=endpoint-alpha"
    assert source_endpoint_related_path =~ "nav_from_target=command_release_attempt"
    assert source_endpoint_related_path =~ "nav_from_target_id=#{release_attempt_id}"
    assert source_endpoint_related_path =~ "nav_trail="
    assert source_endpoint_related_path =~ "replay_run_id=#{replay_run_id}"

    assert source_endpoint_related_path =~
             "data_source_id=#{replay_sources.operational_data_source_id}"

    assert source_endpoint_related_path =~
             "source_binding_id=#{replay_sources.operational_binding_id}"

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="source_endpoint"][data-data-link-target-id="endpoint-alpha"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Source endpoint"]),
             "endpoint-alpha"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=source_endpoint"][data-clipboard-text*="selected_id=endpoint-alpha"][data-clipboard-text*="nav_from_target=command_release_attempt"][data-clipboard-text*="nav_from_target_id=#{release_attempt_id}"][data-clipboard-text*="replay_run_id=#{replay_run_id}"][data-clipboard-text*="data_source_id=#{replay_sources.operational_data_source_id}"][data-clipboard-text*="source_binding_id=#{replay_sources.operational_binding_id}"])
           )

    source_endpoint_copied_path =
      view
      |> render()
      |> element_attribute("#dashboard-data-link-copy-link", "data-clipboard-text")

    assert source_endpoint_copied_path =~ "panel=data_link"
    assert source_endpoint_copied_path =~ "selected_target=source_endpoint"
    assert source_endpoint_copied_path =~ "selected_id=endpoint-alpha"
    assert source_endpoint_copied_path =~ "nav_from_target=command_release_attempt"
    assert source_endpoint_copied_path =~ "nav_from_target_id=#{release_attempt_id}"
    assert source_endpoint_copied_path =~ "replay_run_id=#{replay_run_id}"

    assert source_endpoint_copied_path =~
             "data_source_id=#{replay_sources.operational_data_source_id}"

    assert source_endpoint_copied_path =~
             "source_binding_id=#{replay_sources.operational_binding_id}"

    {:ok, reopened_source_endpoint_view, _html} = live(conn, source_endpoint_copied_path)

    assert has_element?(
             reopened_source_endpoint_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="source_endpoint"][data-data-link-target-id="endpoint-alpha"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    assert has_element?(
             reopened_source_endpoint_view,
             ~s(#dashboard-data-link-inspector [data-data-link-navigation] [data-data-link-nav-entry-id="#{release_attempt_id}"][phx-value-target="command_release_attempt"])
           )

    assert has_element?(
             reopened_source_endpoint_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Source endpoint"]),
             "endpoint-alpha"
           )

    reopened_source_endpoint_view
    |> element(
      ~s(#dashboard-data-link-inspector [data-data-link-navigation] [data-data-link-nav-entry-id="#{release_attempt_id}"][phx-value-target="command_release_attempt"][data-data-link-nav-entry-index="2"])
    )
    |> render_click()

    source_endpoint_release_attempt_back_path = assert_patch(reopened_source_endpoint_view)
    assert source_endpoint_release_attempt_back_path =~ "panel=data_link"
    assert source_endpoint_release_attempt_back_path =~ "selected_target=command_release_attempt"
    assert source_endpoint_release_attempt_back_path =~ "selected_id=#{release_attempt_id}"
    assert source_endpoint_release_attempt_back_path =~ "replay_run_id=#{replay_run_id}"

    assert source_endpoint_release_attempt_back_path =~
             "data_source_id=#{replay_sources.operational_data_source_id}"

    assert source_endpoint_release_attempt_back_path =~
             "source_binding_id=#{replay_sources.operational_binding_id}"

    assert has_element?(
             reopened_source_endpoint_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="command_release_attempt"][data-data-link-target-id="#{release_attempt_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    assert has_element?(
             reopened_source_endpoint_view,
             ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=command_release_attempt"][data-clipboard-text*="selected_id=#{release_attempt_id}"][data-clipboard-text*="replay_run_id=#{replay_run_id}"][data-clipboard-text*="data_source_id=#{replay_sources.operational_data_source_id}"][data-clipboard-text*="source_binding_id=#{replay_sources.operational_binding_id}"])
           )

    source_endpoint_release_attempt_back_copied_path =
      reopened_source_endpoint_view
      |> render()
      |> element_attribute("#dashboard-data-link-copy-link", "data-clipboard-text")

    assert source_endpoint_release_attempt_back_copied_path =~ "panel=data_link"

    assert source_endpoint_release_attempt_back_copied_path =~
             "selected_target=command_release_attempt"

    assert source_endpoint_release_attempt_back_copied_path =~ "selected_id=#{release_attempt_id}"
    assert source_endpoint_release_attempt_back_copied_path =~ "replay_run_id=#{replay_run_id}"

    assert source_endpoint_release_attempt_back_copied_path =~
             "data_source_id=#{replay_sources.operational_data_source_id}"

    assert source_endpoint_release_attempt_back_copied_path =~
             "source_binding_id=#{replay_sources.operational_binding_id}"

    {:ok, reopened_source_endpoint_release_attempt_view, _html} =
      live(conn, source_endpoint_release_attempt_back_copied_path)

    assert has_element?(
             reopened_source_endpoint_release_attempt_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="command_release_attempt"][data-data-link-target-id="#{release_attempt_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    assert has_element?(
             reopened_source_endpoint_release_attempt_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Command release attempt"]),
             release_attempt_id
           )

    assert has_element?(
             reopened_source_endpoint_release_attempt_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Command request"]),
             release_attempt.command_request_id
           )

    assert has_element?(
             reopened_source_endpoint_release_attempt_view,
             ~s(#dashboard-data-link-inspector [data-data-link-context="Replay run"]),
             replay_run_id
           )

    view
    |> element(
      ~s(#dashboard-data-link-inspector [data-data-link-navigation] [data-data-link-nav-entry-id="#{release_attempt_id}"][data-data-link-nav-entry-index="2"])
    )
    |> render_click()

    release_attempt_resource_back_path = assert_patch(view)
    assert release_attempt_resource_back_path =~ "selected_target=command_release_attempt"
    assert release_attempt_resource_back_path =~ "selected_id=#{release_attempt_id}"

    contact_related_selector =
      ~s(#dashboard-data-link-inspector [data-data-link-related-target="contact"][data-data-link-related-id="replay-contact-alpha"])

    assert has_element?(view, contact_related_selector)

    view
    |> element(contact_related_selector)
    |> render_click()

    contact_related_path = assert_patch(view)
    assert contact_related_path =~ "panel=data_link"
    assert contact_related_path =~ "selected_target=contact"
    assert contact_related_path =~ "selected_id=replay-contact-alpha"
    assert contact_related_path =~ "nav_from_target=command_release_attempt"
    assert contact_related_path =~ "nav_from_target_id=#{release_attempt_id}"
    assert contact_related_path =~ "nav_trail="
    assert contact_related_path =~ "replay_run_id=#{replay_run_id}"

    assert contact_related_path =~
             "data_source_id=#{replay_sources.operational_data_source_id}"

    assert contact_related_path =~
             "source_binding_id=#{replay_sources.operational_binding_id}"

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="contact"][data-data-link-target-id="replay-contact-alpha"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Realized contact"]),
             "replay-contact-alpha"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=contact"][data-clipboard-text*="selected_id=replay-contact-alpha"][data-clipboard-text*="nav_from_target=command_release_attempt"][data-clipboard-text*="nav_from_target_id=#{release_attempt_id}"][data-clipboard-text*="replay_run_id=#{replay_run_id}"][data-clipboard-text*="data_source_id=#{replay_sources.operational_data_source_id}"][data-clipboard-text*="source_binding_id=#{replay_sources.operational_binding_id}"])
           )

    contact_copied_path =
      view
      |> render()
      |> element_attribute("#dashboard-data-link-copy-link", "data-clipboard-text")

    assert contact_copied_path =~ "panel=data_link"
    assert contact_copied_path =~ "selected_target=contact"
    assert contact_copied_path =~ "selected_id=replay-contact-alpha"
    assert contact_copied_path =~ "nav_from_target=command_release_attempt"
    assert contact_copied_path =~ "nav_from_target_id=#{release_attempt_id}"
    assert contact_copied_path =~ "replay_run_id=#{replay_run_id}"
    assert contact_copied_path =~ "data_source_id=#{replay_sources.operational_data_source_id}"
    assert contact_copied_path =~ "source_binding_id=#{replay_sources.operational_binding_id}"

    {:ok, reopened_contact_view, _html} = live(conn, contact_copied_path)

    assert has_element?(
             reopened_contact_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="contact"][data-data-link-target-id="replay-contact-alpha"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    assert has_element?(
             reopened_contact_view,
             ~s(#dashboard-data-link-inspector [data-data-link-navigation] [data-data-link-nav-entry-id="#{release_attempt_id}"][phx-value-target="command_release_attempt"])
           )

    assert has_element?(
             reopened_contact_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Realized contact"]),
             "replay-contact-alpha"
           )

    reopened_contact_view
    |> element(
      ~s(#dashboard-data-link-inspector [data-data-link-navigation] [data-data-link-nav-entry-id="#{release_attempt_id}"][phx-value-target="command_release_attempt"][data-data-link-nav-entry-index="2"])
    )
    |> render_click()

    contact_release_attempt_back_path = assert_patch(reopened_contact_view)
    assert contact_release_attempt_back_path =~ "panel=data_link"
    assert contact_release_attempt_back_path =~ "selected_target=command_release_attempt"
    assert contact_release_attempt_back_path =~ "selected_id=#{release_attempt_id}"
    assert contact_release_attempt_back_path =~ "replay_run_id=#{replay_run_id}"

    assert contact_release_attempt_back_path =~
             "data_source_id=#{replay_sources.operational_data_source_id}"

    assert contact_release_attempt_back_path =~
             "source_binding_id=#{replay_sources.operational_binding_id}"

    assert has_element?(
             reopened_contact_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="command_release_attempt"][data-data-link-target-id="#{release_attempt_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    assert has_element?(
             reopened_contact_view,
             ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=command_release_attempt"][data-clipboard-text*="selected_id=#{release_attempt_id}"][data-clipboard-text*="replay_run_id=#{replay_run_id}"][data-clipboard-text*="data_source_id=#{replay_sources.operational_data_source_id}"][data-clipboard-text*="source_binding_id=#{replay_sources.operational_binding_id}"])
           )

    contact_release_attempt_back_copied_path =
      reopened_contact_view
      |> render()
      |> element_attribute("#dashboard-data-link-copy-link", "data-clipboard-text")

    assert contact_release_attempt_back_copied_path =~ "panel=data_link"
    assert contact_release_attempt_back_copied_path =~ "selected_target=command_release_attempt"
    assert contact_release_attempt_back_copied_path =~ "selected_id=#{release_attempt_id}"
    assert contact_release_attempt_back_copied_path =~ "replay_run_id=#{replay_run_id}"

    assert contact_release_attempt_back_copied_path =~
             "data_source_id=#{replay_sources.operational_data_source_id}"

    assert contact_release_attempt_back_copied_path =~
             "source_binding_id=#{replay_sources.operational_binding_id}"

    {:ok, reopened_contact_release_attempt_view, _html} =
      live(conn, contact_release_attempt_back_copied_path)

    assert has_element?(
             reopened_contact_release_attempt_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="command_release_attempt"][data-data-link-target-id="#{release_attempt_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    assert has_element?(
             reopened_contact_release_attempt_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Command release attempt"]),
             release_attempt_id
           )

    assert has_element?(
             reopened_contact_release_attempt_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Command request"]),
             release_attempt.command_request_id
           )

    assert has_element?(
             reopened_contact_release_attempt_view,
             ~s(#dashboard-data-link-inspector [data-data-link-context="Replay run"]),
             replay_run_id
           )

    view
    |> element(
      ~s(#dashboard-data-link-inspector [data-data-link-navigation] [data-data-link-nav-entry-id="#{release_attempt_id}"][data-data-link-nav-entry-index="2"])
    )
    |> render_click()

    release_attempt_contact_back_path = assert_patch(view)
    assert release_attempt_contact_back_path =~ "selected_target=command_release_attempt"
    assert release_attempt_contact_back_path =~ "selected_id=#{release_attempt_id}"

    view
    |> element(transport_action_related_selector)
    |> render_click()

    transport_action_related_path = assert_patch(view)
    assert transport_action_related_path =~ "panel=data_link"
    assert transport_action_related_path =~ "selected_target=transport_action_request"
    assert transport_action_related_path =~ "selected_id=transport-action-request-1"
    assert transport_action_related_path =~ "nav_from_target=command_release_attempt"
    assert transport_action_related_path =~ "nav_from_target_id=#{release_attempt_id}"
    assert transport_action_related_path =~ "nav_trail="
    assert transport_action_related_path =~ "replay_run_id=#{replay_run_id}"

    assert transport_action_related_path =~
             "data_source_id=#{replay_sources.operational_data_source_id}"

    assert transport_action_related_path =~
             "source_binding_id=#{replay_sources.operational_binding_id}"

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="transport_action_request"][data-data-link-target-id="transport-action-request-1"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Signal phase"])
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=transport_action_request"][data-clipboard-text*="selected_id=transport-action-request-1"][data-clipboard-text*="nav_from_target=command_release_attempt"][data-clipboard-text*="nav_from_target_id=#{release_attempt_id}"][data-clipboard-text*="replay_run_id=#{replay_run_id}"][data-clipboard-text*="data_source_id=#{replay_sources.operational_data_source_id}"][data-clipboard-text*="source_binding_id=#{replay_sources.operational_binding_id}"])
           )

    transport_action_copied_path =
      view
      |> render()
      |> element_attribute("#dashboard-data-link-copy-link", "data-clipboard-text")

    assert transport_action_copied_path =~ "panel=data_link"
    assert transport_action_copied_path =~ "selected_target=transport_action_request"
    assert transport_action_copied_path =~ "selected_id=transport-action-request-1"
    assert transport_action_copied_path =~ "nav_from_target=command_release_attempt"
    assert transport_action_copied_path =~ "nav_from_target_id=#{release_attempt_id}"
    assert transport_action_copied_path =~ "replay_run_id=#{replay_run_id}"

    assert transport_action_copied_path =~
             "data_source_id=#{replay_sources.operational_data_source_id}"

    assert transport_action_copied_path =~
             "source_binding_id=#{replay_sources.operational_binding_id}"

    {:ok, reopened_transport_action_view, _html} = live(conn, transport_action_copied_path)

    assert has_element?(
             reopened_transport_action_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="transport_action_request"][data-data-link-target-id="transport-action-request-1"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    assert has_element?(
             reopened_transport_action_view,
             ~s(#dashboard-data-link-inspector [data-data-link-navigation] [data-data-link-nav-entry-id="#{release_attempt_id}"][phx-value-target="command_release_attempt"])
           )

    assert has_element?(
             reopened_transport_action_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Transport action request"]),
             "transport-action-request-1"
           )

    assert_transport_action_runtime_context!(
      reopened_transport_action_view,
      release_attempt_id,
      release_attempt.command_request_id,
      replay_run_id
    )

    assert has_element?(
             reopened_transport_action_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Signal phase"])
           )

    action_event_id = action_event.event_id
    action_event_route_id = URI.encode_www_form(action_event_id)
    action_event_at_ms = DateTime.to_unix(action_at, :millisecond)

    transport_action_event_related_selector =
      ~s(#dashboard-data-link-inspector [data-data-link-related-target="operational event"][data-data-link-related-id="#{action_event_id}"])

    assert has_element?(
             reopened_transport_action_view,
             transport_action_event_related_selector
           )

    reopened_transport_action_view
    |> element(transport_action_event_related_selector)
    |> render_click()

    transport_action_event_path = assert_patch(reopened_transport_action_view)
    assert transport_action_event_path =~ "panel=data_link"
    assert transport_action_event_path =~ "selected_target=operational_event"
    assert transport_action_event_path =~ "selected_id=#{action_event_route_id}"
    assert transport_action_event_path =~ "selected_time=#{action_event_at_ms}"
    assert transport_action_event_path =~ "nav_from_target=transport_action_request"
    assert transport_action_event_path =~ "nav_from_target_id=transport-action-request-1"
    assert transport_action_event_path =~ "nav_trail="
    assert transport_action_event_path =~ "replay_run_id=#{replay_run_id}"

    assert transport_action_event_path =~
             "data_source_id=#{replay_sources.operational_data_source_id}"

    assert transport_action_event_path =~
             "source_binding_id=#{replay_sources.operational_binding_id}"

    assert has_element?(
             reopened_transport_action_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="operational_event"][data-data-link-target-id="#{action_event_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    assert has_element?(
             reopened_transport_action_view,
             ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=operational_event"][data-clipboard-text*="selected_id=#{action_event_route_id}"][data-clipboard-text*="selected_time=#{action_event_at_ms}"][data-clipboard-text*="nav_from_target=transport_action_request"][data-clipboard-text*="nav_from_target_id=transport-action-request-1"][data-clipboard-text*="replay_run_id=#{replay_run_id}"][data-clipboard-text*="data_source_id=#{replay_sources.operational_data_source_id}"][data-clipboard-text*="source_binding_id=#{replay_sources.operational_binding_id}"])
           )

    transport_action_event_copied_path =
      reopened_transport_action_view
      |> render()
      |> element_attribute("#dashboard-data-link-copy-link", "data-clipboard-text")

    assert transport_action_event_copied_path =~ "panel=data_link"
    assert transport_action_event_copied_path =~ "selected_target=operational_event"
    assert transport_action_event_copied_path =~ "selected_id=#{action_event_route_id}"
    assert transport_action_event_copied_path =~ "selected_time=#{action_event_at_ms}"
    assert transport_action_event_copied_path =~ "nav_from_target=transport_action_request"
    assert transport_action_event_copied_path =~ "nav_from_target_id=transport-action-request-1"
    assert transport_action_event_copied_path =~ "replay_run_id=#{replay_run_id}"

    assert transport_action_event_copied_path =~
             "data_source_id=#{replay_sources.operational_data_source_id}"

    assert transport_action_event_copied_path =~
             "source_binding_id=#{replay_sources.operational_binding_id}"

    {:ok, reopened_transport_action_event_view, _html} =
      live(conn, transport_action_event_copied_path)

    assert has_element?(
             reopened_transport_action_event_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="operational_event"][data-data-link-target-id="#{action_event_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    assert has_element?(
             reopened_transport_action_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-navigation] [data-data-link-nav-entry-id="transport-action-request-1"][phx-value-target="transport_action_request"])
           )

    assert has_element?(
             reopened_transport_action_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-navigation] [data-data-link-nav-entry-id="#{release_attempt_id}"][phx-value-target="command_release_attempt"])
           )

    {:ok, reopened_transport_action_event_back_source_view, _html} =
      live(conn, transport_action_event_copied_path)

    assert has_element?(
             reopened_transport_action_event_back_source_view,
             ~s(#dashboard-data-link-inspector [data-data-link-navigation] [data-data-link-nav-entry-id="#{release_attempt_id}"][phx-value-target="command_release_attempt"])
           )

    reopened_transport_action_event_back_source_view
    |> element(
      ~s(#dashboard-data-link-inspector [data-data-link-navigation] [data-data-link-nav-entry-id="#{release_attempt_id}"][phx-value-target="command_release_attempt"])
    )
    |> render_click()

    release_attempt_event_back_path =
      assert_patch(reopened_transport_action_event_back_source_view)

    assert release_attempt_event_back_path =~ "panel=data_link"
    assert release_attempt_event_back_path =~ "selected_target=command_release_attempt"
    assert release_attempt_event_back_path =~ "selected_id=#{release_attempt_id}"
    assert release_attempt_event_back_path =~ "selected_time=#{action_event_at_ms}"
    assert release_attempt_event_back_path =~ "replay_run_id=#{replay_run_id}"

    assert release_attempt_event_back_path =~
             "data_source_id=#{replay_sources.operational_data_source_id}"

    assert release_attempt_event_back_path =~
             "source_binding_id=#{replay_sources.operational_binding_id}"

    assert has_element?(
             reopened_transport_action_event_back_source_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="command_release_attempt"][data-data-link-target-id="#{release_attempt_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    assert has_element?(
             reopened_transport_action_event_back_source_view,
             ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=command_release_attempt"][data-clipboard-text*="selected_id=#{release_attempt_id}"][data-clipboard-text*="selected_time=#{action_event_at_ms}"][data-clipboard-text*="replay_run_id=#{replay_run_id}"][data-clipboard-text*="data_source_id=#{replay_sources.operational_data_source_id}"][data-clipboard-text*="source_binding_id=#{replay_sources.operational_binding_id}"])
           )

    release_attempt_event_back_copied_path =
      reopened_transport_action_event_back_source_view
      |> render()
      |> element_attribute("#dashboard-data-link-copy-link", "data-clipboard-text")

    assert release_attempt_event_back_copied_path =~ "panel=data_link"

    assert release_attempt_event_back_copied_path =~
             "selected_target=command_release_attempt"

    assert release_attempt_event_back_copied_path =~ "selected_id=#{release_attempt_id}"
    assert release_attempt_event_back_copied_path =~ "selected_time=#{action_event_at_ms}"
    assert release_attempt_event_back_copied_path =~ "replay_run_id=#{replay_run_id}"

    assert release_attempt_event_back_copied_path =~
             "data_source_id=#{replay_sources.operational_data_source_id}"

    assert release_attempt_event_back_copied_path =~
             "source_binding_id=#{replay_sources.operational_binding_id}"

    {:ok, reopened_release_attempt_event_back_view, _html} =
      live(conn, release_attempt_event_back_copied_path)

    assert has_element?(
             reopened_release_attempt_event_back_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="command_release_attempt"][data-data-link-target-id="#{release_attempt_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    assert has_element?(
             reopened_release_attempt_event_back_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Command release attempt"]),
             release_attempt_id
           )

    assert has_element?(
             reopened_release_attempt_event_back_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Command request"]),
             release_attempt.command_request_id
           )

    assert has_element?(
             reopened_release_attempt_event_back_view,
             ~s(#dashboard-data-link-inspector [data-data-link-context="Replay run"]),
             replay_run_id
           )

    assert has_element?(
             reopened_transport_action_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Transport action request"]),
             "transport-action-request-1"
           )

    assert_transport_action_runtime_context!(
      reopened_transport_action_event_view,
      release_attempt_id,
      release_attempt.command_request_id,
      replay_run_id
    )

    assert has_element?(
             reopened_transport_action_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Action kind"]),
             "release_command"
           )

    assert has_element?(
             reopened_transport_action_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Signal phase"]),
             "start"
           )

    view
    |> element(action_row_selector <> ~s( [data-state-timeline-row-evidence]))
    |> render_click()

    assert_patch(view)

    failed_verifier_evidence_selector =
      ~s(#dashboard-evidence-inspector [data-evidence-ref-kind="command verifier instance"][data-evidence-ref-id="#{failed_verifier_instance.command_verifier_instance_id}"])

    failed_verifier_id = failed_verifier_instance.command_verifier_instance_id

    failed_verifier_matched_at_ms =
      DateTime.to_unix(failed_verifier_instance.matched_at, :millisecond)

    failed_verifier_evidence =
      view
      |> render()
      |> LazyHTML.from_fragment()
      |> LazyHTML.query(failed_verifier_evidence_selector)

    assert ["command_verifier_instance"] =
             LazyHTML.attribute(failed_verifier_evidence, "phx-value-target")

    assert [^failed_verifier_id] =
             LazyHTML.attribute(failed_verifier_evidence, "phx-value-target-id")

    assert [failed_verifier_matched_at_ms_text] =
             LazyHTML.attribute(failed_verifier_evidence, "phx-value-timestamp-ms")

    assert failed_verifier_matched_at_ms_text == Integer.to_string(failed_verifier_matched_at_ms)

    assert ["evidence-ref:command_verifier_instance:" <> _] =
             LazyHTML.attribute(failed_verifier_evidence, "phx-value-link-id")

    view
    |> element(failed_verifier_evidence_selector)
    |> render_click(%{
      "link-id" => "evidence-ref:command_verifier_instance:#{failed_verifier_id}",
      "target" => "command_verifier_instance",
      "target-id" => failed_verifier_id,
      "timestamp-ms" => failed_verifier_matched_at_ms,
      "realm" => "replay",
      "time-mode" => "replay_run",
      "replay-run-id" => replay_run_id,
      "data-source-id" => replay_sources.operational_data_source_id,
      "source-binding-id" => replay_sources.operational_binding_id
    })

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="command_verifier_instance"][data-data-link-target-id="#{failed_verifier_id}"])
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="command_verifier_instance"][data-data-link-target-id="#{failed_verifier_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    failed_verifier_path = assert_patch(view)
    assert failed_verifier_path =~ "panel=data_link"
    assert failed_verifier_path =~ "selected_target=command_verifier_instance"
    assert failed_verifier_path =~ "selected_id=#{failed_verifier_id}"
    assert failed_verifier_path =~ "selected_time=#{failed_verifier_matched_at_ms}"
    assert failed_verifier_path =~ "replay_run_id=#{replay_run_id}"

    assert has_element?(
             view,
             ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=command_verifier_instance"][data-clipboard-text*="selected_id=#{failed_verifier_id}"][data-clipboard-text*="replay_run_id=#{replay_run_id}"][data-clipboard-text*="data_source_id=#{replay_sources.operational_data_source_id}"][data-clipboard-text*="source_binding_id=#{replay_sources.operational_binding_id}"])
           )

    failed_verifier_copied_path =
      view
      |> render()
      |> element_attribute("#dashboard-data-link-copy-link", "data-clipboard-text")

    assert failed_verifier_copied_path =~ "panel=data_link"
    assert failed_verifier_copied_path =~ "selected_target=command_verifier_instance"
    assert failed_verifier_copied_path =~ "selected_id=#{failed_verifier_id}"
    assert failed_verifier_copied_path =~ "selected_time=#{failed_verifier_matched_at_ms}"
    assert failed_verifier_copied_path =~ "replay_run_id=#{replay_run_id}"

    assert failed_verifier_copied_path =~
             "data_source_id=#{replay_sources.operational_data_source_id}"

    assert failed_verifier_copied_path =~
             "source_binding_id=#{replay_sources.operational_binding_id}"

    {:ok, reopened_failed_verifier_view, _html} = live(conn, failed_verifier_copied_path)

    assert has_element?(
             reopened_failed_verifier_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="command_verifier_instance"][data-data-link-target-id="#{failed_verifier_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    assert has_element?(
             reopened_failed_verifier_view,
             ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=command_verifier_instance"][data-clipboard-text*="selected_id=#{failed_verifier_id}"][data-clipboard-text*="selected_time=#{failed_verifier_matched_at_ms}"][data-clipboard-text*="replay_run_id=#{replay_run_id}"])
           )

    assert has_element?(
             reopened_failed_verifier_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Command verifier instance"]),
             failed_verifier_id
           )

    assert has_element?(
             reopened_failed_verifier_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Lifecycle state"]),
             "failed"
           )

    assert has_element?(
             reopened_failed_verifier_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Command release attempt"]),
             release_attempt_id
           )

    assert has_element?(
             reopened_failed_verifier_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Command request"]),
             release_attempt.command_request_id
           )

    assert has_element?(
             reopened_failed_verifier_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Failure reason"]),
             "failure_criteria_matched"
           )

    failed_verifier_transport_action_related_selector =
      ~s(#dashboard-data-link-inspector [data-data-link-related-target="transport action request"][data-data-link-related-id="transport-action-request-1"])

    assert has_element?(
             reopened_failed_verifier_view,
             failed_verifier_transport_action_related_selector
           )

    reopened_failed_verifier_view
    |> element(failed_verifier_transport_action_related_selector)
    |> render_click()

    failed_verifier_transport_action_path = assert_patch(reopened_failed_verifier_view)
    assert failed_verifier_transport_action_path =~ "panel=data_link"
    assert failed_verifier_transport_action_path =~ "selected_target=transport_action_request"
    assert failed_verifier_transport_action_path =~ "selected_id=transport-action-request-1"
    assert failed_verifier_transport_action_path =~ "nav_from_target=command_verifier_instance"
    assert failed_verifier_transport_action_path =~ "nav_from_target_id=#{failed_verifier_id}"
    assert failed_verifier_transport_action_path =~ "nav_trail="
    assert failed_verifier_transport_action_path =~ "replay_run_id=#{replay_run_id}"

    assert failed_verifier_transport_action_path =~
             "data_source_id=#{replay_sources.operational_data_source_id}"

    assert failed_verifier_transport_action_path =~
             "source_binding_id=#{replay_sources.operational_binding_id}"

    assert has_element?(
             reopened_failed_verifier_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="transport_action_request"][data-data-link-target-id="transport-action-request-1"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    assert has_element?(
             reopened_failed_verifier_view,
             ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=transport_action_request"][data-clipboard-text*="selected_id=transport-action-request-1"][data-clipboard-text*="nav_from_target=command_verifier_instance"][data-clipboard-text*="nav_from_target_id=#{failed_verifier_id}"][data-clipboard-text*="replay_run_id=#{replay_run_id}"][data-clipboard-text*="data_source_id=#{replay_sources.operational_data_source_id}"][data-clipboard-text*="source_binding_id=#{replay_sources.operational_binding_id}"])
           )

    failed_verifier_transport_action_copied_path =
      reopened_failed_verifier_view
      |> render()
      |> element_attribute("#dashboard-data-link-copy-link", "data-clipboard-text")

    assert failed_verifier_transport_action_copied_path =~ "panel=data_link"

    assert failed_verifier_transport_action_copied_path =~
             "selected_target=transport_action_request"

    assert failed_verifier_transport_action_copied_path =~
             "selected_id=transport-action-request-1"

    assert failed_verifier_transport_action_copied_path =~
             "nav_from_target=command_verifier_instance"

    assert failed_verifier_transport_action_copied_path =~
             "nav_from_target_id=#{failed_verifier_id}"

    assert failed_verifier_transport_action_copied_path =~ "replay_run_id=#{replay_run_id}"

    {:ok, reopened_failed_verifier_transport_action_view, _html} =
      live(conn, failed_verifier_transport_action_copied_path)

    assert has_element?(
             reopened_failed_verifier_transport_action_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="transport_action_request"][data-data-link-target-id="transport-action-request-1"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    assert has_element?(
             reopened_failed_verifier_transport_action_view,
             ~s(#dashboard-data-link-inspector [data-data-link-navigation] [data-data-link-nav-entry-id="#{failed_verifier_id}"][phx-value-target="command_verifier_instance"])
           )

    assert has_element?(
             reopened_failed_verifier_transport_action_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Transport action request"]),
             "transport-action-request-1"
           )

    assert_transport_action_runtime_context!(
      reopened_failed_verifier_transport_action_view,
      release_attempt_id,
      release_attempt.command_request_id,
      replay_run_id
    )

    reopened_failed_verifier_transport_action_view
    |> element(
      ~s(#dashboard-data-link-inspector [data-data-link-navigation] [data-data-link-nav-entry-id="#{failed_verifier_id}"][phx-value-target="command_verifier_instance"])
    )
    |> render_click()

    failed_verifier_transport_action_back_path =
      assert_patch(reopened_failed_verifier_transport_action_view)

    assert failed_verifier_transport_action_back_path =~ "panel=data_link"

    assert failed_verifier_transport_action_back_path =~
             "selected_target=command_verifier_instance"

    assert failed_verifier_transport_action_back_path =~ "selected_id=#{failed_verifier_id}"
    assert failed_verifier_transport_action_back_path =~ "replay_run_id=#{replay_run_id}"

    assert failed_verifier_transport_action_back_path =~
             "data_source_id=#{replay_sources.operational_data_source_id}"

    assert failed_verifier_transport_action_back_path =~
             "source_binding_id=#{replay_sources.operational_binding_id}"

    assert has_element?(
             reopened_failed_verifier_transport_action_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="command_verifier_instance"][data-data-link-target-id="#{failed_verifier_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    assert has_element?(
             reopened_failed_verifier_transport_action_view,
             ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=command_verifier_instance"][data-clipboard-text*="selected_id=#{failed_verifier_id}"][data-clipboard-text*="replay_run_id=#{replay_run_id}"][data-clipboard-text*="data_source_id=#{replay_sources.operational_data_source_id}"][data-clipboard-text*="source_binding_id=#{replay_sources.operational_binding_id}"])
           )

    failed_verifier_transport_action_back_copied_path =
      reopened_failed_verifier_transport_action_view
      |> render()
      |> element_attribute("#dashboard-data-link-copy-link", "data-clipboard-text")

    assert failed_verifier_transport_action_back_copied_path =~ "panel=data_link"

    assert failed_verifier_transport_action_back_copied_path =~
             "selected_target=command_verifier_instance"

    assert failed_verifier_transport_action_back_copied_path =~
             "selected_id=#{failed_verifier_id}"

    assert failed_verifier_transport_action_back_copied_path =~ "replay_run_id=#{replay_run_id}"

    assert failed_verifier_transport_action_back_copied_path =~
             "data_source_id=#{replay_sources.operational_data_source_id}"

    assert failed_verifier_transport_action_back_copied_path =~
             "source_binding_id=#{replay_sources.operational_binding_id}"

    {:ok, reopened_failed_verifier_transport_action_back_view, _html} =
      live(conn, failed_verifier_transport_action_back_copied_path)

    assert has_element?(
             reopened_failed_verifier_transport_action_back_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="command_verifier_instance"][data-data-link-target-id="#{failed_verifier_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    assert has_element?(
             reopened_failed_verifier_transport_action_back_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Command verifier instance"]),
             failed_verifier_id
           )

    assert has_element?(
             reopened_failed_verifier_transport_action_back_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Lifecycle state"]),
             "failed"
           )

    assert has_element?(
             reopened_failed_verifier_transport_action_back_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Matched record"]),
             "transport-action-request-1"
           )

    assert has_element?(
             reopened_failed_verifier_transport_action_back_view,
             failed_verifier_transport_action_related_selector
           )

    reopened_failed_verifier_transport_action_back_view
    |> element(failed_verifier_transport_action_related_selector)
    |> render_click()

    failed_verifier_transport_action_back_matched_record_path =
      assert_patch(reopened_failed_verifier_transport_action_back_view)

    assert failed_verifier_transport_action_back_matched_record_path =~ "panel=data_link"

    assert failed_verifier_transport_action_back_matched_record_path =~
             "selected_target=transport_action_request"

    assert failed_verifier_transport_action_back_matched_record_path =~
             "selected_id=transport-action-request-1"

    assert failed_verifier_transport_action_back_matched_record_path =~
             "nav_from_target=command_verifier_instance"

    assert failed_verifier_transport_action_back_matched_record_path =~
             "nav_from_target_id=#{failed_verifier_id}"

    assert failed_verifier_transport_action_back_matched_record_path =~
             "replay_run_id=#{replay_run_id}"

    assert failed_verifier_transport_action_back_matched_record_path =~
             "data_source_id=#{replay_sources.operational_data_source_id}"

    assert failed_verifier_transport_action_back_matched_record_path =~
             "source_binding_id=#{replay_sources.operational_binding_id}"

    assert has_element?(
             reopened_failed_verifier_transport_action_back_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="transport_action_request"][data-data-link-target-id="transport-action-request-1"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    assert has_element?(
             reopened_failed_verifier_transport_action_back_view,
             ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=transport_action_request"][data-clipboard-text*="selected_id=transport-action-request-1"][data-clipboard-text*="nav_from_target=command_verifier_instance"][data-clipboard-text*="nav_from_target_id=#{failed_verifier_id}"][data-clipboard-text*="replay_run_id=#{replay_run_id}"][data-clipboard-text*="data_source_id=#{replay_sources.operational_data_source_id}"][data-clipboard-text*="source_binding_id=#{replay_sources.operational_binding_id}"])
           )

    failed_verifier_transport_action_back_matched_record_copied_path =
      reopened_failed_verifier_transport_action_back_view
      |> render()
      |> element_attribute("#dashboard-data-link-copy-link", "data-clipboard-text")

    assert failed_verifier_transport_action_back_matched_record_copied_path =~
             "panel=data_link"

    assert failed_verifier_transport_action_back_matched_record_copied_path =~
             "selected_target=transport_action_request"

    assert failed_verifier_transport_action_back_matched_record_copied_path =~
             "selected_id=transport-action-request-1"

    assert failed_verifier_transport_action_back_matched_record_copied_path =~
             "nav_from_target=command_verifier_instance"

    assert failed_verifier_transport_action_back_matched_record_copied_path =~
             "nav_from_target_id=#{failed_verifier_id}"

    assert failed_verifier_transport_action_back_matched_record_copied_path =~
             "replay_run_id=#{replay_run_id}"

    assert failed_verifier_transport_action_back_matched_record_copied_path =~
             "data_source_id=#{replay_sources.operational_data_source_id}"

    assert failed_verifier_transport_action_back_matched_record_copied_path =~
             "source_binding_id=#{replay_sources.operational_binding_id}"

    {:ok, reopened_failed_verifier_transport_action_back_matched_record_view, _html} =
      live(conn, failed_verifier_transport_action_back_matched_record_copied_path)

    assert has_element?(
             reopened_failed_verifier_transport_action_back_matched_record_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="transport_action_request"][data-data-link-target-id="transport-action-request-1"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    assert has_element?(
             reopened_failed_verifier_transport_action_back_matched_record_view,
             ~s(#dashboard-data-link-inspector [data-data-link-navigation] [data-data-link-nav-entry-id="#{failed_verifier_id}"][phx-value-target="command_verifier_instance"])
           )

    assert has_element?(
             reopened_failed_verifier_transport_action_back_matched_record_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Transport action request"]),
             "transport-action-request-1"
           )

    assert_transport_action_runtime_context!(
      reopened_failed_verifier_transport_action_back_matched_record_view,
      release_attempt_id,
      release_attempt.command_request_id,
      replay_run_id
    )

    assert has_element?(
             reopened_failed_verifier_transport_action_back_matched_record_view,
             transport_action_event_related_selector
           )

    failed_verifier_transport_action_event_link =
      reopened_failed_verifier_transport_action_back_matched_record_view
      |> render()
      |> LazyHTML.from_fragment()
      |> LazyHTML.query(transport_action_event_related_selector)

    assert [failed_verifier_transport_action_event_at_ms_text] =
             LazyHTML.attribute(
               failed_verifier_transport_action_event_link,
               "phx-value-timestamp-ms"
             )

    reopened_failed_verifier_transport_action_back_matched_record_view
    |> element(transport_action_event_related_selector)
    |> render_click()

    failed_verifier_transport_action_back_matched_record_event_path =
      assert_patch(reopened_failed_verifier_transport_action_back_matched_record_view)

    assert failed_verifier_transport_action_back_matched_record_event_path =~ "panel=data_link"

    assert failed_verifier_transport_action_back_matched_record_event_path =~
             "selected_target=operational_event"

    assert failed_verifier_transport_action_back_matched_record_event_path =~
             "selected_id=#{action_event_route_id}"

    assert failed_verifier_transport_action_back_matched_record_event_path =~
             "selected_time=#{failed_verifier_transport_action_event_at_ms_text}"

    assert failed_verifier_transport_action_back_matched_record_event_path =~
             "nav_from_target=transport_action_request"

    assert failed_verifier_transport_action_back_matched_record_event_path =~
             "nav_from_target_id=transport-action-request-1"

    assert failed_verifier_transport_action_back_matched_record_event_path =~
             "replay_run_id=#{replay_run_id}"

    assert failed_verifier_transport_action_back_matched_record_event_path =~
             "data_source_id=#{replay_sources.operational_data_source_id}"

    assert failed_verifier_transport_action_back_matched_record_event_path =~
             "source_binding_id=#{replay_sources.operational_binding_id}"

    assert has_element?(
             reopened_failed_verifier_transport_action_back_matched_record_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="operational_event"][data-data-link-target-id="#{action_event_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    assert has_element?(
             reopened_failed_verifier_transport_action_back_matched_record_view,
             ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=operational_event"][data-clipboard-text*="selected_id=#{action_event_route_id}"][data-clipboard-text*="selected_time=#{failed_verifier_transport_action_event_at_ms_text}"][data-clipboard-text*="nav_from_target=transport_action_request"][data-clipboard-text*="nav_from_target_id=transport-action-request-1"][data-clipboard-text*="replay_run_id=#{replay_run_id}"][data-clipboard-text*="data_source_id=#{replay_sources.operational_data_source_id}"][data-clipboard-text*="source_binding_id=#{replay_sources.operational_binding_id}"])
           )

    failed_verifier_transport_action_back_matched_record_event_copied_path =
      reopened_failed_verifier_transport_action_back_matched_record_view
      |> render()
      |> element_attribute("#dashboard-data-link-copy-link", "data-clipboard-text")

    assert failed_verifier_transport_action_back_matched_record_event_copied_path =~
             "panel=data_link"

    assert failed_verifier_transport_action_back_matched_record_event_copied_path =~
             "selected_target=operational_event"

    assert failed_verifier_transport_action_back_matched_record_event_copied_path =~
             "selected_id=#{action_event_route_id}"

    assert failed_verifier_transport_action_back_matched_record_event_copied_path =~
             "selected_time=#{failed_verifier_transport_action_event_at_ms_text}"

    assert failed_verifier_transport_action_back_matched_record_event_copied_path =~
             "nav_from_target=transport_action_request"

    assert failed_verifier_transport_action_back_matched_record_event_copied_path =~
             "nav_from_target_id=transport-action-request-1"

    assert failed_verifier_transport_action_back_matched_record_event_copied_path =~
             "replay_run_id=#{replay_run_id}"

    assert failed_verifier_transport_action_back_matched_record_event_copied_path =~
             "data_source_id=#{replay_sources.operational_data_source_id}"

    assert failed_verifier_transport_action_back_matched_record_event_copied_path =~
             "source_binding_id=#{replay_sources.operational_binding_id}"

    {:ok, reopened_transport_action_event_view, _html} =
      live(conn, failed_verifier_transport_action_back_matched_record_event_copied_path)

    assert has_element?(
             reopened_transport_action_event_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="operational_event"][data-data-link-target-id="#{action_event_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    assert has_element?(
             reopened_transport_action_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-navigation] [data-data-link-nav-entry-id="transport-action-request-1"][phx-value-target="transport_action_request"])
           )

    assert has_element?(
             reopened_transport_action_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-navigation] [data-data-link-nav-entry-id="#{failed_verifier_id}"][phx-value-target="command_verifier_instance"])
           )

    assert has_element?(
             reopened_transport_action_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Transport action request"]),
             "transport-action-request-1"
           )

    assert_transport_action_runtime_context!(
      reopened_transport_action_event_view,
      release_attempt_id,
      release_attempt.command_request_id,
      replay_run_id
    )

    assert has_element?(
             reopened_transport_action_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Action kind"]),
             "release_command"
           )

    reopened_transport_action_event_view
    |> element(
      ~s(#dashboard-data-link-inspector [data-data-link-navigation] [data-data-link-nav-entry-id="#{failed_verifier_id}"][phx-value-target="command_verifier_instance"])
    )
    |> render_click()

    failed_verifier_transport_action_back_matched_record_event_verifier_path =
      assert_patch(reopened_transport_action_event_view)

    assert failed_verifier_transport_action_back_matched_record_event_verifier_path =~
             "panel=data_link"

    assert failed_verifier_transport_action_back_matched_record_event_verifier_path =~
             "selected_target=command_verifier_instance"

    assert failed_verifier_transport_action_back_matched_record_event_verifier_path =~
             "selected_id=#{failed_verifier_id}"

    assert failed_verifier_transport_action_back_matched_record_event_verifier_path =~
             "replay_run_id=#{replay_run_id}"

    assert failed_verifier_transport_action_back_matched_record_event_verifier_path =~
             "data_source_id=#{replay_sources.operational_data_source_id}"

    assert failed_verifier_transport_action_back_matched_record_event_verifier_path =~
             "source_binding_id=#{replay_sources.operational_binding_id}"

    assert has_element?(
             reopened_transport_action_event_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="command_verifier_instance"][data-data-link-target-id="#{failed_verifier_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    assert has_element?(
             reopened_transport_action_event_view,
             ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=command_verifier_instance"][data-clipboard-text*="selected_id=#{failed_verifier_id}"][data-clipboard-text*="replay_run_id=#{replay_run_id}"][data-clipboard-text*="data_source_id=#{replay_sources.operational_data_source_id}"][data-clipboard-text*="source_binding_id=#{replay_sources.operational_binding_id}"])
           )

    failed_verifier_transport_action_back_matched_record_event_verifier_copied_path =
      reopened_transport_action_event_view
      |> render()
      |> element_attribute("#dashboard-data-link-copy-link", "data-clipboard-text")

    assert failed_verifier_transport_action_back_matched_record_event_verifier_copied_path =~
             "panel=data_link"

    assert failed_verifier_transport_action_back_matched_record_event_verifier_copied_path =~
             "selected_target=command_verifier_instance"

    assert failed_verifier_transport_action_back_matched_record_event_verifier_copied_path =~
             "selected_id=#{failed_verifier_id}"

    assert failed_verifier_transport_action_back_matched_record_event_verifier_copied_path =~
             "replay_run_id=#{replay_run_id}"

    assert failed_verifier_transport_action_back_matched_record_event_verifier_copied_path =~
             "data_source_id=#{replay_sources.operational_data_source_id}"

    assert failed_verifier_transport_action_back_matched_record_event_verifier_copied_path =~
             "source_binding_id=#{replay_sources.operational_binding_id}"

    {:ok, reopened_back_verifier_view, _html} =
      live(
        conn,
        failed_verifier_transport_action_back_matched_record_event_verifier_copied_path
      )

    assert has_element?(
             reopened_back_verifier_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="command_verifier_instance"][data-data-link-target-id="#{failed_verifier_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    assert has_element?(
             reopened_back_verifier_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Command verifier instance"]),
             failed_verifier_id
           )

    assert has_element?(
             reopened_back_verifier_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Lifecycle state"]),
             "failed"
           )

    assert has_element?(
             reopened_back_verifier_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Matched record"]),
             "transport-action-request-1"
           )

    assert has_element?(
             reopened_back_verifier_view,
             failed_verifier_transport_action_related_selector
           )

    reopened_back_verifier_view
    |> element(failed_verifier_transport_action_related_selector)
    |> render_click()

    failed_verifier_transport_action_back_matched_record_event_verifier_matched_record_path =
      assert_patch(reopened_back_verifier_view)

    assert failed_verifier_transport_action_back_matched_record_event_verifier_matched_record_path =~
             "panel=data_link"

    assert failed_verifier_transport_action_back_matched_record_event_verifier_matched_record_path =~
             "selected_target=transport_action_request"

    assert failed_verifier_transport_action_back_matched_record_event_verifier_matched_record_path =~
             "selected_id=transport-action-request-1"

    assert failed_verifier_transport_action_back_matched_record_event_verifier_matched_record_path =~
             "nav_from_target=command_verifier_instance"

    assert failed_verifier_transport_action_back_matched_record_event_verifier_matched_record_path =~
             "nav_from_target_id=#{failed_verifier_id}"

    assert failed_verifier_transport_action_back_matched_record_event_verifier_matched_record_path =~
             "replay_run_id=#{replay_run_id}"

    assert failed_verifier_transport_action_back_matched_record_event_verifier_matched_record_path =~
             "data_source_id=#{replay_sources.operational_data_source_id}"

    assert failed_verifier_transport_action_back_matched_record_event_verifier_matched_record_path =~
             "source_binding_id=#{replay_sources.operational_binding_id}"

    assert has_element?(
             reopened_back_verifier_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="transport_action_request"][data-data-link-target-id="transport-action-request-1"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    assert has_element?(
             reopened_back_verifier_view,
             ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=transport_action_request"][data-clipboard-text*="selected_id=transport-action-request-1"][data-clipboard-text*="nav_from_target=command_verifier_instance"][data-clipboard-text*="nav_from_target_id=#{failed_verifier_id}"][data-clipboard-text*="replay_run_id=#{replay_run_id}"][data-clipboard-text*="data_source_id=#{replay_sources.operational_data_source_id}"][data-clipboard-text*="source_binding_id=#{replay_sources.operational_binding_id}"])
           )

    failed_verifier_transport_action_back_matched_record_event_verifier_matched_record_copied_path =
      reopened_back_verifier_view
      |> render()
      |> element_attribute("#dashboard-data-link-copy-link", "data-clipboard-text")

    assert failed_verifier_transport_action_back_matched_record_event_verifier_matched_record_copied_path =~
             "panel=data_link"

    assert failed_verifier_transport_action_back_matched_record_event_verifier_matched_record_copied_path =~
             "selected_target=transport_action_request"

    assert failed_verifier_transport_action_back_matched_record_event_verifier_matched_record_copied_path =~
             "selected_id=transport-action-request-1"

    assert failed_verifier_transport_action_back_matched_record_event_verifier_matched_record_copied_path =~
             "nav_from_target=command_verifier_instance"

    assert failed_verifier_transport_action_back_matched_record_event_verifier_matched_record_copied_path =~
             "nav_from_target_id=#{failed_verifier_id}"

    assert failed_verifier_transport_action_back_matched_record_event_verifier_matched_record_copied_path =~
             "replay_run_id=#{replay_run_id}"

    assert failed_verifier_transport_action_back_matched_record_event_verifier_matched_record_copied_path =~
             "data_source_id=#{replay_sources.operational_data_source_id}"

    assert failed_verifier_transport_action_back_matched_record_event_verifier_matched_record_copied_path =~
             "source_binding_id=#{replay_sources.operational_binding_id}"

    {:ok, reopened_back_record_view, _html} =
      live(
        conn,
        failed_verifier_transport_action_back_matched_record_event_verifier_matched_record_copied_path
      )

    assert has_element?(
             reopened_back_record_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="transport_action_request"][data-data-link-target-id="transport-action-request-1"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    assert has_element?(
             reopened_back_record_view,
             ~s(#dashboard-data-link-inspector [data-data-link-navigation] [data-data-link-nav-entry-id="#{failed_verifier_id}"][phx-value-target="command_verifier_instance"])
           )

    assert has_element?(
             reopened_back_record_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Transport action request"]),
             "transport-action-request-1"
           )

    assert_transport_action_runtime_context!(
      reopened_back_record_view,
      release_attempt_id,
      release_attempt.command_request_id,
      replay_run_id
    )

    assert has_element?(
             reopened_back_record_view,
             transport_action_event_related_selector
           )

    failed_verifier_transport_action_event_verifier_matched_record_event_link =
      reopened_back_record_view
      |> render()
      |> LazyHTML.from_fragment()
      |> LazyHTML.query(transport_action_event_related_selector)

    assert [failed_verifier_transport_action_event_verifier_matched_record_event_at_ms_text] =
             LazyHTML.attribute(
               failed_verifier_transport_action_event_verifier_matched_record_event_link,
               "phx-value-timestamp-ms"
             )

    reopened_back_record_view
    |> element(transport_action_event_related_selector)
    |> render_click()

    failed_verifier_transport_action_back_matched_record_event_verifier_matched_record_event_path =
      assert_patch(reopened_back_record_view)

    assert failed_verifier_transport_action_back_matched_record_event_verifier_matched_record_event_path =~
             "panel=data_link"

    assert failed_verifier_transport_action_back_matched_record_event_verifier_matched_record_event_path =~
             "selected_target=operational_event"

    assert failed_verifier_transport_action_back_matched_record_event_verifier_matched_record_event_path =~
             "selected_id=#{action_event_route_id}"

    assert failed_verifier_transport_action_back_matched_record_event_verifier_matched_record_event_path =~
             "selected_time=#{failed_verifier_transport_action_event_verifier_matched_record_event_at_ms_text}"

    assert failed_verifier_transport_action_back_matched_record_event_verifier_matched_record_event_path =~
             "nav_from_target=transport_action_request"

    assert failed_verifier_transport_action_back_matched_record_event_verifier_matched_record_event_path =~
             "nav_from_target_id=transport-action-request-1"

    assert failed_verifier_transport_action_back_matched_record_event_verifier_matched_record_event_path =~
             "replay_run_id=#{replay_run_id}"

    assert failed_verifier_transport_action_back_matched_record_event_verifier_matched_record_event_path =~
             "data_source_id=#{replay_sources.operational_data_source_id}"

    assert failed_verifier_transport_action_back_matched_record_event_verifier_matched_record_event_path =~
             "source_binding_id=#{replay_sources.operational_binding_id}"

    assert has_element?(
             reopened_back_record_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="operational_event"][data-data-link-target-id="#{action_event_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    assert has_element?(
             reopened_back_record_view,
             ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=operational_event"][data-clipboard-text*="selected_id=#{action_event_route_id}"][data-clipboard-text*="selected_time=#{failed_verifier_transport_action_event_verifier_matched_record_event_at_ms_text}"][data-clipboard-text*="nav_from_target=transport_action_request"][data-clipboard-text*="nav_from_target_id=transport-action-request-1"][data-clipboard-text*="replay_run_id=#{replay_run_id}"][data-clipboard-text*="data_source_id=#{replay_sources.operational_data_source_id}"][data-clipboard-text*="source_binding_id=#{replay_sources.operational_binding_id}"])
           )

    failed_verifier_transport_action_back_matched_record_event_verifier_matched_record_event_copied_path =
      reopened_back_record_view
      |> render()
      |> element_attribute("#dashboard-data-link-copy-link", "data-clipboard-text")

    assert failed_verifier_transport_action_back_matched_record_event_verifier_matched_record_event_copied_path =~
             "panel=data_link"

    assert failed_verifier_transport_action_back_matched_record_event_verifier_matched_record_event_copied_path =~
             "selected_target=operational_event"

    assert failed_verifier_transport_action_back_matched_record_event_verifier_matched_record_event_copied_path =~
             "selected_id=#{action_event_route_id}"

    assert failed_verifier_transport_action_back_matched_record_event_verifier_matched_record_event_copied_path =~
             "selected_time=#{failed_verifier_transport_action_event_verifier_matched_record_event_at_ms_text}"

    assert failed_verifier_transport_action_back_matched_record_event_verifier_matched_record_event_copied_path =~
             "nav_from_target=transport_action_request"

    assert failed_verifier_transport_action_back_matched_record_event_verifier_matched_record_event_copied_path =~
             "nav_from_target_id=transport-action-request-1"

    assert failed_verifier_transport_action_back_matched_record_event_verifier_matched_record_event_copied_path =~
             "replay_run_id=#{replay_run_id}"

    assert failed_verifier_transport_action_back_matched_record_event_verifier_matched_record_event_copied_path =~
             "data_source_id=#{replay_sources.operational_data_source_id}"

    assert failed_verifier_transport_action_back_matched_record_event_verifier_matched_record_event_copied_path =~
             "source_binding_id=#{replay_sources.operational_binding_id}"

    {:ok, reopened_back_event_view, _html} =
      live(
        conn,
        failed_verifier_transport_action_back_matched_record_event_verifier_matched_record_event_copied_path
      )

    assert has_element?(
             reopened_back_event_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="operational_event"][data-data-link-target-id="#{action_event_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    assert has_element?(
             reopened_back_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-navigation] [data-data-link-nav-entry-id="transport-action-request-1"][phx-value-target="transport_action_request"])
           )

    assert has_element?(
             reopened_back_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-navigation] [data-data-link-nav-entry-id="#{failed_verifier_id}"][phx-value-target="command_verifier_instance"])
           )

    assert has_element?(
             reopened_back_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Transport action request"]),
             "transport-action-request-1"
           )

    assert_transport_action_runtime_context!(
      reopened_back_event_view,
      release_attempt_id,
      release_attempt.command_request_id,
      replay_run_id
    )

    reopened_back_event_view
    |> element(
      ~s(#dashboard-data-link-inspector [data-data-link-navigation] [data-data-link-nav-entry-id="#{failed_verifier_id}"][phx-value-target="command_verifier_instance"])
    )
    |> render_click()

    failed_verifier_transport_action_back_matched_record_event_verifier_matched_record_event_verifier_path =
      assert_patch(reopened_back_event_view)

    assert failed_verifier_transport_action_back_matched_record_event_verifier_matched_record_event_verifier_path =~
             "panel=data_link"

    assert failed_verifier_transport_action_back_matched_record_event_verifier_matched_record_event_verifier_path =~
             "selected_target=command_verifier_instance"

    assert failed_verifier_transport_action_back_matched_record_event_verifier_matched_record_event_verifier_path =~
             "selected_id=#{failed_verifier_id}"

    assert failed_verifier_transport_action_back_matched_record_event_verifier_matched_record_event_verifier_path =~
             "replay_run_id=#{replay_run_id}"

    assert failed_verifier_transport_action_back_matched_record_event_verifier_matched_record_event_verifier_path =~
             "data_source_id=#{replay_sources.operational_data_source_id}"

    assert failed_verifier_transport_action_back_matched_record_event_verifier_matched_record_event_verifier_path =~
             "source_binding_id=#{replay_sources.operational_binding_id}"

    assert has_element?(
             reopened_back_event_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="command_verifier_instance"][data-data-link-target-id="#{failed_verifier_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    assert has_element?(
             reopened_back_event_view,
             ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=command_verifier_instance"][data-clipboard-text*="selected_id=#{failed_verifier_id}"][data-clipboard-text*="replay_run_id=#{replay_run_id}"][data-clipboard-text*="data_source_id=#{replay_sources.operational_data_source_id}"][data-clipboard-text*="source_binding_id=#{replay_sources.operational_binding_id}"])
           )

    deep_event_verifier_copied_path =
      reopened_back_event_view
      |> render()
      |> element_attribute("#dashboard-data-link-copy-link", "data-clipboard-text")

    assert deep_event_verifier_copied_path =~
             "panel=data_link"

    assert deep_event_verifier_copied_path =~
             "selected_target=command_verifier_instance"

    assert deep_event_verifier_copied_path =~
             "selected_id=#{failed_verifier_id}"

    assert deep_event_verifier_copied_path =~
             "replay_run_id=#{replay_run_id}"

    assert deep_event_verifier_copied_path =~
             "data_source_id=#{replay_sources.operational_data_source_id}"

    assert deep_event_verifier_copied_path =~
             "source_binding_id=#{replay_sources.operational_binding_id}"

    {:ok, reopened_deep_event_verifier_view, _html} =
      live(conn, deep_event_verifier_copied_path)

    assert has_element?(
             reopened_deep_event_verifier_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="command_verifier_instance"][data-data-link-target-id="#{failed_verifier_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    assert has_element?(
             reopened_deep_event_verifier_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Command verifier instance"]),
             failed_verifier_id
           )

    assert has_element?(
             reopened_deep_event_verifier_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Lifecycle state"]),
             "failed"
           )

    assert has_element?(
             reopened_deep_event_verifier_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Matched record"]),
             "transport-action-request-1"
           )

    assert has_element?(
             reopened_deep_event_verifier_view,
             failed_verifier_transport_action_related_selector
           )

    reopened_deep_event_verifier_view
    |> element(failed_verifier_transport_action_related_selector)
    |> render_click()

    deep_event_verifier_matched_record_path =
      assert_patch(reopened_deep_event_verifier_view)

    assert deep_event_verifier_matched_record_path =~ "panel=data_link"

    assert deep_event_verifier_matched_record_path =~
             "selected_target=transport_action_request"

    assert deep_event_verifier_matched_record_path =~
             "selected_id=transport-action-request-1"

    assert deep_event_verifier_matched_record_path =~
             "nav_from_target=command_verifier_instance"

    assert deep_event_verifier_matched_record_path =~
             "nav_from_target_id=#{failed_verifier_id}"

    assert deep_event_verifier_matched_record_path =~
             "replay_run_id=#{replay_run_id}"

    assert deep_event_verifier_matched_record_path =~
             "data_source_id=#{replay_sources.operational_data_source_id}"

    assert deep_event_verifier_matched_record_path =~
             "source_binding_id=#{replay_sources.operational_binding_id}"

    assert has_element?(
             reopened_deep_event_verifier_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="transport_action_request"][data-data-link-target-id="transport-action-request-1"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    assert has_element?(
             reopened_deep_event_verifier_view,
             ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=transport_action_request"][data-clipboard-text*="selected_id=transport-action-request-1"][data-clipboard-text*="nav_from_target=command_verifier_instance"][data-clipboard-text*="nav_from_target_id=#{failed_verifier_id}"][data-clipboard-text*="replay_run_id=#{replay_run_id}"][data-clipboard-text*="data_source_id=#{replay_sources.operational_data_source_id}"][data-clipboard-text*="source_binding_id=#{replay_sources.operational_binding_id}"])
           )

    deep_event_verifier_matched_record_copied_path =
      reopened_deep_event_verifier_view
      |> render()
      |> element_attribute("#dashboard-data-link-copy-link", "data-clipboard-text")

    assert deep_event_verifier_matched_record_copied_path =~ "panel=data_link"

    assert deep_event_verifier_matched_record_copied_path =~
             "selected_target=transport_action_request"

    assert deep_event_verifier_matched_record_copied_path =~
             "selected_id=transport-action-request-1"

    assert deep_event_verifier_matched_record_copied_path =~
             "nav_from_target=command_verifier_instance"

    assert deep_event_verifier_matched_record_copied_path =~
             "nav_from_target_id=#{failed_verifier_id}"

    assert deep_event_verifier_matched_record_copied_path =~
             "replay_run_id=#{replay_run_id}"

    assert deep_event_verifier_matched_record_copied_path =~
             "data_source_id=#{replay_sources.operational_data_source_id}"

    assert deep_event_verifier_matched_record_copied_path =~
             "source_binding_id=#{replay_sources.operational_binding_id}"

    {:ok, reopened_deep_event_matched_record_view, _html} =
      live(conn, deep_event_verifier_matched_record_copied_path)

    assert has_element?(
             reopened_deep_event_matched_record_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="transport_action_request"][data-data-link-target-id="transport-action-request-1"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    assert has_element?(
             reopened_deep_event_matched_record_view,
             ~s(#dashboard-data-link-inspector [data-data-link-navigation] [data-data-link-nav-entry-id="#{failed_verifier_id}"][phx-value-target="command_verifier_instance"])
           )

    assert has_element?(
             reopened_deep_event_matched_record_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Transport action request"]),
             "transport-action-request-1"
           )

    assert_transport_action_runtime_context!(
      reopened_deep_event_matched_record_view,
      release_attempt_id,
      release_attempt.command_request_id,
      replay_run_id
    )

    assert has_element?(
             reopened_deep_event_matched_record_view,
             transport_action_event_related_selector
           )

    deep_event_matched_record_event_link =
      reopened_deep_event_matched_record_view
      |> render()
      |> LazyHTML.from_fragment()
      |> LazyHTML.query(transport_action_event_related_selector)

    assert [deep_event_matched_record_event_at_ms_text] =
             LazyHTML.attribute(
               deep_event_matched_record_event_link,
               "phx-value-timestamp-ms"
             )

    reopened_deep_event_matched_record_view
    |> element(transport_action_event_related_selector)
    |> render_click()

    deep_event_matched_record_event_path =
      assert_patch(reopened_deep_event_matched_record_view)

    assert deep_event_matched_record_event_path =~ "panel=data_link"

    assert deep_event_matched_record_event_path =~
             "selected_target=operational_event"

    assert deep_event_matched_record_event_path =~
             "selected_id=#{action_event_route_id}"

    assert deep_event_matched_record_event_path =~
             "selected_time=#{deep_event_matched_record_event_at_ms_text}"

    assert deep_event_matched_record_event_path =~
             "nav_from_target=transport_action_request"

    assert deep_event_matched_record_event_path =~
             "nav_from_target_id=transport-action-request-1"

    assert deep_event_matched_record_event_path =~
             "replay_run_id=#{replay_run_id}"

    assert deep_event_matched_record_event_path =~
             "data_source_id=#{replay_sources.operational_data_source_id}"

    assert deep_event_matched_record_event_path =~
             "source_binding_id=#{replay_sources.operational_binding_id}"

    assert has_element?(
             reopened_deep_event_matched_record_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="operational_event"][data-data-link-target-id="#{action_event_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    assert has_element?(
             reopened_deep_event_matched_record_view,
             ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=operational_event"][data-clipboard-text*="selected_id=#{action_event_route_id}"][data-clipboard-text*="selected_time=#{deep_event_matched_record_event_at_ms_text}"][data-clipboard-text*="nav_from_target=transport_action_request"][data-clipboard-text*="nav_from_target_id=transport-action-request-1"][data-clipboard-text*="replay_run_id=#{replay_run_id}"][data-clipboard-text*="data_source_id=#{replay_sources.operational_data_source_id}"][data-clipboard-text*="source_binding_id=#{replay_sources.operational_binding_id}"])
           )

    deep_event_matched_record_event_copied_path =
      reopened_deep_event_matched_record_view
      |> render()
      |> element_attribute("#dashboard-data-link-copy-link", "data-clipboard-text")

    assert deep_event_matched_record_event_copied_path =~ "panel=data_link"

    assert deep_event_matched_record_event_copied_path =~
             "selected_target=operational_event"

    assert deep_event_matched_record_event_copied_path =~
             "selected_id=#{action_event_route_id}"

    assert deep_event_matched_record_event_copied_path =~
             "selected_time=#{deep_event_matched_record_event_at_ms_text}"

    assert deep_event_matched_record_event_copied_path =~
             "nav_from_target=transport_action_request"

    assert deep_event_matched_record_event_copied_path =~
             "nav_from_target_id=transport-action-request-1"

    assert deep_event_matched_record_event_copied_path =~
             "replay_run_id=#{replay_run_id}"

    assert deep_event_matched_record_event_copied_path =~
             "data_source_id=#{replay_sources.operational_data_source_id}"

    assert deep_event_matched_record_event_copied_path =~
             "source_binding_id=#{replay_sources.operational_binding_id}"

    {:ok, reopened_deep_event_matched_record_event_view, _html} =
      live(conn, deep_event_matched_record_event_copied_path)

    assert has_element?(
             reopened_deep_event_matched_record_event_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="operational_event"][data-data-link-target-id="#{action_event_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    assert has_element?(
             reopened_deep_event_matched_record_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-navigation] [data-data-link-nav-entry-id="transport-action-request-1"][phx-value-target="transport_action_request"])
           )

    assert has_element?(
             reopened_deep_event_matched_record_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-navigation] [data-data-link-nav-entry-id="#{failed_verifier_id}"][phx-value-target="command_verifier_instance"])
           )

    assert has_element?(
             reopened_deep_event_matched_record_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Transport action request"]),
             "transport-action-request-1"
           )

    assert_transport_action_runtime_context!(
      reopened_deep_event_matched_record_event_view,
      release_attempt_id,
      release_attempt.command_request_id,
      replay_run_id
    )

    reopened_deep_event_matched_record_event_view
    |> element(
      ~s(#dashboard-data-link-inspector [data-data-link-navigation] [data-data-link-nav-entry-id="#{failed_verifier_id}"][phx-value-target="command_verifier_instance"])
    )
    |> render_click()

    deep_event_matched_record_event_verifier_path =
      assert_patch(reopened_deep_event_matched_record_event_view)

    assert deep_event_matched_record_event_verifier_path =~ "panel=data_link"

    assert deep_event_matched_record_event_verifier_path =~
             "selected_target=command_verifier_instance"

    assert deep_event_matched_record_event_verifier_path =~
             "selected_id=#{failed_verifier_id}"

    assert deep_event_matched_record_event_verifier_path =~
             "replay_run_id=#{replay_run_id}"

    assert deep_event_matched_record_event_verifier_path =~
             "data_source_id=#{replay_sources.operational_data_source_id}"

    assert deep_event_matched_record_event_verifier_path =~
             "source_binding_id=#{replay_sources.operational_binding_id}"

    assert has_element?(
             reopened_deep_event_matched_record_event_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="command_verifier_instance"][data-data-link-target-id="#{failed_verifier_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    assert has_element?(
             reopened_deep_event_matched_record_event_view,
             ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=command_verifier_instance"][data-clipboard-text*="selected_id=#{failed_verifier_id}"][data-clipboard-text*="replay_run_id=#{replay_run_id}"][data-clipboard-text*="data_source_id=#{replay_sources.operational_data_source_id}"][data-clipboard-text*="source_binding_id=#{replay_sources.operational_binding_id}"])
           )

    deep_event_matched_record_event_verifier_copied_path =
      reopened_deep_event_matched_record_event_view
      |> render()
      |> element_attribute("#dashboard-data-link-copy-link", "data-clipboard-text")

    assert deep_event_matched_record_event_verifier_copied_path =~ "panel=data_link"

    assert deep_event_matched_record_event_verifier_copied_path =~
             "selected_target=command_verifier_instance"

    assert deep_event_matched_record_event_verifier_copied_path =~
             "selected_id=#{failed_verifier_id}"

    assert deep_event_matched_record_event_verifier_copied_path =~
             "replay_run_id=#{replay_run_id}"

    assert deep_event_matched_record_event_verifier_copied_path =~
             "data_source_id=#{replay_sources.operational_data_source_id}"

    assert deep_event_matched_record_event_verifier_copied_path =~
             "source_binding_id=#{replay_sources.operational_binding_id}"

    {:ok, reopened_deep_event_verifier_again_view, _html} =
      live(conn, deep_event_matched_record_event_verifier_copied_path)

    assert has_element?(
             reopened_deep_event_verifier_again_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="command_verifier_instance"][data-data-link-target-id="#{failed_verifier_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    assert has_element?(
             reopened_deep_event_verifier_again_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Command verifier instance"]),
             failed_verifier_id
           )

    assert has_element?(
             reopened_deep_event_verifier_again_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Lifecycle state"]),
             "failed"
           )

    assert has_element?(
             reopened_deep_event_verifier_again_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Matched record"]),
             "transport-action-request-1"
           )

    assert has_element?(
             reopened_deep_event_verifier_again_view,
             failed_verifier_transport_action_related_selector
           )

    reopened_deep_event_verifier_again_view
    |> element(failed_verifier_transport_action_related_selector)
    |> render_click()

    deep_verifier_again_matched_record_path =
      assert_patch(reopened_deep_event_verifier_again_view)

    assert deep_verifier_again_matched_record_path =~ "panel=data_link"

    assert deep_verifier_again_matched_record_path =~
             "selected_target=transport_action_request"

    assert deep_verifier_again_matched_record_path =~
             "selected_id=transport-action-request-1"

    assert deep_verifier_again_matched_record_path =~
             "nav_from_target=command_verifier_instance"

    assert deep_verifier_again_matched_record_path =~
             "nav_from_target_id=#{failed_verifier_id}"

    assert deep_verifier_again_matched_record_path =~
             "replay_run_id=#{replay_run_id}"

    assert deep_verifier_again_matched_record_path =~
             "data_source_id=#{replay_sources.operational_data_source_id}"

    assert deep_verifier_again_matched_record_path =~
             "source_binding_id=#{replay_sources.operational_binding_id}"

    assert has_element?(
             reopened_deep_event_verifier_again_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="transport_action_request"][data-data-link-target-id="transport-action-request-1"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    assert has_element?(
             reopened_deep_event_verifier_again_view,
             ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=transport_action_request"][data-clipboard-text*="selected_id=transport-action-request-1"][data-clipboard-text*="nav_from_target=command_verifier_instance"][data-clipboard-text*="nav_from_target_id=#{failed_verifier_id}"][data-clipboard-text*="replay_run_id=#{replay_run_id}"][data-clipboard-text*="data_source_id=#{replay_sources.operational_data_source_id}"][data-clipboard-text*="source_binding_id=#{replay_sources.operational_binding_id}"])
           )

    deep_verifier_again_matched_record_copied_path =
      reopened_deep_event_verifier_again_view
      |> render()
      |> element_attribute("#dashboard-data-link-copy-link", "data-clipboard-text")

    assert deep_verifier_again_matched_record_copied_path =~
             "panel=data_link"

    assert deep_verifier_again_matched_record_copied_path =~
             "selected_target=transport_action_request"

    assert deep_verifier_again_matched_record_copied_path =~
             "selected_id=transport-action-request-1"

    assert deep_verifier_again_matched_record_copied_path =~
             "nav_from_target=command_verifier_instance"

    assert deep_verifier_again_matched_record_copied_path =~
             "nav_from_target_id=#{failed_verifier_id}"

    assert deep_verifier_again_matched_record_copied_path =~
             "replay_run_id=#{replay_run_id}"

    assert deep_verifier_again_matched_record_copied_path =~
             "data_source_id=#{replay_sources.operational_data_source_id}"

    assert deep_verifier_again_matched_record_copied_path =~
             "source_binding_id=#{replay_sources.operational_binding_id}"

    {:ok, reopened_deep_verifier_again_matched_record_view, _html} =
      live(conn, deep_verifier_again_matched_record_copied_path)

    assert has_element?(
             reopened_deep_verifier_again_matched_record_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="transport_action_request"][data-data-link-target-id="transport-action-request-1"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    assert has_element?(
             reopened_deep_verifier_again_matched_record_view,
             ~s(#dashboard-data-link-inspector [data-data-link-navigation] [data-data-link-nav-entry-id="#{failed_verifier_id}"][phx-value-target="command_verifier_instance"])
           )

    assert has_element?(
             reopened_deep_verifier_again_matched_record_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Transport action request"]),
             "transport-action-request-1"
           )

    assert_transport_action_runtime_context!(
      reopened_deep_verifier_again_matched_record_view,
      release_attempt_id,
      release_attempt.command_request_id,
      replay_run_id
    )

    assert has_element?(
             reopened_deep_verifier_again_matched_record_view,
             transport_action_event_related_selector
           )

    deep_again_matched_record_event_link =
      reopened_deep_verifier_again_matched_record_view
      |> render()
      |> LazyHTML.from_fragment()
      |> LazyHTML.query(transport_action_event_related_selector)

    assert [deep_again_matched_record_event_at_ms_text] =
             LazyHTML.attribute(
               deep_again_matched_record_event_link,
               "phx-value-timestamp-ms"
             )

    reopened_deep_verifier_again_matched_record_view
    |> element(transport_action_event_related_selector)
    |> render_click()

    deep_again_matched_record_event_path =
      assert_patch(reopened_deep_verifier_again_matched_record_view)

    assert deep_again_matched_record_event_path =~ "panel=data_link"

    assert deep_again_matched_record_event_path =~
             "selected_target=operational_event"

    assert deep_again_matched_record_event_path =~
             "selected_id=#{action_event_route_id}"

    assert deep_again_matched_record_event_path =~
             "selected_time=#{deep_again_matched_record_event_at_ms_text}"

    assert deep_again_matched_record_event_path =~
             "nav_from_target=transport_action_request"

    assert deep_again_matched_record_event_path =~
             "nav_from_target_id=transport-action-request-1"

    assert deep_again_matched_record_event_path =~
             "replay_run_id=#{replay_run_id}"

    assert deep_again_matched_record_event_path =~
             "data_source_id=#{replay_sources.operational_data_source_id}"

    assert deep_again_matched_record_event_path =~
             "source_binding_id=#{replay_sources.operational_binding_id}"

    assert has_element?(
             reopened_deep_verifier_again_matched_record_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="operational_event"][data-data-link-target-id="#{action_event_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    assert has_element?(
             reopened_deep_verifier_again_matched_record_view,
             ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=operational_event"][data-clipboard-text*="selected_id=#{action_event_route_id}"][data-clipboard-text*="selected_time=#{deep_again_matched_record_event_at_ms_text}"][data-clipboard-text*="nav_from_target=transport_action_request"][data-clipboard-text*="nav_from_target_id=transport-action-request-1"][data-clipboard-text*="replay_run_id=#{replay_run_id}"][data-clipboard-text*="data_source_id=#{replay_sources.operational_data_source_id}"][data-clipboard-text*="source_binding_id=#{replay_sources.operational_binding_id}"])
           )

    deep_again_matched_record_event_copied_path =
      reopened_deep_verifier_again_matched_record_view
      |> render()
      |> element_attribute("#dashboard-data-link-copy-link", "data-clipboard-text")

    assert deep_again_matched_record_event_copied_path =~ "panel=data_link"

    assert deep_again_matched_record_event_copied_path =~
             "selected_target=operational_event"

    assert deep_again_matched_record_event_copied_path =~
             "selected_id=#{action_event_route_id}"

    assert deep_again_matched_record_event_copied_path =~
             "selected_time=#{deep_again_matched_record_event_at_ms_text}"

    assert deep_again_matched_record_event_copied_path =~
             "nav_from_target=transport_action_request"

    assert deep_again_matched_record_event_copied_path =~
             "nav_from_target_id=transport-action-request-1"

    assert deep_again_matched_record_event_copied_path =~
             "replay_run_id=#{replay_run_id}"

    assert deep_again_matched_record_event_copied_path =~
             "data_source_id=#{replay_sources.operational_data_source_id}"

    assert deep_again_matched_record_event_copied_path =~
             "source_binding_id=#{replay_sources.operational_binding_id}"

    {:ok, reopened_deep_again_matched_record_event_view, _html} =
      live(conn, deep_again_matched_record_event_copied_path)

    assert has_element?(
             reopened_deep_again_matched_record_event_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="operational_event"][data-data-link-target-id="#{action_event_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    assert has_element?(
             reopened_deep_again_matched_record_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-navigation] [data-data-link-nav-entry-id="transport-action-request-1"][phx-value-target="transport_action_request"])
           )

    assert has_element?(
             reopened_deep_again_matched_record_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-navigation] [data-data-link-nav-entry-id="#{failed_verifier_id}"][phx-value-target="command_verifier_instance"])
           )

    assert has_element?(
             reopened_deep_again_matched_record_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Transport action request"]),
             "transport-action-request-1"
           )

    assert_transport_action_runtime_context!(
      reopened_deep_again_matched_record_event_view,
      release_attempt_id,
      release_attempt.command_request_id,
      replay_run_id
    )

    reopened_deep_again_matched_record_event_view
    |> element(
      ~s(#dashboard-data-link-inspector [data-data-link-navigation] [data-data-link-nav-entry-id="#{failed_verifier_id}"][phx-value-target="command_verifier_instance"])
    )
    |> render_click()

    deep_again_event_verifier_path =
      assert_patch(reopened_deep_again_matched_record_event_view)

    assert deep_again_event_verifier_path =~ "panel=data_link"

    assert deep_again_event_verifier_path =~
             "selected_target=command_verifier_instance"

    assert deep_again_event_verifier_path =~
             "selected_id=#{failed_verifier_id}"

    assert deep_again_event_verifier_path =~
             "replay_run_id=#{replay_run_id}"

    assert deep_again_event_verifier_path =~
             "data_source_id=#{replay_sources.operational_data_source_id}"

    assert deep_again_event_verifier_path =~
             "source_binding_id=#{replay_sources.operational_binding_id}"

    assert has_element?(
             reopened_deep_again_matched_record_event_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="command_verifier_instance"][data-data-link-target-id="#{failed_verifier_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    assert has_element?(
             reopened_deep_again_matched_record_event_view,
             ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=command_verifier_instance"][data-clipboard-text*="selected_id=#{failed_verifier_id}"][data-clipboard-text*="replay_run_id=#{replay_run_id}"][data-clipboard-text*="data_source_id=#{replay_sources.operational_data_source_id}"][data-clipboard-text*="source_binding_id=#{replay_sources.operational_binding_id}"])
           )

    deep_again_event_verifier_copied_path =
      reopened_deep_again_matched_record_event_view
      |> render()
      |> element_attribute("#dashboard-data-link-copy-link", "data-clipboard-text")

    assert deep_again_event_verifier_copied_path =~ "panel=data_link"

    assert deep_again_event_verifier_copied_path =~
             "selected_target=command_verifier_instance"

    assert deep_again_event_verifier_copied_path =~
             "selected_id=#{failed_verifier_id}"

    assert deep_again_event_verifier_copied_path =~
             "replay_run_id=#{replay_run_id}"

    assert deep_again_event_verifier_copied_path =~
             "data_source_id=#{replay_sources.operational_data_source_id}"

    assert deep_again_event_verifier_copied_path =~
             "source_binding_id=#{replay_sources.operational_binding_id}"

    {:ok, reopened_deep_again_event_verifier_view, _html} =
      live(conn, deep_again_event_verifier_copied_path)

    assert has_element?(
             reopened_deep_again_event_verifier_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="command_verifier_instance"][data-data-link-target-id="#{failed_verifier_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    assert has_element?(
             reopened_deep_again_event_verifier_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Command verifier instance"]),
             failed_verifier_id
           )

    assert has_element?(
             reopened_deep_again_event_verifier_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Lifecycle state"]),
             "failed"
           )

    assert has_element?(
             reopened_deep_again_event_verifier_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Matched record"]),
             "transport-action-request-1"
           )

    assert has_element?(
             reopened_deep_again_event_verifier_view,
             failed_verifier_transport_action_related_selector
           )

    reopened_deep_again_event_verifier_view
    |> element(failed_verifier_transport_action_related_selector)
    |> render_click()

    deep_again_event_verifier_matched_record_path =
      assert_patch(reopened_deep_again_event_verifier_view)

    assert deep_again_event_verifier_matched_record_path =~ "panel=data_link"

    assert deep_again_event_verifier_matched_record_path =~
             "selected_target=transport_action_request"

    assert deep_again_event_verifier_matched_record_path =~
             "selected_id=transport-action-request-1"

    assert deep_again_event_verifier_matched_record_path =~
             "nav_from_target=command_verifier_instance"

    assert deep_again_event_verifier_matched_record_path =~
             "nav_from_target_id=#{failed_verifier_id}"

    assert deep_again_event_verifier_matched_record_path =~
             "replay_run_id=#{replay_run_id}"

    assert deep_again_event_verifier_matched_record_path =~
             "data_source_id=#{replay_sources.operational_data_source_id}"

    assert deep_again_event_verifier_matched_record_path =~
             "source_binding_id=#{replay_sources.operational_binding_id}"

    assert has_element?(
             reopened_deep_again_event_verifier_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="transport_action_request"][data-data-link-target-id="transport-action-request-1"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    assert has_element?(
             reopened_deep_again_event_verifier_view,
             ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=transport_action_request"][data-clipboard-text*="selected_id=transport-action-request-1"][data-clipboard-text*="nav_from_target=command_verifier_instance"][data-clipboard-text*="nav_from_target_id=#{failed_verifier_id}"][data-clipboard-text*="replay_run_id=#{replay_run_id}"][data-clipboard-text*="data_source_id=#{replay_sources.operational_data_source_id}"][data-clipboard-text*="source_binding_id=#{replay_sources.operational_binding_id}"])
           )

    deep_again_event_verifier_matched_record_copied_path =
      reopened_deep_again_event_verifier_view
      |> render()
      |> element_attribute("#dashboard-data-link-copy-link", "data-clipboard-text")

    assert deep_again_event_verifier_matched_record_copied_path =~
             "panel=data_link"

    assert deep_again_event_verifier_matched_record_copied_path =~
             "selected_target=transport_action_request"

    assert deep_again_event_verifier_matched_record_copied_path =~
             "selected_id=transport-action-request-1"

    assert deep_again_event_verifier_matched_record_copied_path =~
             "nav_from_target=command_verifier_instance"

    assert deep_again_event_verifier_matched_record_copied_path =~
             "nav_from_target_id=#{failed_verifier_id}"

    assert deep_again_event_verifier_matched_record_copied_path =~
             "replay_run_id=#{replay_run_id}"

    assert deep_again_event_verifier_matched_record_copied_path =~
             "data_source_id=#{replay_sources.operational_data_source_id}"

    assert deep_again_event_verifier_matched_record_copied_path =~
             "source_binding_id=#{replay_sources.operational_binding_id}"

    {:ok, reopened_deep_again_event_verifier_matched_record_view, _html} =
      live(conn, deep_again_event_verifier_matched_record_copied_path)

    assert has_element?(
             reopened_deep_again_event_verifier_matched_record_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="transport_action_request"][data-data-link-target-id="transport-action-request-1"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    assert has_element?(
             reopened_deep_again_event_verifier_matched_record_view,
             ~s(#dashboard-data-link-inspector [data-data-link-navigation] [data-data-link-nav-entry-id="#{failed_verifier_id}"][phx-value-target="command_verifier_instance"])
           )

    assert has_element?(
             reopened_deep_again_event_verifier_matched_record_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Transport action request"]),
             "transport-action-request-1"
           )

    assert_transport_action_runtime_context!(
      reopened_deep_again_event_verifier_matched_record_view,
      release_attempt_id,
      release_attempt.command_request_id,
      replay_run_id
    )

    assert has_element?(
             reopened_deep_again_event_verifier_matched_record_view,
             transport_action_event_related_selector
           )

    deep_again_event_verifier_matched_record_event_link =
      reopened_deep_again_event_verifier_matched_record_view
      |> render()
      |> LazyHTML.from_fragment()
      |> LazyHTML.query(transport_action_event_related_selector)

    assert [deep_again_event_verifier_matched_record_event_at_ms_text] =
             LazyHTML.attribute(
               deep_again_event_verifier_matched_record_event_link,
               "phx-value-timestamp-ms"
             )

    reopened_deep_again_event_verifier_matched_record_view
    |> element(transport_action_event_related_selector)
    |> render_click()

    deep_again_event_verifier_matched_record_event_path =
      assert_patch(reopened_deep_again_event_verifier_matched_record_view)

    assert deep_again_event_verifier_matched_record_event_path =~ "panel=data_link"

    assert deep_again_event_verifier_matched_record_event_path =~
             "selected_target=operational_event"

    assert deep_again_event_verifier_matched_record_event_path =~
             "selected_id=#{action_event_route_id}"

    assert deep_again_event_verifier_matched_record_event_path =~
             "selected_time=#{deep_again_event_verifier_matched_record_event_at_ms_text}"

    assert deep_again_event_verifier_matched_record_event_path =~
             "nav_from_target=transport_action_request"

    assert deep_again_event_verifier_matched_record_event_path =~
             "nav_from_target_id=transport-action-request-1"

    assert deep_again_event_verifier_matched_record_event_path =~
             "replay_run_id=#{replay_run_id}"

    assert deep_again_event_verifier_matched_record_event_path =~
             "data_source_id=#{replay_sources.operational_data_source_id}"

    assert deep_again_event_verifier_matched_record_event_path =~
             "source_binding_id=#{replay_sources.operational_binding_id}"

    assert has_element?(
             reopened_deep_again_event_verifier_matched_record_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="operational_event"][data-data-link-target-id="#{action_event_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    assert has_element?(
             reopened_deep_again_event_verifier_matched_record_view,
             ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=operational_event"][data-clipboard-text*="selected_id=#{action_event_route_id}"][data-clipboard-text*="selected_time=#{deep_again_event_verifier_matched_record_event_at_ms_text}"][data-clipboard-text*="nav_from_target=transport_action_request"][data-clipboard-text*="nav_from_target_id=transport-action-request-1"][data-clipboard-text*="replay_run_id=#{replay_run_id}"][data-clipboard-text*="data_source_id=#{replay_sources.operational_data_source_id}"][data-clipboard-text*="source_binding_id=#{replay_sources.operational_binding_id}"])
           )

    deep_again_event_verifier_matched_record_event_copied_path =
      reopened_deep_again_event_verifier_matched_record_view
      |> render()
      |> element_attribute("#dashboard-data-link-copy-link", "data-clipboard-text")

    assert deep_again_event_verifier_matched_record_event_copied_path =~
             "panel=data_link"

    assert deep_again_event_verifier_matched_record_event_copied_path =~
             "selected_target=operational_event"

    assert deep_again_event_verifier_matched_record_event_copied_path =~
             "selected_id=#{action_event_route_id}"

    assert deep_again_event_verifier_matched_record_event_copied_path =~
             "selected_time=#{deep_again_event_verifier_matched_record_event_at_ms_text}"

    assert deep_again_event_verifier_matched_record_event_copied_path =~
             "nav_from_target=transport_action_request"

    assert deep_again_event_verifier_matched_record_event_copied_path =~
             "nav_from_target_id=transport-action-request-1"

    assert deep_again_event_verifier_matched_record_event_copied_path =~
             "replay_run_id=#{replay_run_id}"

    assert deep_again_event_verifier_matched_record_event_copied_path =~
             "data_source_id=#{replay_sources.operational_data_source_id}"

    assert deep_again_event_verifier_matched_record_event_copied_path =~
             "source_binding_id=#{replay_sources.operational_binding_id}"

    {:ok, reopened_deep_again_event_verifier_matched_record_event_view, _html} =
      live(conn, deep_again_event_verifier_matched_record_event_copied_path)

    assert has_element?(
             reopened_deep_again_event_verifier_matched_record_event_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="operational_event"][data-data-link-target-id="#{action_event_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    assert has_element?(
             reopened_deep_again_event_verifier_matched_record_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-navigation] [data-data-link-nav-entry-id="transport-action-request-1"][phx-value-target="transport_action_request"])
           )

    assert has_element?(
             reopened_deep_again_event_verifier_matched_record_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-navigation] [data-data-link-nav-entry-id="#{failed_verifier_id}"][phx-value-target="command_verifier_instance"])
           )

    assert has_element?(
             reopened_deep_again_event_verifier_matched_record_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Transport action request"]),
             "transport-action-request-1"
           )

    assert_transport_action_runtime_context!(
      reopened_deep_again_event_verifier_matched_record_event_view,
      release_attempt_id,
      release_attempt.command_request_id,
      replay_run_id
    )

    reopened_deep_again_event_verifier_matched_record_event_view
    |> element(
      ~s(#dashboard-data-link-inspector [data-data-link-navigation] [data-data-link-nav-entry-id="#{failed_verifier_id}"][phx-value-target="command_verifier_instance"])
    )
    |> render_click()

    deep_again_record_event_verifier_path =
      assert_patch(reopened_deep_again_event_verifier_matched_record_event_view)

    assert deep_again_record_event_verifier_path =~ "panel=data_link"

    assert deep_again_record_event_verifier_path =~
             "selected_target=command_verifier_instance"

    assert deep_again_record_event_verifier_path =~
             "selected_id=#{failed_verifier_id}"

    assert deep_again_record_event_verifier_path =~
             "replay_run_id=#{replay_run_id}"

    assert deep_again_record_event_verifier_path =~
             "data_source_id=#{replay_sources.operational_data_source_id}"

    assert deep_again_record_event_verifier_path =~
             "source_binding_id=#{replay_sources.operational_binding_id}"

    assert has_element?(
             reopened_deep_again_event_verifier_matched_record_event_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="command_verifier_instance"][data-data-link-target-id="#{failed_verifier_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    assert has_element?(
             reopened_deep_again_event_verifier_matched_record_event_view,
             ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=command_verifier_instance"][data-clipboard-text*="selected_id=#{failed_verifier_id}"][data-clipboard-text*="replay_run_id=#{replay_run_id}"][data-clipboard-text*="data_source_id=#{replay_sources.operational_data_source_id}"][data-clipboard-text*="source_binding_id=#{replay_sources.operational_binding_id}"])
           )

    deep_again_record_event_verifier_copied_path =
      reopened_deep_again_event_verifier_matched_record_event_view
      |> render()
      |> element_attribute("#dashboard-data-link-copy-link", "data-clipboard-text")

    assert deep_again_record_event_verifier_copied_path =~ "panel=data_link"

    assert deep_again_record_event_verifier_copied_path =~
             "selected_target=command_verifier_instance"

    assert deep_again_record_event_verifier_copied_path =~
             "selected_id=#{failed_verifier_id}"

    assert deep_again_record_event_verifier_copied_path =~
             "replay_run_id=#{replay_run_id}"

    assert deep_again_record_event_verifier_copied_path =~
             "data_source_id=#{replay_sources.operational_data_source_id}"

    assert deep_again_record_event_verifier_copied_path =~
             "source_binding_id=#{replay_sources.operational_binding_id}"

    {:ok, reopened_deep_again_record_event_verifier_view, _html} =
      live(conn, deep_again_record_event_verifier_copied_path)

    assert has_element?(
             reopened_deep_again_record_event_verifier_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="command_verifier_instance"][data-data-link-target-id="#{failed_verifier_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    assert has_element?(
             reopened_deep_again_record_event_verifier_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Command verifier instance"]),
             failed_verifier_id
           )

    assert has_element?(
             reopened_deep_again_record_event_verifier_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Lifecycle state"]),
             "failed"
           )

    assert has_element?(
             reopened_deep_again_record_event_verifier_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Matched record"]),
             "transport-action-request-1"
           )

    assert has_element?(
             reopened_deep_again_record_event_verifier_view,
             failed_verifier_transport_action_related_selector
           )

    reopened_deep_again_record_event_verifier_view
    |> element(failed_verifier_transport_action_related_selector)
    |> render_click()

    deep_again_record_event_verifier_matched_record_path =
      assert_patch(reopened_deep_again_record_event_verifier_view)

    assert deep_again_record_event_verifier_matched_record_path =~ "panel=data_link"

    assert deep_again_record_event_verifier_matched_record_path =~
             "selected_target=transport_action_request"

    assert deep_again_record_event_verifier_matched_record_path =~
             "selected_id=transport-action-request-1"

    assert deep_again_record_event_verifier_matched_record_path =~
             "nav_from_target=command_verifier_instance"

    assert deep_again_record_event_verifier_matched_record_path =~
             "nav_from_target_id=#{failed_verifier_id}"

    assert deep_again_record_event_verifier_matched_record_path =~
             "replay_run_id=#{replay_run_id}"

    assert deep_again_record_event_verifier_matched_record_path =~
             "data_source_id=#{replay_sources.operational_data_source_id}"

    assert deep_again_record_event_verifier_matched_record_path =~
             "source_binding_id=#{replay_sources.operational_binding_id}"

    assert has_element?(
             reopened_deep_again_record_event_verifier_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="transport_action_request"][data-data-link-target-id="transport-action-request-1"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    assert has_element?(
             reopened_deep_again_record_event_verifier_view,
             ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=transport_action_request"][data-clipboard-text*="selected_id=transport-action-request-1"][data-clipboard-text*="nav_from_target=command_verifier_instance"][data-clipboard-text*="nav_from_target_id=#{failed_verifier_id}"][data-clipboard-text*="replay_run_id=#{replay_run_id}"][data-clipboard-text*="data_source_id=#{replay_sources.operational_data_source_id}"][data-clipboard-text*="source_binding_id=#{replay_sources.operational_binding_id}"])
           )

    deep_again_record_event_verifier_matched_record_copied_path =
      reopened_deep_again_record_event_verifier_view
      |> render()
      |> element_attribute("#dashboard-data-link-copy-link", "data-clipboard-text")

    assert deep_again_record_event_verifier_matched_record_copied_path =~
             "panel=data_link"

    assert deep_again_record_event_verifier_matched_record_copied_path =~
             "selected_target=transport_action_request"

    assert deep_again_record_event_verifier_matched_record_copied_path =~
             "selected_id=transport-action-request-1"

    assert deep_again_record_event_verifier_matched_record_copied_path =~
             "nav_from_target=command_verifier_instance"

    assert deep_again_record_event_verifier_matched_record_copied_path =~
             "nav_from_target_id=#{failed_verifier_id}"

    assert deep_again_record_event_verifier_matched_record_copied_path =~
             "replay_run_id=#{replay_run_id}"

    assert deep_again_record_event_verifier_matched_record_copied_path =~
             "data_source_id=#{replay_sources.operational_data_source_id}"

    assert deep_again_record_event_verifier_matched_record_copied_path =~
             "source_binding_id=#{replay_sources.operational_binding_id}"

    {:ok, reopened_deep_again_record_event_verifier_matched_record_view, _html} =
      live(conn, deep_again_record_event_verifier_matched_record_copied_path)

    assert has_element?(
             reopened_deep_again_record_event_verifier_matched_record_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="transport_action_request"][data-data-link-target-id="transport-action-request-1"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    assert has_element?(
             reopened_deep_again_record_event_verifier_matched_record_view,
             ~s(#dashboard-data-link-inspector [data-data-link-navigation] [data-data-link-nav-entry-id="#{failed_verifier_id}"][phx-value-target="command_verifier_instance"])
           )

    assert has_element?(
             reopened_deep_again_record_event_verifier_matched_record_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Transport action request"]),
             "transport-action-request-1"
           )

    assert_transport_action_runtime_context!(
      reopened_deep_again_record_event_verifier_matched_record_view,
      release_attempt_id,
      release_attempt.command_request_id,
      replay_run_id
    )

    assert has_element?(
             reopened_deep_again_record_event_verifier_matched_record_view,
             transport_action_event_related_selector
           )

    deep_again_record_event_verifier_matched_record_event_link =
      reopened_deep_again_record_event_verifier_matched_record_view
      |> render()
      |> LazyHTML.from_fragment()
      |> LazyHTML.query(transport_action_event_related_selector)

    assert [deep_again_record_event_verifier_matched_record_event_at_ms_text] =
             LazyHTML.attribute(
               deep_again_record_event_verifier_matched_record_event_link,
               "phx-value-timestamp-ms"
             )

    reopened_deep_again_record_event_verifier_matched_record_view
    |> element(transport_action_event_related_selector)
    |> render_click()

    deep_again_record_event_verifier_matched_record_event_path =
      assert_patch(reopened_deep_again_record_event_verifier_matched_record_view)

    assert deep_again_record_event_verifier_matched_record_event_path =~ "panel=data_link"

    assert deep_again_record_event_verifier_matched_record_event_path =~
             "selected_target=operational_event"

    assert deep_again_record_event_verifier_matched_record_event_path =~
             "selected_id=#{action_event_route_id}"

    assert deep_again_record_event_verifier_matched_record_event_path =~
             "selected_time=#{deep_again_record_event_verifier_matched_record_event_at_ms_text}"

    assert deep_again_record_event_verifier_matched_record_event_path =~
             "nav_from_target=transport_action_request"

    assert deep_again_record_event_verifier_matched_record_event_path =~
             "nav_from_target_id=transport-action-request-1"

    assert deep_again_record_event_verifier_matched_record_event_path =~
             "replay_run_id=#{replay_run_id}"

    assert deep_again_record_event_verifier_matched_record_event_path =~
             "data_source_id=#{replay_sources.operational_data_source_id}"

    assert deep_again_record_event_verifier_matched_record_event_path =~
             "source_binding_id=#{replay_sources.operational_binding_id}"

    assert has_element?(
             reopened_deep_again_record_event_verifier_matched_record_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="operational_event"][data-data-link-target-id="#{action_event_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    assert has_element?(
             reopened_deep_again_record_event_verifier_matched_record_view,
             ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=operational_event"][data-clipboard-text*="selected_id=#{action_event_route_id}"][data-clipboard-text*="selected_time=#{deep_again_record_event_verifier_matched_record_event_at_ms_text}"][data-clipboard-text*="nav_from_target=transport_action_request"][data-clipboard-text*="nav_from_target_id=transport-action-request-1"][data-clipboard-text*="replay_run_id=#{replay_run_id}"][data-clipboard-text*="data_source_id=#{replay_sources.operational_data_source_id}"][data-clipboard-text*="source_binding_id=#{replay_sources.operational_binding_id}"])
           )

    deep_again_record_event_verifier_matched_record_event_copied_path =
      reopened_deep_again_record_event_verifier_matched_record_view
      |> render()
      |> element_attribute("#dashboard-data-link-copy-link", "data-clipboard-text")

    assert deep_again_record_event_verifier_matched_record_event_copied_path =~
             "panel=data_link"

    assert deep_again_record_event_verifier_matched_record_event_copied_path =~
             "selected_target=operational_event"

    assert deep_again_record_event_verifier_matched_record_event_copied_path =~
             "selected_id=#{action_event_route_id}"

    assert deep_again_record_event_verifier_matched_record_event_copied_path =~
             "selected_time=#{deep_again_record_event_verifier_matched_record_event_at_ms_text}"

    assert deep_again_record_event_verifier_matched_record_event_copied_path =~
             "nav_from_target=transport_action_request"

    assert deep_again_record_event_verifier_matched_record_event_copied_path =~
             "nav_from_target_id=transport-action-request-1"

    assert deep_again_record_event_verifier_matched_record_event_copied_path =~
             "replay_run_id=#{replay_run_id}"

    assert deep_again_record_event_verifier_matched_record_event_copied_path =~
             "data_source_id=#{replay_sources.operational_data_source_id}"

    assert deep_again_record_event_verifier_matched_record_event_copied_path =~
             "source_binding_id=#{replay_sources.operational_binding_id}"

    {:ok, reopened_deep_again_record_event_verifier_matched_record_event_view, _html} =
      live(conn, deep_again_record_event_verifier_matched_record_event_copied_path)

    assert has_element?(
             reopened_deep_again_record_event_verifier_matched_record_event_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="operational_event"][data-data-link-target-id="#{action_event_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    assert has_element?(
             reopened_deep_again_record_event_verifier_matched_record_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-navigation] [data-data-link-nav-entry-id="transport-action-request-1"][phx-value-target="transport_action_request"])
           )

    assert has_element?(
             reopened_deep_again_record_event_verifier_matched_record_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-navigation] [data-data-link-nav-entry-id="#{failed_verifier_id}"][phx-value-target="command_verifier_instance"])
           )

    assert has_element?(
             reopened_deep_again_record_event_verifier_matched_record_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Transport action request"]),
             "transport-action-request-1"
           )

    assert_transport_action_runtime_context!(
      reopened_deep_again_record_event_verifier_matched_record_event_view,
      release_attempt_id,
      release_attempt.command_request_id,
      replay_run_id
    )

    reopened_deep_again_record_event_verifier_matched_record_event_view
    |> element(
      ~s(#dashboard-data-link-inspector [data-data-link-navigation] [data-data-link-nav-entry-id="#{failed_verifier_id}"][phx-value-target="command_verifier_instance"])
    )
    |> render_click()

    deep_again_record_event_verifier_matched_record_event_verifier_path =
      assert_patch(reopened_deep_again_record_event_verifier_matched_record_event_view)

    assert deep_again_record_event_verifier_matched_record_event_verifier_path =~
             "panel=data_link"

    assert deep_again_record_event_verifier_matched_record_event_verifier_path =~
             "selected_target=command_verifier_instance"

    assert deep_again_record_event_verifier_matched_record_event_verifier_path =~
             "selected_id=#{failed_verifier_id}"

    assert deep_again_record_event_verifier_matched_record_event_verifier_path =~
             "replay_run_id=#{replay_run_id}"

    assert deep_again_record_event_verifier_matched_record_event_verifier_path =~
             "data_source_id=#{replay_sources.operational_data_source_id}"

    assert deep_again_record_event_verifier_matched_record_event_verifier_path =~
             "source_binding_id=#{replay_sources.operational_binding_id}"

    assert has_element?(
             reopened_deep_again_record_event_verifier_matched_record_event_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="command_verifier_instance"][data-data-link-target-id="#{failed_verifier_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    assert has_element?(
             reopened_deep_again_record_event_verifier_matched_record_event_view,
             ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=command_verifier_instance"][data-clipboard-text*="selected_id=#{failed_verifier_id}"][data-clipboard-text*="replay_run_id=#{replay_run_id}"][data-clipboard-text*="data_source_id=#{replay_sources.operational_data_source_id}"][data-clipboard-text*="source_binding_id=#{replay_sources.operational_binding_id}"])
           )

    deep_again_record_event_verifier_matched_record_event_verifier_copied_path =
      reopened_deep_again_record_event_verifier_matched_record_event_view
      |> render()
      |> element_attribute("#dashboard-data-link-copy-link", "data-clipboard-text")

    assert deep_again_record_event_verifier_matched_record_event_verifier_copied_path =~
             "panel=data_link"

    assert deep_again_record_event_verifier_matched_record_event_verifier_copied_path =~
             "selected_target=command_verifier_instance"

    assert deep_again_record_event_verifier_matched_record_event_verifier_copied_path =~
             "selected_id=#{failed_verifier_id}"

    assert deep_again_record_event_verifier_matched_record_event_verifier_copied_path =~
             "replay_run_id=#{replay_run_id}"

    assert deep_again_record_event_verifier_matched_record_event_verifier_copied_path =~
             "data_source_id=#{replay_sources.operational_data_source_id}"

    assert deep_again_record_event_verifier_matched_record_event_verifier_copied_path =~
             "source_binding_id=#{replay_sources.operational_binding_id}"

    {:ok, reopened_record_verifier_view, _html} =
      live(conn, deep_again_record_event_verifier_matched_record_event_verifier_copied_path)

    assert has_element?(
             reopened_record_verifier_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="command_verifier_instance"][data-data-link-target-id="#{failed_verifier_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    assert has_element?(
             reopened_record_verifier_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Command verifier instance"]),
             failed_verifier_id
           )

    assert has_element?(
             reopened_record_verifier_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Lifecycle state"]),
             "failed"
           )

    assert has_element?(
             reopened_record_verifier_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Matched record"]),
             "transport-action-request-1"
           )

    assert has_element?(
             reopened_record_verifier_view,
             failed_verifier_transport_action_related_selector
           )

    reopened_record_verifier_view
    |> element(failed_verifier_transport_action_related_selector)
    |> render_click()

    deep_again_record_event_verifier_matched_record_event_verifier_matched_record_path =
      assert_patch(reopened_record_verifier_view)

    assert deep_again_record_event_verifier_matched_record_event_verifier_matched_record_path =~
             "panel=data_link"

    assert deep_again_record_event_verifier_matched_record_event_verifier_matched_record_path =~
             "selected_target=transport_action_request"

    assert deep_again_record_event_verifier_matched_record_event_verifier_matched_record_path =~
             "selected_id=transport-action-request-1"

    assert deep_again_record_event_verifier_matched_record_event_verifier_matched_record_path =~
             "nav_from_target=command_verifier_instance"

    assert deep_again_record_event_verifier_matched_record_event_verifier_matched_record_path =~
             "nav_from_target_id=#{failed_verifier_id}"

    assert deep_again_record_event_verifier_matched_record_event_verifier_matched_record_path =~
             "replay_run_id=#{replay_run_id}"

    assert deep_again_record_event_verifier_matched_record_event_verifier_matched_record_path =~
             "data_source_id=#{replay_sources.operational_data_source_id}"

    assert deep_again_record_event_verifier_matched_record_event_verifier_matched_record_path =~
             "source_binding_id=#{replay_sources.operational_binding_id}"

    assert has_element?(
             reopened_record_verifier_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="transport_action_request"][data-data-link-target-id="transport-action-request-1"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    assert has_element?(
             reopened_record_verifier_view,
             ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=transport_action_request"][data-clipboard-text*="selected_id=transport-action-request-1"][data-clipboard-text*="nav_from_target=command_verifier_instance"][data-clipboard-text*="nav_from_target_id=#{failed_verifier_id}"][data-clipboard-text*="replay_run_id=#{replay_run_id}"][data-clipboard-text*="data_source_id=#{replay_sources.operational_data_source_id}"][data-clipboard-text*="source_binding_id=#{replay_sources.operational_binding_id}"])
           )

    deep_again_record_event_verifier_matched_record_event_verifier_matched_record_copied_path =
      reopened_record_verifier_view
      |> render()
      |> element_attribute("#dashboard-data-link-copy-link", "data-clipboard-text")

    assert deep_again_record_event_verifier_matched_record_event_verifier_matched_record_copied_path =~
             "panel=data_link"

    assert deep_again_record_event_verifier_matched_record_event_verifier_matched_record_copied_path =~
             "selected_target=transport_action_request"

    assert deep_again_record_event_verifier_matched_record_event_verifier_matched_record_copied_path =~
             "selected_id=transport-action-request-1"

    assert deep_again_record_event_verifier_matched_record_event_verifier_matched_record_copied_path =~
             "nav_from_target=command_verifier_instance"

    assert deep_again_record_event_verifier_matched_record_event_verifier_matched_record_copied_path =~
             "nav_from_target_id=#{failed_verifier_id}"

    assert deep_again_record_event_verifier_matched_record_event_verifier_matched_record_copied_path =~
             "replay_run_id=#{replay_run_id}"

    assert deep_again_record_event_verifier_matched_record_event_verifier_matched_record_copied_path =~
             "data_source_id=#{replay_sources.operational_data_source_id}"

    assert deep_again_record_event_verifier_matched_record_event_verifier_matched_record_copied_path =~
             "source_binding_id=#{replay_sources.operational_binding_id}"

    {:ok, reopened_verifier_record_view, _html} =
      live(
        conn,
        deep_again_record_event_verifier_matched_record_event_verifier_matched_record_copied_path
      )

    assert has_element?(
             reopened_verifier_record_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="transport_action_request"][data-data-link-target-id="transport-action-request-1"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    assert has_element?(
             reopened_verifier_record_view,
             ~s(#dashboard-data-link-inspector [data-data-link-navigation] [data-data-link-nav-entry-id="#{failed_verifier_id}"][phx-value-target="command_verifier_instance"])
           )

    assert has_element?(
             reopened_verifier_record_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Transport action request"]),
             "transport-action-request-1"
           )

    assert_transport_action_runtime_context!(
      reopened_verifier_record_view,
      release_attempt_id,
      release_attempt.command_request_id,
      replay_run_id
    )

    assert has_element?(
             reopened_verifier_record_view,
             transport_action_event_related_selector
           )

    deep_again_record_event_verifier_matched_record_event_verifier_matched_record_event_link =
      reopened_verifier_record_view
      |> render()
      |> LazyHTML.from_fragment()
      |> LazyHTML.query(transport_action_event_related_selector)

    assert [
             deep_again_record_event_verifier_matched_record_event_verifier_matched_record_event_at_ms_text
           ] =
             LazyHTML.attribute(
               deep_again_record_event_verifier_matched_record_event_verifier_matched_record_event_link,
               "phx-value-timestamp-ms"
             )

    reopened_verifier_record_view
    |> element(transport_action_event_related_selector)
    |> render_click()

    deep_again_record_event_verifier_matched_record_event_verifier_matched_record_event_path =
      assert_patch(reopened_verifier_record_view)

    assert deep_again_record_event_verifier_matched_record_event_verifier_matched_record_event_path =~
             "panel=data_link"

    assert deep_again_record_event_verifier_matched_record_event_verifier_matched_record_event_path =~
             "selected_target=operational_event"

    assert deep_again_record_event_verifier_matched_record_event_verifier_matched_record_event_path =~
             "selected_id=#{action_event_route_id}"

    assert deep_again_record_event_verifier_matched_record_event_verifier_matched_record_event_path =~
             "selected_time=#{deep_again_record_event_verifier_matched_record_event_verifier_matched_record_event_at_ms_text}"

    assert deep_again_record_event_verifier_matched_record_event_verifier_matched_record_event_path =~
             "nav_from_target=transport_action_request"

    assert deep_again_record_event_verifier_matched_record_event_verifier_matched_record_event_path =~
             "nav_from_target_id=transport-action-request-1"

    assert deep_again_record_event_verifier_matched_record_event_verifier_matched_record_event_path =~
             "replay_run_id=#{replay_run_id}"

    assert deep_again_record_event_verifier_matched_record_event_verifier_matched_record_event_path =~
             "data_source_id=#{replay_sources.operational_data_source_id}"

    assert deep_again_record_event_verifier_matched_record_event_verifier_matched_record_event_path =~
             "source_binding_id=#{replay_sources.operational_binding_id}"

    assert has_element?(
             reopened_verifier_record_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="operational_event"][data-data-link-target-id="#{action_event_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    assert has_element?(
             reopened_verifier_record_view,
             ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=operational_event"][data-clipboard-text*="selected_id=#{action_event_route_id}"][data-clipboard-text*="selected_time=#{deep_again_record_event_verifier_matched_record_event_verifier_matched_record_event_at_ms_text}"][data-clipboard-text*="nav_from_target=transport_action_request"][data-clipboard-text*="nav_from_target_id=transport-action-request-1"][data-clipboard-text*="replay_run_id=#{replay_run_id}"][data-clipboard-text*="data_source_id=#{replay_sources.operational_data_source_id}"][data-clipboard-text*="source_binding_id=#{replay_sources.operational_binding_id}"])
           )

    deep_again_record_event_verifier_matched_record_event_verifier_matched_record_event_copied_path =
      reopened_verifier_record_view
      |> render()
      |> element_attribute("#dashboard-data-link-copy-link", "data-clipboard-text")

    assert deep_again_record_event_verifier_matched_record_event_verifier_matched_record_event_copied_path =~
             "panel=data_link"

    assert deep_again_record_event_verifier_matched_record_event_verifier_matched_record_event_copied_path =~
             "selected_target=operational_event"

    assert deep_again_record_event_verifier_matched_record_event_verifier_matched_record_event_copied_path =~
             "selected_id=#{action_event_route_id}"

    assert deep_again_record_event_verifier_matched_record_event_verifier_matched_record_event_copied_path =~
             "selected_time=#{deep_again_record_event_verifier_matched_record_event_verifier_matched_record_event_at_ms_text}"

    assert deep_again_record_event_verifier_matched_record_event_verifier_matched_record_event_copied_path =~
             "nav_from_target=transport_action_request"

    assert deep_again_record_event_verifier_matched_record_event_verifier_matched_record_event_copied_path =~
             "nav_from_target_id=transport-action-request-1"

    assert deep_again_record_event_verifier_matched_record_event_verifier_matched_record_event_copied_path =~
             "replay_run_id=#{replay_run_id}"

    assert deep_again_record_event_verifier_matched_record_event_verifier_matched_record_event_copied_path =~
             "data_source_id=#{replay_sources.operational_data_source_id}"

    assert deep_again_record_event_verifier_matched_record_event_verifier_matched_record_event_copied_path =~
             "source_binding_id=#{replay_sources.operational_binding_id}"

    {:ok, reopened_verifier_event_view, _html} =
      live(
        conn,
        deep_again_record_event_verifier_matched_record_event_verifier_matched_record_event_copied_path
      )

    assert has_element?(
             reopened_verifier_event_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="operational_event"][data-data-link-target-id="#{action_event_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    assert has_element?(
             reopened_verifier_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-navigation] [data-data-link-nav-entry-id="transport-action-request-1"][phx-value-target="transport_action_request"])
           )

    assert has_element?(
             reopened_verifier_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-navigation] [data-data-link-nav-entry-id="#{failed_verifier_id}"][phx-value-target="command_verifier_instance"])
           )

    assert has_element?(
             reopened_verifier_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Transport action request"]),
             "transport-action-request-1"
           )

    assert_transport_action_runtime_context!(
      reopened_verifier_event_view,
      release_attempt_id,
      release_attempt.command_request_id,
      replay_run_id
    )

    reopened_verifier_event_view
    |> element(
      ~s(#dashboard-data-link-inspector [data-data-link-navigation] [data-data-link-nav-entry-id="#{failed_verifier_id}"][phx-value-target="command_verifier_instance"])
    )
    |> render_click()

    verifier_path =
      assert_patch(reopened_verifier_event_view)

    assert verifier_path =~
             "panel=data_link"

    assert verifier_path =~
             "selected_target=command_verifier_instance"

    assert verifier_path =~
             "selected_id=#{failed_verifier_id}"

    assert verifier_path =~
             "replay_run_id=#{replay_run_id}"

    assert verifier_path =~
             "data_source_id=#{replay_sources.operational_data_source_id}"

    assert verifier_path =~
             "source_binding_id=#{replay_sources.operational_binding_id}"

    assert has_element?(
             reopened_verifier_event_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="command_verifier_instance"][data-data-link-target-id="#{failed_verifier_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    assert has_element?(
             reopened_verifier_event_view,
             ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=command_verifier_instance"][data-clipboard-text*="selected_id=#{failed_verifier_id}"][data-clipboard-text*="replay_run_id=#{replay_run_id}"][data-clipboard-text*="data_source_id=#{replay_sources.operational_data_source_id}"][data-clipboard-text*="source_binding_id=#{replay_sources.operational_binding_id}"])
           )

    verifier_reopen_path =
      reopened_verifier_event_view
      |> render()
      |> element_attribute("#dashboard-data-link-copy-link", "data-clipboard-text")

    assert verifier_reopen_path =~
             "panel=data_link"

    assert verifier_reopen_path =~
             "selected_target=command_verifier_instance"

    assert verifier_reopen_path =~
             "selected_id=#{failed_verifier_id}"

    assert verifier_reopen_path =~
             "replay_run_id=#{replay_run_id}"

    assert verifier_reopen_path =~
             "data_source_id=#{replay_sources.operational_data_source_id}"

    assert verifier_reopen_path =~
             "source_binding_id=#{replay_sources.operational_binding_id}"

    {:ok, reopened_verifier_view, _html} =
      live(
        conn,
        verifier_reopen_path
      )

    assert has_element?(
             reopened_verifier_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="command_verifier_instance"][data-data-link-target-id="#{failed_verifier_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    assert has_element?(
             reopened_verifier_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Command verifier instance"]),
             failed_verifier_id
           )

    assert has_element?(
             reopened_verifier_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Lifecycle state"]),
             "failed"
           )

    assert has_element?(
             reopened_verifier_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Matched record"]),
             "transport-action-request-1"
           )

    assert has_element?(
             reopened_verifier_view,
             failed_verifier_transport_action_related_selector
           )

    reopened_verifier_view
    |> element(failed_verifier_transport_action_related_selector)
    |> render_click()

    action_request_path =
      assert_patch(reopened_verifier_view)

    assert action_request_path =~
             "panel=data_link"

    assert action_request_path =~
             "selected_target=transport_action_request"

    assert action_request_path =~
             "selected_id=transport-action-request-1"

    assert action_request_path =~
             "nav_from_target=command_verifier_instance"

    assert action_request_path =~
             "nav_from_target_id=#{failed_verifier_id}"

    assert action_request_path =~
             "replay_run_id=#{replay_run_id}"

    assert action_request_path =~
             "data_source_id=#{replay_sources.operational_data_source_id}"

    assert action_request_path =~
             "source_binding_id=#{replay_sources.operational_binding_id}"

    assert has_element?(
             reopened_verifier_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="transport_action_request"][data-data-link-target-id="transport-action-request-1"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    assert has_element?(
             reopened_verifier_view,
             ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=transport_action_request"][data-clipboard-text*="selected_id=transport-action-request-1"][data-clipboard-text*="nav_from_target=command_verifier_instance"][data-clipboard-text*="nav_from_target_id=#{failed_verifier_id}"][data-clipboard-text*="replay_run_id=#{replay_run_id}"][data-clipboard-text*="data_source_id=#{replay_sources.operational_data_source_id}"][data-clipboard-text*="source_binding_id=#{replay_sources.operational_binding_id}"])
           )

    action_request_reopen_path =
      reopened_verifier_view
      |> render()
      |> element_attribute("#dashboard-data-link-copy-link", "data-clipboard-text")

    assert action_request_reopen_path =~
             "panel=data_link"

    assert action_request_reopen_path =~
             "selected_target=transport_action_request"

    assert action_request_reopen_path =~
             "selected_id=transport-action-request-1"

    assert action_request_reopen_path =~
             "nav_from_target=command_verifier_instance"

    assert action_request_reopen_path =~
             "nav_from_target_id=#{failed_verifier_id}"

    assert action_request_reopen_path =~
             "replay_run_id=#{replay_run_id}"

    assert action_request_reopen_path =~
             "data_source_id=#{replay_sources.operational_data_source_id}"

    assert action_request_reopen_path =~
             "source_binding_id=#{replay_sources.operational_binding_id}"

    {:ok, reopened_action_request_view, _html} =
      live(
        conn,
        action_request_reopen_path
      )

    assert has_element?(
             reopened_action_request_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="transport_action_request"][data-data-link-target-id="transport-action-request-1"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    assert has_element?(
             reopened_action_request_view,
             ~s(#dashboard-data-link-inspector [data-data-link-navigation] [data-data-link-nav-entry-id="#{failed_verifier_id}"][phx-value-target="command_verifier_instance"])
           )

    assert has_element?(
             reopened_action_request_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Transport action request"]),
             "transport-action-request-1"
           )

    assert_transport_action_runtime_context!(
      reopened_action_request_view,
      release_attempt_id,
      release_attempt.command_request_id,
      replay_run_id
    )

    assert has_element?(
             reopened_action_request_view,
             transport_action_event_related_selector
           )

    action_event_link =
      reopened_action_request_view
      |> render()
      |> LazyHTML.from_fragment()
      |> LazyHTML.query(transport_action_event_related_selector)

    assert [
             action_event_at_ms_text
           ] =
             LazyHTML.attribute(
               action_event_link,
               "phx-value-timestamp-ms"
             )

    reopened_action_request_view
    |> element(transport_action_event_related_selector)
    |> render_click()

    action_event_path =
      assert_patch(reopened_action_request_view)

    assert action_event_path =~
             "panel=data_link"

    assert action_event_path =~
             "selected_target=operational_event"

    assert action_event_path =~
             "selected_id=#{action_event_route_id}"

    assert action_event_path =~
             "selected_time=#{action_event_at_ms_text}"

    assert action_event_path =~
             "nav_from_target=transport_action_request"

    assert action_event_path =~
             "nav_from_target_id=transport-action-request-1"

    assert action_event_path =~
             "replay_run_id=#{replay_run_id}"

    assert action_event_path =~
             "data_source_id=#{replay_sources.operational_data_source_id}"

    assert action_event_path =~
             "source_binding_id=#{replay_sources.operational_binding_id}"

    assert has_element?(
             reopened_action_request_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="operational_event"][data-data-link-target-id="#{action_event_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    assert has_element?(
             reopened_action_request_view,
             ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=operational_event"][data-clipboard-text*="selected_id=#{action_event_route_id}"][data-clipboard-text*="selected_time=#{action_event_at_ms_text}"][data-clipboard-text*="nav_from_target=transport_action_request"][data-clipboard-text*="nav_from_target_id=transport-action-request-1"][data-clipboard-text*="replay_run_id=#{replay_run_id}"][data-clipboard-text*="data_source_id=#{replay_sources.operational_data_source_id}"][data-clipboard-text*="source_binding_id=#{replay_sources.operational_binding_id}"])
           )

    action_event_reopen_path =
      reopened_action_request_view
      |> render()
      |> element_attribute("#dashboard-data-link-copy-link", "data-clipboard-text")

    assert action_event_reopen_path =~
             "panel=data_link"

    assert action_event_reopen_path =~
             "selected_target=operational_event"

    assert action_event_reopen_path =~
             "selected_id=#{action_event_route_id}"

    assert action_event_reopen_path =~
             "selected_time=#{action_event_at_ms_text}"

    assert action_event_reopen_path =~
             "nav_from_target=transport_action_request"

    assert action_event_reopen_path =~
             "nav_from_target_id=transport-action-request-1"

    assert action_event_reopen_path =~
             "replay_run_id=#{replay_run_id}"

    assert action_event_reopen_path =~
             "data_source_id=#{replay_sources.operational_data_source_id}"

    assert action_event_reopen_path =~
             "source_binding_id=#{replay_sources.operational_binding_id}"

    {:ok, reopened_action_event_view, _html} =
      live(
        conn,
        action_event_reopen_path
      )

    assert has_element?(
             reopened_action_event_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="operational_event"][data-data-link-target-id="#{action_event_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    assert has_element?(
             reopened_action_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-navigation] [data-data-link-nav-entry-id="transport-action-request-1"][phx-value-target="transport_action_request"])
           )

    assert has_element?(
             reopened_action_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-navigation] [data-data-link-nav-entry-id="#{failed_verifier_id}"][phx-value-target="command_verifier_instance"])
           )

    assert has_element?(
             reopened_action_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Transport action request"]),
             "transport-action-request-1"
           )

    assert_transport_action_runtime_context!(
      reopened_action_event_view,
      release_attempt_id,
      release_attempt.command_request_id,
      replay_run_id
    )

    stop_dashboard_view(reopened_action_event_view)

    stop_dashboard_view(reopened_action_request_view)

    stop_dashboard_view(reopened_verifier_view)

    stop_dashboard_view(reopened_verifier_event_view)

    stop_dashboard_view(reopened_verifier_record_view)

    stop_dashboard_view(reopened_record_verifier_view)

    stop_dashboard_view(reopened_deep_again_record_event_verifier_matched_record_event_view)

    stop_dashboard_view(reopened_deep_again_record_event_verifier_matched_record_view)

    stop_dashboard_view(reopened_deep_again_record_event_verifier_view)

    stop_dashboard_view(reopened_deep_again_event_verifier_matched_record_event_view)

    stop_dashboard_view(reopened_deep_again_event_verifier_matched_record_view)

    stop_dashboard_view(reopened_deep_again_event_verifier_view)

    stop_dashboard_view(reopened_deep_again_matched_record_event_view)

    stop_dashboard_view(reopened_deep_verifier_again_matched_record_view)

    stop_dashboard_view(reopened_deep_event_verifier_again_view)

    stop_dashboard_view(reopened_deep_event_matched_record_event_view)

    stop_dashboard_view(reopened_deep_event_matched_record_view)

    stop_dashboard_view(reopened_deep_event_verifier_view)

    stop_dashboard_view(reopened_back_event_view)

    stop_dashboard_view(reopened_back_record_view)

    stop_dashboard_view(reopened_back_verifier_view)

    stop_dashboard_view(reopened_transport_action_event_view)

    stop_dashboard_view(reopened_failed_verifier_transport_action_back_matched_record_view)

    stop_dashboard_view(reopened_failed_verifier_transport_action_back_view)

    stop_dashboard_view(reopened_failed_verifier_transport_action_view)

    view
    |> element(action_row_selector <> ~s( [data-state-timeline-row-evidence]))
    |> render_click()

    assert_patch(view)

    capability_verifier_evidence_selector =
      ~s(#dashboard-evidence-inspector [data-evidence-ref-kind="command verifier instance"][data-evidence-ref-id="#{capability_verifier_instance.command_verifier_instance_id}"])

    capability_verifier_id = capability_verifier_instance.command_verifier_instance_id
    capability_related_id = "transport-runtime-record-1"

    capability_verifier_matched_at_ms =
      DateTime.to_unix(capability_verifier_instance.matched_at, :millisecond)

    capability_verifier_evidence =
      view
      |> render()
      |> LazyHTML.from_fragment()
      |> LazyHTML.query(capability_verifier_evidence_selector)

    assert ["command_verifier_instance"] =
             LazyHTML.attribute(capability_verifier_evidence, "phx-value-target")

    assert [^capability_verifier_id] =
             LazyHTML.attribute(capability_verifier_evidence, "phx-value-target-id")

    assert [capability_verifier_matched_at_ms_text] =
             LazyHTML.attribute(capability_verifier_evidence, "phx-value-timestamp-ms")

    assert capability_verifier_matched_at_ms_text ==
             Integer.to_string(capability_verifier_matched_at_ms)

    view
    |> element(capability_verifier_evidence_selector)
    |> render_click(%{
      "link-id" => "evidence-ref:command_verifier_instance:#{capability_verifier_id}",
      "target" => "command_verifier_instance",
      "target-id" => capability_verifier_id,
      "timestamp-ms" => capability_verifier_matched_at_ms,
      "realm" => "replay",
      "time-mode" => "replay_run",
      "replay-run-id" => replay_run_id,
      "data-source-id" => replay_sources.operational_data_source_id,
      "source-binding-id" => replay_sources.operational_binding_id
    })

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="command_verifier_instance"][data-data-link-target-id="#{capability_verifier_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    capability_verifier_path = assert_patch(view)
    assert capability_verifier_path =~ "panel=data_link"
    assert capability_verifier_path =~ "selected_target=command_verifier_instance"
    assert capability_verifier_path =~ "selected_id=#{capability_verifier_id}"
    assert capability_verifier_path =~ "selected_time=#{capability_verifier_matched_at_ms}"
    assert capability_verifier_path =~ "replay_run_id=#{replay_run_id}"

    capability_verifier_copied_path =
      view
      |> render()
      |> element_attribute("#dashboard-data-link-copy-link", "data-clipboard-text")

    assert capability_verifier_copied_path =~ "panel=data_link"
    assert capability_verifier_copied_path =~ "selected_target=command_verifier_instance"
    assert capability_verifier_copied_path =~ "selected_id=#{capability_verifier_id}"
    assert capability_verifier_copied_path =~ "selected_time=#{capability_verifier_matched_at_ms}"
    assert capability_verifier_copied_path =~ "replay_run_id=#{replay_run_id}"

    assert capability_verifier_copied_path =~
             "data_source_id=#{replay_sources.operational_data_source_id}"

    assert capability_verifier_copied_path =~
             "source_binding_id=#{replay_sources.operational_binding_id}"

    {:ok, reopened_capability_verifier_view, _html} = live(conn, capability_verifier_copied_path)

    assert has_element?(
             reopened_capability_verifier_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="command_verifier_instance"][data-data-link-target-id="#{capability_verifier_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    assert has_element?(
             reopened_capability_verifier_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Command verifier instance"]),
             capability_verifier_id
           )

    assert has_element?(
             reopened_capability_verifier_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Matched record"]),
             capability_related_id
           )

    capability_verifier_transport_capability_related_selector =
      ~s(#dashboard-data-link-inspector [data-data-link-related-target="transport capability record"][data-data-link-related-id="#{capability_related_id}"])

    assert has_element?(
             reopened_capability_verifier_view,
             capability_verifier_transport_capability_related_selector
           )

    reopened_capability_verifier_view
    |> element(capability_verifier_transport_capability_related_selector)
    |> render_click()

    capability_verifier_transport_capability_path =
      assert_patch(reopened_capability_verifier_view)

    assert capability_verifier_transport_capability_path =~ "panel=data_link"

    assert capability_verifier_transport_capability_path =~
             "selected_target=transport_capability_record"

    assert capability_verifier_transport_capability_path =~
             "selected_id=#{capability_related_id}"

    assert capability_verifier_transport_capability_path =~
             "nav_from_target=command_verifier_instance"

    assert capability_verifier_transport_capability_path =~
             "nav_from_target_id=#{capability_verifier_id}"

    assert capability_verifier_transport_capability_path =~ "nav_trail="
    assert capability_verifier_transport_capability_path =~ "replay_run_id=#{replay_run_id}"

    assert capability_verifier_transport_capability_path =~
             "data_source_id=#{replay_sources.operational_data_source_id}"

    assert capability_verifier_transport_capability_path =~
             "source_binding_id=#{replay_sources.operational_binding_id}"

    assert has_element?(
             reopened_capability_verifier_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="transport_capability_record"][data-data-link-target-id="#{capability_related_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    assert has_element?(
             reopened_capability_verifier_view,
             ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=transport_capability_record"][data-clipboard-text*="selected_id=#{capability_related_id}"][data-clipboard-text*="nav_from_target=command_verifier_instance"][data-clipboard-text*="nav_from_target_id=#{capability_verifier_id}"][data-clipboard-text*="replay_run_id=#{replay_run_id}"][data-clipboard-text*="data_source_id=#{replay_sources.operational_data_source_id}"][data-clipboard-text*="source_binding_id=#{replay_sources.operational_binding_id}"])
           )

    capability_verifier_transport_capability_copied_path =
      reopened_capability_verifier_view
      |> render()
      |> element_attribute("#dashboard-data-link-copy-link", "data-clipboard-text")

    assert capability_verifier_transport_capability_copied_path =~ "panel=data_link"

    assert capability_verifier_transport_capability_copied_path =~
             "selected_target=transport_capability_record"

    assert capability_verifier_transport_capability_copied_path =~
             "selected_id=#{capability_related_id}"

    assert capability_verifier_transport_capability_copied_path =~
             "nav_from_target=command_verifier_instance"

    assert capability_verifier_transport_capability_copied_path =~
             "nav_from_target_id=#{capability_verifier_id}"

    assert capability_verifier_transport_capability_copied_path =~
             "replay_run_id=#{replay_run_id}"

    {:ok, reopened_capability_related_view, _html} =
      live(conn, capability_verifier_transport_capability_copied_path)

    assert has_element?(
             reopened_capability_related_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="transport_capability_record"][data-data-link-target-id="#{capability_related_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    assert has_element?(
             reopened_capability_related_view,
             ~s(#dashboard-data-link-inspector [data-data-link-navigation] [data-data-link-nav-entry-id="#{capability_verifier_id}"][phx-value-target="command_verifier_instance"])
           )

    assert has_element?(
             reopened_capability_related_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Transport capability record"]),
             capability_related_id
           )

    assert has_element?(
             reopened_capability_related_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Contact"]),
             "replay-contact-alpha"
           )

    assert has_element?(
             reopened_capability_related_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Capability instance"]),
             "transport-alpha"
           )

    assert has_element?(
             reopened_capability_related_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Replay run"]),
             replay_run_id
           )

    capability_event_id = record_event.event_id
    capability_event_route_id = URI.encode_www_form(capability_event_id)

    capability_event_related_selector =
      ~s(#dashboard-data-link-inspector [data-data-link-related-target="operational event"][data-data-link-related-id="#{capability_event_id}"])

    assert has_element?(
             reopened_capability_related_view,
             capability_event_related_selector
           )

    reopened_capability_related_view
    |> element(capability_event_related_selector)
    |> render_click()

    capability_event_path = assert_patch(reopened_capability_related_view)
    assert capability_event_path =~ "panel=data_link"
    assert capability_event_path =~ "selected_target=operational_event"
    assert capability_event_path =~ "selected_id=#{capability_event_route_id}"
    assert capability_event_path =~ "nav_from_target=transport_capability_record"
    assert capability_event_path =~ "nav_from_target_id=#{capability_related_id}"
    assert capability_event_path =~ "nav_trail="
    assert capability_event_path =~ "replay_run_id=#{replay_run_id}"

    assert capability_event_path =~
             "data_source_id=#{replay_sources.operational_data_source_id}"

    assert capability_event_path =~
             "source_binding_id=#{replay_sources.operational_binding_id}"

    assert has_element?(
             reopened_capability_related_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="operational_event"][data-data-link-target-id="#{capability_event_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    assert has_element?(
             reopened_capability_related_view,
             ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=operational_event"][data-clipboard-text*="selected_id=#{capability_event_route_id}"][data-clipboard-text*="nav_from_target=transport_capability_record"][data-clipboard-text*="nav_from_target_id=#{capability_related_id}"][data-clipboard-text*="replay_run_id=#{replay_run_id}"][data-clipboard-text*="data_source_id=#{replay_sources.operational_data_source_id}"][data-clipboard-text*="source_binding_id=#{replay_sources.operational_binding_id}"])
           )

    capability_event_copied_path =
      reopened_capability_related_view
      |> render()
      |> element_attribute("#dashboard-data-link-copy-link", "data-clipboard-text")

    assert capability_event_copied_path =~ "panel=data_link"
    assert capability_event_copied_path =~ "selected_target=operational_event"
    assert capability_event_copied_path =~ "selected_id=#{capability_event_route_id}"
    assert capability_event_copied_path =~ "nav_from_target=transport_capability_record"
    assert capability_event_copied_path =~ "nav_from_target_id=#{capability_related_id}"
    assert capability_event_copied_path =~ "replay_run_id=#{replay_run_id}"

    {:ok, reopened_capability_event_view, _html} =
      live(conn, capability_event_copied_path)

    assert has_element?(
             reopened_capability_event_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="operational_event"][data-data-link-target-id="#{capability_event_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    assert has_element?(
             reopened_capability_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-navigation] [data-data-link-nav-entry-id="#{capability_related_id}"][phx-value-target="transport_capability_record"])
           )

    assert has_element?(
             reopened_capability_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-navigation] [data-data-link-nav-entry-id="#{capability_verifier_id}"][phx-value-target="command_verifier_instance"])
           )

    assert has_element?(
             reopened_capability_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Transport capability record"]),
             capability_related_id
           )

    assert has_element?(
             reopened_capability_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Event kind"]),
             "control_input_handled"
           )

    assert has_element?(
             reopened_capability_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Replay run"]),
             replay_run_id
           )

    {:ok, reopened_capability_event_verifier_view, _html} =
      live(conn, capability_event_copied_path)

    assert has_element?(
             reopened_capability_event_verifier_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="operational_event"][data-data-link-target-id="#{capability_event_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    reopened_capability_event_verifier_view
    |> element(
      ~s(#dashboard-data-link-inspector [data-data-link-navigation] [data-data-link-nav-entry-id="#{capability_verifier_id}"][phx-value-target="command_verifier_instance"])
    )
    |> render_click()

    capability_event_verifier_back_path =
      assert_patch(reopened_capability_event_verifier_view)

    assert capability_event_verifier_back_path =~ "panel=data_link"

    assert capability_event_verifier_back_path =~
             "selected_target=command_verifier_instance"

    assert capability_event_verifier_back_path =~ "selected_id=#{capability_verifier_id}"
    assert capability_event_verifier_back_path =~ "replay_run_id=#{replay_run_id}"

    assert capability_event_verifier_back_path =~
             "data_source_id=#{replay_sources.operational_data_source_id}"

    assert capability_event_verifier_back_path =~
             "source_binding_id=#{replay_sources.operational_binding_id}"

    assert has_element?(
             reopened_capability_event_verifier_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="command_verifier_instance"][data-data-link-target-id="#{capability_verifier_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    assert has_element?(
             reopened_capability_event_verifier_view,
             ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=command_verifier_instance"][data-clipboard-text*="selected_id=#{capability_verifier_id}"][data-clipboard-text*="replay_run_id=#{replay_run_id}"][data-clipboard-text*="data_source_id=#{replay_sources.operational_data_source_id}"][data-clipboard-text*="source_binding_id=#{replay_sources.operational_binding_id}"])
           )

    capability_event_verifier_back_copied_path =
      reopened_capability_event_verifier_view
      |> render()
      |> element_attribute("#dashboard-data-link-copy-link", "data-clipboard-text")

    assert capability_event_verifier_back_copied_path =~ "panel=data_link"

    assert capability_event_verifier_back_copied_path =~
             "selected_target=command_verifier_instance"

    assert capability_event_verifier_back_copied_path =~
             "selected_id=#{capability_verifier_id}"

    assert capability_event_verifier_back_copied_path =~ "replay_run_id=#{replay_run_id}"

    assert capability_event_verifier_back_copied_path =~
             "data_source_id=#{replay_sources.operational_data_source_id}"

    assert capability_event_verifier_back_copied_path =~
             "source_binding_id=#{replay_sources.operational_binding_id}"

    {:ok, reopened_capability_event_verifier_back_view, _html} =
      live(conn, capability_event_verifier_back_copied_path)

    assert has_element?(
             reopened_capability_event_verifier_back_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="command_verifier_instance"][data-data-link-target-id="#{capability_verifier_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    assert has_element?(
             reopened_capability_event_verifier_back_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Command verifier instance"]),
             capability_verifier_id
           )

    assert has_element?(
             reopened_capability_event_verifier_back_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Matched record"]),
             capability_related_id
           )

    assert has_element?(
             reopened_capability_event_verifier_back_view,
             capability_verifier_transport_capability_related_selector
           )

    reopened_capability_event_verifier_back_view
    |> element(capability_verifier_transport_capability_related_selector)
    |> render_click()

    capability_event_verifier_matched_record_path =
      assert_patch(reopened_capability_event_verifier_back_view)

    assert capability_event_verifier_matched_record_path =~ "panel=data_link"

    assert capability_event_verifier_matched_record_path =~
             "selected_target=transport_capability_record"

    assert capability_event_verifier_matched_record_path =~
             "selected_id=#{capability_related_id}"

    assert capability_event_verifier_matched_record_path =~
             "nav_from_target=command_verifier_instance"

    assert capability_event_verifier_matched_record_path =~
             "nav_from_target_id=#{capability_verifier_id}"

    assert capability_event_verifier_matched_record_path =~ "replay_run_id=#{replay_run_id}"

    assert capability_event_verifier_matched_record_path =~
             "data_source_id=#{replay_sources.operational_data_source_id}"

    assert capability_event_verifier_matched_record_path =~
             "source_binding_id=#{replay_sources.operational_binding_id}"

    assert has_element?(
             reopened_capability_event_verifier_back_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="transport_capability_record"][data-data-link-target-id="#{capability_related_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    assert has_element?(
             reopened_capability_event_verifier_back_view,
             ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=transport_capability_record"][data-clipboard-text*="selected_id=#{capability_related_id}"][data-clipboard-text*="nav_from_target=command_verifier_instance"][data-clipboard-text*="nav_from_target_id=#{capability_verifier_id}"][data-clipboard-text*="replay_run_id=#{replay_run_id}"][data-clipboard-text*="data_source_id=#{replay_sources.operational_data_source_id}"][data-clipboard-text*="source_binding_id=#{replay_sources.operational_binding_id}"])
           )

    capability_event_verifier_matched_record_copied_path =
      reopened_capability_event_verifier_back_view
      |> render()
      |> element_attribute("#dashboard-data-link-copy-link", "data-clipboard-text")

    assert capability_event_verifier_matched_record_copied_path =~ "panel=data_link"

    assert capability_event_verifier_matched_record_copied_path =~
             "selected_target=transport_capability_record"

    assert capability_event_verifier_matched_record_copied_path =~
             "selected_id=#{capability_related_id}"

    assert capability_event_verifier_matched_record_copied_path =~
             "nav_from_target=command_verifier_instance"

    assert capability_event_verifier_matched_record_copied_path =~
             "nav_from_target_id=#{capability_verifier_id}"

    assert capability_event_verifier_matched_record_copied_path =~
             "replay_run_id=#{replay_run_id}"

    assert capability_event_verifier_matched_record_copied_path =~
             "data_source_id=#{replay_sources.operational_data_source_id}"

    assert capability_event_verifier_matched_record_copied_path =~
             "source_binding_id=#{replay_sources.operational_binding_id}"

    {:ok, reopened_capability_event_verifier_matched_record_view, _html} =
      live(conn, capability_event_verifier_matched_record_copied_path)

    assert has_element?(
             reopened_capability_event_verifier_matched_record_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="transport_capability_record"][data-data-link-target-id="#{capability_related_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    assert has_element?(
             reopened_capability_event_verifier_matched_record_view,
             ~s(#dashboard-data-link-inspector [data-data-link-navigation] [data-data-link-nav-entry-id="#{capability_verifier_id}"][phx-value-target="command_verifier_instance"])
           )

    assert has_element?(
             reopened_capability_event_verifier_matched_record_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Transport capability record"]),
             capability_related_id
           )

    assert has_element?(
             reopened_capability_event_verifier_matched_record_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Capability instance"]),
             "transport-alpha"
           )

    assert has_element?(
             reopened_capability_event_verifier_matched_record_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Replay run"]),
             replay_run_id
           )

    assert has_element?(
             reopened_capability_event_verifier_matched_record_view,
             capability_event_related_selector
           )

    reopened_capability_event_verifier_matched_record_view
    |> element(capability_event_related_selector)
    |> render_click()

    capability_event_verifier_matched_record_event_path =
      assert_patch(reopened_capability_event_verifier_matched_record_view)

    assert capability_event_verifier_matched_record_event_path =~ "panel=data_link"

    assert capability_event_verifier_matched_record_event_path =~
             "selected_target=operational_event"

    assert capability_event_verifier_matched_record_event_path =~
             "selected_id=#{capability_event_route_id}"

    assert capability_event_verifier_matched_record_event_path =~
             "nav_from_target=transport_capability_record"

    assert capability_event_verifier_matched_record_event_path =~
             "nav_from_target_id=#{capability_related_id}"

    assert capability_event_verifier_matched_record_event_path =~
             "replay_run_id=#{replay_run_id}"

    assert capability_event_verifier_matched_record_event_path =~
             "data_source_id=#{replay_sources.operational_data_source_id}"

    assert capability_event_verifier_matched_record_event_path =~
             "source_binding_id=#{replay_sources.operational_binding_id}"

    assert has_element?(
             reopened_capability_event_verifier_matched_record_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="operational_event"][data-data-link-target-id="#{capability_event_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    assert has_element?(
             reopened_capability_event_verifier_matched_record_view,
             ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=operational_event"][data-clipboard-text*="selected_id=#{capability_event_route_id}"][data-clipboard-text*="nav_from_target=transport_capability_record"][data-clipboard-text*="nav_from_target_id=#{capability_related_id}"][data-clipboard-text*="replay_run_id=#{replay_run_id}"][data-clipboard-text*="data_source_id=#{replay_sources.operational_data_source_id}"][data-clipboard-text*="source_binding_id=#{replay_sources.operational_binding_id}"])
           )

    capability_event_verifier_matched_record_event_copied_path =
      reopened_capability_event_verifier_matched_record_view
      |> render()
      |> element_attribute("#dashboard-data-link-copy-link", "data-clipboard-text")

    assert capability_event_verifier_matched_record_event_copied_path =~ "panel=data_link"

    assert capability_event_verifier_matched_record_event_copied_path =~
             "selected_target=operational_event"

    assert capability_event_verifier_matched_record_event_copied_path =~
             "selected_id=#{capability_event_route_id}"

    assert capability_event_verifier_matched_record_event_copied_path =~
             "nav_from_target=transport_capability_record"

    assert capability_event_verifier_matched_record_event_copied_path =~
             "nav_from_target_id=#{capability_related_id}"

    assert capability_event_verifier_matched_record_event_copied_path =~
             "replay_run_id=#{replay_run_id}"

    assert capability_event_verifier_matched_record_event_copied_path =~
             "data_source_id=#{replay_sources.operational_data_source_id}"

    assert capability_event_verifier_matched_record_event_copied_path =~
             "source_binding_id=#{replay_sources.operational_binding_id}"

    {:ok, reopened_capability_event_verifier_matched_record_event_view, _html} =
      live(conn, capability_event_verifier_matched_record_event_copied_path)

    assert has_element?(
             reopened_capability_event_verifier_matched_record_event_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="operational_event"][data-data-link-target-id="#{capability_event_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    assert has_element?(
             reopened_capability_event_verifier_matched_record_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-navigation] [data-data-link-nav-entry-id="#{capability_related_id}"][phx-value-target="transport_capability_record"])
           )

    assert has_element?(
             reopened_capability_event_verifier_matched_record_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-navigation] [data-data-link-nav-entry-id="#{capability_verifier_id}"][phx-value-target="command_verifier_instance"])
           )

    assert has_element?(
             reopened_capability_event_verifier_matched_record_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Transport capability record"]),
             capability_related_id
           )

    assert has_element?(
             reopened_capability_event_verifier_matched_record_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Event kind"]),
             "control_input_handled"
           )

    assert has_element?(
             reopened_capability_event_verifier_matched_record_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Replay run"]),
             replay_run_id
           )

    stop_dashboard_view(reopened_capability_event_verifier_matched_record_event_view)

    stop_dashboard_view(reopened_capability_event_verifier_matched_record_view)

    stop_dashboard_view(reopened_capability_event_verifier_back_view)
    stop_dashboard_view(reopened_capability_event_verifier_view)

    reopened_capability_event_view
    |> element(
      ~s(#dashboard-data-link-inspector [data-data-link-navigation] [data-data-link-nav-entry-id="#{capability_related_id}"][phx-value-target="transport_capability_record"])
    )
    |> render_click()

    capability_event_back_path = assert_patch(reopened_capability_event_view)
    assert capability_event_back_path =~ "panel=data_link"

    assert capability_event_back_path =~
             "selected_target=transport_capability_record"

    assert capability_event_back_path =~ "selected_id=#{capability_related_id}"
    assert capability_event_back_path =~ "replay_run_id=#{replay_run_id}"

    assert capability_event_back_path =~
             "data_source_id=#{replay_sources.operational_data_source_id}"

    assert capability_event_back_path =~
             "source_binding_id=#{replay_sources.operational_binding_id}"

    assert has_element?(
             reopened_capability_event_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="transport_capability_record"][data-data-link-target-id="#{capability_related_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    assert has_element?(
             reopened_capability_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-navigation] [data-data-link-nav-entry-id="#{capability_verifier_id}"][phx-value-target="command_verifier_instance"])
           )

    assert has_element?(
             reopened_capability_event_view,
             ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=transport_capability_record"][data-clipboard-text*="selected_id=#{capability_related_id}"][data-clipboard-text*="replay_run_id=#{replay_run_id}"][data-clipboard-text*="data_source_id=#{replay_sources.operational_data_source_id}"][data-clipboard-text*="source_binding_id=#{replay_sources.operational_binding_id}"])
           )

    capability_event_back_copied_path =
      reopened_capability_event_view
      |> render()
      |> element_attribute("#dashboard-data-link-copy-link", "data-clipboard-text")

    assert capability_event_back_copied_path =~ "panel=data_link"

    assert capability_event_back_copied_path =~
             "selected_target=transport_capability_record"

    assert capability_event_back_copied_path =~ "selected_id=#{capability_related_id}"
    assert capability_event_back_copied_path =~ "replay_run_id=#{replay_run_id}"

    assert capability_event_back_copied_path =~
             "data_source_id=#{replay_sources.operational_data_source_id}"

    assert capability_event_back_copied_path =~
             "source_binding_id=#{replay_sources.operational_binding_id}"

    {:ok, reopened_capability_event_back_view, _html} =
      live(conn, capability_event_back_copied_path)

    assert has_element?(
             reopened_capability_event_back_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="transport_capability_record"][data-data-link-target-id="#{capability_related_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    assert has_element?(
             reopened_capability_event_back_view,
             ~s(#dashboard-data-link-inspector [data-data-link-navigation] [data-data-link-nav-entry-id="#{capability_verifier_id}"][phx-value-target="command_verifier_instance"])
           )

    assert has_element?(
             reopened_capability_event_back_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Transport capability record"]),
             capability_related_id
           )

    assert has_element?(
             reopened_capability_event_back_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Capability instance"]),
             "transport-alpha"
           )

    assert has_element?(
             reopened_capability_event_back_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Replay run"]),
             replay_run_id
           )

    reopened_capability_event_back_view
    |> element(
      ~s(#dashboard-data-link-inspector [data-data-link-navigation] [data-data-link-nav-entry-id="#{capability_verifier_id}"][phx-value-target="command_verifier_instance"])
    )
    |> render_click()

    capability_event_back_verifier_path =
      assert_patch(reopened_capability_event_back_view)

    assert capability_event_back_verifier_path =~ "panel=data_link"

    assert capability_event_back_verifier_path =~
             "selected_target=command_verifier_instance"

    assert capability_event_back_verifier_path =~ "selected_id=#{capability_verifier_id}"
    assert capability_event_back_verifier_path =~ "replay_run_id=#{replay_run_id}"

    assert capability_event_back_verifier_path =~
             "data_source_id=#{replay_sources.operational_data_source_id}"

    assert capability_event_back_verifier_path =~
             "source_binding_id=#{replay_sources.operational_binding_id}"

    assert has_element?(
             reopened_capability_event_back_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="command_verifier_instance"][data-data-link-target-id="#{capability_verifier_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    assert has_element?(
             reopened_capability_event_back_view,
             ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=command_verifier_instance"][data-clipboard-text*="selected_id=#{capability_verifier_id}"][data-clipboard-text*="replay_run_id=#{replay_run_id}"][data-clipboard-text*="data_source_id=#{replay_sources.operational_data_source_id}"][data-clipboard-text*="source_binding_id=#{replay_sources.operational_binding_id}"])
           )

    capability_event_back_verifier_copied_path =
      reopened_capability_event_back_view
      |> render()
      |> element_attribute("#dashboard-data-link-copy-link", "data-clipboard-text")

    assert capability_event_back_verifier_copied_path =~ "panel=data_link"

    assert capability_event_back_verifier_copied_path =~
             "selected_target=command_verifier_instance"

    assert capability_event_back_verifier_copied_path =~
             "selected_id=#{capability_verifier_id}"

    assert capability_event_back_verifier_copied_path =~ "replay_run_id=#{replay_run_id}"

    assert capability_event_back_verifier_copied_path =~
             "data_source_id=#{replay_sources.operational_data_source_id}"

    assert capability_event_back_verifier_copied_path =~
             "source_binding_id=#{replay_sources.operational_binding_id}"

    {:ok, reopened_capability_event_back_verifier_view, _html} =
      live(conn, capability_event_back_verifier_copied_path)

    assert has_element?(
             reopened_capability_event_back_verifier_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="command_verifier_instance"][data-data-link-target-id="#{capability_verifier_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    assert has_element?(
             reopened_capability_event_back_verifier_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Command verifier instance"]),
             capability_verifier_id
           )

    assert has_element?(
             reopened_capability_event_back_verifier_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Matched record"]),
             capability_related_id
           )

    assert has_element?(
             reopened_capability_event_back_verifier_view,
             capability_verifier_transport_capability_related_selector
           )

    stop_dashboard_view(reopened_capability_event_back_verifier_view)

    stop_dashboard_view(reopened_capability_event_back_view)

    stop_dashboard_view(reopened_capability_event_view)

    stop_dashboard_view(reopened_capability_related_view)

    view
    |> element(action_row_selector <> ~s( [data-state-timeline-row-evidence]))
    |> render_click()

    assert_patch(view)

    telemetry_verifier_evidence_selector =
      ~s(#dashboard-evidence-inspector [data-evidence-ref-kind="command verifier instance"][data-evidence-ref-id="#{telemetry_verifier_instance.command_verifier_instance_id}"])

    telemetry_verifier_id = telemetry_verifier_instance.command_verifier_instance_id
    telemetry_related_id = telemetry_sample.sample_id

    telemetry_verifier_matched_at_ms =
      DateTime.to_unix(telemetry_verifier_instance.matched_at, :millisecond)

    telemetry_verifier_evidence =
      view
      |> render()
      |> LazyHTML.from_fragment()
      |> LazyHTML.query(telemetry_verifier_evidence_selector)

    assert ["command_verifier_instance"] =
             LazyHTML.attribute(telemetry_verifier_evidence, "phx-value-target")

    assert [^telemetry_verifier_id] =
             LazyHTML.attribute(telemetry_verifier_evidence, "phx-value-target-id")

    assert [telemetry_verifier_matched_at_ms_text] =
             LazyHTML.attribute(telemetry_verifier_evidence, "phx-value-timestamp-ms")

    assert telemetry_verifier_matched_at_ms_text ==
             Integer.to_string(telemetry_verifier_matched_at_ms)

    view
    |> element(telemetry_verifier_evidence_selector)
    |> render_click(%{
      "link-id" => "evidence-ref:command_verifier_instance:#{telemetry_verifier_id}",
      "target" => "command_verifier_instance",
      "target-id" => telemetry_verifier_id,
      "timestamp-ms" => telemetry_verifier_matched_at_ms,
      "realm" => "replay",
      "time-mode" => "replay_run",
      "replay-run-id" => replay_run_id,
      "data-source-id" => replay_sources.operational_data_source_id,
      "source-binding-id" => replay_sources.operational_binding_id
    })

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="command_verifier_instance"][data-data-link-target-id="#{telemetry_verifier_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    telemetry_verifier_path = assert_patch(view)
    assert telemetry_verifier_path =~ "panel=data_link"
    assert telemetry_verifier_path =~ "selected_target=command_verifier_instance"
    assert telemetry_verifier_path =~ "selected_id=#{telemetry_verifier_id}"
    assert telemetry_verifier_path =~ "selected_time=#{telemetry_verifier_matched_at_ms}"
    assert telemetry_verifier_path =~ "replay_run_id=#{replay_run_id}"

    telemetry_verifier_copied_path =
      view
      |> render()
      |> element_attribute("#dashboard-data-link-copy-link", "data-clipboard-text")

    assert telemetry_verifier_copied_path =~ "panel=data_link"
    assert telemetry_verifier_copied_path =~ "selected_target=command_verifier_instance"
    assert telemetry_verifier_copied_path =~ "selected_id=#{telemetry_verifier_id}"
    assert telemetry_verifier_copied_path =~ "selected_time=#{telemetry_verifier_matched_at_ms}"
    assert telemetry_verifier_copied_path =~ "replay_run_id=#{replay_run_id}"

    assert telemetry_verifier_copied_path =~
             "data_source_id=#{replay_sources.operational_data_source_id}"

    assert telemetry_verifier_copied_path =~
             "source_binding_id=#{replay_sources.operational_binding_id}"

    {:ok, reopened_telemetry_verifier_view, _html} = live(conn, telemetry_verifier_copied_path)

    assert has_element?(
             reopened_telemetry_verifier_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="command_verifier_instance"][data-data-link-target-id="#{telemetry_verifier_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    assert has_element?(
             reopened_telemetry_verifier_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Command verifier instance"]),
             telemetry_verifier_id
           )

    assert has_element?(
             reopened_telemetry_verifier_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Matched record"]),
             telemetry_related_id
           )

    telemetry_verifier_sample_related_selector =
      ~s(#dashboard-data-link-inspector [data-data-link-related-target="telemetry sample"][data-data-link-related-id="#{telemetry_related_id}"])

    assert has_element?(
             reopened_telemetry_verifier_view,
             telemetry_verifier_sample_related_selector
           )

    reopened_telemetry_verifier_view
    |> element(telemetry_verifier_sample_related_selector)
    |> render_click()

    telemetry_verifier_sample_path = assert_patch(reopened_telemetry_verifier_view)
    assert telemetry_verifier_sample_path =~ "panel=data_link"
    assert telemetry_verifier_sample_path =~ "selected_target=telemetry_sample"
    assert telemetry_verifier_sample_path =~ "selected_id=#{telemetry_related_id}"
    assert telemetry_verifier_sample_path =~ "nav_from_target=command_verifier_instance"
    assert telemetry_verifier_sample_path =~ "nav_from_target_id=#{telemetry_verifier_id}"
    assert telemetry_verifier_sample_path =~ "nav_trail="
    assert telemetry_verifier_sample_path =~ "replay_run_id=#{replay_run_id}"

    assert telemetry_verifier_sample_path =~
             "data_source_id=#{replay_sources.operational_data_source_id}"

    assert telemetry_verifier_sample_path =~
             "source_binding_id=#{replay_sources.operational_binding_id}"

    assert has_element?(
             reopened_telemetry_verifier_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="telemetry_sample"][data-data-link-target-id="#{telemetry_related_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    assert has_element?(
             reopened_telemetry_verifier_view,
             ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=telemetry_sample"][data-clipboard-text*="selected_id=#{telemetry_related_id}"][data-clipboard-text*="nav_from_target=command_verifier_instance"][data-clipboard-text*="nav_from_target_id=#{telemetry_verifier_id}"][data-clipboard-text*="replay_run_id=#{replay_run_id}"][data-clipboard-text*="data_source_id=#{replay_sources.operational_data_source_id}"][data-clipboard-text*="source_binding_id=#{replay_sources.operational_binding_id}"])
           )

    telemetry_verifier_sample_copied_path =
      reopened_telemetry_verifier_view
      |> render()
      |> element_attribute("#dashboard-data-link-copy-link", "data-clipboard-text")

    assert telemetry_verifier_sample_copied_path =~ "panel=data_link"
    assert telemetry_verifier_sample_copied_path =~ "selected_target=telemetry_sample"
    assert telemetry_verifier_sample_copied_path =~ "selected_id=#{telemetry_related_id}"
    assert telemetry_verifier_sample_copied_path =~ "nav_from_target=command_verifier_instance"
    assert telemetry_verifier_sample_copied_path =~ "nav_from_target_id=#{telemetry_verifier_id}"
    assert telemetry_verifier_sample_copied_path =~ "replay_run_id=#{replay_run_id}"

    {:ok, reopened_telemetry_related_view, _html} =
      live(conn, telemetry_verifier_sample_copied_path)

    assert has_element?(
             reopened_telemetry_related_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="telemetry_sample"][data-data-link-target-id="#{telemetry_related_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    assert has_element?(
             reopened_telemetry_related_view,
             ~s(#dashboard-data-link-inspector [data-data-link-navigation] [data-data-link-nav-entry-id="#{telemetry_verifier_id}"][phx-value-target="command_verifier_instance"])
           )

    assert has_element?(
             reopened_telemetry_related_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Sample"]),
             telemetry_related_id
           )

    assert has_element?(
             reopened_telemetry_related_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Point"]),
             telemetry_sample.point_id
           )

    assert has_element?(
             reopened_telemetry_related_view,
             ~s(#dashboard-data-link-inspector [data-data-link-context="Replay run"]),
             replay_run_id
           )

    reopened_telemetry_related_view
    |> element(
      ~s(#dashboard-data-link-inspector [data-data-link-navigation] [data-data-link-nav-entry-id="#{telemetry_verifier_id}"][phx-value-target="command_verifier_instance"])
    )
    |> render_click()

    telemetry_verifier_sample_back_path =
      assert_patch(reopened_telemetry_related_view)

    assert telemetry_verifier_sample_back_path =~ "panel=data_link"

    assert telemetry_verifier_sample_back_path =~
             "selected_target=command_verifier_instance"

    assert telemetry_verifier_sample_back_path =~ "selected_id=#{telemetry_verifier_id}"
    assert telemetry_verifier_sample_back_path =~ "replay_run_id=#{replay_run_id}"

    assert telemetry_verifier_sample_back_path =~
             "data_source_id=#{replay_sources.operational_data_source_id}"

    assert telemetry_verifier_sample_back_path =~
             "source_binding_id=#{replay_sources.operational_binding_id}"

    assert has_element?(
             reopened_telemetry_related_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="command_verifier_instance"][data-data-link-target-id="#{telemetry_verifier_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    assert has_element?(
             reopened_telemetry_related_view,
             ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=command_verifier_instance"][data-clipboard-text*="selected_id=#{telemetry_verifier_id}"][data-clipboard-text*="replay_run_id=#{replay_run_id}"][data-clipboard-text*="data_source_id=#{replay_sources.operational_data_source_id}"][data-clipboard-text*="source_binding_id=#{replay_sources.operational_binding_id}"])
           )

    telemetry_verifier_sample_back_copied_path =
      reopened_telemetry_related_view
      |> render()
      |> element_attribute("#dashboard-data-link-copy-link", "data-clipboard-text")

    assert telemetry_verifier_sample_back_copied_path =~ "panel=data_link"

    assert telemetry_verifier_sample_back_copied_path =~
             "selected_target=command_verifier_instance"

    assert telemetry_verifier_sample_back_copied_path =~
             "selected_id=#{telemetry_verifier_id}"

    assert telemetry_verifier_sample_back_copied_path =~ "replay_run_id=#{replay_run_id}"

    assert telemetry_verifier_sample_back_copied_path =~
             "data_source_id=#{replay_sources.operational_data_source_id}"

    assert telemetry_verifier_sample_back_copied_path =~
             "source_binding_id=#{replay_sources.operational_binding_id}"

    {:ok, reopened_telemetry_verifier_back_view, _html} =
      live(conn, telemetry_verifier_sample_back_copied_path)

    assert has_element?(
             reopened_telemetry_verifier_back_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="command_verifier_instance"][data-data-link-target-id="#{telemetry_verifier_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    assert has_element?(
             reopened_telemetry_verifier_back_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Command verifier instance"]),
             telemetry_verifier_id
           )

    assert has_element?(
             reopened_telemetry_verifier_back_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Matched record"]),
             telemetry_related_id
           )

    assert has_element?(
             reopened_telemetry_verifier_back_view,
             telemetry_verifier_sample_related_selector
           )

    stop_dashboard_view(reopened_telemetry_verifier_back_view)

    stop_dashboard_view(reopened_telemetry_related_view)

    view
    |> element(action_row_selector <> ~s( [data-state-timeline-row-evidence]))
    |> render_click()

    assert_patch(view)

    view
    |> element(failed_verifier_evidence_selector)
    |> render_click(%{
      "link-id" => "evidence-ref:command_verifier_instance:#{failed_verifier_id}",
      "target" => "command_verifier_instance",
      "target-id" => failed_verifier_id,
      "timestamp-ms" => failed_verifier_matched_at_ms,
      "realm" => "replay",
      "time-mode" => "replay_run",
      "replay-run-id" => replay_run_id,
      "data-source-id" => replay_sources.operational_data_source_id,
      "source-binding-id" => replay_sources.operational_binding_id
    })

    assert_patch(view)

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Command verifier instance"])
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Lifecycle state"])
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Failure reason"])
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Matched record"])
           )

    view
    |> element(action_row_selector <> ~s( [data-state-timeline-row-evidence]))
    |> render_click()

    assert_patch(view)

    transport_capability_evidence_selector =
      ~s(#dashboard-evidence-inspector [data-evidence-ref-kind="transport capability record"][data-evidence-ref-id="transport-runtime-record-1"])

    transport_capability_id = "transport-runtime-record-1"

    transport_capability_matched_at_ms =
      DateTime.to_unix(capability_verifier_instance.matched_at, :millisecond)

    transport_capability_evidence =
      view
      |> render()
      |> LazyHTML.from_fragment()
      |> LazyHTML.query(transport_capability_evidence_selector)

    assert ["transport_capability_record"] =
             LazyHTML.attribute(transport_capability_evidence, "phx-value-target")

    assert [^transport_capability_id] =
             LazyHTML.attribute(transport_capability_evidence, "phx-value-target-id")

    assert [transport_capability_matched_at_ms_text] =
             LazyHTML.attribute(transport_capability_evidence, "phx-value-timestamp-ms")

    assert transport_capability_matched_at_ms_text ==
             Integer.to_string(transport_capability_matched_at_ms)

    assert ["evidence-ref:transport_capability_record:" <> _] =
             LazyHTML.attribute(transport_capability_evidence, "phx-value-link-id")

    view
    |> element(transport_capability_evidence_selector)
    |> render_click(%{
      "link-id" => "evidence-ref:transport_capability_record:#{transport_capability_id}",
      "target" => "transport_capability_record",
      "target-id" => transport_capability_id,
      "timestamp-ms" => transport_capability_matched_at_ms,
      "realm" => "replay",
      "time-mode" => "replay_run",
      "replay-run-id" => replay_run_id,
      "data-source-id" => replay_sources.operational_data_source_id,
      "source-binding-id" => replay_sources.operational_binding_id
    })

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="transport_capability_record"][data-data-link-target-id="transport-runtime-record-1"])
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="transport_capability_record"][data-data-link-target-id="transport-runtime-record-1"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    transport_capability_path = assert_patch(view)
    assert transport_capability_path =~ "panel=data_link"
    assert transport_capability_path =~ "selected_target=transport_capability_record"
    assert transport_capability_path =~ "selected_id=transport-runtime-record-1"
    assert transport_capability_path =~ "selected_time=#{transport_capability_matched_at_ms}"
    assert transport_capability_path =~ "replay_run_id=#{replay_run_id}"

    assert has_element?(
             view,
             ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=transport_capability_record"][data-clipboard-text*="selected_id=transport-runtime-record-1"][data-clipboard-text*="replay_run_id=#{replay_run_id}"][data-clipboard-text*="data_source_id=#{replay_sources.operational_data_source_id}"][data-clipboard-text*="source_binding_id=#{replay_sources.operational_binding_id}"])
           )

    transport_capability_copied_path =
      view
      |> render()
      |> element_attribute("#dashboard-data-link-copy-link", "data-clipboard-text")

    assert transport_capability_copied_path =~ "panel=data_link"
    assert transport_capability_copied_path =~ "selected_target=transport_capability_record"
    assert transport_capability_copied_path =~ "selected_id=#{transport_capability_id}"

    assert transport_capability_copied_path =~
             "selected_time=#{transport_capability_matched_at_ms}"

    assert transport_capability_copied_path =~ "replay_run_id=#{replay_run_id}"

    assert transport_capability_copied_path =~
             "data_source_id=#{replay_sources.operational_data_source_id}"

    assert transport_capability_copied_path =~
             "source_binding_id=#{replay_sources.operational_binding_id}"

    {:ok, reopened_transport_capability_view, _html} =
      live(conn, transport_capability_copied_path)

    assert has_element?(
             reopened_transport_capability_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="transport_capability_record"][data-data-link-target-id="#{transport_capability_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    assert has_element?(
             reopened_transport_capability_view,
             ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=transport_capability_record"][data-clipboard-text*="selected_id=#{transport_capability_id}"][data-clipboard-text*="selected_time=#{transport_capability_matched_at_ms}"][data-clipboard-text*="replay_run_id=#{replay_run_id}"])
           )

    assert has_element?(
             reopened_transport_capability_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Transport capability record"]),
             transport_capability_id
           )

    assert has_element?(
             reopened_transport_capability_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Contact"]),
             "replay-contact-alpha"
           )

    assert has_element?(
             reopened_transport_capability_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Path"]),
             "replay-uplink-path"
           )

    assert has_element?(
             reopened_transport_capability_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Capability instance"]),
             "transport-alpha"
           )

    assert has_element?(
             reopened_transport_capability_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Family"]),
             "uplink_gateway"
           )

    assert has_element?(
             reopened_transport_capability_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Binding set"]),
             "transport-binding-set-alpha"
           )

    assert has_element?(
             reopened_transport_capability_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Binding set version"]),
             "1"
           )

    assert has_element?(
             reopened_transport_capability_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Activation"]),
             "transport-activation-alpha"
           )

    assert has_element?(
             reopened_transport_capability_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Partition affinity"]),
             "source_endpoint"
           )

    assert has_element?(
             reopened_transport_capability_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Partition value"]),
             "endpoint-alpha"
           )

    assert has_element?(
             reopened_transport_capability_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Event kind"]),
             "control_input_handled"
           )

    assert has_element?(
             reopened_transport_capability_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Emitted record kinds"]),
             "uplink_frame"
           )

    assert has_element?(
             reopened_transport_capability_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Emitted record count"]),
             "1"
           )

    assert has_element?(
             reopened_transport_capability_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Action request count"]),
             "1"
           )

    assert has_element?(
             reopened_transport_capability_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Record metadata"]),
             "uplink-frame-1"
           )

    assert has_element?(
             reopened_transport_capability_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Recorded"])
           )

    assert has_element?(
             reopened_transport_capability_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Operational event"])
           )

    assert has_element?(
             reopened_transport_capability_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Replay run"]),
             replay_run_id
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Transport capability record"])
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Operational event"])
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Replay run"])
           )

    view
    |> element(action_row_selector <> ~s( [data-state-timeline-row-evidence]))
    |> render_click()

    assert_patch(view)

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

    assert has_element?(
             reopened_record_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Transport capability record"]),
             "transport-runtime-record-1"
           )

    assert has_element?(
             reopened_record_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Contact"]),
             "replay-contact-alpha"
           )

    assert has_element?(
             reopened_record_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Path"]),
             "replay-uplink-path"
           )

    assert has_element?(
             reopened_record_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Capability instance"]),
             "transport-alpha"
           )

    assert has_element?(
             reopened_record_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Family"]),
             "uplink_gateway"
           )

    assert has_element?(
             reopened_record_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Binding set"]),
             "transport-binding-set-alpha"
           )

    assert has_element?(
             reopened_record_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Binding set version"]),
             "1"
           )

    assert has_element?(
             reopened_record_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Activation"]),
             "transport-activation-alpha"
           )

    assert has_element?(
             reopened_record_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Partition affinity"]),
             "source_endpoint"
           )

    assert has_element?(
             reopened_record_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Partition value"]),
             "endpoint-alpha"
           )

    assert has_element?(
             reopened_record_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Event kind"]),
             "control_input_handled"
           )

    assert has_element?(
             reopened_record_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Emitted record kinds"]),
             "uplink_frame"
           )

    assert has_element?(
             reopened_record_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Emitted record count"]),
             "1"
           )

    assert has_element?(
             reopened_record_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Action request count"]),
             "1"
           )

    assert has_element?(
             reopened_record_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="State snapshot"]),
             "cop1_state"
           )

    assert has_element?(
             reopened_record_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Record metadata"]),
             "transport-action-request-1"
           )

    assert has_element?(
             reopened_record_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Record metadata"]),
             "uplink-frame-1"
           )

    assert has_element?(
             reopened_record_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Recorded"])
           )

    assert has_element?(
             reopened_record_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Replay run"]),
             replay_run_id
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Transport capability record"])
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Event kind"])
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Replay run"])
           )

    view
    |> element(action_row_selector <> ~s( [data-state-timeline-row-evidence]))
    |> render_click()

    assert_patch(view)

    transport_action_evidence_selector =
      ~s(#dashboard-evidence-inspector [data-evidence-ref-kind="transport action request"][data-evidence-ref-id="transport-action-request-1"])

    transport_action_id = "transport-action-request-1"
    transport_action_matched_at_ms = DateTime.to_unix(verifier_instance.matched_at, :millisecond)

    transport_action_evidence =
      view
      |> render()
      |> LazyHTML.from_fragment()
      |> LazyHTML.query(transport_action_evidence_selector)

    assert ["transport_action_request"] =
             LazyHTML.attribute(transport_action_evidence, "phx-value-target")

    assert [^transport_action_id] =
             LazyHTML.attribute(transport_action_evidence, "phx-value-target-id")

    assert [transport_action_matched_at_ms_text] =
             LazyHTML.attribute(transport_action_evidence, "phx-value-timestamp-ms")

    assert transport_action_matched_at_ms_text ==
             Integer.to_string(transport_action_matched_at_ms)

    assert ["evidence-ref:transport_action_request:" <> _] =
             LazyHTML.attribute(transport_action_evidence, "phx-value-link-id")

    view
    |> element(transport_action_evidence_selector)
    |> render_click(%{
      "link-id" => "evidence-ref:transport_action_request:#{transport_action_id}",
      "target" => "transport_action_request",
      "target-id" => transport_action_id,
      "timestamp-ms" => transport_action_matched_at_ms,
      "realm" => "replay",
      "time-mode" => "replay_run",
      "replay-run-id" => replay_run_id,
      "data-source-id" => replay_sources.operational_data_source_id,
      "source-binding-id" => replay_sources.operational_binding_id
    })

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="transport_action_request"][data-data-link-target-id="transport-action-request-1"])
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="transport_action_request"][data-data-link-target-id="transport-action-request-1"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    transport_action_path = assert_patch(view)
    assert transport_action_path =~ "panel=data_link"
    assert transport_action_path =~ "selected_target=transport_action_request"
    assert transport_action_path =~ "selected_id=transport-action-request-1"
    assert transport_action_path =~ "selected_time=#{transport_action_matched_at_ms}"
    assert transport_action_path =~ "replay_run_id=#{replay_run_id}"

    assert has_element?(
             view,
             ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=transport_action_request"][data-clipboard-text*="selected_id=transport-action-request-1"][data-clipboard-text*="replay_run_id=#{replay_run_id}"][data-clipboard-text*="data_source_id=#{replay_sources.operational_data_source_id}"][data-clipboard-text*="source_binding_id=#{replay_sources.operational_binding_id}"])
           )

    transport_action_matched_copied_path =
      view
      |> render()
      |> element_attribute("#dashboard-data-link-copy-link", "data-clipboard-text")

    assert transport_action_matched_copied_path =~ "panel=data_link"
    assert transport_action_matched_copied_path =~ "selected_target=transport_action_request"
    assert transport_action_matched_copied_path =~ "selected_id=#{transport_action_id}"

    assert transport_action_matched_copied_path =~
             "selected_time=#{transport_action_matched_at_ms}"

    assert transport_action_matched_copied_path =~ "replay_run_id=#{replay_run_id}"

    assert transport_action_matched_copied_path =~
             "data_source_id=#{replay_sources.operational_data_source_id}"

    assert transport_action_matched_copied_path =~
             "source_binding_id=#{replay_sources.operational_binding_id}"

    {:ok, reopened_transport_action_matched_view, _html} =
      live(conn, transport_action_matched_copied_path)

    assert has_element?(
             reopened_transport_action_matched_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="transport_action_request"][data-data-link-target-id="#{transport_action_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    assert has_element?(
             reopened_transport_action_matched_view,
             ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=transport_action_request"][data-clipboard-text*="selected_id=#{transport_action_id}"][data-clipboard-text*="selected_time=#{transport_action_matched_at_ms}"][data-clipboard-text*="replay_run_id=#{replay_run_id}"])
           )

    assert has_element?(
             reopened_transport_action_matched_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Transport action request"]),
             transport_action_id
           )

    assert_transport_action_runtime_context!(
      reopened_transport_action_matched_view,
      release_attempt_id,
      release_attempt.command_request_id,
      replay_run_id
    )

    assert has_element?(
             reopened_transport_action_matched_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Command release attempt"]),
             release_attempt_id
           )

    assert has_element?(
             reopened_transport_action_matched_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Command request"]),
             release_attempt.command_request_id
           )

    assert has_element?(
             reopened_transport_action_matched_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Command"]),
             "NOOP"
           )

    assert has_element?(
             reopened_transport_action_matched_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Signal phase"]),
             "start"
           )

    assert has_element?(
             reopened_transport_action_matched_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Action kind"]),
             "release_command"
           )

    assert has_element?(
             reopened_transport_action_matched_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Request document"]),
             "command-request-1"
           )

    assert has_element?(
             reopened_transport_action_matched_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Request document"]),
             "frame_count"
           )

    assert has_element?(
             reopened_transport_action_matched_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Action metadata"]),
             "release-attempt-1"
           )

    assert has_element?(
             reopened_transport_action_matched_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Replay run"]),
             replay_run_id
           )

    action_event_id = action_event.event_id
    action_event_route_id = URI.encode_www_form(action_event_id)
    action_event_at_ms = DateTime.to_unix(action_at, :millisecond)

    matched_transport_action_event_related_selector =
      ~s(#dashboard-data-link-inspector [data-data-link-related-target="operational event"][data-data-link-related-id="#{action_event_id}"])

    assert has_element?(
             reopened_transport_action_matched_view,
             matched_transport_action_event_related_selector
           )

    reopened_transport_action_matched_view
    |> element(matched_transport_action_event_related_selector)
    |> render_click()

    matched_transport_action_event_path =
      assert_patch(reopened_transport_action_matched_view)

    assert matched_transport_action_event_path =~ "panel=data_link"
    assert matched_transport_action_event_path =~ "selected_target=operational_event"
    assert matched_transport_action_event_path =~ "selected_id=#{action_event_route_id}"
    assert matched_transport_action_event_path =~ "selected_time=#{action_event_at_ms}"
    assert matched_transport_action_event_path =~ "nav_from_target=transport_action_request"
    assert matched_transport_action_event_path =~ "nav_from_target_id=#{transport_action_id}"
    assert matched_transport_action_event_path =~ "replay_run_id=#{replay_run_id}"

    assert matched_transport_action_event_path =~
             "data_source_id=#{replay_sources.operational_data_source_id}"

    assert matched_transport_action_event_path =~
             "source_binding_id=#{replay_sources.operational_binding_id}"

    assert has_element?(
             reopened_transport_action_matched_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="operational_event"][data-data-link-target-id="#{action_event_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    assert has_element?(
             reopened_transport_action_matched_view,
             ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=operational_event"][data-clipboard-text*="selected_id=#{action_event_route_id}"][data-clipboard-text*="selected_time=#{action_event_at_ms}"][data-clipboard-text*="nav_from_target=transport_action_request"][data-clipboard-text*="nav_from_target_id=#{transport_action_id}"][data-clipboard-text*="replay_run_id=#{replay_run_id}"][data-clipboard-text*="data_source_id=#{replay_sources.operational_data_source_id}"][data-clipboard-text*="source_binding_id=#{replay_sources.operational_binding_id}"])
           )

    matched_transport_action_event_copied_path =
      reopened_transport_action_matched_view
      |> render()
      |> element_attribute("#dashboard-data-link-copy-link", "data-clipboard-text")

    assert matched_transport_action_event_copied_path =~ "panel=data_link"
    assert matched_transport_action_event_copied_path =~ "selected_target=operational_event"
    assert matched_transport_action_event_copied_path =~ "selected_id=#{action_event_route_id}"
    assert matched_transport_action_event_copied_path =~ "selected_time=#{action_event_at_ms}"

    assert matched_transport_action_event_copied_path =~
             "nav_from_target=transport_action_request"

    assert matched_transport_action_event_copied_path =~
             "nav_from_target_id=#{transport_action_id}"

    assert matched_transport_action_event_copied_path =~ "replay_run_id=#{replay_run_id}"

    assert matched_transport_action_event_copied_path =~
             "data_source_id=#{replay_sources.operational_data_source_id}"

    assert matched_transport_action_event_copied_path =~
             "source_binding_id=#{replay_sources.operational_binding_id}"

    {:ok, reopened_matched_transport_action_event_view, _html} =
      live(conn, matched_transport_action_event_copied_path)

    assert has_element?(
             reopened_matched_transport_action_event_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="operational_event"][data-data-link-target-id="#{action_event_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    assert has_element?(
             reopened_matched_transport_action_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-navigation] [data-data-link-nav-entry-id="#{transport_action_id}"][phx-value-target="transport_action_request"])
           )

    reopened_matched_transport_action_event_view
    |> element(
      ~s(#dashboard-data-link-inspector [data-data-link-navigation] [data-data-link-nav-entry-id="#{transport_action_id}"][phx-value-target="transport_action_request"])
    )
    |> render_click()

    matched_transport_action_back_path =
      assert_patch(reopened_matched_transport_action_event_view)

    assert matched_transport_action_back_path =~ "panel=data_link"
    assert matched_transport_action_back_path =~ "selected_target=transport_action_request"
    assert matched_transport_action_back_path =~ "selected_id=#{transport_action_id}"
    assert matched_transport_action_back_path =~ "selected_time=#{action_event_at_ms}"
    assert matched_transport_action_back_path =~ "replay_run_id=#{replay_run_id}"

    assert matched_transport_action_back_path =~
             "data_source_id=#{replay_sources.operational_data_source_id}"

    assert matched_transport_action_back_path =~
             "source_binding_id=#{replay_sources.operational_binding_id}"

    assert has_element?(
             reopened_matched_transport_action_event_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="transport_action_request"][data-data-link-target-id="#{transport_action_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    assert has_element?(
             reopened_matched_transport_action_event_view,
             ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=transport_action_request"][data-clipboard-text*="selected_id=#{transport_action_id}"][data-clipboard-text*="selected_time=#{action_event_at_ms}"][data-clipboard-text*="replay_run_id=#{replay_run_id}"][data-clipboard-text*="data_source_id=#{replay_sources.operational_data_source_id}"][data-clipboard-text*="source_binding_id=#{replay_sources.operational_binding_id}"])
           )

    matched_transport_action_back_copied_path =
      reopened_matched_transport_action_event_view
      |> render()
      |> element_attribute("#dashboard-data-link-copy-link", "data-clipboard-text")

    assert matched_transport_action_back_copied_path =~ "panel=data_link"

    assert matched_transport_action_back_copied_path =~
             "selected_target=transport_action_request"

    assert matched_transport_action_back_copied_path =~
             "selected_id=#{transport_action_id}"

    assert matched_transport_action_back_copied_path =~
             "selected_time=#{action_event_at_ms}"

    assert matched_transport_action_back_copied_path =~ "replay_run_id=#{replay_run_id}"

    assert matched_transport_action_back_copied_path =~
             "data_source_id=#{replay_sources.operational_data_source_id}"

    assert matched_transport_action_back_copied_path =~
             "source_binding_id=#{replay_sources.operational_binding_id}"

    {:ok, reopened_matched_transport_action_back_view, _html} =
      live(conn, matched_transport_action_back_copied_path)

    assert has_element?(
             reopened_matched_transport_action_back_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="transport_action_request"][data-data-link-target-id="#{transport_action_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    assert has_element?(
             reopened_matched_transport_action_back_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Transport action request"]),
             transport_action_id
           )

    assert_transport_action_runtime_context!(
      reopened_matched_transport_action_back_view,
      release_attempt_id,
      release_attempt.command_request_id,
      replay_run_id
    )

    assert has_element?(
             reopened_matched_transport_action_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Transport action request"]),
             transport_action_id
           )

    assert_transport_action_runtime_context!(
      reopened_matched_transport_action_event_view,
      release_attempt_id,
      release_attempt.command_request_id,
      replay_run_id
    )

    assert has_element?(
             reopened_matched_transport_action_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Action kind"]),
             "release_command"
           )

    assert has_element?(
             reopened_matched_transport_action_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Signal phase"]),
             "start"
           )

    view
    |> element(action_row_selector <> ~s( [data-state-timeline-row-evidence]))
    |> render_click()

    assert_patch(view)

    action_event_selector =
      ~s(#dashboard-evidence-inspector [data-evidence-ref-kind="operational event"][data-evidence-ref-id="#{action_event.event_id}"])

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
      "realm" => "replay",
      "time-mode" => "replay_run",
      "replay-run-id" => replay_run_id,
      "data-source-id" => replay_sources.operational_data_source_id,
      "source-binding-id" => replay_sources.operational_binding_id
    })

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="operational_event"][data-data-link-target-id="#{action_event_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    action_event_path = assert_patch(view)
    assert action_event_path =~ "panel=data_link"
    assert action_event_path =~ "selected_target=operational_event"
    assert action_event_path =~ "selected_id=#{action_event_route_id}"
    assert action_event_path =~ "selected_time=#{action_event_at_ms}"
    assert action_event_path =~ "replay_run_id=#{replay_run_id}"

    assert has_element?(
             view,
             ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=operational_event"][data-clipboard-text*="selected_id=#{action_event_route_id}"][data-clipboard-text*="replay_run_id=#{replay_run_id}"][data-clipboard-text*="data_source_id=#{replay_sources.operational_data_source_id}"][data-clipboard-text*="source_binding_id=#{replay_sources.operational_binding_id}"])
           )

    action_event_copied_path =
      view
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
             ~s(#dashboard-data-link-inspector [data-data-link-field="Transport action request"]),
             transport_action_id
           )

    assert_transport_action_runtime_context!(
      reopened_action_event_view,
      release_attempt_id,
      release_attempt.command_request_id,
      replay_run_id
    )

    assert has_element?(
             reopened_action_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Action kind"]),
             "release_command"
           )

    assert has_element?(
             reopened_action_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Command"]),
             "NOOP"
           )

    assert has_element?(
             reopened_action_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Signal phase"]),
             "start"
           )

    assert has_element?(
             reopened_action_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Request document"]),
             "frame_count"
           )

    assert has_element?(
             reopened_action_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Command release attempt"]),
             release_attempt_id
           )

    assert has_element?(
             reopened_action_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Command request"]),
             release_attempt.command_request_id
           )

    assert has_element?(
             reopened_action_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Action metadata"]),
             "release-attempt-1"
           )

    assert has_element?(
             reopened_action_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Replay run"]),
             replay_run_id
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Transport action request"])
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Action kind"])
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Replay run"])
           )

    view
    |> element(action_row_selector <> ~s( [data-state-timeline-row-evidence]))
    |> render_click()

    assert_patch(view)

    transport_timer_event = Enum.find(transport_events, &(&1.kind == :transport_timer_fired))
    assert transport_timer_event

    transport_timer_event_selector =
      ~s(#dashboard-evidence-inspector [data-evidence-ref-kind="operational event"][data-evidence-ref-id="#{transport_timer_event.event_id}"])

    transport_timer_event_id = transport_timer_event.event_id
    transport_timer_event_route_id = URI.encode_www_form(transport_timer_event_id)
    transport_timer_event_at_ms = DateTime.to_unix(timer_at, :millisecond)

    transport_timer_event_evidence =
      view
      |> render()
      |> LazyHTML.from_fragment()
      |> LazyHTML.query(transport_timer_event_selector)

    assert ["operational_event"] =
             LazyHTML.attribute(transport_timer_event_evidence, "phx-value-target")

    assert [^transport_timer_event_id] =
             LazyHTML.attribute(transport_timer_event_evidence, "phx-value-target-id")

    assert ["evidence-ref:operational_event:" <> _] =
             LazyHTML.attribute(transport_timer_event_evidence, "phx-value-link-id")

    view
    |> element(transport_timer_event_selector)
    |> render_click(%{
      "link-id" => "evidence-ref:operational_event:#{transport_timer_event_id}",
      "target" => "operational_event",
      "target-id" => transport_timer_event_id,
      "timestamp-ms" => transport_timer_event_at_ms,
      "realm" => "replay",
      "time-mode" => "replay_run",
      "replay-run-id" => replay_run_id,
      "data-source-id" => replay_sources.operational_data_source_id,
      "source-binding-id" => replay_sources.operational_binding_id
    })

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="operational_event"][data-data-link-target-id="#{transport_timer_event_id}"])
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="operational_event"][data-data-link-target-id="#{transport_timer_event_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    transport_timer_event_path = assert_patch(view)
    assert transport_timer_event_path =~ "panel=data_link"
    assert transport_timer_event_path =~ "selected_target=operational_event"
    assert transport_timer_event_path =~ "selected_id=#{transport_timer_event_route_id}"
    assert transport_timer_event_path =~ "selected_time=#{transport_timer_event_at_ms}"
    assert transport_timer_event_path =~ "replay_run_id=#{replay_run_id}"

    assert has_element?(
             view,
             ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=operational_event"][data-clipboard-text*="selected_id=#{transport_timer_event_route_id}"][data-clipboard-text*="replay_run_id=#{replay_run_id}"][data-clipboard-text*="data_source_id=#{replay_sources.operational_data_source_id}"][data-clipboard-text*="source_binding_id=#{replay_sources.operational_binding_id}"])
           )

    transport_timer_event_copied_path =
      view
      |> render()
      |> element_attribute("#dashboard-data-link-copy-link", "data-clipboard-text")

    assert transport_timer_event_copied_path =~ "panel=data_link"
    assert transport_timer_event_copied_path =~ "selected_target=operational_event"
    assert transport_timer_event_copied_path =~ "selected_id=#{transport_timer_event_route_id}"
    assert transport_timer_event_copied_path =~ "selected_time=#{transport_timer_event_at_ms}"
    assert transport_timer_event_copied_path =~ "replay_run_id=#{replay_run_id}"

    assert transport_timer_event_copied_path =~
             "data_source_id=#{replay_sources.operational_data_source_id}"

    assert transport_timer_event_copied_path =~
             "source_binding_id=#{replay_sources.operational_binding_id}"

    {:ok, reopened_transport_timer_event_view, _html} =
      live(conn, transport_timer_event_copied_path)

    assert has_element?(
             reopened_transport_timer_event_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="operational_event"][data-data-link-target-id="#{transport_timer_event_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    assert has_element?(
             reopened_transport_timer_event_view,
             ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=operational_event"][data-clipboard-text*="selected_id=#{transport_timer_event_route_id}"][data-clipboard-text*="selected_time=#{transport_timer_event_at_ms}"][data-clipboard-text*="replay_run_id=#{replay_run_id}"])
           )

    assert_transport_timer_runtime_context!(reopened_transport_timer_event_view, replay_run_id)

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Transport timer event"])
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Timer"])
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Replay run"])
           )

    view
    |> element(action_row_selector <> ~s( [data-state-timeline-row-evidence]))
    |> render_click()

    assert_patch(view)

    telemetry_sample_evidence_selector =
      ~s(#dashboard-evidence-inspector [data-evidence-ref-kind="telemetry sample"][data-evidence-ref-id="#{telemetry_sample.sample_id}"])

    telemetry_sample_id = telemetry_sample.sample_id

    telemetry_sample_matched_at_ms =
      DateTime.to_unix(telemetry_verifier_instance.matched_at, :millisecond)

    telemetry_sample_evidence =
      view
      |> render()
      |> LazyHTML.from_fragment()
      |> LazyHTML.query(telemetry_sample_evidence_selector)

    assert ["telemetry_sample"] =
             LazyHTML.attribute(telemetry_sample_evidence, "phx-value-target")

    assert [^telemetry_sample_id] =
             LazyHTML.attribute(telemetry_sample_evidence, "phx-value-target-id")

    assert [telemetry_sample_matched_at_ms_text] =
             LazyHTML.attribute(telemetry_sample_evidence, "phx-value-timestamp-ms")

    assert telemetry_sample_matched_at_ms_text ==
             Integer.to_string(telemetry_sample_matched_at_ms)

    assert ["evidence-ref:telemetry_sample:" <> _] =
             LazyHTML.attribute(telemetry_sample_evidence, "phx-value-link-id")

    view
    |> element(telemetry_sample_evidence_selector)
    |> render_click(%{
      "link-id" => "evidence-ref:telemetry_sample:#{telemetry_sample_id}",
      "target" => "telemetry_sample",
      "target-id" => telemetry_sample_id,
      "timestamp-ms" => telemetry_sample_matched_at_ms,
      "realm" => "replay",
      "time-mode" => "replay_run",
      "replay-run-id" => replay_run_id,
      "data-source-id" => replay_sources.operational_data_source_id,
      "source-binding-id" => replay_sources.operational_binding_id
    })

    assert_push_event(
      view,
      "tlm:select",
      %{
        "selection" => %{
          "target" => "telemetry_sample",
          "target_id" => ^telemetry_sample_id
        }
      },
      1_000
    )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="telemetry_sample"][data-data-link-target-id="#{telemetry_sample.sample_id}"])
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="telemetry_sample"][data-data-link-target-id="#{telemetry_sample.sample_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    telemetry_sample_path = assert_patch(view)
    assert telemetry_sample_path =~ "panel=data_link"
    assert telemetry_sample_path =~ "selected_target=telemetry_sample"
    assert telemetry_sample_path =~ "selected_id=#{telemetry_sample.sample_id}"
    assert telemetry_sample_path =~ "selected_time=#{telemetry_sample_matched_at_ms}"
    assert telemetry_sample_path =~ "replay_run_id=#{replay_run_id}"

    assert has_element?(
             view,
             ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=telemetry_sample"][data-clipboard-text*="selected_id=#{telemetry_sample.sample_id}"][data-clipboard-text*="replay_run_id=#{replay_run_id}"][data-clipboard-text*="data_source_id=#{replay_sources.operational_data_source_id}"][data-clipboard-text*="source_binding_id=#{replay_sources.operational_binding_id}"])
           )

    telemetry_sample_copied_path =
      view
      |> render()
      |> element_attribute("#dashboard-data-link-copy-link", "data-clipboard-text")

    assert telemetry_sample_copied_path =~ "panel=data_link"
    assert telemetry_sample_copied_path =~ "selected_target=telemetry_sample"
    assert telemetry_sample_copied_path =~ "selected_id=#{telemetry_sample_id}"
    assert telemetry_sample_copied_path =~ "selected_time=#{telemetry_sample_matched_at_ms}"
    assert telemetry_sample_copied_path =~ "replay_run_id=#{replay_run_id}"

    assert telemetry_sample_copied_path =~
             "data_source_id=#{replay_sources.operational_data_source_id}"

    assert telemetry_sample_copied_path =~
             "source_binding_id=#{replay_sources.operational_binding_id}"

    {:ok, reopened_telemetry_sample_view, _html} = live(conn, telemetry_sample_copied_path)

    assert has_element?(
             reopened_telemetry_sample_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="telemetry_sample"][data-data-link-target-id="#{telemetry_sample_id}"][data-data-link-status="resolved"][data-data-link-selected-replay-run-id="#{replay_run_id}"][data-data-link-selected-data-source-id="#{replay_sources.operational_data_source_id}"][data-data-link-selected-source-binding-id="#{replay_sources.operational_binding_id}"])
           )

    assert has_element?(
             reopened_telemetry_sample_view,
             ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=telemetry_sample"][data-clipboard-text*="selected_id=#{telemetry_sample_id}"][data-clipboard-text*="selected_time=#{telemetry_sample_matched_at_ms}"][data-clipboard-text*="replay_run_id=#{replay_run_id}"])
           )

    assert has_element?(
             reopened_telemetry_sample_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Sample"]),
             telemetry_sample_id
           )

    assert has_element?(
             reopened_telemetry_sample_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Point"]),
             telemetry_sample.point_id
           )

    assert has_element?(
             reopened_telemetry_sample_view,
             ~s(#dashboard-data-link-inspector [data-data-link-context="Replay run"]),
             replay_run_id
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Sample"])
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Point"])
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector [data-data-link-context="Replay run"])
           )

    stop_dashboard_view(view)
  end
end
