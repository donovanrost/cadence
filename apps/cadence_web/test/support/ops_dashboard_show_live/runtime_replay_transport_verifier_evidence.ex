defmodule CadenceWeb.OpsDashboardShowLive.RuntimeReplayTransportVerifierEvidence do
  @moduledoc false

  @endpoint CadenceWeb.Endpoint

  import ExUnit.Assertions
  import Phoenix.ConnTest
  import Phoenix.LiveViewTest
  import CadenceWeb.OpsDashboardShowLive.ViewTestSupport
  import CadenceWeb.OpsDashboardShowLive.RuntimeReplayEvidenceFixtures

  def run(context) do
    %{
      action_row_selector: action_row_selector,
      capability_verifier_instance: capability_verifier_instance,
      conn: conn,
      failed_verifier_evidence_selector: failed_verifier_evidence_selector,
      failed_verifier_id: failed_verifier_id,
      failed_verifier_matched_at_ms: failed_verifier_matched_at_ms,
      record_event: record_event,
      replay_run_id: replay_run_id,
      replay_sources: replay_sources,
      telemetry_sample: telemetry_sample,
      telemetry_verifier_instance: telemetry_verifier_instance,
      view: view
    } = context

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

    context
  end
end
