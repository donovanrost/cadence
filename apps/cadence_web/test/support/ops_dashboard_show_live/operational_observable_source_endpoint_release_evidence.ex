defmodule CadenceWeb.OpsDashboardShowLive.OperationalObservableSourceEndpointReleaseEvidence do
  @moduledoc false

  @endpoint CadenceWeb.Endpoint

  import ExUnit.Assertions
  import Phoenix.ConnTest
  import Phoenix.LiveViewTest
  import CadenceWeb.OpsDashboardShowLive.OperationalObservableSourceEndpointScopeFixtures
  import CadenceWeb.OpsDashboardShowLive.ViewTestSupport

  def run(context) do
    %{
      command_request_route_id: command_request_route_id,
      conn: conn,
      queue_entry: queue_entry,
      realized_contact: realized_contact,
      release_attempt: release_attempt,
      reopened_command_request_for_release_view: reopened_command_request_for_release_view,
      source_endpoint: source_endpoint,
      transport_action_event: transport_action_event
    } = context

    command_request_release_attempt_related_selector =
      ~s(#dashboard-data-link-inspector [data-data-link-related-target="command release attempt"][data-data-link-related-id="#{release_attempt.command_release_attempt_id}"])

    assert has_element?(
             reopened_command_request_for_release_view,
             command_request_release_attempt_related_selector
           )

    reopened_command_request_for_release_view
    |> element(command_request_release_attempt_related_selector)
    |> render_click()

    release_attempt_route_id = URI.encode_www_form(release_attempt.command_release_attempt_id)

    command_request_release_attempt_path =
      assert_patch(reopened_command_request_for_release_view)

    assert command_request_release_attempt_path =~ "panel=data_link"
    assert command_request_release_attempt_path =~ "selected_target=command_release_attempt"
    assert command_request_release_attempt_path =~ "selected_id=#{release_attempt_route_id}"
    assert command_request_release_attempt_path =~ "nav_from_target=command_request"

    assert command_request_release_attempt_path =~
             "nav_from_target_id=#{command_request_route_id}"

    assert command_request_release_attempt_path =~ "time_mode=live"
    assert command_request_release_attempt_path =~ "realm=flight"
    assert command_request_release_attempt_path =~ "scope_kind=source_endpoint"

    assert command_request_release_attempt_path =~
             "scope_id=#{source_endpoint.source_endpoint_id}"

    assert command_request_release_attempt_path =~
             "data_source_id=managed_operational_observables"

    assert command_request_release_attempt_path =~
             "source_binding_id=default_flight_operational_observables"

    assert has_element?(
             reopened_command_request_for_release_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="command_release_attempt"][data-data-link-target-id="#{release_attempt.command_release_attempt_id}"][data-data-link-status="resolved"][data-data-link-selected-data-source-id="managed_operational_observables"][data-data-link-selected-source-binding-id="default_flight_operational_observables"][data-data-link-selected-time-mode="live"])
           )

    assert has_element?(
             reopened_command_request_for_release_view,
             ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=command_release_attempt"][data-clipboard-text*="selected_id=#{release_attempt_route_id}"][data-clipboard-text*="nav_from_target=command_request"][data-clipboard-text*="nav_from_target_id=#{command_request_route_id}"][data-clipboard-text*="scope_kind=source_endpoint"][data-clipboard-text*="scope_id=#{source_endpoint.source_endpoint_id}"])
           )

    command_request_release_attempt_copied_path =
      reopened_command_request_for_release_view
      |> render()
      |> LazyHTML.from_fragment()
      |> LazyHTML.query("#dashboard-data-link-copy-link")
      |> LazyHTML.attribute("data-clipboard-text")
      |> List.first()

    assert command_request_release_attempt_copied_path =~ "panel=data_link"

    assert command_request_release_attempt_copied_path =~
             "selected_target=command_release_attempt"

    assert command_request_release_attempt_copied_path =~
             "selected_id=#{release_attempt_route_id}"

    assert command_request_release_attempt_copied_path =~ "nav_from_target=command_request"

    assert command_request_release_attempt_copied_path =~
             "nav_from_target_id=#{command_request_route_id}"

    assert command_request_release_attempt_copied_path =~ "time_mode=live"
    assert command_request_release_attempt_copied_path =~ "realm=flight"
    assert command_request_release_attempt_copied_path =~ "scope_kind=source_endpoint"

    assert command_request_release_attempt_copied_path =~
             "scope_id=#{source_endpoint.source_endpoint_id}"

    assert command_request_release_attempt_copied_path =~
             "data_source_id=managed_operational_observables"

    assert command_request_release_attempt_copied_path =~
             "source_binding_id=default_flight_operational_observables"

    {:ok, reopened_release_attempt_view, _html} =
      live(conn, command_request_release_attempt_copied_path)

    await_dashboard_resolved(reopened_release_attempt_view)

    assert has_element?(
             reopened_release_attempt_view,
             ~s(#ops-dashboard-show-page[data-dashboard-time-mode="live"][data-dashboard-data-realm="flight"][data-dashboard-scope-kind="source_endpoint"][data-dashboard-scope-id="#{source_endpoint.source_endpoint_id}"])
           )

    assert has_element?(
             reopened_release_attempt_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="command_release_attempt"][data-data-link-target-id="#{release_attempt.command_release_attempt_id}"][data-data-link-status="resolved"][data-data-link-selected-data-source-id="managed_operational_observables"][data-data-link-selected-source-binding-id="default_flight_operational_observables"][data-data-link-selected-time-mode="live"])
           )

    assert has_element?(
             reopened_release_attempt_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Command release attempt"]),
             release_attempt.command_release_attempt_id
           )

    assert has_element?(
             reopened_release_attempt_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Lifecycle state"]),
             "released"
           )

    assert has_element?(
             reopened_release_attempt_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Verification state"]),
             "pending"
           )

    assert has_element?(
             reopened_release_attempt_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Command request"]),
             queue_entry.command_request_id
           )

    assert has_element?(
             reopened_release_attempt_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Command queue entry"]),
             queue_entry.command_queue_entry_id
           )

    assert has_element?(
             reopened_release_attempt_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Source endpoint"]),
             source_endpoint.source_endpoint_id
           )

    assert has_element?(
             reopened_release_attempt_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Transport action request"]),
             transport_action_request_id!(release_attempt)
           )

    assert has_element?(
             reopened_release_attempt_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Signal phase"]),
             "start"
           )

    assert has_element?(
             reopened_release_attempt_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Action kind"]),
             "release_command"
           )

    assert has_element?(
             reopened_release_attempt_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Transport operational event"]),
             transport_action_event.event_id
           )

    assert has_element?(
             reopened_release_attempt_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Realized contact"]),
             "dashboard-contact-alpha"
           )

    {:ok, reopened_release_attempt_for_source_endpoint_view, _html} =
      live(conn, command_request_release_attempt_copied_path)

    await_dashboard_resolved(reopened_release_attempt_for_source_endpoint_view)

    release_attempt_source_endpoint_related_selector =
      ~s(#dashboard-data-link-inspector [data-data-link-related-target="source endpoint"][data-data-link-related-id="#{source_endpoint.source_endpoint_id}"])

    assert has_element?(
             reopened_release_attempt_for_source_endpoint_view,
             release_attempt_source_endpoint_related_selector
           )

    reopened_release_attempt_for_source_endpoint_view
    |> element(release_attempt_source_endpoint_related_selector)
    |> render_click()

    source_endpoint_route_id = URI.encode_www_form(source_endpoint.source_endpoint_id)

    release_attempt_source_endpoint_path =
      assert_patch(reopened_release_attempt_for_source_endpoint_view)

    assert release_attempt_source_endpoint_path =~ "panel=data_link"
    assert release_attempt_source_endpoint_path =~ "selected_target=source_endpoint"
    assert release_attempt_source_endpoint_path =~ "selected_id=#{source_endpoint_route_id}"
    assert release_attempt_source_endpoint_path =~ "nav_from_target=command_release_attempt"

    assert release_attempt_source_endpoint_path =~
             "nav_from_target_id=#{release_attempt_route_id}"

    assert release_attempt_source_endpoint_path =~ "time_mode=live"
    assert release_attempt_source_endpoint_path =~ "realm=flight"
    assert release_attempt_source_endpoint_path =~ "scope_kind=source_endpoint"

    assert release_attempt_source_endpoint_path =~
             "scope_id=#{source_endpoint.source_endpoint_id}"

    assert release_attempt_source_endpoint_path =~
             "data_source_id=managed_operational_observables"

    assert release_attempt_source_endpoint_path =~
             "source_binding_id=default_flight_operational_observables"

    assert has_element?(
             reopened_release_attempt_for_source_endpoint_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="source_endpoint"][data-data-link-target-id="#{source_endpoint.source_endpoint_id}"][data-data-link-status="resolved"][data-data-link-selected-data-source-id="managed_operational_observables"][data-data-link-selected-source-binding-id="default_flight_operational_observables"][data-data-link-selected-time-mode="live"])
           )

    assert has_element?(
             reopened_release_attempt_for_source_endpoint_view,
             ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=source_endpoint"][data-clipboard-text*="selected_id=#{source_endpoint_route_id}"][data-clipboard-text*="nav_from_target=command_release_attempt"][data-clipboard-text*="nav_from_target_id=#{release_attempt_route_id}"][data-clipboard-text*="scope_kind=source_endpoint"][data-clipboard-text*="scope_id=#{source_endpoint.source_endpoint_id}"])
           )

    release_attempt_source_endpoint_copied_path =
      reopened_release_attempt_for_source_endpoint_view
      |> render()
      |> LazyHTML.from_fragment()
      |> LazyHTML.query("#dashboard-data-link-copy-link")
      |> LazyHTML.attribute("data-clipboard-text")
      |> List.first()

    assert release_attempt_source_endpoint_copied_path =~ "panel=data_link"

    assert release_attempt_source_endpoint_copied_path =~
             "selected_target=source_endpoint"

    assert release_attempt_source_endpoint_copied_path =~
             "selected_id=#{source_endpoint_route_id}"

    assert release_attempt_source_endpoint_copied_path =~
             "nav_from_target=command_release_attempt"

    assert release_attempt_source_endpoint_copied_path =~
             "nav_from_target_id=#{release_attempt_route_id}"

    assert release_attempt_source_endpoint_copied_path =~ "time_mode=live"
    assert release_attempt_source_endpoint_copied_path =~ "realm=flight"
    assert release_attempt_source_endpoint_copied_path =~ "scope_kind=source_endpoint"

    assert release_attempt_source_endpoint_copied_path =~
             "scope_id=#{source_endpoint.source_endpoint_id}"

    assert release_attempt_source_endpoint_copied_path =~
             "data_source_id=managed_operational_observables"

    assert release_attempt_source_endpoint_copied_path =~
             "source_binding_id=default_flight_operational_observables"

    {:ok, reopened_release_attempt_source_endpoint_view, _html} =
      live(conn, release_attempt_source_endpoint_copied_path)

    await_dashboard_resolved(reopened_release_attempt_source_endpoint_view)

    assert has_element?(
             reopened_release_attempt_source_endpoint_view,
             ~s(#ops-dashboard-show-page[data-dashboard-time-mode="live"][data-dashboard-data-realm="flight"][data-dashboard-scope-kind="source_endpoint"][data-dashboard-scope-id="#{source_endpoint.source_endpoint_id}"])
           )

    assert has_element?(
             reopened_release_attempt_source_endpoint_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="source_endpoint"][data-data-link-target-id="#{source_endpoint.source_endpoint_id}"][data-data-link-status="resolved"][data-data-link-selected-data-source-id="managed_operational_observables"][data-data-link-selected-source-binding-id="default_flight_operational_observables"][data-data-link-selected-time-mode="live"])
           )

    assert has_element?(
             reopened_release_attempt_source_endpoint_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Source endpoint"]),
             source_endpoint.source_endpoint_id
           )

    assert has_element?(
             reopened_release_attempt_source_endpoint_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Display name"]),
             "Alpha Command Endpoint"
           )

    reopened_release_attempt_source_endpoint_view
    |> element(
      ~s(#dashboard-data-link-inspector [data-data-link-navigation] [data-data-link-nav-entry-id="#{release_attempt.command_release_attempt_id}"][phx-value-target="command_release_attempt"][data-data-link-nav-entry-index="2"])
    )
    |> render_click()

    source_endpoint_release_attempt_back_path =
      assert_patch(reopened_release_attempt_source_endpoint_view)

    assert source_endpoint_release_attempt_back_path =~ "panel=data_link"

    assert source_endpoint_release_attempt_back_path =~
             "selected_target=command_release_attempt"

    assert source_endpoint_release_attempt_back_path =~
             "selected_id=#{release_attempt_route_id}"

    assert source_endpoint_release_attempt_back_path =~ "time_mode=live"
    assert source_endpoint_release_attempt_back_path =~ "realm=flight"
    assert source_endpoint_release_attempt_back_path =~ "scope_kind=source_endpoint"

    assert source_endpoint_release_attempt_back_path =~
             "scope_id=#{source_endpoint.source_endpoint_id}"

    assert source_endpoint_release_attempt_back_path =~
             "data_source_id=managed_operational_observables"

    assert source_endpoint_release_attempt_back_path =~
             "source_binding_id=default_flight_operational_observables"

    assert has_element?(
             reopened_release_attempt_source_endpoint_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="command_release_attempt"][data-data-link-target-id="#{release_attempt.command_release_attempt_id}"][data-data-link-status="resolved"][data-data-link-selected-data-source-id="managed_operational_observables"][data-data-link-selected-source-binding-id="default_flight_operational_observables"][data-data-link-selected-time-mode="live"])
           )

    assert has_element?(
             reopened_release_attempt_source_endpoint_view,
             ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=command_release_attempt"][data-clipboard-text*="selected_id=#{release_attempt_route_id}"][data-clipboard-text*="scope_kind=source_endpoint"][data-clipboard-text*="scope_id=#{source_endpoint.source_endpoint_id}"])
           )

    source_endpoint_release_attempt_back_copied_path =
      reopened_release_attempt_source_endpoint_view
      |> render()
      |> LazyHTML.from_fragment()
      |> LazyHTML.query("#dashboard-data-link-copy-link")
      |> LazyHTML.attribute("data-clipboard-text")
      |> List.first()

    assert source_endpoint_release_attempt_back_copied_path =~ "panel=data_link"

    assert source_endpoint_release_attempt_back_copied_path =~
             "selected_target=command_release_attempt"

    assert source_endpoint_release_attempt_back_copied_path =~
             "selected_id=#{release_attempt_route_id}"

    assert source_endpoint_release_attempt_back_copied_path =~ "time_mode=live"
    assert source_endpoint_release_attempt_back_copied_path =~ "realm=flight"
    assert source_endpoint_release_attempt_back_copied_path =~ "scope_kind=source_endpoint"

    assert source_endpoint_release_attempt_back_copied_path =~
             "scope_id=#{source_endpoint.source_endpoint_id}"

    assert source_endpoint_release_attempt_back_copied_path =~
             "data_source_id=managed_operational_observables"

    assert source_endpoint_release_attempt_back_copied_path =~
             "source_binding_id=default_flight_operational_observables"

    {:ok, reopened_source_endpoint_release_attempt_view, _html} =
      live(conn, source_endpoint_release_attempt_back_copied_path)

    await_dashboard_resolved(reopened_source_endpoint_release_attempt_view)

    assert has_element?(
             reopened_source_endpoint_release_attempt_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="command_release_attempt"][data-data-link-target-id="#{release_attempt.command_release_attempt_id}"][data-data-link-status="resolved"][data-data-link-selected-data-source-id="managed_operational_observables"][data-data-link-selected-source-binding-id="default_flight_operational_observables"][data-data-link-selected-time-mode="live"])
           )

    assert has_element?(
             reopened_source_endpoint_release_attempt_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Command release attempt"]),
             release_attempt.command_release_attempt_id
           )

    assert has_element?(
             reopened_source_endpoint_release_attempt_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Command request"]),
             queue_entry.command_request_id
           )

    assert has_element?(
             reopened_source_endpoint_release_attempt_view,
             ~s(#dashboard-data-link-inspector [data-data-link-context="Data source"]),
             "managed_operational_observables"
           )

    {:ok, reopened_release_attempt_for_contact_view, _html} =
      live(conn, command_request_release_attempt_copied_path)

    await_dashboard_resolved(reopened_release_attempt_for_contact_view)

    release_attempt_contact_related_selector =
      ~s(#dashboard-data-link-inspector [data-data-link-related-target="contact"][data-data-link-related-id="#{realized_contact.realized_contact_id}"])

    assert has_element?(
             reopened_release_attempt_for_contact_view,
             release_attempt_contact_related_selector
           )

    reopened_release_attempt_for_contact_view
    |> element(release_attempt_contact_related_selector)
    |> render_click()

    realized_contact_route_id = URI.encode_www_form(realized_contact.realized_contact_id)
    release_attempt_contact_path = assert_patch(reopened_release_attempt_for_contact_view)

    assert release_attempt_contact_path =~ "panel=data_link"
    assert release_attempt_contact_path =~ "selected_target=contact"
    assert release_attempt_contact_path =~ "selected_id=#{realized_contact_route_id}"
    assert release_attempt_contact_path =~ "nav_from_target=command_release_attempt"

    assert release_attempt_contact_path =~
             "nav_from_target_id=#{release_attempt_route_id}"

    assert release_attempt_contact_path =~ "time_mode=live"
    assert release_attempt_contact_path =~ "realm=flight"
    assert release_attempt_contact_path =~ "scope_kind=source_endpoint"

    assert release_attempt_contact_path =~
             "scope_id=#{source_endpoint.source_endpoint_id}"

    assert release_attempt_contact_path =~ "data_source_id=managed_operational_observables"

    assert release_attempt_contact_path =~
             "source_binding_id=default_flight_operational_observables"

    assert has_element?(
             reopened_release_attempt_for_contact_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="contact"][data-data-link-target-id="#{realized_contact.realized_contact_id}"][data-data-link-status="resolved"][data-data-link-selected-data-source-id="managed_operational_observables"][data-data-link-selected-source-binding-id="default_flight_operational_observables"][data-data-link-selected-time-mode="live"])
           )

    assert has_element?(
             reopened_release_attempt_for_contact_view,
             ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=contact"][data-clipboard-text*="selected_id=#{realized_contact_route_id}"][data-clipboard-text*="nav_from_target=command_release_attempt"][data-clipboard-text*="nav_from_target_id=#{release_attempt_route_id}"][data-clipboard-text*="scope_kind=source_endpoint"][data-clipboard-text*="scope_id=#{source_endpoint.source_endpoint_id}"])
           )

    release_attempt_contact_copied_path =
      reopened_release_attempt_for_contact_view
      |> render()
      |> LazyHTML.from_fragment()
      |> LazyHTML.query("#dashboard-data-link-copy-link")
      |> LazyHTML.attribute("data-clipboard-text")
      |> List.first()

    assert release_attempt_contact_copied_path =~ "panel=data_link"
    assert release_attempt_contact_copied_path =~ "selected_target=contact"
    assert release_attempt_contact_copied_path =~ "selected_id=#{realized_contact_route_id}"

    assert release_attempt_contact_copied_path =~
             "nav_from_target=command_release_attempt"

    assert release_attempt_contact_copied_path =~
             "nav_from_target_id=#{release_attempt_route_id}"

    assert release_attempt_contact_copied_path =~ "time_mode=live"
    assert release_attempt_contact_copied_path =~ "realm=flight"
    assert release_attempt_contact_copied_path =~ "scope_kind=source_endpoint"

    assert release_attempt_contact_copied_path =~
             "scope_id=#{source_endpoint.source_endpoint_id}"

    assert release_attempt_contact_copied_path =~
             "data_source_id=managed_operational_observables"

    assert release_attempt_contact_copied_path =~
             "source_binding_id=default_flight_operational_observables"

    {:ok, reopened_release_attempt_contact_view, _html} =
      live(conn, release_attempt_contact_copied_path)

    await_dashboard_resolved(reopened_release_attempt_contact_view)

    assert has_element?(
             reopened_release_attempt_contact_view,
             ~s(#ops-dashboard-show-page[data-dashboard-time-mode="live"][data-dashboard-data-realm="flight"][data-dashboard-scope-kind="source_endpoint"][data-dashboard-scope-id="#{source_endpoint.source_endpoint_id}"])
           )

    assert has_element?(
             reopened_release_attempt_contact_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="contact"][data-data-link-target-id="#{realized_contact.realized_contact_id}"][data-data-link-status="resolved"][data-data-link-selected-data-source-id="managed_operational_observables"][data-data-link-selected-source-binding-id="default_flight_operational_observables"][data-data-link-selected-time-mode="live"])
           )

    assert has_element?(
             reopened_release_attempt_contact_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Realized contact"]),
             realized_contact.realized_contact_id
           )

    assert has_element?(
             reopened_release_attempt_contact_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Contact type"]),
             "realized_contact"
           )

    assert has_element?(
             reopened_release_attempt_contact_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Lifecycle state"]),
             "active"
           )

    assert has_element?(
             reopened_release_attempt_contact_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Source endpoints"]),
             source_endpoint.source_endpoint_id
           )

    reopened_release_attempt_contact_view
    |> element(
      ~s(#dashboard-data-link-inspector [data-data-link-navigation] [data-data-link-nav-entry-id="#{release_attempt.command_release_attempt_id}"][phx-value-target="command_release_attempt"][data-data-link-nav-entry-index="2"])
    )
    |> render_click()

    contact_release_attempt_back_path = assert_patch(reopened_release_attempt_contact_view)
    assert contact_release_attempt_back_path =~ "panel=data_link"
    assert contact_release_attempt_back_path =~ "selected_target=command_release_attempt"
    assert contact_release_attempt_back_path =~ "selected_id=#{release_attempt_route_id}"
    assert contact_release_attempt_back_path =~ "time_mode=live"
    assert contact_release_attempt_back_path =~ "realm=flight"
    assert contact_release_attempt_back_path =~ "scope_kind=source_endpoint"

    assert contact_release_attempt_back_path =~
             "scope_id=#{source_endpoint.source_endpoint_id}"

    assert contact_release_attempt_back_path =~
             "data_source_id=managed_operational_observables"

    assert contact_release_attempt_back_path =~
             "source_binding_id=default_flight_operational_observables"

    assert has_element?(
             reopened_release_attempt_contact_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="command_release_attempt"][data-data-link-target-id="#{release_attempt.command_release_attempt_id}"][data-data-link-status="resolved"][data-data-link-selected-data-source-id="managed_operational_observables"][data-data-link-selected-source-binding-id="default_flight_operational_observables"][data-data-link-selected-time-mode="live"])
           )

    assert has_element?(
             reopened_release_attempt_contact_view,
             ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=command_release_attempt"][data-clipboard-text*="selected_id=#{release_attempt_route_id}"][data-clipboard-text*="scope_kind=source_endpoint"][data-clipboard-text*="scope_id=#{source_endpoint.source_endpoint_id}"])
           )

    contact_release_attempt_back_copied_path =
      reopened_release_attempt_contact_view
      |> render()
      |> LazyHTML.from_fragment()
      |> LazyHTML.query("#dashboard-data-link-copy-link")
      |> LazyHTML.attribute("data-clipboard-text")
      |> List.first()

    assert contact_release_attempt_back_copied_path =~ "panel=data_link"
    assert contact_release_attempt_back_copied_path =~ "selected_target=command_release_attempt"
    assert contact_release_attempt_back_copied_path =~ "selected_id=#{release_attempt_route_id}"
    assert contact_release_attempt_back_copied_path =~ "time_mode=live"
    assert contact_release_attempt_back_copied_path =~ "realm=flight"
    assert contact_release_attempt_back_copied_path =~ "scope_kind=source_endpoint"

    assert contact_release_attempt_back_copied_path =~
             "scope_id=#{source_endpoint.source_endpoint_id}"

    assert contact_release_attempt_back_copied_path =~
             "data_source_id=managed_operational_observables"

    assert contact_release_attempt_back_copied_path =~
             "source_binding_id=default_flight_operational_observables"

    {:ok, reopened_contact_release_attempt_view, _html} =
      live(conn, contact_release_attempt_back_copied_path)

    await_dashboard_resolved(reopened_contact_release_attempt_view)

    assert has_element?(
             reopened_contact_release_attempt_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="command_release_attempt"][data-data-link-target-id="#{release_attempt.command_release_attempt_id}"][data-data-link-status="resolved"][data-data-link-selected-data-source-id="managed_operational_observables"][data-data-link-selected-source-binding-id="default_flight_operational_observables"][data-data-link-selected-time-mode="live"])
           )

    assert has_element?(
             reopened_contact_release_attempt_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Command release attempt"]),
             release_attempt.command_release_attempt_id
           )

    assert has_element?(
             reopened_contact_release_attempt_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Command request"]),
             queue_entry.command_request_id
           )

    assert has_element?(
             reopened_contact_release_attempt_view,
             ~s(#dashboard-data-link-inspector [data-data-link-context="Data source"]),
             "managed_operational_observables"
           )

    Map.merge(context, %{
      command_request_release_attempt_copied_path: command_request_release_attempt_copied_path,
      release_attempt_route_id: release_attempt_route_id,
      reopened_contact_release_attempt_view: reopened_contact_release_attempt_view,
      reopened_release_attempt_contact_view: reopened_release_attempt_contact_view,
      reopened_release_attempt_for_contact_view: reopened_release_attempt_for_contact_view,
      reopened_release_attempt_for_source_endpoint_view:
        reopened_release_attempt_for_source_endpoint_view,
      reopened_release_attempt_source_endpoint_view:
        reopened_release_attempt_source_endpoint_view,
      reopened_release_attempt_view: reopened_release_attempt_view,
      reopened_source_endpoint_release_attempt_view: reopened_source_endpoint_release_attempt_view
    })
  end
end
