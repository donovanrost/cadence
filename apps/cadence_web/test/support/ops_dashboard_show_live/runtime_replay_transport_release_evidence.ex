defmodule CadenceWeb.OpsDashboardShowLive.RuntimeReplayTransportReleaseEvidence do
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
      conn: conn,
      failed_verifier_instance: failed_verifier_instance,
      release_attempt: release_attempt,
      replay_run_id: replay_run_id,
      replay_sources: replay_sources,
      view: view
    } = context

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

    Map.merge(context, %{
      action_event_id: action_event_id,
      action_event_route_id: action_event_route_id,
      release_attempt_id: release_attempt_id,
      transport_action_event_related_selector: transport_action_event_related_selector
    })
  end
end
