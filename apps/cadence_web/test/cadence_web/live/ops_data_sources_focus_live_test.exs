defmodule CadenceWeb.OpsDataSourcesFocusLiveTest do
  use CadenceWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias Cadence.Comms.{GroundStationStore, RoutingRuleStore, TransportStore}

  alias Cadence.Comms.{GroundStation, RoutingRule, Transport}

  alias Cadence.Projections.DataSources.Health, as: SourceHealth

  alias Cadence.Management.DataSources

  alias Cadence.Management.DataSources.Credentials, as: SourceCredentials

  alias Cadence.DataSources.{DataBinding, DataSource}

  alias Cadence.SourceEndpoints.SourceEndpoint
  alias CadenceWeb.TestFixtures

  defp signed_in_org_and_mission do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org, role: :organization_admin)
    mission = TestFixtures.persist_mission!(org, slug: "ops", display_name: "Ops Mission")

    {TestFixtures.member_conn(user), user, org, mission}
  end

  defp persist_focus_inventory!(org, mission) do
    assert {:ok, _reference, _event} =
             SourceCredentials.register_reference(%{
               credentials_ref: "cred-focus-rehearsal-questdb",
               organization_id: org.organization_id,
               mission_id: mission.mission_id,
               data_source_id: "focus-rehearsal-questdb",
               owner: :customer,
               kind: :byo_tsdb_connection,
               provider: "questdb",
               metadata: %{vault_path: "cadence/focus/questdb"}
             })

    assert {:ok, _source} =
             DataSources.persist_data_source(%DataSource{
               data_source_id: "focus-rehearsal-questdb",
               owner: :customer,
               kind: :byo_tsdb,
               adapter: Cadence.Dashboards.Sources.Telemetry,
               organization_id: org.organization_id,
               mission_id: mission.mission_id,
               isolation_level: :customer_owned,
               credentials_ref: "cred-focus-rehearsal-questdb",
               capabilities: %{latest?: true, range_scan?: true, watermarks?: true},
               metadata: %{storage: :questdb}
             })

    assert {:ok, _source} =
             DataSources.persist_data_source(%DataSource{
               data_source_id: "focus-history-telemetry-alt",
               owner: :cadence,
               kind: :managed_tsdb,
               adapter: Cadence.Dashboards.Sources.Telemetry,
               organization_id: org.organization_id,
               mission_id: mission.mission_id,
               isolation_level: :mission_isolated,
               capabilities: %{latest?: true, range_scan?: true, watermarks?: true},
               metadata: %{storage: :questdb}
             })

    assert {:ok, _source} =
             DataSources.persist_data_source(%DataSource{
               data_source_id: "focus-latest-only-telemetry",
               owner: :cadence,
               kind: :managed_tsdb,
               adapter: Cadence.Dashboards.Sources.Telemetry,
               organization_id: org.organization_id,
               mission_id: mission.mission_id,
               isolation_level: :mission_isolated,
               capabilities: %{latest?: true, range_scan?: false, watermarks?: true},
               metadata: %{storage: :questdb}
             })

    assert {:ok, _binding} =
             DataSources.persist_data_binding(%DataBinding{
               binding_id: "focus-rehearsal-telemetry-binding",
               organization_id: org.organization_id,
               mission_id: mission.mission_id,
               realm: :rehearsal,
               logical_source: :telemetry,
               data_source_id: "focus-rehearsal-questdb",
               dataset: "ait-rehearsal",
               priority: 0
             })
  end

  defp persist_focus_operational_resources!(org, mission) do
    transport =
      Transport.new(%{
        mission_id: mission.mission_id,
        transport_id: "transport-alpha",
        display_name: "Lab TCP",
        transport_kind: :tcp_socket,
        direction_capability: :inbound,
        adapter_key: :tcp_socket,
        configuration: %{
          "mode" => "listen",
          "direction_capability" => "inbound",
          "host" => "0.0.0.0",
          "port" => "5000",
          "framing_mode" => "raw",
          "tls_enabled" => "false"
        },
        metadata: %{
          "source_endpoint_id" => "endpoint-alpha",
          "ground_station_id" => "dss-14"
        }
      })

    assert {:ok, _transport} =
             TransportStore.persist_transport(org.organization_id, transport)

    source_endpoint =
      SourceEndpoint.new(%{
        mission_id: mission.mission_id,
        source_endpoint_id: "endpoint-alpha",
        display_name: "Goldstone DSS-14",
        source_ref: "provider/goldstone",
        metadata: %{"ground_station_id" => "dss-14"}
      })

    assert {:ok, _source_endpoint} =
             Cadence.SourceEndpoints.persist_source_endpoint(org.organization_id, source_endpoint)

    ground_station =
      GroundStation.new(%{
        mission_id: mission.mission_id,
        ground_station_id: "dss-14",
        display_name: "Goldstone DSS-14",
        provider: "DSN",
        region: "goldstone"
      })

    assert {:ok, _ground_station} =
             GroundStationStore.persist_ground_station(
               org.organization_id,
               ground_station
             )

    spacecraft = TestFixtures.persist_spacecraft!(mission, display_name: "Alpha", scid: 42)

    routing_rule =
      RoutingRule.new(%{
        mission_id: mission.mission_id,
        spacecraft_id: spacecraft.spacecraft_id,
        display_name: "Alpha live telemetry via Lab TCP",
        purpose_label: "Live telemetry",
        direction: :inbound,
        transport_id: transport.transport_id,
        transport_version: transport.version,
        role: :primary
      })

    assert {:ok, routing_rule} =
             RoutingRuleStore.create_routing_rule(org.organization_id, routing_rule)

    routing_rule
  end

  test "focuses source inventory rows from dashboard evidence query params" do
    {conn, _user, org, mission} = signed_in_org_and_mission()
    persist_focus_inventory!(org, mission)

    {:ok, view, _html} =
      live(
        conn,
        ~p"/missions/#{mission.mission_id}/ops/data-sources?#{%{data_source_id: "focus-rehearsal-questdb", source_binding_id: "focus-rehearsal-telemetry-binding", logical_source: "telemetry", realm: "rehearsal", scope_kind: "spacecraft", scope_id: "spacecraft-1", contact_id: "contact-1", source_endpoint_id: "endpoint-1", source_empty_reason: "contact_scope_no_data"}}"
      )

    page = ops_data_sources_page(view)
    focus = page["focus"]

    assert focus["state"] == "matched"
    assert focus["data_source_id"] == "focus-rehearsal-questdb"
    assert focus["source_binding_id"] == "focus-rehearsal-telemetry-binding"
    assert focus["contact_id"] == "contact-1"
    assert focus["source_endpoint_id"] == "endpoint-1"
    assert focus["logical_source"] == "telemetry"
    assert focus["realm"] == "rehearsal"
    assert focus["scope_kind"] == "spacecraft"
    assert focus["scope_id"] == "spacecraft-1"
    assert focus["source_empty_reason"] == "contact_scope_no_data"
    assert focus["notice"]["id"] == "source-focus-status"
    assert source_row(page, "focus-rehearsal-questdb")["focused"] == true
    assert binding_row(page, "focus-rehearsal-telemetry-binding")["focused"] == true
  end

  test "focuses operational resource context from dashboard inspector source actions" do
    {conn, _user, org, mission} = signed_in_org_and_mission()
    persist_focus_inventory!(org, mission)
    routing_rule = persist_focus_operational_resources!(org, mission)
    link_id = routing_rule.materialized_link_assignment_id

    {:ok, view, _html} =
      live(
        conn,
        ~p"/missions/#{mission.mission_id}/ops/data-sources/focus-rehearsal-questdb/settings?#{%{source_binding_id: "focus-rehearsal-telemetry-binding", logical_source: "telemetry", realm: "rehearsal", selected_target: "transport", selected_id: "transport-alpha", transport_id: "transport-alpha", source_endpoint_id: "endpoint-alpha", ground_station_id: "dss-14", link_id: link_id}}"
      )

    page = ops_data_sources_page(view)
    focus = page["focus"]
    resource = focus["resource"]

    assert focus["state"] == "matched"
    assert focus["selected_target"] == "transport"
    assert focus["selected_id"] == "transport-alpha"
    assert focus["transport_id"] == "transport-alpha"
    assert focus["source_endpoint_id"] == "endpoint-alpha"
    assert focus["ground_station_id"] == "dss-14"
    assert focus["link_id"] == link_id
    assert focus["notice"]["detail"] =~ "transport_id=transport-alpha"
    assert resource["selected_target"] == "transport"
    assert resource["selected_id"] == "transport-alpha"

    transport = resource_row(resource, "transport_id")
    assert transport["value"] == "transport-alpha"
    assert transport["display_value"] == "Lab TCP / tcp_socket"
    assert transport["status"] == "resolved"

    assert transport["href"] ==
             "/missions/#{mission.mission_id}/comms/transports/transport-alpha"

    endpoint = resource_row(resource, "source_endpoint_id")
    assert endpoint["value"] == "endpoint-alpha"
    assert endpoint["display_value"] == "Goldstone DSS-14 / provider/goldstone"
    assert endpoint["status"] == "resolved"

    assert endpoint["href"] ==
             "/missions/#{mission.mission_id}/comms?source_endpoint_id=endpoint-alpha"

    station = resource_row(resource, "ground_station_id")
    assert station["value"] == "dss-14"
    assert station["display_value"] == "Goldstone DSS-14"
    assert station["status"] == "resolved"

    assert station["href"] ==
             "/missions/#{mission.mission_id}/comms/ground-stations/dss-14"

    link = resource_row(resource, "link_id")
    assert link["value"] == link_id
    assert link["status"] == "resolved"

    assert link["href"] ==
             "/missions/#{mission.mission_id}/comms/routing/#{routing_rule.routing_rule_id}"

    assert source_row(page, "focus-rehearsal-questdb")["focused"] == true
    assert binding_row(page, "focus-rehearsal-telemetry-binding")["focused"] == true

    probe = source_action(page, "focus-rehearsal-questdb", "probe_source")
    assert probe["payload"] == %{"data-source-id" => "focus-rehearsal-questdb"}
    render_hook(view, "probe_source", probe["payload"])

    assert [health_status] =
             SourceHealth.list_source_health_statuses(org.organization_id, mission.mission_id,
               data_source_id: "focus-rehearsal-questdb"
             )

    assert health_status.payload["source_focus_selected_target"] == "transport"
    assert health_status.payload["source_focus_selected_id"] == "transport-alpha"
    assert health_status.payload["source_focus_transport_id"] == "transport-alpha"
    assert health_status.payload["source_focus_source_endpoint_id"] == "endpoint-alpha"
    assert health_status.payload["source_focus_ground_station_id"] == "dss-14"
    assert health_status.payload["source_focus_link_id"] == link_id
  end

  test "highlights source evidence state from readiness activity query params" do
    {conn, _user, org, mission} = signed_in_org_and_mission()
    persist_focus_inventory!(org, mission)

    {:ok, view, _html} =
      live(
        conn,
        ~p"/missions/#{mission.mission_id}/ops/data-sources/focus-rehearsal-questdb/settings?#{%{source_binding_id: "focus-rehearsal-telemetry-binding", logical_source: "telemetry", realm: "rehearsal", source_empty_reason: "stale_data", selected_evidence_kind: "source", selected_source_evidence_mode: "health", selected_source_evidence_state: "stale", source_dashboard_id: "dashboard-return-1", source_return_activity_event: "dashboard-readiness-event-1", source_return_activity_filter: "publish_readiness", source_return_panel: "versions"}}"
      )

    page = ops_data_sources_page(view)
    focus = page["focus"]
    evidence = focus["evidence"]

    assert focus["state"] == "matched"
    assert focus["selected_evidence_kind"] == "source"
    assert focus["selected_source_evidence_mode"] == "health"
    assert focus["selected_source_evidence_state"] == "stale"
    assert focus["source_empty_reason"] == "stale_data"
    assert evidence["kind"] == "source"
    assert evidence["mode"] == "health"
    assert evidence["state"] == "stale"
    assert evidence["reason"] == "stale_data"
    assert evidence["title"] == "Source freshness evidence is stale"
    assert focus["remediation"] == nil
    assert evidence["dashboard_return"]["dashboard_id"] == "dashboard-return-1"

    assert evidence["dashboard_return"]["activity_event"] ==
             "dashboard-readiness-event-1"

    assert evidence["dashboard_return"]["href"] =~ "refresh_readiness=source_return"

    probe = source_action(page, "focus-rehearsal-questdb", "probe_source")
    render_hook(view, "probe_source", probe["payload"])

    assert [health_status] =
             SourceHealth.list_source_health_statuses(org.organization_id, mission.mission_id,
               data_source_id: "focus-rehearsal-questdb"
             )

    assert health_status.payload["source"] == "ops_data_sources_live"
    assert health_status.payload["source_dashboard_id"] == "dashboard-return-1"
    assert health_status.payload["source_return_activity_event"] == "dashboard-readiness-event-1"
    assert health_status.payload["source_focus_reason"] == "stale_data"
    assert health_status.payload["selected_evidence_kind"] == "source"
    assert health_status.payload["selected_source_evidence_state"] == "stale"
  end

  test "marks stale source inventory evidence targets as missing" do
    {conn, _user, _org, mission} = signed_in_org_and_mission()

    {:ok, view, _html} =
      live(
        conn,
        ~p"/missions/#{mission.mission_id}/ops/data-sources?#{%{data_source_id: "retired-rehearsal-questdb", source_binding_id: "retired-rehearsal-telemetry-binding", logical_source: "telemetry", realm: "rehearsal"}}"
      )

    focus = ops_data_sources_page(view)["focus"]
    assert focus["state"] == "missing"
    assert focus["data_source_id"] == "retired-rehearsal-questdb"
    assert focus["source_binding_id"] == "retired-rehearsal-telemetry-binding"
    assert focus["notice"]["id"] == "source-focus-status"
  end

  test "shows publish blocker remediation for missing source binding focus" do
    {conn, _user, _org, mission} = signed_in_org_and_mission()

    {:ok, view, _html} =
      live(
        conn,
        ~p"/missions/#{mission.mission_id}/ops/data-sources/registration/new?#{%{logical_source: "telemetry", realm: "rehearsal", scope_kind: "spacecraft", scope_id: "spacecraft-1", source_dashboard_id: "dashboard-return-1", source_empty_reason: "missing_source_binding", source_return_activity_event: "dashboard-readiness-event-1", source_return_activity_filter: "publish_readiness", source_return_panel: "versions"}}"
      )

    page = ops_data_sources_page(view)
    focus = page["focus"]
    remediation = focus["remediation"]
    dashboard_return = remediation["dashboard_return"]

    assert remediation["kind"] == "missing_source_binding"
    assert remediation["target"] == "source_registration"
    assert focus["source_dashboard_id"] == "dashboard-return-1"
    assert remediation["action"]["id"] == "source-focus-register-source"
    assert remediation["action"]["event"] == "open_register_source"
    assert remediation["action"]["payload"] == %{}
    assert dashboard_return["dashboard_id"] == "dashboard-return-1"
    assert dashboard_return["panel"] == "versions"
    assert dashboard_return["activity_filter"] == "publish_readiness"
    assert dashboard_return["activity_event"] == "dashboard-readiness-event-1"
    assert dashboard_return["href"] =~ "/ops/dashboards/dashboard-return-1"
    assert dashboard_return["href"] =~ "panel=versions"
    assert dashboard_return["href"] =~ "activity_filter=publish_readiness"
    assert dashboard_return["href"] =~ "activity_event=dashboard-readiness-event-1"
    assert dashboard_return["href"] =~ "refresh_readiness=source_return"
    assert page["admin"]["registration"]["id"] == "register-source-panel"
  end

  defp ops_data_sources_page(view_or_html) do
    view_or_html
    |> LiveVue.Test.get_vue(id: "ops-data-sources-component")
    |> then(& &1.props["page"])
  end

  defp source_row(page, data_source_id) do
    Enum.find(page["sources"]["rows"], &(&1["data_source_id"] == data_source_id))
  end

  defp binding_row(page, binding_id) do
    page["bindings"]["groups"]
    |> Enum.flat_map(& &1["rows"])
    |> Enum.find(&(&1["binding_id"] == binding_id))
  end

  defp source_action(page, data_source_id, event) do
    page
    |> source_row(data_source_id)
    |> Map.get("actions", [])
    |> Enum.find(&(&1["event"] == event))
  end

  defp resource_row(resource, key) do
    Enum.find(resource["rows"], &(&1["key"] == key))
  end
end
