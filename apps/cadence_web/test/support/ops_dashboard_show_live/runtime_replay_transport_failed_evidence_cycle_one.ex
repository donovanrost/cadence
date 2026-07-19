defmodule CadenceWeb.OpsDashboardShowLive.RuntimeReplayTransportFailedEvidenceCycleOne do
  @moduledoc false

  @endpoint CadenceWeb.Endpoint

  import ExUnit.Assertions
  import Phoenix.ConnTest
  import Phoenix.LiveViewTest
  import CadenceWeb.OpsDashboardShowLive.RuntimeReplayEvidenceFixtures

  def run(context) do
    %{
      action_event_id: action_event_id,
      action_event_route_id: action_event_route_id,
      conn: conn,
      current_view: reopened_back_event_view,
      failed_verifier_id: failed_verifier_id,
      failed_verifier_transport_action_related_selector:
        failed_verifier_transport_action_related_selector,
      release_attempt: release_attempt,
      release_attempt_id: release_attempt_id,
      replay_run_id: replay_run_id,
      replay_sources: replay_sources,
      transport_action_event_related_selector: transport_action_event_related_selector
    } = context

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

    Enum.each(
      [
        reopened_deep_event_verifier_view,
        reopened_deep_event_matched_record_view,
        reopened_deep_event_matched_record_event_view,
        reopened_deep_event_verifier_again_view,
        reopened_deep_verifier_again_matched_record_view
      ],
      &stop_dashboard_view/1
    )

    %{context | current_view: reopened_deep_again_matched_record_event_view}
  end
end
