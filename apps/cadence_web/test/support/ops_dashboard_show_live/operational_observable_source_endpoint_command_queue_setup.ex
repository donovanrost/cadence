defmodule CadenceWeb.OpsDashboardShowLive.OperationalObservableSourceEndpointCommandQueueSetup do
  @moduledoc false

  @endpoint CadenceWeb.Endpoint

  import ExUnit.Assertions
  import Phoenix.ConnTest
  import Phoenix.LiveViewTest
  import CadenceWeb.OpsDashboardShowLive.ViewTestSupport
  import CadenceWeb.OpsDashboardShowLive.OperationalObservableSourceEndpointScopeFixtures

  alias Cadence.SourceEndpoints.SourceEndpoint
  alias CadenceWeb.TestFixtures

  def run do
    {conn, org, mission} = signed_in_org_and_mission()

    source_endpoint =
      SourceEndpoint.new(%{
        source_endpoint_id: "dashboard-command-endpoint-alpha",
        mission_id: mission.mission_id,
        display_name: "Alpha Command Endpoint",
        metadata: %{}
      })

    beta_endpoint =
      SourceEndpoint.new(%{
        source_endpoint_id: "dashboard-command-endpoint-beta",
        mission_id: mission.mission_id,
        display_name: "Beta Command Endpoint",
        metadata: %{}
      })

    assert {:ok, _source_endpoint} =
             Cadence.SourceEndpoints.persist_source_endpoint(org.organization_id, source_endpoint)

    assert {:ok, _source_endpoint} =
             Cadence.SourceEndpoints.persist_source_endpoint(org.organization_id, beta_endpoint)

    queue_entry =
      persist_command_queue_entry!(
        org,
        mission,
        "live-command-queue-entry-alpha",
        source_endpoint.source_endpoint_id
      )

    release_attempt = persist_command_release_attempt!(org, mission, queue_entry)

    realized_contact =
      persist_realized_contact_for_release_attempt!(org, mission, release_attempt)

    verifier_instance =
      persist_command_verifier_instance_for_release_attempt!(org, mission, release_attempt)

    transport_action_event =
      persist_transport_action_event_for_release_attempt!(org, mission, release_attempt)

    _beta_entry =
      persist_command_queue_entry!(
        org,
        mission,
        "live-command-queue-entry-beta",
        beta_endpoint.source_endpoint_id
      )

    _released_entry =
      persist_command_queue_entry!(
        org,
        mission,
        "live-command-queue-entry-released",
        source_endpoint.source_endpoint_id,
        :released
      )

    dashboard =
      TestFixtures.persist_dashboard_document!(mission,
        name: "Source Endpoint Command Queue",
        widgets: [
          %{
            type: :status_matrix,
            title: "Source Endpoint Command Queue",
            binding: %{
              source: :operational_observables,
              observables: ["commanding.queue_depth"]
            }
          }
        ]
      )

    document = fetch_dashboard_document!(org, mission, dashboard)
    matrix_widget = render_item_by_title(document, "Source Endpoint Command Queue").widget

    {:ok, view, _html} =
      live(
        conn,
        show_path(mission, dashboard) <>
          "?scope_kind=source_endpoint&scope_id=#{source_endpoint.source_endpoint_id}"
      )

    await_dashboard_resolved(view)

    assert has_element?(
             view,
             ~s(#ops-dashboard-show-page[data-dashboard-time-mode="live"][data-dashboard-data-realm="flight"][data-dashboard-scope-kind="source_endpoint"][data-dashboard-scope-id="#{source_endpoint.source_endpoint_id}"])
           )

    row_selector =
      ~s(#widget-#{matrix_widget.widget_id} [data-status-matrix-row="commanding.queue_depth:#{source_endpoint.source_endpoint_id}"])

    assert has_element?(
             view,
             row_selector <>
               ~s([data-status-matrix-source="operational_observables"][data-status-matrix-status-policy="metric_value"][data-status-matrix-realm="flight"][data-status-matrix-resource-id="#{source_endpoint.source_endpoint_id}"][data-status-matrix-scope-kind="source_endpoint"][data-status-matrix-source-endpoint-id="#{source_endpoint.source_endpoint_id}"][data-status-matrix-product-family="commanding"][data-status-matrix-supported-capability="command_queue_depth"][data-status-matrix-data-source-id="managed_operational_observables"][data-status-matrix-source-binding-id="default_flight_operational_observables"])
           )

    assert has_element?(
             view,
             row_selector <> ~s( [data-status-matrix-field="value"]),
             "1"
           )

    assert has_element?(
             view,
             row_selector <>
               ~s( [data-status-matrix-row-evidence="commanding.queue_depth:#{source_endpoint.source_endpoint_id}"][data-status-matrix-row-evidence-observable="commanding.queue_depth"][phx-value-realm="flight"][phx-value-logical-source="operational_observables"][phx-value-data-source-id="managed_operational_observables"][phx-value-source-binding-id="default_flight_operational_observables"])
           )

    view
    |> element(row_selector <> ~s( [data-status-matrix-row-evidence]))
    |> render_click()

    evidence_path = assert_patch(view)
    assert evidence_path =~ "panel=evidence"
    assert evidence_path =~ "selected_evidence_kind=frame"
    assert evidence_path =~ "selected_placement=#{URI.encode_www_form(matrix_widget.widget_id)}"
    assert evidence_path =~ "selected_observable=commanding.queue_depth"
    assert evidence_path =~ "selected_data_source=managed_operational_observables"
    assert evidence_path =~ "selected_source_binding=default_flight_operational_observables"
    assert evidence_path =~ "scope_kind=source_endpoint"
    assert evidence_path =~ "scope_id=#{source_endpoint.source_endpoint_id}"
    assert evidence_path =~ "selected_realm=flight"

    assert has_element?(
             view,
             ~s(#dashboard-evidence-inspector[data-evidence-kind="frame"][data-evidence-status="resolved"])
           )

    assert has_element?(
             view,
             ~s(#dashboard-evidence-inspector [data-evidence-ref-kind="command queue entry"][data-evidence-ref-id="#{queue_entry.command_queue_entry_id}"][data-evidence-ref-link-target="command_queue_entry"])
           )

    refute has_element?(
             view,
             ~s(#dashboard-evidence-inspector [data-evidence-ref-id="live-command-queue-entry-beta"])
           )

    refute has_element?(
             view,
             ~s(#dashboard-evidence-inspector [data-evidence-ref-id="live-command-queue-entry-released"])
           )

    assert has_element?(
             view,
             ~s(#dashboard-evidence-copy-link[data-clipboard-text*="panel=evidence"][data-clipboard-text*="selected_evidence_kind=frame"][data-clipboard-text*="selected_observable=#{URI.encode_www_form("commanding.queue_depth")}"][data-clipboard-text*="selected_data_source=managed_operational_observables"][data-clipboard-text*="selected_source_binding=default_flight_operational_observables"][data-clipboard-text*="scope_kind=source_endpoint"][data-clipboard-text*="scope_id=#{source_endpoint.source_endpoint_id}"])
           )

    command_queue_entry_route_id = URI.encode_www_form(queue_entry.command_queue_entry_id)
    command_queue_entry_at_ms = DateTime.to_unix(queue_entry.enqueued_at, :millisecond)

    command_queue_entry_selector =
      ~s(#dashboard-evidence-inspector [data-evidence-ref-kind="command queue entry"][data-evidence-ref-id="#{queue_entry.command_queue_entry_id}"][data-evidence-ref-link-target="command_queue_entry"])

    view
    |> element(command_queue_entry_selector)
    |> render_click(%{
      "link-id" => "evidence-ref:command_queue_entry:#{queue_entry.command_queue_entry_id}",
      "target" => "command_queue_entry",
      "target-id" => queue_entry.command_queue_entry_id,
      "timestamp-ms" => command_queue_entry_at_ms,
      "realm" => "flight",
      "time-mode" => "live",
      "data-source-id" => "managed_operational_observables",
      "source-binding-id" => "default_flight_operational_observables",
      "scope-kind" => "source_endpoint",
      "scope-id" => source_endpoint.source_endpoint_id,
      "source-endpoint-id" => source_endpoint.source_endpoint_id
    })

    assert has_element?(
             view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="command_queue_entry"][data-data-link-target-id="#{queue_entry.command_queue_entry_id}"][data-data-link-status="resolved"][data-data-link-selected-data-source-id="managed_operational_observables"][data-data-link-selected-source-binding-id="default_flight_operational_observables"][data-data-link-selected-time-mode="live"])
           )

    command_queue_entry_path = assert_patch(view)
    assert command_queue_entry_path =~ "panel=data_link"
    assert command_queue_entry_path =~ "selected_target=command_queue_entry"
    assert command_queue_entry_path =~ "selected_id=#{command_queue_entry_route_id}"
    assert command_queue_entry_path =~ "selected_time=#{command_queue_entry_at_ms}"
    assert command_queue_entry_path =~ "time_mode=live"
    assert command_queue_entry_path =~ "realm=flight"
    assert command_queue_entry_path =~ "scope_kind=source_endpoint"
    assert command_queue_entry_path =~ "scope_id=#{source_endpoint.source_endpoint_id}"
    assert command_queue_entry_path =~ "data_source_id=managed_operational_observables"

    assert command_queue_entry_path =~
             "source_binding_id=default_flight_operational_observables"

    assert has_element?(
             view,
             ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=command_queue_entry"][data-clipboard-text*="selected_id=#{command_queue_entry_route_id}"][data-clipboard-text*="selected_time=#{command_queue_entry_at_ms}"][data-clipboard-text*="data_source_id=managed_operational_observables"][data-clipboard-text*="source_binding_id=default_flight_operational_observables"][data-clipboard-text*="scope_kind=source_endpoint"][data-clipboard-text*="scope_id=#{source_endpoint.source_endpoint_id}"])
           )

    command_queue_entry_copied_path =
      view
      |> render()
      |> LazyHTML.from_fragment()
      |> LazyHTML.query("#dashboard-data-link-copy-link")
      |> LazyHTML.attribute("data-clipboard-text")
      |> List.first()

    assert command_queue_entry_copied_path =~ "panel=data_link"
    assert command_queue_entry_copied_path =~ "selected_target=command_queue_entry"
    assert command_queue_entry_copied_path =~ "selected_id=#{command_queue_entry_route_id}"
    assert command_queue_entry_copied_path =~ "selected_time=#{command_queue_entry_at_ms}"
    assert command_queue_entry_copied_path =~ "time_mode=live"
    assert command_queue_entry_copied_path =~ "realm=flight"
    assert command_queue_entry_copied_path =~ "scope_kind=source_endpoint"
    assert command_queue_entry_copied_path =~ "scope_id=#{source_endpoint.source_endpoint_id}"
    assert command_queue_entry_copied_path =~ "data_source_id=managed_operational_observables"

    assert command_queue_entry_copied_path =~
             "source_binding_id=default_flight_operational_observables"

    {:ok, reopened_command_queue_entry_view, _html} =
      live(conn, command_queue_entry_copied_path)

    await_dashboard_resolved(reopened_command_queue_entry_view)

    assert has_element?(
             reopened_command_queue_entry_view,
             ~s(#ops-dashboard-show-page[data-dashboard-time-mode="live"][data-dashboard-data-realm="flight"][data-dashboard-scope-kind="source_endpoint"][data-dashboard-scope-id="#{source_endpoint.source_endpoint_id}"])
           )

    assert has_element?(
             reopened_command_queue_entry_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="command_queue_entry"][data-data-link-target-id="#{queue_entry.command_queue_entry_id}"][data-data-link-status="resolved"][data-data-link-selected-data-source-id="managed_operational_observables"][data-data-link-selected-source-binding-id="default_flight_operational_observables"][data-data-link-selected-time-mode="live"])
           )

    assert has_element?(
             reopened_command_queue_entry_view,
             ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=command_queue_entry"][data-clipboard-text*="selected_id=#{command_queue_entry_route_id}"][data-clipboard-text*="selected_time=#{command_queue_entry_at_ms}"])
           )

    assert has_element?(
             reopened_command_queue_entry_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Command queue entry"]),
             queue_entry.command_queue_entry_id
           )

    assert has_element?(
             reopened_command_queue_entry_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Lifecycle state"]),
             "pending"
           )

    assert has_element?(
             reopened_command_queue_entry_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Command request"]),
             queue_entry.command_request_id
           )

    assert has_element?(
             reopened_command_queue_entry_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Source endpoint"]),
             source_endpoint.source_endpoint_id
           )

    assert has_element?(
             reopened_command_queue_entry_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Queue lane"]),
             source_endpoint.source_endpoint_id
           )

    assert has_element?(
             reopened_command_queue_entry_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Priority"]),
             "3"
           )

    assert has_element?(
             reopened_command_queue_entry_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Enqueued at"]),
             "2026-06-17T12:00:00"
           )

    command_request_related_selector =
      ~s(#dashboard-data-link-inspector [data-data-link-related-target="command request"][data-data-link-related-id="#{queue_entry.command_request_id}"])

    assert has_element?(reopened_command_queue_entry_view, command_request_related_selector)

    reopened_command_queue_entry_view
    |> element(command_request_related_selector)
    |> render_click()

    command_request_route_id = URI.encode_www_form(queue_entry.command_request_id)
    command_request_path = assert_patch(reopened_command_queue_entry_view)
    assert command_request_path =~ "panel=data_link"
    assert command_request_path =~ "selected_target=command_request"
    assert command_request_path =~ "selected_id=#{command_request_route_id}"
    assert command_request_path =~ "nav_from_target=command_queue_entry"
    assert command_request_path =~ "nav_from_target_id=#{command_queue_entry_route_id}"
    assert command_request_path =~ "nav_trail="
    assert command_request_path =~ "time_mode=live"
    assert command_request_path =~ "realm=flight"
    assert command_request_path =~ "scope_kind=source_endpoint"
    assert command_request_path =~ "scope_id=#{source_endpoint.source_endpoint_id}"
    assert command_request_path =~ "data_source_id=managed_operational_observables"

    assert command_request_path =~
             "source_binding_id=default_flight_operational_observables"

    assert has_element?(
             reopened_command_queue_entry_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="command_request"][data-data-link-target-id="#{queue_entry.command_request_id}"][data-data-link-status="resolved"][data-data-link-selected-data-source-id="managed_operational_observables"][data-data-link-selected-source-binding-id="default_flight_operational_observables"][data-data-link-selected-time-mode="live"])
           )

    assert has_element?(
             reopened_command_queue_entry_view,
             ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=command_request"][data-clipboard-text*="selected_id=#{command_request_route_id}"][data-clipboard-text*="nav_from_target=command_queue_entry"][data-clipboard-text*="nav_from_target_id=#{command_queue_entry_route_id}"][data-clipboard-text*="scope_kind=source_endpoint"][data-clipboard-text*="scope_id=#{source_endpoint.source_endpoint_id}"])
           )

    command_request_copied_path =
      reopened_command_queue_entry_view
      |> render()
      |> LazyHTML.from_fragment()
      |> LazyHTML.query("#dashboard-data-link-copy-link")
      |> LazyHTML.attribute("data-clipboard-text")
      |> List.first()

    assert command_request_copied_path =~ "panel=data_link"
    assert command_request_copied_path =~ "selected_target=command_request"
    assert command_request_copied_path =~ "selected_id=#{command_request_route_id}"
    assert command_request_copied_path =~ "nav_from_target=command_queue_entry"
    assert command_request_copied_path =~ "nav_from_target_id=#{command_queue_entry_route_id}"
    assert command_request_copied_path =~ "time_mode=live"
    assert command_request_copied_path =~ "realm=flight"
    assert command_request_copied_path =~ "scope_kind=source_endpoint"
    assert command_request_copied_path =~ "scope_id=#{source_endpoint.source_endpoint_id}"
    assert command_request_copied_path =~ "data_source_id=managed_operational_observables"

    assert command_request_copied_path =~
             "source_binding_id=default_flight_operational_observables"

    {:ok, reopened_command_request_view, _html} = live(conn, command_request_copied_path)
    await_dashboard_resolved(reopened_command_request_view)

    assert has_element?(
             reopened_command_request_view,
             ~s(#ops-dashboard-show-page[data-dashboard-time-mode="live"][data-dashboard-data-realm="flight"][data-dashboard-scope-kind="source_endpoint"][data-dashboard-scope-id="#{source_endpoint.source_endpoint_id}"])
           )

    assert has_element?(
             reopened_command_request_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="command_request"][data-data-link-target-id="#{queue_entry.command_request_id}"][data-data-link-status="resolved"][data-data-link-selected-data-source-id="managed_operational_observables"][data-data-link-selected-source-binding-id="default_flight_operational_observables"][data-data-link-selected-time-mode="live"])
           )

    assert has_element?(
             reopened_command_request_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Command request"]),
             queue_entry.command_request_id
           )

    assert has_element?(
             reopened_command_request_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Lifecycle state"]),
             "queued"
           )

    assert has_element?(
             reopened_command_request_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Source endpoint"]),
             source_endpoint.source_endpoint_id
           )

    assert has_element?(
             reopened_command_request_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Command"]),
             "NOOP"
           )

    assert has_element?(
             reopened_command_request_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Command id"]),
             queue_entry.command_queue_entry_id <> "-command"
           )

    assert has_element?(
             reopened_command_request_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Requested at"]),
             "2026-06-17T12:00:00"
           )

    command_request_queue_entry_related_selector =
      ~s(#dashboard-data-link-inspector [data-data-link-related-target="command queue entry"][data-data-link-related-id="#{queue_entry.command_queue_entry_id}"])

    assert has_element?(
             reopened_command_request_view,
             command_request_queue_entry_related_selector
           )

    reopened_command_request_view
    |> element(command_request_queue_entry_related_selector)
    |> render_click()

    command_request_queue_entry_path = assert_patch(reopened_command_request_view)
    assert command_request_queue_entry_path =~ "panel=data_link"
    assert command_request_queue_entry_path =~ "selected_target=command_queue_entry"
    assert command_request_queue_entry_path =~ "selected_id=#{command_queue_entry_route_id}"
    assert command_request_queue_entry_path =~ "nav_from_target=command_request"
    assert command_request_queue_entry_path =~ "nav_from_target_id=#{command_request_route_id}"
    assert command_request_queue_entry_path =~ "time_mode=live"
    assert command_request_queue_entry_path =~ "realm=flight"
    assert command_request_queue_entry_path =~ "scope_kind=source_endpoint"
    assert command_request_queue_entry_path =~ "scope_id=#{source_endpoint.source_endpoint_id}"
    assert command_request_queue_entry_path =~ "data_source_id=managed_operational_observables"

    assert command_request_queue_entry_path =~
             "source_binding_id=default_flight_operational_observables"

    assert has_element?(
             reopened_command_request_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="command_queue_entry"][data-data-link-target-id="#{queue_entry.command_queue_entry_id}"][data-data-link-status="resolved"][data-data-link-selected-data-source-id="managed_operational_observables"][data-data-link-selected-source-binding-id="default_flight_operational_observables"][data-data-link-selected-time-mode="live"])
           )

    assert has_element?(
             reopened_command_request_view,
             ~s(#dashboard-data-link-copy-link[data-clipboard-text*="panel=data_link"][data-clipboard-text*="selected_target=command_queue_entry"][data-clipboard-text*="selected_id=#{command_queue_entry_route_id}"][data-clipboard-text*="nav_from_target=command_request"][data-clipboard-text*="nav_from_target_id=#{command_request_route_id}"][data-clipboard-text*="scope_kind=source_endpoint"][data-clipboard-text*="scope_id=#{source_endpoint.source_endpoint_id}"])
           )

    command_request_queue_entry_copied_path =
      reopened_command_request_view
      |> render()
      |> LazyHTML.from_fragment()
      |> LazyHTML.query("#dashboard-data-link-copy-link")
      |> LazyHTML.attribute("data-clipboard-text")
      |> List.first()

    assert command_request_queue_entry_copied_path =~ "panel=data_link"
    assert command_request_queue_entry_copied_path =~ "selected_target=command_queue_entry"

    assert command_request_queue_entry_copied_path =~
             "selected_id=#{command_queue_entry_route_id}"

    assert command_request_queue_entry_copied_path =~ "nav_from_target=command_request"

    assert command_request_queue_entry_copied_path =~
             "nav_from_target_id=#{command_request_route_id}"

    assert command_request_queue_entry_copied_path =~ "time_mode=live"
    assert command_request_queue_entry_copied_path =~ "realm=flight"
    assert command_request_queue_entry_copied_path =~ "scope_kind=source_endpoint"

    assert command_request_queue_entry_copied_path =~
             "scope_id=#{source_endpoint.source_endpoint_id}"

    assert command_request_queue_entry_copied_path =~
             "data_source_id=managed_operational_observables"

    assert command_request_queue_entry_copied_path =~
             "source_binding_id=default_flight_operational_observables"

    {:ok, reopened_command_request_queue_entry_view, _html} =
      live(conn, command_request_queue_entry_copied_path)

    await_dashboard_resolved(reopened_command_request_queue_entry_view)

    assert has_element?(
             reopened_command_request_queue_entry_view,
             ~s(#ops-dashboard-show-page[data-dashboard-time-mode="live"][data-dashboard-data-realm="flight"][data-dashboard-scope-kind="source_endpoint"][data-dashboard-scope-id="#{source_endpoint.source_endpoint_id}"])
           )

    assert has_element?(
             reopened_command_request_queue_entry_view,
             ~s(#dashboard-data-link-inspector[data-data-link-target="command_queue_entry"][data-data-link-target-id="#{queue_entry.command_queue_entry_id}"][data-data-link-status="resolved"][data-data-link-selected-data-source-id="managed_operational_observables"][data-data-link-selected-source-binding-id="default_flight_operational_observables"][data-data-link-selected-time-mode="live"])
           )

    assert has_element?(
             reopened_command_request_queue_entry_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Command queue entry"]),
             queue_entry.command_queue_entry_id
           )

    assert has_element?(
             reopened_command_request_queue_entry_view,
             ~s(#dashboard-data-link-inspector [data-data-link-field="Command request"]),
             queue_entry.command_request_id
           )

    {:ok, reopened_command_request_for_release_view, _html} =
      live(conn, command_request_copied_path)

    await_dashboard_resolved(reopened_command_request_for_release_view)

    %{
      command_queue_entry_route_id: command_queue_entry_route_id,
      command_request_route_id: command_request_route_id,
      conn: conn,
      queue_entry: queue_entry,
      realized_contact: realized_contact,
      release_attempt: release_attempt,
      reopened_command_queue_entry_view: reopened_command_queue_entry_view,
      reopened_command_request_for_release_view: reopened_command_request_for_release_view,
      reopened_command_request_queue_entry_view: reopened_command_request_queue_entry_view,
      reopened_command_request_view: reopened_command_request_view,
      source_endpoint: source_endpoint,
      transport_action_event: transport_action_event,
      verifier_instance: verifier_instance,
      view: view
    }
  end
end
