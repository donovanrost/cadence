defmodule CadenceWeb.OpsDashboardShowLive.OperationalObservableSourceEndpointReleaseBackLinks do
  @moduledoc false

  @endpoint CadenceWeb.Endpoint

  import ExUnit.Assertions
  import Phoenix.ConnTest
  import Phoenix.LiveViewTest
  import CadenceWeb.OpsDashboardShowLive.OperationalObservableSourceEndpointScopeFixtures

  def run(context) do
    %{
      command_queue_entry_route_id: command_queue_entry_route_id,
      command_request_route_id: command_request_route_id,
      conn: conn,
      queue_entry: queue_entry,
      release_attempt_route_id: release_attempt_route_id,
      reopened_command_queue_entry_view: reopened_command_queue_entry_view,
      reopened_command_request_for_release_view: reopened_command_request_for_release_view,
      reopened_command_request_queue_entry_view: reopened_command_request_queue_entry_view,
      reopened_command_request_view: reopened_command_request_view,
      reopened_contact_release_attempt_view: reopened_contact_release_attempt_view,
      reopened_release_attempt_contact_view: reopened_release_attempt_contact_view,
      reopened_release_attempt_event_back_view: reopened_release_attempt_event_back_view,
      reopened_release_attempt_for_command_request_view:
        reopened_release_attempt_for_command_request_view,
      reopened_release_attempt_for_contact_view: reopened_release_attempt_for_contact_view,
      reopened_release_attempt_for_source_endpoint_view:
        reopened_release_attempt_for_source_endpoint_view,
      reopened_release_attempt_for_transport_action_view:
        reopened_release_attempt_for_transport_action_view,
      reopened_release_attempt_for_verifier_view: reopened_release_attempt_for_verifier_view,
      reopened_release_attempt_source_endpoint_view:
        reopened_release_attempt_source_endpoint_view,
      reopened_release_attempt_transport_action_event_view:
        reopened_release_attempt_transport_action_event_view,
      reopened_release_attempt_transport_action_view:
        reopened_release_attempt_transport_action_view,
      reopened_release_attempt_verifier_view: reopened_release_attempt_verifier_view,
      reopened_release_attempt_view: reopened_release_attempt_view,
      reopened_source_endpoint_release_attempt_view:
        reopened_source_endpoint_release_attempt_view,
      reopened_verifier_transport_action_event_view:
        reopened_verifier_transport_action_event_view,
      reopened_verifier_transport_action_view: reopened_verifier_transport_action_view,
      source_endpoint: source_endpoint,
      view: view
    } = context

    release_attempt_command_request_related_selector =
      ~s(#dashboard-data-link-inspector [data-data-link-related-target="command request"][data-data-link-related-id="#{queue_entry.command_request_id}"])

    assert has_element?(
             reopened_release_attempt_for_command_request_view,
             release_attempt_command_request_related_selector
           )

    reopened_release_attempt_for_command_request_view
    |> element(release_attempt_command_request_related_selector)
    |> render_click()

    release_attempt_command_request_path =
      assert_patch(reopened_release_attempt_for_command_request_view)

    assert release_attempt_command_request_path =~ "panel=data_link"
    assert release_attempt_command_request_path =~ "selected_target=command_request"
    assert release_attempt_command_request_path =~ "selected_id=#{command_request_route_id}"
    assert release_attempt_command_request_path =~ "nav_from_target=command_release_attempt"

    assert release_attempt_command_request_path =~
             "nav_from_target_id=#{release_attempt_route_id}"

    assert release_attempt_command_request_path =~ "time_mode=live"
    assert release_attempt_command_request_path =~ "realm=flight"
    assert release_attempt_command_request_path =~ "scope_kind=source_endpoint"

    assert release_attempt_command_request_path =~
             "scope_id=#{source_endpoint.source_endpoint_id}"

    assert release_attempt_command_request_path =~
             "data_source_id=managed_operational_observables"

    assert release_attempt_command_request_path =~
             "source_binding_id=default_flight_operational_observables"

    assert has_element?(
             reopened_release_attempt_for_command_request_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="command_request"][data-data-link-target-id="#{queue_entry.command_request_id}"][data-data-link-status="resolved"][data-data-link-selected-data-source-id="managed_operational_observables"][data-data-link-selected-source-binding-id="default_flight_operational_observables"][data-data-link-selected-time-mode="live"])
           )

    assert has_element?(
             reopened_release_attempt_for_command_request_view,
             ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=command_request"][data-clipboard-text*="selected_id=#{command_request_route_id}"][data-clipboard-text*="nav_from_target=command_release_attempt"][data-clipboard-text*="nav_from_target_id=#{release_attempt_route_id}"][data-clipboard-text*="scope_kind=source_endpoint"][data-clipboard-text*="scope_id=#{source_endpoint.source_endpoint_id}"])
           )

    release_attempt_command_request_copied_path =
      reopened_release_attempt_for_command_request_view
      |> render()
      |> LazyHTML.from_fragment()
      |> LazyHTML.query("#dashboard-data-link-copy-link")
      |> LazyHTML.attribute("data-clipboard-text")
      |> List.first()

    assert release_attempt_command_request_copied_path =~ "panel=data_link"

    assert release_attempt_command_request_copied_path =~
             "selected_target=command_request"

    assert release_attempt_command_request_copied_path =~
             "selected_id=#{command_request_route_id}"

    assert release_attempt_command_request_copied_path =~
             "nav_from_target=command_release_attempt"

    assert release_attempt_command_request_copied_path =~
             "nav_from_target_id=#{release_attempt_route_id}"

    assert release_attempt_command_request_copied_path =~ "time_mode=live"
    assert release_attempt_command_request_copied_path =~ "realm=flight"
    assert release_attempt_command_request_copied_path =~ "scope_kind=source_endpoint"

    assert release_attempt_command_request_copied_path =~
             "scope_id=#{source_endpoint.source_endpoint_id}"

    assert release_attempt_command_request_copied_path =~
             "data_source_id=managed_operational_observables"

    assert release_attempt_command_request_copied_path =~
             "source_binding_id=default_flight_operational_observables"

    {:ok, reopened_release_attempt_command_request_view, _html} =
      live(conn, release_attempt_command_request_copied_path)

    assert has_element?(
             reopened_release_attempt_command_request_view,
             ~s(#ops-dashboard-show-page[data-dashboard-time-mode="live"][data-dashboard-data-realm="flight"][data-dashboard-scope-kind="source_endpoint"][data-dashboard-scope-id="#{source_endpoint.source_endpoint_id}"])
           )

    assert has_element?(
             reopened_release_attempt_command_request_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="command_request"][data-data-link-target-id="#{queue_entry.command_request_id}"][data-data-link-status="resolved"][data-data-link-selected-data-source-id="managed_operational_observables"][data-data-link-selected-source-binding-id="default_flight_operational_observables"][data-data-link-selected-time-mode="live"])
           )

    assert has_element?(
             reopened_release_attempt_command_request_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Command request"]),
             queue_entry.command_request_id
           )

    assert has_element?(
             reopened_release_attempt_command_request_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Lifecycle state"]),
             "queued"
           )

    assert has_element?(
             reopened_release_attempt_command_request_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Source endpoint"]),
             source_endpoint.source_endpoint_id
           )

    assert has_element?(
             reopened_release_attempt_command_request_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Command"]),
             "NOOP"
           )

    assert has_element?(
             reopened_release_attempt_command_request_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Command id"]),
             queue_entry.command_queue_entry_id <> "-command"
           )

    release_attempt_queue_entry_related_selector =
      ~s(#dashboard-data-link-inspector [data-data-link-related-target="command queue entry"][data-data-link-related-id="#{queue_entry.command_queue_entry_id}"])

    assert has_element?(
             reopened_release_attempt_view,
             release_attempt_queue_entry_related_selector
           )

    reopened_release_attempt_view
    |> element(release_attempt_queue_entry_related_selector)
    |> render_click()

    release_attempt_queue_entry_path = assert_patch(reopened_release_attempt_view)
    assert release_attempt_queue_entry_path =~ "panel=data_link"
    assert release_attempt_queue_entry_path =~ "selected_target=command_queue_entry"
    assert release_attempt_queue_entry_path =~ "selected_id=#{command_queue_entry_route_id}"
    assert release_attempt_queue_entry_path =~ "nav_from_target=command_release_attempt"
    assert release_attempt_queue_entry_path =~ "nav_from_target_id=#{release_attempt_route_id}"
    assert release_attempt_queue_entry_path =~ "time_mode=live"
    assert release_attempt_queue_entry_path =~ "realm=flight"
    assert release_attempt_queue_entry_path =~ "scope_kind=source_endpoint"
    assert release_attempt_queue_entry_path =~ "scope_id=#{source_endpoint.source_endpoint_id}"
    assert release_attempt_queue_entry_path =~ "data_source_id=managed_operational_observables"

    assert release_attempt_queue_entry_path =~
             "source_binding_id=default_flight_operational_observables"

    assert has_element?(
             reopened_release_attempt_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="command_queue_entry"][data-data-link-target-id="#{queue_entry.command_queue_entry_id}"][data-data-link-status="resolved"][data-data-link-selected-data-source-id="managed_operational_observables"][data-data-link-selected-source-binding-id="default_flight_operational_observables"][data-data-link-selected-time-mode="live"])
           )

    assert has_element?(
             reopened_release_attempt_view,
             ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=command_queue_entry"][data-clipboard-text*="selected_id=#{command_queue_entry_route_id}"][data-clipboard-text*="nav_from_target=command_release_attempt"][data-clipboard-text*="nav_from_target_id=#{release_attempt_route_id}"][data-clipboard-text*="scope_kind=source_endpoint"][data-clipboard-text*="scope_id=#{source_endpoint.source_endpoint_id}"])
           )

    release_attempt_queue_entry_copied_path =
      reopened_release_attempt_view
      |> render()
      |> LazyHTML.from_fragment()
      |> LazyHTML.query("#dashboard-data-link-copy-link")
      |> LazyHTML.attribute("data-clipboard-text")
      |> List.first()

    assert release_attempt_queue_entry_copied_path =~ "panel=data_link"
    assert release_attempt_queue_entry_copied_path =~ "selected_target=command_queue_entry"

    assert release_attempt_queue_entry_copied_path =~
             "selected_id=#{command_queue_entry_route_id}"

    assert release_attempt_queue_entry_copied_path =~ "nav_from_target=command_release_attempt"

    assert release_attempt_queue_entry_copied_path =~
             "nav_from_target_id=#{release_attempt_route_id}"

    assert release_attempt_queue_entry_copied_path =~ "time_mode=live"
    assert release_attempt_queue_entry_copied_path =~ "realm=flight"
    assert release_attempt_queue_entry_copied_path =~ "scope_kind=source_endpoint"

    assert release_attempt_queue_entry_copied_path =~
             "scope_id=#{source_endpoint.source_endpoint_id}"

    assert release_attempt_queue_entry_copied_path =~
             "data_source_id=managed_operational_observables"

    assert release_attempt_queue_entry_copied_path =~
             "source_binding_id=default_flight_operational_observables"

    {:ok, reopened_release_attempt_queue_entry_view, _html} =
      live(conn, release_attempt_queue_entry_copied_path)

    assert has_element?(
             reopened_release_attempt_queue_entry_view,
             ~s(#ops-dashboard-show-page[data-dashboard-time-mode="live"][data-dashboard-data-realm="flight"][data-dashboard-scope-kind="source_endpoint"][data-dashboard-scope-id="#{source_endpoint.source_endpoint_id}"])
           )

    assert has_element?(
             reopened_release_attempt_queue_entry_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="command_queue_entry"][data-data-link-target-id="#{queue_entry.command_queue_entry_id}"][data-data-link-status="resolved"][data-data-link-selected-data-source-id="managed_operational_observables"][data-data-link-selected-source-binding-id="default_flight_operational_observables"][data-data-link-selected-time-mode="live"])
           )

    assert has_element?(
             reopened_release_attempt_queue_entry_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Command queue entry"]),
             queue_entry.command_queue_entry_id
           )

    assert has_element?(
             reopened_release_attempt_queue_entry_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Command request"]),
             queue_entry.command_request_id
           )

    stop_dashboard_view(reopened_release_attempt_queue_entry_view)
    stop_dashboard_view(reopened_release_attempt_command_request_view)
    stop_dashboard_view(reopened_release_attempt_for_command_request_view)
    stop_dashboard_view(reopened_release_attempt_event_back_view)
    stop_dashboard_view(reopened_release_attempt_transport_action_event_view)
    stop_dashboard_view(reopened_release_attempt_transport_action_view)
    stop_dashboard_view(reopened_release_attempt_for_transport_action_view)
    stop_dashboard_view(reopened_verifier_transport_action_event_view)
    stop_dashboard_view(reopened_verifier_transport_action_view)
    stop_dashboard_view(reopened_release_attempt_verifier_view)
    stop_dashboard_view(reopened_release_attempt_for_verifier_view)
    stop_dashboard_view(reopened_contact_release_attempt_view)
    stop_dashboard_view(reopened_release_attempt_contact_view)
    stop_dashboard_view(reopened_release_attempt_for_contact_view)
    stop_dashboard_view(reopened_source_endpoint_release_attempt_view)
    stop_dashboard_view(reopened_release_attempt_source_endpoint_view)
    stop_dashboard_view(reopened_release_attempt_for_source_endpoint_view)
    stop_dashboard_view(reopened_release_attempt_view)
    stop_dashboard_view(reopened_command_request_for_release_view)
    stop_dashboard_view(reopened_command_request_queue_entry_view)
    stop_dashboard_view(reopened_command_request_view)
    stop_dashboard_view(reopened_command_queue_entry_view)
    stop_dashboard_view(view)
  end
end
