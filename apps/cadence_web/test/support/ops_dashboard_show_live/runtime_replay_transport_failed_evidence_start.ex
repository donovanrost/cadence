defmodule CadenceWeb.OpsDashboardShowLive.RuntimeReplayTransportFailedEvidenceStart do
  @moduledoc false

  @endpoint CadenceWeb.Endpoint

  import ExUnit.Assertions
  import Phoenix.ConnTest
  import Phoenix.LiveViewTest
  use CadenceWeb.OpsDashboardShowLive.ViewTestSupport
  import CadenceWeb.OpsDashboardShowLive.RuntimeReplayEvidenceFixtures

  def run(context) do
    %{
      action_event_id: action_event_id,
      action_event_route_id: action_event_route_id,
      conn: conn,
      failed_verifier_instance: failed_verifier_instance,
      release_attempt: release_attempt,
      release_attempt_id: release_attempt_id,
      replay_run_id: replay_run_id,
      replay_sources: replay_sources,
      transport_action_event_related_selector: transport_action_event_related_selector,
      view: view
    } = context

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

    Enum.each(
      [
        reopened_failed_verifier_view,
        reopened_failed_verifier_transport_action_view,
        reopened_failed_verifier_transport_action_back_view,
        reopened_failed_verifier_transport_action_back_matched_record_view,
        reopened_transport_action_event_view,
        reopened_back_verifier_view,
        reopened_back_record_view
      ],
      &stop_dashboard_view/1
    )

    Map.merge(context, %{
      current_view: reopened_back_event_view,
      failed_verifier_evidence_selector: failed_verifier_evidence_selector,
      failed_verifier_id: failed_verifier_id,
      failed_verifier_matched_at_ms: failed_verifier_matched_at_ms,
      failed_verifier_transport_action_related_selector:
        failed_verifier_transport_action_related_selector
    })
  end
end
