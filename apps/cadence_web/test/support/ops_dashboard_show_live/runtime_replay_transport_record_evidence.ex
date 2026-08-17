defmodule CadenceWeb.OpsDashboardShowLive.RuntimeReplayTransportRecordEvidence do
  @moduledoc false

  @endpoint CadenceWeb.Endpoint

  import ExUnit.Assertions
  import Phoenix.ConnTest
  import Phoenix.LiveViewTest
  import CadenceWeb.OpsDashboardShowLive.ViewTestSupport
  import CadenceWeb.OpsDashboardShowLive.RuntimeReplayEvidenceFixtures

  def run(context) do
    %{
      action_at: action_at,
      action_event: action_event,
      action_row_selector: action_row_selector,
      capability_verifier_instance: capability_verifier_instance,
      conn: conn,
      record_at: record_at,
      record_event: record_event,
      release_attempt: release_attempt,
      release_attempt_id: release_attempt_id,
      replay_run_id: replay_run_id,
      replay_sources: replay_sources,
      telemetry_sample: telemetry_sample,
      telemetry_verifier_instance: telemetry_verifier_instance,
      timer_at: timer_at,
      transport_events: transport_events,
      verifier_instance: verifier_instance,
      view: view
    } = context

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
