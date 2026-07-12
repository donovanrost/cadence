defmodule CadenceWeb.OpsDataSourcesFocusLiveTest do
  use CadenceWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias Cadence.Comms.{GroundStation, RoutingRule, Transport}

  alias Cadence.Dashboards.{
    DataBinding,
    DataSource,
    DataSources,
    SourceCredentials,
    SourceHealth
  }

  alias Cadence.SourceEndpoints.SourceEndpoint
  alias CadenceWeb.TestFixtures

  defp signed_in_org_and_mission do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org)
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

    assert {:ok, _transport} = Cadence.persist_transport(org.organization_id, transport)

    source_endpoint =
      SourceEndpoint.new(%{
        mission_id: mission.mission_id,
        source_endpoint_id: "endpoint-alpha",
        display_name: "Goldstone DSS-14",
        source_ref: "provider/goldstone",
        metadata: %{"ground_station_id" => "dss-14"}
      })

    assert {:ok, _source_endpoint} =
             Cadence.persist_source_endpoint(org.organization_id, source_endpoint)

    ground_station =
      GroundStation.new(%{
        mission_id: mission.mission_id,
        ground_station_id: "dss-14",
        display_name: "Goldstone DSS-14",
        provider: "DSN",
        region: "goldstone"
      })

    assert {:ok, _ground_station} =
             Cadence.persist_ground_station(org.organization_id, ground_station)

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

    assert {:ok, routing_rule} = Cadence.create_routing_rule(org.organization_id, routing_rule)
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

    assert has_element?(
             view,
             ~s(#ops-data-sources-page[data-source-focus-state="matched"][data-source-focus-data-source="focus-rehearsal-questdb"][data-source-focus-binding="focus-rehearsal-telemetry-binding"][data-source-focus-contact-id="contact-1"][data-source-focus-source-endpoint-id="endpoint-1"])
           )

    assert has_element?(
             view,
             ~s(#source-focus-status[data-source-focus-state="matched"][data-source-focus-logical-source="telemetry"][data-source-focus-realm="rehearsal"][data-source-focus-scope-kind="spacecraft"][data-source-focus-scope-id="spacecraft-1"][data-source-focus-empty-reason="contact_scope_no_data"])
           )

    assert has_element?(
             view,
             ~s(#data-source-focus-rehearsal-questdb[data-source-focus])
           )

    assert has_element?(
             view,
             ~s(#source-binding-focus-rehearsal-telemetry-binding[data-source-focus])
           )
  end

  test "focuses operational resource context from dashboard inspector source actions" do
    {conn, _user, org, mission} = signed_in_org_and_mission()
    persist_focus_inventory!(org, mission)
    routing_rule = persist_focus_operational_resources!(org, mission)
    link_id = routing_rule.materialized_link_assignment_id

    {:ok, view, _html} =
      live(
        conn,
        ~p"/missions/#{mission.mission_id}/ops/data-sources?#{%{data_source_id: "focus-rehearsal-questdb", source_binding_id: "focus-rehearsal-telemetry-binding", logical_source: "telemetry", realm: "rehearsal", selected_target: "transport", selected_id: "transport-alpha", transport_id: "transport-alpha", source_endpoint_id: "endpoint-alpha", ground_station_id: "dss-14", link_id: link_id}}"
      )

    assert has_element?(
             view,
             ~s(#ops-data-sources-page[data-source-focus-state="matched"][data-source-focus-selected-target="transport"][data-source-focus-selected-id="transport-alpha"][data-source-focus-transport-id="transport-alpha"][data-source-focus-source-endpoint-id="endpoint-alpha"][data-source-focus-ground-station-id="dss-14"][data-source-focus-link-id="#{link_id}"])
           )

    assert has_element?(
             view,
             ~s(#source-focus-status[data-source-focus-state="matched"][data-source-focus-selected-target="transport"][data-source-focus-selected-id="transport-alpha"]),
             "transport_id=transport-alpha"
           )

    assert has_element?(
             view,
             ~s(#source-focus-resource[data-source-resource-selected-target="transport"][data-source-resource-selected-id="transport-alpha"][data-source-resource-transport-id="transport-alpha"][data-source-resource-source-endpoint-id="endpoint-alpha"][data-source-resource-ground-station-id="dss-14"][data-source-resource-link-id="#{link_id}"])
           )

    assert has_element?(
             view,
             ~s(#source-focus-resource [data-source-resource-link="transport_id"][href="/missions/#{mission.mission_id}/comms/transports/transport-alpha"])
           )

    assert has_element?(
             view,
             ~s(#source-focus-resource [data-source-resource-link="source_endpoint_id"][href="/missions/#{mission.mission_id}/comms?source_endpoint_id=endpoint-alpha"])
           )

    assert has_element?(
             view,
             ~s(#source-focus-resource [data-source-resource-row="transport_id"][data-source-resource-row-value="transport-alpha"][data-source-resource-row-name="Lab TCP / tcp_socket"][data-source-resource-row-status="resolved"])
           )

    assert has_element?(
             view,
             ~s(#source-focus-resource [data-source-resource-row="source_endpoint_id"][data-source-resource-row-value="endpoint-alpha"][data-source-resource-row-name="Goldstone DSS-14 / provider/goldstone"][data-source-resource-row-status="resolved"])
           )

    assert has_element?(
             view,
             ~s(#source-focus-resource [data-source-resource-row="ground_station_id"][data-source-resource-row-value="dss-14"][data-source-resource-row-name="Goldstone DSS-14"][data-source-resource-row-status="resolved"])
           )

    assert has_element?(
             view,
             ~s(#source-focus-resource [data-source-resource-link="ground_station_id"][href="/missions/#{mission.mission_id}/comms/ground-stations/dss-14"])
           )

    assert has_element?(
             view,
             ~s(#source-focus-resource [data-source-resource-row="link_id"][data-source-resource-row-value="#{link_id}"][data-source-resource-row-status="resolved"])
           )

    assert has_element?(
             view,
             ~s(#source-focus-resource [data-source-resource-link="link_id"][href="/missions/#{mission.mission_id}/comms/routing/#{routing_rule.routing_rule_id}"])
           )

    assert has_element?(
             view,
             ~s(#data-source-focus-rehearsal-questdb[data-source-focus])
           )

    assert has_element?(
             view,
             ~s(#source-binding-focus-rehearsal-telemetry-binding[data-source-focus])
           )

    view
    |> element("#probe-source-focus-rehearsal-questdb")
    |> render_click()

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
        ~p"/missions/#{mission.mission_id}/ops/data-sources?#{%{data_source_id: "focus-rehearsal-questdb", source_binding_id: "focus-rehearsal-telemetry-binding", logical_source: "telemetry", realm: "rehearsal", source_empty_reason: "stale_data", selected_evidence_kind: "source", selected_source_evidence_mode: "health", selected_source_evidence_state: "stale", source_dashboard_id: "dashboard-return-1", source_return_activity_event: "dashboard-readiness-event-1", source_return_activity_filter: "publish_readiness", source_return_panel: "versions"}}"
      )

    assert has_element?(
             view,
             ~s(#ops-data-sources-page[data-source-focus-state="matched"][data-source-focus-evidence-kind="source"][data-source-focus-evidence-mode="health"][data-source-focus-evidence-state="stale"])
           )

    assert has_element?(
             view,
             ~s(#source-focus-status[data-source-focus-state="matched"][data-source-focus-empty-reason="stale_data"][data-source-focus-evidence-state="stale"])
           )

    assert has_element?(
             view,
             ~s(#source-focus-evidence[data-source-evidence-kind="source"][data-source-evidence-mode="health"][data-source-evidence-state="stale"][data-source-evidence-reason="stale_data"]),
             "Source freshness evidence is stale"
           )

    refute has_element?(view, "#source-focus-remediation")

    assert has_element?(
             view,
             ~s(#source-focus-evidence-dashboard-return[data-source-focus-dashboard-return="dashboard-return-1"][data-source-focus-dashboard-return-activity-event="dashboard-readiness-event-1"][href*="refresh_readiness=source_return"])
           )

    view
    |> element("#probe-source-focus-rehearsal-questdb")
    |> render_click()

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

    assert has_element?(
             view,
             ~s(#ops-data-sources-page[data-source-focus-state="missing"][data-source-focus-data-source="retired-rehearsal-questdb"][data-source-focus-binding="retired-rehearsal-telemetry-binding"])
           )

    assert has_element?(
             view,
             ~s(#source-focus-status[data-source-focus-state="missing"])
           )
  end

  test "shows publish blocker remediation for missing source binding focus" do
    {conn, _user, _org, mission} = signed_in_org_and_mission()

    {:ok, view, _html} =
      live(
        conn,
        ~p"/missions/#{mission.mission_id}/ops/data-sources?#{%{logical_source: "telemetry", realm: "rehearsal", scope_kind: "spacecraft", scope_id: "spacecraft-1", source_dashboard_id: "dashboard-return-1", source_empty_reason: "missing_source_binding", source_return_activity_event: "dashboard-readiness-event-1", source_return_activity_filter: "publish_readiness", source_return_panel: "versions"}}"
      )

    assert has_element?(
             view,
             ~s(#source-focus-remediation[data-source-remediation-kind="missing_source_binding"][data-source-remediation-target="source_registration"])
           )

    assert has_element?(
             view,
             ~s(#source-focus-status[data-source-focus-dashboard="dashboard-return-1"])
           )

    assert has_element?(view, "#source-focus-register-source")

    assert has_element?(
             view,
             ~s(#source-focus-dashboard-return[data-source-focus-dashboard-return="dashboard-return-1"][data-source-focus-dashboard-return-panel="versions"][data-source-focus-dashboard-return-activity-filter="publish_readiness"][data-source-focus-dashboard-return-activity-event="dashboard-readiness-event-1"][href*="/ops/dashboards/dashboard-return-1"][href*="panel=versions"][href*="activity_filter=publish_readiness"][href*="activity_event=dashboard-readiness-event-1"][href*="refresh_readiness=source_return"])
           )

    view
    |> element("#source-focus-register-source")
    |> render_click()

    assert has_element?(view, "#register-source-panel")
  end
end
