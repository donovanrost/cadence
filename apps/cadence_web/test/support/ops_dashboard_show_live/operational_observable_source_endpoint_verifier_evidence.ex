defmodule CadenceWeb.OpsDashboardShowLive.OperationalObservableSourceEndpointVerifierEvidence do
  @moduledoc false

  @endpoint CadenceWeb.Endpoint

  import ExUnit.Assertions
  import Phoenix.ConnTest
  import Phoenix.LiveViewTest
  import CadenceWeb.OpsDashboardShowLive.OperationalObservableSourceEndpointScopeFixtures

  def run(context) do
    %{
      command_request_release_attempt_copied_path: command_request_release_attempt_copied_path,
      conn: conn,
      queue_entry: queue_entry,
      release_attempt: release_attempt,
      release_attempt_route_id: release_attempt_route_id,
      source_endpoint: source_endpoint,
      transport_action_event: transport_action_event,
      verifier_instance: verifier_instance
    } = context

    transport_action_request_id = transport_action_request_id!(release_attempt)
    transport_action_request_route_id = URI.encode_www_form(transport_action_request_id)

    {:ok, reopened_release_attempt_for_verifier_view, _html} =
      live(conn, command_request_release_attempt_copied_path)

    release_attempt_verifier_related_selector =
      ~s(#dashboard-data-link-inspector [data-data-link-related-target="command verifier instance"][data-data-link-related-id="#{verifier_instance.command_verifier_instance_id}"])

    assert has_element?(
             reopened_release_attempt_for_verifier_view,
             release_attempt_verifier_related_selector
           )

    reopened_release_attempt_for_verifier_view
    |> element(release_attempt_verifier_related_selector)
    |> render_click()

    verifier_instance_route_id =
      URI.encode_www_form(verifier_instance.command_verifier_instance_id)

    release_attempt_verifier_path = assert_patch(reopened_release_attempt_for_verifier_view)

    assert release_attempt_verifier_path =~ "panel=data_link"
    assert release_attempt_verifier_path =~ "selected_target=command_verifier_instance"
    assert release_attempt_verifier_path =~ "selected_id=#{verifier_instance_route_id}"
    assert release_attempt_verifier_path =~ "nav_from_target=command_release_attempt"

    assert release_attempt_verifier_path =~
             "nav_from_target_id=#{release_attempt_route_id}"

    assert release_attempt_verifier_path =~ "time_mode=live"
    assert release_attempt_verifier_path =~ "realm=flight"
    assert release_attempt_verifier_path =~ "scope_kind=source_endpoint"

    assert release_attempt_verifier_path =~
             "scope_id=#{source_endpoint.source_endpoint_id}"

    assert release_attempt_verifier_path =~ "data_source_id=managed_operational_observables"

    assert release_attempt_verifier_path =~
             "source_binding_id=default_flight_operational_observables"

    assert has_element?(
             reopened_release_attempt_for_verifier_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="command_verifier_instance"][data-data-link-target-id="#{verifier_instance.command_verifier_instance_id}"][data-data-link-status="resolved"][data-data-link-selected-data-source-id="managed_operational_observables"][data-data-link-selected-source-binding-id="default_flight_operational_observables"][data-data-link-selected-time-mode="live"])
           )

    assert has_element?(
             reopened_release_attempt_for_verifier_view,
             ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=command_verifier_instance"][data-clipboard-text*="selected_id=#{verifier_instance_route_id}"][data-clipboard-text*="nav_from_target=command_release_attempt"][data-clipboard-text*="nav_from_target_id=#{release_attempt_route_id}"][data-clipboard-text*="scope_kind=source_endpoint"][data-clipboard-text*="scope_id=#{source_endpoint.source_endpoint_id}"])
           )

    release_attempt_verifier_copied_path =
      reopened_release_attempt_for_verifier_view
      |> render()
      |> LazyHTML.from_fragment()
      |> LazyHTML.query("#dashboard-data-link-copy-link")
      |> LazyHTML.attribute("data-clipboard-text")
      |> List.first()

    assert release_attempt_verifier_copied_path =~ "panel=data_link"

    assert release_attempt_verifier_copied_path =~
             "selected_target=command_verifier_instance"

    assert release_attempt_verifier_copied_path =~
             "selected_id=#{verifier_instance_route_id}"

    assert release_attempt_verifier_copied_path =~
             "nav_from_target=command_release_attempt"

    assert release_attempt_verifier_copied_path =~
             "nav_from_target_id=#{release_attempt_route_id}"

    assert release_attempt_verifier_copied_path =~ "time_mode=live"
    assert release_attempt_verifier_copied_path =~ "realm=flight"
    assert release_attempt_verifier_copied_path =~ "scope_kind=source_endpoint"

    assert release_attempt_verifier_copied_path =~
             "scope_id=#{source_endpoint.source_endpoint_id}"

    assert release_attempt_verifier_copied_path =~
             "data_source_id=managed_operational_observables"

    assert release_attempt_verifier_copied_path =~
             "source_binding_id=default_flight_operational_observables"

    {:ok, reopened_release_attempt_verifier_view, _html} =
      live(conn, release_attempt_verifier_copied_path)

    assert has_element?(
             reopened_release_attempt_verifier_view,
             ~s(#ops-dashboard-show-page[data-dashboard-time-mode="live"][data-dashboard-data-realm="flight"][data-dashboard-scope-kind="source_endpoint"][data-dashboard-scope-id="#{source_endpoint.source_endpoint_id}"])
           )

    assert has_element?(
             reopened_release_attempt_verifier_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="command_verifier_instance"][data-data-link-target-id="#{verifier_instance.command_verifier_instance_id}"][data-data-link-status="resolved"][data-data-link-selected-data-source-id="managed_operational_observables"][data-data-link-selected-source-binding-id="default_flight_operational_observables"][data-data-link-selected-time-mode="live"])
           )

    assert has_element?(
             reopened_release_attempt_verifier_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Command verifier instance"]),
             verifier_instance.command_verifier_instance_id
           )

    assert has_element?(
             reopened_release_attempt_verifier_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Verifier name"]),
             "Live transport verifier"
           )

    assert has_element?(
             reopened_release_attempt_verifier_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Lifecycle state"]),
             "satisfied"
           )

    assert has_element?(
             reopened_release_attempt_verifier_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Command release attempt"]),
             release_attempt.command_release_attempt_id
           )

    assert has_element?(
             reopened_release_attempt_verifier_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Command request"]),
             queue_entry.command_request_id
           )

    assert has_element?(
             reopened_release_attempt_verifier_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Source endpoint"]),
             source_endpoint.source_endpoint_id
           )

    assert has_element?(
             reopened_release_attempt_verifier_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Matched record kind"]),
             "transport_action_request"
           )

    assert has_element?(
             reopened_release_attempt_verifier_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Matched record"]),
             transport_action_request_id
           )

    verifier_transport_action_related_selector =
      ~s(#dashboard-data-link-inspector [data-data-link-related-target="transport action request"][data-data-link-related-id="#{transport_action_request_id}"])

    assert has_element?(
             reopened_release_attempt_verifier_view,
             verifier_transport_action_related_selector
           )

    reopened_release_attempt_verifier_view
    |> element(verifier_transport_action_related_selector)
    |> render_click()

    verifier_transport_action_path = assert_patch(reopened_release_attempt_verifier_view)

    assert verifier_transport_action_path =~ "panel=data_link"
    assert verifier_transport_action_path =~ "selected_target=transport_action_request"
    assert verifier_transport_action_path =~ "selected_id=#{transport_action_request_route_id}"
    assert verifier_transport_action_path =~ "nav_from_target=command_verifier_instance"
    assert verifier_transport_action_path =~ "nav_from_target_id=#{verifier_instance_route_id}"
    assert verifier_transport_action_path =~ "time_mode=live"
    assert verifier_transport_action_path =~ "realm=flight"
    assert verifier_transport_action_path =~ "scope_kind=source_endpoint"
    assert verifier_transport_action_path =~ "scope_id=#{source_endpoint.source_endpoint_id}"
    assert verifier_transport_action_path =~ "data_source_id=managed_operational_observables"

    assert verifier_transport_action_path =~
             "source_binding_id=default_flight_operational_observables"

    assert has_element?(
             reopened_release_attempt_verifier_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="transport_action_request"][data-data-link-target-id="#{transport_action_request_id}"][data-data-link-status="resolved"][data-data-link-selected-data-source-id="managed_operational_observables"][data-data-link-selected-source-binding-id="default_flight_operational_observables"][data-data-link-selected-time-mode="live"])
           )

    assert has_element?(
             reopened_release_attempt_verifier_view,
             ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=transport_action_request"][data-clipboard-text*="selected_id=#{transport_action_request_route_id}"][data-clipboard-text*="nav_from_target=command_verifier_instance"][data-clipboard-text*="nav_from_target_id=#{verifier_instance_route_id}"][data-clipboard-text*="scope_kind=source_endpoint"][data-clipboard-text*="scope_id=#{source_endpoint.source_endpoint_id}"])
           )

    verifier_transport_action_copied_path =
      reopened_release_attempt_verifier_view
      |> render()
      |> LazyHTML.from_fragment()
      |> LazyHTML.query("#dashboard-data-link-copy-link")
      |> LazyHTML.attribute("data-clipboard-text")
      |> List.first()

    assert verifier_transport_action_copied_path =~ "panel=data_link"

    assert verifier_transport_action_copied_path =~
             "selected_target=transport_action_request"

    assert verifier_transport_action_copied_path =~
             "selected_id=#{transport_action_request_route_id}"

    assert verifier_transport_action_copied_path =~ "nav_from_target=command_verifier_instance"

    assert verifier_transport_action_copied_path =~
             "nav_from_target_id=#{verifier_instance_route_id}"

    assert verifier_transport_action_copied_path =~ "time_mode=live"
    assert verifier_transport_action_copied_path =~ "realm=flight"
    assert verifier_transport_action_copied_path =~ "scope_kind=source_endpoint"

    assert verifier_transport_action_copied_path =~
             "scope_id=#{source_endpoint.source_endpoint_id}"

    assert verifier_transport_action_copied_path =~
             "data_source_id=managed_operational_observables"

    assert verifier_transport_action_copied_path =~
             "source_binding_id=default_flight_operational_observables"

    {:ok, reopened_verifier_transport_action_view, _html} =
      live(conn, verifier_transport_action_copied_path)

    assert has_element?(
             reopened_verifier_transport_action_view,
             ~s(#ops-dashboard-show-page[data-dashboard-time-mode="live"][data-dashboard-data-realm="flight"][data-dashboard-scope-kind="source_endpoint"][data-dashboard-scope-id="#{source_endpoint.source_endpoint_id}"])
           )

    assert has_element?(
             reopened_verifier_transport_action_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="transport_action_request"][data-data-link-target-id="#{transport_action_request_id}"][data-data-link-status="resolved"][data-data-link-selected-data-source-id="managed_operational_observables"][data-data-link-selected-source-binding-id="default_flight_operational_observables"][data-data-link-selected-time-mode="live"])
           )

    assert has_element?(
             reopened_verifier_transport_action_view,
             ~s(#dashboard-data-link-inspector [data-data-link-navigation] [data-data-link-nav-entry-id="#{verifier_instance.command_verifier_instance_id}"][phx-value-target="command_verifier_instance"])
           )

    assert has_element?(
             reopened_verifier_transport_action_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Transport action request"]),
             transport_action_request_id
           )

    assert has_element?(
             reopened_verifier_transport_action_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Operational event"]),
             transport_action_event.event_id
           )

    assert has_element?(
             reopened_verifier_transport_action_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Command release attempt"]),
             release_attempt.command_release_attempt_id
           )

    assert has_element?(
             reopened_verifier_transport_action_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Command request"]),
             queue_entry.command_request_id
           )

    assert has_element?(
             reopened_verifier_transport_action_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Signal phase"]),
             "start"
           )

    assert has_element?(
             reopened_verifier_transport_action_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Action kind"]),
             "release_command"
           )

    verifier_transport_action_event_route_id =
      URI.encode_www_form(transport_action_event.event_id)

    verifier_transport_action_event_related_selector =
      ~s(#dashboard-data-link-inspector [data-data-link-related-target="operational event"][data-data-link-related-id="#{transport_action_event.event_id}"])

    assert has_element?(
             reopened_verifier_transport_action_view,
             verifier_transport_action_event_related_selector
           )

    reopened_verifier_transport_action_view
    |> element(verifier_transport_action_event_related_selector)
    |> render_click()

    verifier_transport_action_event_path =
      assert_patch(reopened_verifier_transport_action_view)

    assert verifier_transport_action_event_path =~ "panel=data_link"
    assert verifier_transport_action_event_path =~ "selected_target=operational_event"

    assert verifier_transport_action_event_path =~
             "selected_id=#{verifier_transport_action_event_route_id}"

    assert verifier_transport_action_event_path =~ "nav_from_target=transport_action_request"

    assert verifier_transport_action_event_path =~
             "nav_from_target_id=#{transport_action_request_route_id}"

    assert verifier_transport_action_event_path =~ "time_mode=live"
    assert verifier_transport_action_event_path =~ "realm=flight"
    assert verifier_transport_action_event_path =~ "scope_kind=source_endpoint"

    assert verifier_transport_action_event_path =~
             "scope_id=#{source_endpoint.source_endpoint_id}"

    assert verifier_transport_action_event_path =~
             "data_source_id=managed_operational_observables"

    assert verifier_transport_action_event_path =~
             "source_binding_id=default_flight_operational_observables"

    assert has_element?(
             reopened_verifier_transport_action_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="operational_event"][data-data-link-target-id="#{transport_action_event.event_id}"][data-data-link-status="resolved"][data-data-link-selected-data-source-id="managed_operational_observables"][data-data-link-selected-source-binding-id="default_flight_operational_observables"][data-data-link-selected-time-mode="live"])
           )

    assert has_element?(
             reopened_verifier_transport_action_view,
             ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=operational_event"][data-clipboard-text*="selected_id=#{verifier_transport_action_event_route_id}"][data-clipboard-text*="nav_from_target=transport_action_request"][data-clipboard-text*="nav_from_target_id=#{transport_action_request_route_id}"][data-clipboard-text*="scope_kind=source_endpoint"][data-clipboard-text*="scope_id=#{source_endpoint.source_endpoint_id}"])
           )

    verifier_transport_action_event_copied_path =
      reopened_verifier_transport_action_view
      |> render()
      |> LazyHTML.from_fragment()
      |> LazyHTML.query("#dashboard-data-link-copy-link")
      |> LazyHTML.attribute("data-clipboard-text")
      |> List.first()

    assert verifier_transport_action_event_copied_path =~ "panel=data_link"

    assert verifier_transport_action_event_copied_path =~
             "selected_target=operational_event"

    assert verifier_transport_action_event_copied_path =~
             "selected_id=#{verifier_transport_action_event_route_id}"

    assert verifier_transport_action_event_copied_path =~
             "nav_from_target=transport_action_request"

    assert verifier_transport_action_event_copied_path =~
             "nav_from_target_id=#{transport_action_request_route_id}"

    assert verifier_transport_action_event_copied_path =~ "time_mode=live"
    assert verifier_transport_action_event_copied_path =~ "realm=flight"

    assert verifier_transport_action_event_copied_path =~
             "scope_kind=source_endpoint"

    assert verifier_transport_action_event_copied_path =~
             "scope_id=#{source_endpoint.source_endpoint_id}"

    assert verifier_transport_action_event_copied_path =~
             "data_source_id=managed_operational_observables"

    assert verifier_transport_action_event_copied_path =~
             "source_binding_id=default_flight_operational_observables"

    {:ok, reopened_verifier_transport_action_event_view, _html} =
      live(conn, verifier_transport_action_event_copied_path)

    assert has_element?(
             reopened_verifier_transport_action_event_view,
             ~s(#ops-dashboard-show-page[data-dashboard-time-mode="live"][data-dashboard-data-realm="flight"][data-dashboard-scope-kind="source_endpoint"][data-dashboard-scope-id="#{source_endpoint.source_endpoint_id}"])
           )

    assert has_element?(
             reopened_verifier_transport_action_event_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="operational_event"][data-data-link-target-id="#{transport_action_event.event_id}"][data-data-link-status="resolved"][data-data-link-selected-data-source-id="managed_operational_observables"][data-data-link-selected-source-binding-id="default_flight_operational_observables"][data-data-link-selected-time-mode="live"])
           )

    assert has_element?(
             reopened_verifier_transport_action_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-navigation] [data-data-link-nav-entry-id="#{transport_action_request_id}"][phx-value-target="transport_action_request"])
           )

    assert has_element?(
             reopened_verifier_transport_action_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-navigation] [data-data-link-nav-entry-id="#{verifier_instance.command_verifier_instance_id}"][phx-value-target="command_verifier_instance"])
           )

    assert has_element?(
             reopened_verifier_transport_action_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Operational event"]),
             transport_action_event.event_id
           )

    assert has_element?(
             reopened_verifier_transport_action_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Kind"]),
             "transport_action_requested"
           )

    assert has_element?(
             reopened_verifier_transport_action_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Transport action request"]),
             transport_action_request_id
           )

    assert has_element?(
             reopened_verifier_transport_action_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Command release attempt"]),
             release_attempt.command_release_attempt_id
           )

    assert has_element?(
             reopened_verifier_transport_action_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Command request"]),
             queue_entry.command_request_id
           )

    assert has_element?(
             reopened_verifier_transport_action_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Signal phase"]),
             "start"
           )

    assert has_element?(
             reopened_verifier_transport_action_event_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Action kind"]),
             "release_command"
           )

    {:ok, reopened_release_attempt_for_transport_action_view, _html} =
      live(conn, command_request_release_attempt_copied_path)

    Map.merge(context, %{
      reopened_release_attempt_for_transport_action_view:
        reopened_release_attempt_for_transport_action_view,
      reopened_release_attempt_for_verifier_view: reopened_release_attempt_for_verifier_view,
      reopened_release_attempt_verifier_view: reopened_release_attempt_verifier_view,
      reopened_verifier_transport_action_event_view:
        reopened_verifier_transport_action_event_view,
      reopened_verifier_transport_action_view: reopened_verifier_transport_action_view,
      transport_action_request_id: transport_action_request_id,
      transport_action_request_route_id: transport_action_request_route_id
    })
  end
end
