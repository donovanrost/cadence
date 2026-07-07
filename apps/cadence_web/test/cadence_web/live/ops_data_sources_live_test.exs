defmodule CadenceWeb.OpsDataSourcesLiveTest do
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
    ManagedQuestDBProvisioningJobs,
    SourceCredentials,
    SourceHealth,
    SourceWatermarks
  }

  alias Cadence.SourceEndpoints.SourceEndpoint
  alias Cadence.Telemetry.Storage.QuestDB.{ObservationReader, ObservationRow}
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

  defp persist_operational_history_focus_inventory!(org, mission) do
    assert {:ok, _source} =
             DataSources.persist_data_source(%DataSource{
               data_source_id: "focus-operational-latest-rf-history",
               owner: :cadence,
               kind: :managed_tsdb,
               adapter: Cadence.Dashboards.Sources.OperationalObservables,
               organization_id: org.organization_id,
               mission_id: mission.mission_id,
               isolation_level: :mission_isolated,
               capabilities: %{
                 latest?: true,
                 range_scan?: false,
                 supported_products: [:link_rf_metric_history]
               },
               metadata: %{storage: :postgres_projection}
             })

    assert {:ok, _source} =
             DataSources.persist_data_source(%DataSource{
               data_source_id: "focus-operational-latest-aggregate",
               owner: :cadence,
               kind: :managed_tsdb,
               adapter: Cadence.Dashboards.Sources.OperationalObservables,
               organization_id: org.organization_id,
               mission_id: mission.mission_id,
               isolation_level: :mission_isolated,
               capabilities: %{
                 latest?: true,
                 range_scan?: false,
                 supported_products: [:operational_latest]
               },
               metadata: %{storage: :postgres_projection}
             })

    assert {:ok, _source} =
             DataSources.persist_data_source(%DataSource{
               data_source_id: "focus-operational-rf-history",
               owner: :cadence,
               kind: :managed_tsdb,
               adapter: Cadence.Dashboards.Sources.OperationalObservables,
               organization_id: org.organization_id,
               mission_id: mission.mission_id,
               isolation_level: :mission_isolated,
               capabilities: %{
                 latest?: true,
                 range_scan?: true,
                 supported_products: [:link_rf_metric_history]
               },
               metadata: %{storage: :postgres_projection}
             })

    assert {:ok, _source} =
             DataSources.persist_data_source(%DataSource{
               data_source_id: "focus-operational-bitrate-history",
               owner: :cadence,
               kind: :managed_tsdb,
               adapter: Cadence.Dashboards.Sources.OperationalObservables,
               organization_id: org.organization_id,
               mission_id: mission.mission_id,
               isolation_level: :mission_isolated,
               capabilities: %{
                 latest?: true,
                 range_scan?: true,
                 supported_products: [:transport_bitrate_history]
               },
               metadata: %{storage: :postgres_projection}
             })

    assert {:ok, _binding} =
             DataSources.persist_data_binding(%DataBinding{
               binding_id: "focus-operational-observables-binding",
               organization_id: org.organization_id,
               mission_id: mission.mission_id,
               realm: :flight,
               logical_source: :operational_observables,
               data_source_id: "focus-operational-latest-rf-history",
               dataset: "operational_observables",
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

  test "shows publish blocker remediation for incompatible source capability focus" do
    {conn, _user, org, mission} = signed_in_org_and_mission()
    persist_focus_inventory!(org, mission)

    {:ok, view, _html} =
      live(
        conn,
        ~p"/missions/#{mission.mission_id}/ops/data-sources?#{%{data_source_id: "focus-rehearsal-questdb", source_binding_id: "focus-rehearsal-telemetry-binding", logical_source: "telemetry", realm: "rehearsal", source_dashboard_id: "dashboard-return-1", source_empty_reason: "unsupported_source_capability", source_return_activity_filter: "publish_readiness", source_return_panel: "versions", requested_sampling: "bounded_history", supported_sampling: "latest", requested_products: "bounded_receipt_time_history", supported_products: "latest_value", requested_value_kinds: "engineering", supported_value_kinds: "raw"}}"
      )

    assert has_element?(
             view,
             ~s(#source-focus-remediation[data-source-remediation-kind="unsupported_source_capability"][data-source-remediation-target="binding"][data-source-remediation-target-id="focus-rehearsal-telemetry-binding"])
           )

    assert has_element?(
             view,
             ~s(#source-focus-review-binding[href="#source-binding-focus-rehearsal-telemetry-binding"])
           )

    assert has_element?(
             view,
             ~s(#source-focus-dashboard-return[data-source-focus-dashboard-return="dashboard-return-1"][href*="/ops/dashboards/dashboard-return-1"][href*="activity_filter=publish_readiness"])
           )

    assert has_element?(
             view,
             ~s(#source-binding-focus-rehearsal-telemetry-binding[data-source-focus])
           )

    assert has_element?(view, "#source-focus-capability-mismatch")

    assert has_element?(
             view,
             ~s([data-source-capability-mismatch-field="sampling"])
           )

    assert has_element?(
             view,
             ~s([data-source-capability-mismatch-requested="sampling"]),
             "bounded_history"
           )

    assert has_element?(
             view,
             ~s([data-source-capability-mismatch-supported="sampling"]),
             "latest"
           )

    assert has_element?(
             view,
             ~s([data-source-capability-mismatch-field="products"])
           )

    assert has_element?(
             view,
             ~s([data-source-capability-mismatch-requested="products"]),
             "bounded_receipt_time_history"
           )

    assert has_element?(
             view,
             ~s([data-source-capability-mismatch-supported="products"]),
             "latest_value"
           )

    assert has_element?(
             view,
             ~s([data-source-capability-mismatch-field="value_kinds"])
           )

    assert has_element?(
             view,
             ~s([data-source-capability-mismatch-requested="value_kinds"]),
             "engineering"
           )

    assert has_element?(
             view,
             ~s([data-source-capability-mismatch-supported="value_kinds"]),
             "raw"
           )

    assert has_element?(view, "#source-focus-capability-candidates")

    assert has_element?(
             view,
             ~s([data-source-capability-candidate="focus-history-telemetry-alt"][data-source-capability-compatible="true"][data-source-capability-missing="none"])
           )

    assert has_element?(
             view,
             ~s([data-source-capability-candidate="focus-latest-only-telemetry"][data-source-capability-compatible="false"][data-source-capability-missing*="sampling=bounded_history"])
           )
  end

  test "filters focused capability blocker binding changes to sources that satisfy the request" do
    {conn, _user, org, mission} = signed_in_org_and_mission()
    persist_focus_inventory!(org, mission)

    {:ok, view, _html} =
      live(
        conn,
        ~p"/missions/#{mission.mission_id}/ops/data-sources?#{%{data_source_id: "focus-rehearsal-questdb", source_binding_id: "focus-rehearsal-telemetry-binding", logical_source: "telemetry", realm: "rehearsal", source_dashboard_id: "dashboard-return-1", source_empty_reason: "unsupported_source_capability", source_return_activity_event: "dashboard-readiness-event-2", source_return_activity_filter: "publish_readiness", source_return_panel: "versions", requested_sampling: "bounded_history", supported_sampling: "latest", requested_products: "bounded_receipt_time_history", supported_products: "latest_value", requested_value_kinds: "engineering", supported_value_kinds: "raw"}}"
      )

    view
    |> element("#change-binding-focus-rehearsal-telemetry-binding")
    |> render_click()

    assert has_element?(
             view,
             ~s(#change-binding-form-focus-rehearsal-telemetry-binding option[value="focus-history-telemetry-alt"])
           )

    assert has_element?(
             view,
             ~s(#change-binding-form-focus-rehearsal-telemetry-binding option[value="focus-rehearsal-questdb"])
           )

    refute has_element?(
             view,
             ~s(#change-binding-form-focus-rehearsal-telemetry-binding option[value="focus-latest-only-telemetry"])
           )

    view
    |> form("#change-binding-form-focus-rehearsal-telemetry-binding",
      binding: %{data_source_id: "focus-history-telemetry-alt"}
    )
    |> render_submit()

    assert has_element?(
             view,
             ~s(#source-binding-focus-rehearsal-telemetry-binding[data-data-source-id="focus-history-telemetry-alt"])
           )

    assert [changed_event | _events] =
             DataSources.list_data_binding_events("focus-rehearsal-telemetry-binding")

    assert changed_event.event_type == :changed
    assert changed_event.payload["source"] == "ops_data_sources_live"
    assert changed_event.payload["source_dashboard_id"] == "dashboard-return-1"
    assert changed_event.payload["source_return_activity_event"] == "dashboard-readiness-event-2"
    assert changed_event.payload["source_focus_reason"] == "unsupported_source_capability"
    assert changed_event.payload["source_focus_binding_id"] == "focus-rehearsal-telemetry-binding"
    assert changed_event.payload["previous_data_source_id"] == "focus-rehearsal-questdb"
    assert changed_event.payload["current_data_source_id"] == "focus-history-telemetry-alt"
  end

  test "shows operational metric history capability products in source remediation" do
    {conn, _user, org, mission} = signed_in_org_and_mission()
    persist_operational_history_focus_inventory!(org, mission)

    {:ok, view, _html} =
      live(
        conn,
        ~p"/missions/#{mission.mission_id}/ops/data-sources?#{%{data_source_id: "focus-operational-latest-rf-history", source_binding_id: "focus-operational-observables-binding", logical_source: "operational_observables", realm: "flight", source_dashboard_id: "dashboard-return-1", source_empty_reason: "unsupported_source_capability", source_return_activity_filter: "publish_readiness", source_return_panel: "versions", requested_sampling: "raw_series", supported_sampling: "latest,event_history", requested_products: "link_rf", requested_source_products: "link_rf_metric_history", supported_products: "link_rf_metric_history", requested_product_families: "link_rf", supported_product_families: "link_rf"}}"
      )

    assert has_element?(
             view,
             ~s(#ops-data-sources-page[data-source-focus-requested-source-products="link_rf_metric_history"][data-source-focus-requested-product-families="link_rf"])
           )

    assert has_element?(
             view,
             ~s(#data-source-focus-operational-rf-history[data-source-supported-sampling*="raw_series"][data-source-supported-metric-history-products="link_rf_metric_history"][data-source-supported-product-families="link_rf"])
           )

    assert has_element?(
             view,
             ~s(#data-source-focus-operational-bitrate-history[data-source-supported-metric-history-products="transport_bitrate_history"][data-source-supported-product-families="transport_bitrate"])
           )

    assert has_element?(
             view,
             ~s([data-source-capability-mismatch-field="source_products"])
           )

    assert has_element?(
             view,
             ~s([data-source-capability-mismatch-requested="source_products"]),
             "link_rf_metric_history"
           )

    assert has_element?(
             view,
             ~s([data-source-capability-mismatch-field="product_families"])
           )

    assert has_element?(
             view,
             ~s([data-source-capability-mismatch-requested="product_families"]),
             "link_rf"
           )

    assert has_element?(
             view,
             ~s([data-source-capability-candidate="focus-operational-rf-history"][data-source-capability-compatible="true"][data-source-capability-missing="none"])
           )

    assert has_element?(
             view,
             ~s([data-source-capability-candidate="focus-operational-latest-rf-history"][data-source-capability-compatible="false"][data-source-capability-missing*="sampling=raw_series"])
           )

    assert has_element?(
             view,
             ~s([data-source-capability-candidate="focus-operational-bitrate-history"][data-source-capability-compatible="false"][data-source-capability-missing*="source_products=link_rf_metric_history"][data-source-capability-missing*="product_families=link_rf"])
           )

    view
    |> element("#change-binding-focus-operational-observables-binding")
    |> render_click()

    assert has_element?(
             view,
             ~s(#change-binding-form-focus-operational-observables-binding option[value="focus-operational-rf-history"])
           )

    refute has_element?(
             view,
             ~s(#change-binding-form-focus-operational-observables-binding option[value="focus-operational-latest-rf-history"])
           )

    refute has_element?(
             view,
             ~s(#change-binding-form-focus-operational-observables-binding option[value="focus-operational-bitrate-history"])
           )
  end

  test "shows operational latest aggregate capability products in source remediation" do
    {conn, _user, org, mission} = signed_in_org_and_mission()
    persist_operational_history_focus_inventory!(org, mission)

    {:ok, view, _html} =
      live(
        conn,
        ~p"/missions/#{mission.mission_id}/ops/data-sources?#{%{data_source_id: "focus-operational-rf-history", source_binding_id: "focus-operational-observables-binding", logical_source: "operational_observables", realm: "flight", source_dashboard_id: "dashboard-return-1", source_empty_reason: "unsupported_source_capability", source_return_activity_filter: "publish_readiness", source_return_panel: "versions", requested_sampling: "latest", supported_sampling: "raw_series", requested_products: "link_rf", requested_source_products: "link_rf_metric", supported_products: "link_rf_metric_history", requested_product_families: "link_rf", supported_product_families: "link_rf"}}"
      )

    assert has_element?(
             view,
             ~s(#data-source-focus-operational-latest-aggregate[data-source-supported-products="operational_latest"][data-source-supported-product-families*="link_rf"])
           )

    assert has_element?(
             view,
             ~s([data-source-capability-candidate="focus-operational-latest-aggregate"][data-source-capability-compatible="true"][data-source-capability-missing="none"])
           )

    assert has_element?(
             view,
             ~s([data-source-capability-candidate="focus-operational-rf-history"][data-source-capability-compatible="false"][data-source-capability-missing*="source_products=link_rf_metric"])
           )
  end

  test "lists mission data sources, bindings, credentials, and source health" do
    {conn, user, org, mission} = signed_in_org_and_mission()

    assert {:ok, _reference, _event} =
             SourceCredentials.register_reference(%{
               credentials_ref: "cred-rehearsal-questdb",
               organization_id: org.organization_id,
               mission_id: mission.mission_id,
               data_source_id: "rehearsal-questdb",
               owner: :customer,
               kind: :byo_tsdb_connection,
               provider: "questdb",
               metadata: %{vault_path: "cadence/rehearsal/questdb"}
             })

    assert {:ok, _source} =
             DataSources.persist_data_source(%DataSource{
               data_source_id: "rehearsal-questdb",
               owner: :customer,
               kind: :byo_tsdb,
               adapter: Cadence.Dashboards.Sources.Telemetry,
               organization_id: org.organization_id,
               mission_id: mission.mission_id,
               isolation_level: :customer_owned,
               credentials_ref: "cred-rehearsal-questdb",
               capabilities: %{latest?: true, range_scan?: true, watermarks?: true},
               metadata: %{storage: :questdb}
             })

    assert {:ok, _source} =
             DataSources.persist_data_source(%DataSource{
               data_source_id: "managed-rehearsal-telemetry",
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
               data_source_id: "failed-connection-telemetry",
               owner: :cadence,
               kind: :managed_tsdb,
               adapter: Cadence.Dashboards.Sources.Telemetry,
               organization_id: org.organization_id,
               mission_id: mission.mission_id,
               isolation_level: :mission_isolated,
               capabilities: %{latest?: true, range_scan?: true, watermarks?: true},
               metadata: %{storage: :questdb}
             })

    assert {:ok, _event, _status} =
             SourceHealth.record_source_health(
               %{
                 organization_id: org.organization_id,
                 mission_id: mission.mission_id,
                 logical_source: :telemetry,
                 data_source_id: "managed-rehearsal-telemetry",
                 source_health: :unavailable,
                 reason: :source_connection_failed,
                 observed_at: DateTime.utc_now()
               },
               invalidate_runtime_cache?: false
             )

    assert {:ok, _event, _status} =
             SourceHealth.record_source_health(
               %{
                 organization_id: org.organization_id,
                 mission_id: mission.mission_id,
                 logical_source: :telemetry,
                 data_source_id: "failed-connection-telemetry",
                 source_health: :healthy,
                 reason: :source_probe_succeeded,
                 observed_at: DateTime.utc_now(),
                 payload: %{
                   connection_test_result: "failed",
                   connection_test_kind: "adapter_io",
                   connection_test_message: "Adapter connection test failed.",
                   probe_metadata: %{
                     probe_diagnostic_kind: "connection_unreachable",
                     probe_diagnostic_stage: "connection_test",
                     probe_remediation: "check_questdb_endpoint"
                   }
                 }
               },
               invalidate_runtime_cache?: false
             )

    assert {:ok, _binding} =
             DataSources.persist_data_binding(%DataBinding{
               binding_id: "rehearsal-telemetry-binding",
               organization_id: org.organization_id,
               mission_id: mission.mission_id,
               realm: :rehearsal,
               logical_source: :telemetry,
               data_source_id: "rehearsal-questdb",
               dataset: "ait-rehearsal",
               priority: 0
             })

    assert {:ok, _event, _status} =
             SourceHealth.record_source_health(
               %{
                 organization_id: org.organization_id,
                 mission_id: mission.mission_id,
                 logical_source: :telemetry,
                 data_source_id: "rehearsal-questdb",
                 source_binding_id: "rehearsal-telemetry-binding",
                 realm: :rehearsal,
                 dataset: "ait-rehearsal",
                 source_health: :degraded,
                 reason: :source_probe_failed,
                 observed_at: ~U[2026-06-21 12:00:00Z],
                 payload: %{
                   probe_metadata: %{
                     source_connection_profile: %{
                       credentials_ref: "cred-rehearsal-questdb",
                       credential_provider: "questdb",
                       credential_kind: "byo_tsdb_connection",
                       credential_owner: "customer",
                       credential_version: 1,
                       credential_status: "active",
                       data_source_id: "rehearsal-questdb",
                       data_source_kind: "byo_tsdb",
                       data_source_owner: "customer",
                       isolation_level: "customer_owned",
                       http_endpoint: "http://customer-rehearsal-questdb:9000",
                       secret_material?: true,
                       secret_material_fields: ["bearer_token", "headers"]
                     }
                   }
                 }
               },
               invalidate_runtime_cache?: false
             )

    assert {:ok, _event, _status} =
             SourceWatermarks.record_source_watermark(
               %{
                 organization_id: org.organization_id,
                 mission_id: mission.mission_id,
                 logical_source: :telemetry,
                 data_source_id: "rehearsal-questdb",
                 source_binding_id: "rehearsal-telemetry-binding",
                 realm: :rehearsal,
                 dataset: "ait-rehearsal",
                 complete_through: ~U[2026-06-21 12:04:00Z],
                 latest_receipt_time: ~U[2026-06-21 12:04:00Z],
                 retention_starts_at: ~U[2026-06-21 11:00:00Z],
                 sample_count: 12,
                 confidence: :best_effort,
                 reason: :telemetry_storage_write,
                 observed_at: ~U[2026-06-21 12:04:01Z]
               },
               invalidate_runtime_cache?: false
             )

    dashboard =
      TestFixtures.persist_dashboard_document!(mission,
        name: "Binding Refresh",
        widgets: [
          %{
            type: :value_tile,
            title: "Counter",
            binding: %{mode: :context, point_id: "HK.counter"}
          }
        ]
      )

    {:ok, dashboard_view, _html} =
      live(conn, ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}")

    render_async(dashboard_view, 1_000)

    {:ok, view, _html} = live(conn, ~p"/missions/#{mission.mission_id}/ops/data-sources")

    assert has_element?(view, "#ops-data-sources-page")

    assert has_element?(
             view,
             ~s(#ops-nav-rail a[href="/missions/#{mission.mission_id}/ops/data-sources"])
           )

    assert has_element?(
             view,
             ~s(#source-readiness-policy[data-source-readiness-policy-id="default"][data-source-readiness-block-health="unavailable"][data-source-readiness-block-freshness="fresh"][data-source-readiness-block-connection-test="failed blocked"])
           )

    assert has_element?(
             view,
             ~s(#source-binding-rehearsal-telemetry-binding[data-logical-source="telemetry"][data-source-realm="rehearsal"][data-data-source-id="rehearsal-questdb"][data-source-health="unknown"][data-source-readiness="ready"][data-source-readiness-policy="default"]),
             "source_health_stale"
           )

    assert has_element?(
             view,
             ~s(#source-binding-rehearsal-telemetry-binding),
             "cred-rehearsal-questdb / active v1"
           )

    assert has_element?(
             view,
             ~s(#data-source-rehearsal-questdb[data-data-source-row="rehearsal-questdb"][data-source-credential-state="active"][data-source-credential-provider="questdb"][data-source-credential-version="1"][data-source-credential-material-state="resolved"][data-source-credential-endpoint="http://customer-rehearsal-questdb:9000"][data-source-credential-secret-fields="bearer_token headers"]),
             "byo_tsdb"
           )

    assert has_element?(
             view,
             ~s(#data-source-rehearsal-questdb),
             "cred material"
           )

    assert has_element?(
             view,
             ~s(#data-source-rehearsal-questdb),
             "bearer_token headers"
           )

    refute render(view) =~ "customer-secret-token"

    assert has_element?(
             view,
             ~s(#data-source-rehearsal-questdb[data-data-source-row="rehearsal-questdb"]),
             "2026-06-21T12:04:00.000000Z"
           )

    assert has_element?(
             view,
             ~s(#data-source-rehearsal-questdb[data-data-source-row="rehearsal-questdb"]),
             "best_effort"
           )

    assert has_element?(
             view,
             ~s(#data-source-managed-rehearsal-telemetry[data-source-health="unavailable"][data-source-readiness="blocked"][data-source-readiness-reasons="source_unavailable"][data-source-readiness-policy="default"]),
             "source_connection_failed"
           )

    assert has_element?(
             view,
             ~s(#data-source-failed-connection-telemetry[data-source-health="healthy"][data-source-readiness="blocked"][data-source-readiness-reasons="connection_test_failed"][data-source-connection-test-result="failed"][data-source-connection-test-kind="adapter_io"])
           )

    assert has_element?(
             view,
             ~s(#data-source-failed-connection-telemetry[data-source-probe-diagnostic-kind="connection_unreachable"][data-source-probe-diagnostic-stage="connection_test"][data-source-probe-remediation="check_questdb_endpoint"]),
             "check_questdb_endpoint"
           )

    assert has_element?(
             view,
             ~s(#dashboard-data-binding-events [data-event-type="registered"]),
             "rehearsal-telemetry-binding"
           )

    assert has_element?(
             view,
             ~s(#dashboard-source-health-events [data-event-type="degraded"]),
             "source_probe_failed"
           )

    assert has_element?(
             view,
             ~s(#dashboard-source-health-events [data-event-probe-diagnostic-kind="connection_unreachable"][data-event-probe-diagnostic-stage="connection_test"][data-event-probe-remediation="check_questdb_endpoint"])
           )

    view
    |> element("#change-binding-rehearsal-telemetry-binding")
    |> render_click()

    assert has_element?(view, "#change-binding-form-rehearsal-telemetry-binding")

    view
    |> form("#change-binding-form-rehearsal-telemetry-binding",
      binding: %{data_source_id: "managed-rehearsal-telemetry"}
    )
    |> render_submit()

    assert has_element?(
             view,
             ~s(#source-binding-rehearsal-telemetry-binding[data-data-source-id="managed-rehearsal-telemetry"])
           )

    assert {:ok, updated_binding} = DataSources.fetch_data_binding("rehearsal-telemetry-binding")
    assert updated_binding.data_source_id == "managed-rehearsal-telemetry"

    assert [changed_event | _events] =
             DataSources.list_data_binding_events("rehearsal-telemetry-binding")

    assert changed_event.event_type == :changed
    assert changed_event.actor_id == user.user_id
    assert changed_event.previous_data_source_id == "rehearsal-questdb"
    assert changed_event.current_data_source_id == "managed-rehearsal-telemetry"
    assert changed_event.payload["source"] == "ops_data_sources_live"

    render_async(dashboard_view, 1_000)

    assert has_element?(
             dashboard_view,
             ~s(#ops-dashboard-show-page[data-runtime-last-invalidation-boundary="data_source_binding_changed"][data-runtime-last-invalidation-refresh-reason="runtime_invalidation"])
           )
  end

  test "renders managed TSDB deployment status on source rows" do
    {conn, _user, org, mission} = signed_in_org_and_mission()

    assert {:ok, _source} =
             DataSources.persist_data_source(%DataSource{
               data_source_id: "managed-mission-questdb",
               owner: :cadence,
               kind: :managed_tsdb,
               adapter: Cadence.Dashboards.Sources.Telemetry,
               organization_id: org.organization_id,
               mission_id: mission.mission_id,
               isolation_level: :mission_isolated,
               capabilities: %{latest?: true, range_scan?: true, watermarks?: true},
               metadata: %{
                 storage: :questdb,
                 provisioning_mode: :managed_questdb,
                 provisioning: %{
                   provisioner: :managed_questdb,
                   storage: :questdb,
                   deployment_backend: :questdb,
                   deployment_status: :ready,
                   physical_boundary: :mission,
                   applied_migration_count: 2,
                   applied_migration_versions: ["20260630010101", "20260630020202"]
                 }
               }
             })

    {:ok, view, _html} = live(conn, ~p"/missions/#{mission.mission_id}/ops/data-sources")

    assert has_element?(
             view,
             ~s(#data-source-managed-mission-questdb[data-source-deployment-status="ready"][data-source-deployment-mode="managed_questdb"][data-source-deployment-backend="questdb"][data-source-deployment-boundary="mission"][data-source-deployment-remediation="probe_source_health"]),
             "deploy fix"
           )
  end

  test "renders managed TSDB deployment runs before sources exist" do
    {conn, _user, org, mission} = signed_in_org_and_mission()
    previous_config = Application.get_env(:cadence, :dashboard_managed_questdb_provisioning)

    on_exit(fn ->
      if is_nil(previous_config) do
        Application.delete_env(:cadence, :dashboard_managed_questdb_provisioning)
      else
        Application.put_env(:cadence, :dashboard_managed_questdb_provisioning, previous_config)
      end
    end)

    Application.put_env(:cadence, :dashboard_managed_questdb_provisioning,
      provisioner: fn attrs, _opts ->
        assert attrs["data_source_id"] == "failed-managed-questdb"
        {:error, {:questdb_unavailable, endpoint: "redacted-endpoint-ref"}}
      end
    )

    assert {:ok, failed_job} =
             ManagedQuestDBProvisioningJobs.enqueue(%{
               data_source_id: "failed-managed-questdb",
               organization_id: org.organization_id,
               mission_id: mission.mission_id,
               isolation_level: :mission_isolated,
               endpoint_ref: "endpoint://cadence/failed-managed-questdb",
               topology_ref: "topology://cadence/failed-managed-questdb",
               provisioning_run_id: "failed-managed-questdb-run",
               actor_id: "operator-1"
             })

    assert [claimed_job] = Cadence.Jobs.claim_jobs(1)
    assert claimed_job.job_id == failed_job.job_id
    assert {:ok, _failed_job} = Cadence.Jobs.run_job(claimed_job.job_id)

    assert {:ok, running_job} =
             ManagedQuestDBProvisioningJobs.enqueue(%{
               data_source_id: "running-managed-questdb",
               organization_id: org.organization_id,
               mission_id: mission.mission_id,
               isolation_level: :mission_isolated,
               endpoint_ref: "endpoint://cadence/running-managed-questdb",
               topology_ref: "topology://cadence/running-managed-questdb",
               provisioning_run_id: "running-managed-questdb-run",
               actor_id: "operator-1"
             })

    assert [claimed_running_job] = Cadence.Jobs.claim_jobs(1)
    assert claimed_running_job.job_id == running_job.job_id

    assert {:ok, queued_job} =
             ManagedQuestDBProvisioningJobs.enqueue(%{
               data_source_id: "queued-managed-questdb",
               organization_id: org.organization_id,
               mission_id: mission.mission_id,
               isolation_level: :mission_isolated,
               endpoint_ref: "endpoint://cadence/queued-managed-questdb",
               topology_ref: "topology://cadence/queued-managed-questdb",
               provisioning_run_id: "queued-managed-questdb-run",
               actor_id: "operator-1"
             })

    {:ok, view, _html} = live(conn, ~p"/missions/#{mission.mission_id}/ops/data-sources")

    assert has_element?(
             view,
             ~s(#deployment-run-failed-managed-questdb-run[data-deployment-run-job-id="#{failed_job.job_id}"][data-deployment-run-data-source-id="failed-managed-questdb"][data-deployment-run-status="failed"][data-deployment-run-backend="questdb"][data-deployment-run-boundary="mission"][data-deployment-run-failure-summary="questdb_unavailable"][data-deployment-run-remediation="inspect_provisioning_job_and_retry"]),
             "failed-managed-questdb"
           )

    assert has_element?(
             view,
             ~s(#deployment-run-queued-managed-questdb-run[data-deployment-run-job-id="#{queued_job.job_id}"][data-deployment-run-data-source-id="queued-managed-questdb"][data-deployment-run-status="queued"][data-deployment-run-backend="questdb"][data-deployment-run-boundary="mission"][data-deployment-run-failure-summary="none"][data-deployment-run-remediation="wait_for_provisioning_worker"]),
             "queued-managed-questdb"
           )

    assert has_element?(
             view,
             ~s(#deployment-run-running-managed-questdb-run[data-deployment-run-job-id="#{running_job.job_id}"][data-deployment-run-data-source-id="running-managed-questdb"][data-deployment-run-status="provisioning"][data-deployment-run-backend="questdb"][data-deployment-run-boundary="mission"][data-deployment-run-failure-summary="none"][data-deployment-run-remediation="monitor_schema_migration_job"]),
             "running-managed-questdb"
           )

    view
    |> element("#retry-deployment-run-failed-managed-questdb-run")
    |> render_click()

    assert has_element?(
             view,
             ~s(#deployment-run-failed-managed-questdb-run[data-deployment-run-job-id="#{failed_job.job_id}"][data-deployment-run-status="queued"][data-deployment-run-failure-summary="none"][data-deployment-run-remediation="wait_for_provisioning_worker"])
           )

    refute has_element?(view, "#retry-deployment-run-failed-managed-questdb-run")

    assert {:ok, retried_job} = Cadence.Jobs.fetch_job(failed_job.job_id)
    assert retried_job.status == :queued
    assert retried_job.failure_reason == nil

    view
    |> element("#requeue-deployment-run-running-managed-questdb-run")
    |> render_click()

    assert has_element?(
             view,
             ~s(#deployment-run-running-managed-questdb-run[data-deployment-run-job-id="#{running_job.job_id}"][data-deployment-run-status="queued"][data-deployment-run-failure-summary="managed_questdb_provisioning_requeued"][data-deployment-run-remediation="wait_for_provisioning_worker"])
           )

    refute has_element?(view, "#requeue-deployment-run-running-managed-questdb-run")

    assert {:ok, requeued_job} = Cadence.Jobs.fetch_job(running_job.job_id)
    assert requeued_job.status == :queued
    assert requeued_job.failure_reason == %{"reason" => "managed_questdb_provisioning_requeued"}
  end

  test "registers a BYO mission data source and exposes it to binding changes" do
    {conn, user, org, mission} = signed_in_org_and_mission()
    test_pid = self()
    previous_credential_config = Application.get_env(:cadence, :dashboard_source_credentials, [])
    previous_probe_config = Application.get_env(:cadence, :dashboard_source_probe, [])

    System.put_env("OPS_CUSTOMER_QUESTDB_HTTP", "http://ops-customer-questdb:9000")

    Application.put_env(
      :cadence,
      :dashboard_source_credentials,
      Keyword.merge(previous_credential_config,
        material_resolver: {Cadence.Dashboards.SourceCredentials.EnvMaterialResolver, :resolve}
      )
    )

    Application.put_env(
      :cadence,
      :dashboard_source_probe,
      Keyword.merge(previous_probe_config,
        questdb_exec_fun: questdb_probe_exec_fun(test_pid)
      )
    )

    on_exit(fn ->
      Application.put_env(:cadence, :dashboard_source_credentials, previous_credential_config)
      Application.put_env(:cadence, :dashboard_source_probe, previous_probe_config)
      System.delete_env("OPS_CUSTOMER_QUESTDB_HTTP")
    end)

    assert {:ok, _source} =
             DataSources.persist_data_source(%DataSource{
               data_source_id: "seed-telemetry",
               owner: :cadence,
               kind: :managed_tsdb,
               adapter: Cadence.Dashboards.Sources.Telemetry,
               organization_id: org.organization_id,
               mission_id: mission.mission_id,
               isolation_level: :mission_isolated,
               capabilities: %{latest?: true, range_scan?: true, watermarks?: true},
               metadata: %{storage: :questdb}
             })

    assert {:ok, _binding} =
             DataSources.persist_data_binding(%DataBinding{
               binding_id: "flight-telemetry-binding",
               organization_id: org.organization_id,
               mission_id: mission.mission_id,
               realm: :flight,
               logical_source: :telemetry,
               data_source_id: "seed-telemetry",
               dataset: "flight",
               priority: 0
             })

    {:ok, view, _html} = live(conn, ~p"/missions/#{mission.mission_id}/ops/data-sources")

    view
    |> element("#register-source-button")
    |> render_click()

    assert has_element?(view, "#register-source-panel")

    view
    |> form("#register-source-form",
      source: %{
        data_source_id: "customer-telemetry-questdb",
        logical_source: "telemetry",
        kind: "byo_tsdb",
        isolation_level: "customer_owned",
        credentials_ref: "cred-customer-telemetry",
        credential_provider: "questdb",
        endpoint_ref: "endpoint://customer/ops",
        material_env_profile: "ops-customer-questdb",
        http_endpoint_env: "OPS_CUSTOMER_QUESTDB_HTTP",
        storage: "questdb"
      }
    )
    |> render_submit()

    assert has_element?(
             view,
             ~s(#data-source-customer-telemetry-questdb[data-data-source-row="customer-telemetry-questdb"]),
             "byo_tsdb"
           )

    assert has_element?(
             view,
             ~s(#data-source-customer-telemetry-questdb),
             "cred-customer-telemetry / active v1"
           )

    assert {:ok, reference} = SourceCredentials.fetch_reference("cred-customer-telemetry")
    assert reference.organization_id == org.organization_id
    assert reference.mission_id == mission.mission_id
    assert reference.data_source_id == "customer-telemetry-questdb"
    assert reference.owner == :customer
    assert reference.kind == :byo_tsdb_connection
    assert reference.provider == "questdb"
    assert reference.metadata["endpoint_ref"] == "endpoint://customer/ops"
    assert reference.metadata["material_env_profile"] == "ops-customer-questdb"
    assert reference.metadata["http_endpoint_env"] == "OPS_CUSTOMER_QUESTDB_HTTP"

    assert [credential_event] = SourceCredentials.list_events("cred-customer-telemetry")
    assert credential_event.actor_id == user.user_id
    assert credential_event.payload["source"] == "ops_data_sources_live"

    assert %DataSource{} =
             source =
             org.organization_id
             |> DataSources.list_data_sources(mission.mission_id)
             |> Enum.find(&(&1.data_source_id == "customer-telemetry-questdb"))

    assert source.adapter == Cadence.Dashboards.Sources.Telemetry
    assert source.isolation_level == :customer_owned
    assert source.credentials_ref == "cred-customer-telemetry"
    assert source.metadata["storage"] == "questdb"
    assert source.metadata["endpoint_ref"] == "endpoint://customer/ops"
    assert source.metadata["material_env_profile"] == "ops-customer-questdb"

    assert [source_event] =
             DataSources.list_data_source_events(org.organization_id, mission.mission_id,
               data_source_id: "customer-telemetry-questdb"
             )

    assert source_event.event_type == :registered
    assert source_event.actor_id == user.user_id
    assert source_event.payload["source"] == "ops_data_sources_live"
    assert source_event.payload["storage"] == "questdb"

    assert has_element?(
             view,
             ~s(#dashboard-data-source-events [data-event-type="registered"]),
             "customer-telemetry-questdb"
           )

    view
    |> element("#probe-source-customer-telemetry-questdb")
    |> render_click()

    assert_receive {:questdb_probe_sql, "SELECT 1", first_probe_opts}
    assert first_probe_opts[:http_endpoint] == "http://ops-customer-questdb:9000"

    assert_receive {:questdb_probe_sql, schema_sql, schema_probe_opts}
    assert schema_sql =~ "FROM telemetry_observations LIMIT 0"
    assert schema_probe_opts[:http_endpoint] == "http://ops-customer-questdb:9000"

    assert has_element?(
             view,
             ~s(#data-source-customer-telemetry-questdb[data-source-health="healthy"])
           )

    assert has_element?(
             view,
             ~s(#data-source-customer-telemetry-questdb[data-source-probe-kind="adapter"][data-source-probe-metadata*="storage=questdb"])
           )

    assert has_element?(
             view,
             ~s(#data-source-customer-telemetry-questdb[data-source-connection-test-result="succeeded"][data-source-connection-test-kind="adapter_io"])
           )

    assert has_element?(
             view,
             ~s(#data-source-customer-telemetry-questdb),
             "Adapter connection test succeeded."
           )

    assert has_element?(
             view,
             ~s(#data-source-customer-telemetry-questdb[data-source-credential-material-state="resolved"][data-source-credential-endpoint="http://ops-customer-questdb:9000"])
           )

    assert has_element?(
             view,
             ~s(#data-source-customer-telemetry-questdb[data-source-probe-metadata*="source_capability_fingerprint=source-capability:"])
           )

    assert {:ok, %DataSource{} = materialized_source} =
             DataSources.fetch_data_source("customer-telemetry-questdb")

    assert materialized_source.capabilities["native_decimation?"] == true
    assert materialized_source.capabilities["watermarks?"] == true
    assert materialized_source.metadata["adapter_capability_discovery?"] == true
    assert materialized_source.metadata["adapter_capability_discovery_source"] == "probe"

    assert materialized_source.metadata["adapter_capability_discovery_fingerprint"] =~
             "source-capability:"

    assert [health_status] =
             SourceHealth.list_source_health_statuses(org.organization_id, mission.mission_id,
               data_source_id: "customer-telemetry-questdb"
             )

    assert health_status.source_health == :healthy
    assert health_status.reason == :source_probe_succeeded
    assert health_status.payload["source"] == "ops_data_sources_live"
    assert health_status.payload["probe_kind"] == "adapter"
    assert health_status.payload["actor_id"] == user.user_id
    assert health_status.payload["connection_test_result"] == "succeeded"
    assert health_status.payload["connection_test_kind"] == "adapter_io"

    assert source_events =
             DataSources.list_data_source_events(org.organization_id, mission.mission_id,
               data_source_id: "customer-telemetry-questdb"
             )

    assert materialized_event =
             Enum.find(source_events, fn event ->
               event.event_type == :changed and
                 event.payload["adapter_capability_discovery?"] == true
             end)

    assert materialized_event.actor_id == user.user_id
    assert materialized_event.payload["source"] == "data_source_probe"

    assert materialized_event.payload["source_health_event_id"] ==
             health_status.source_health_event_id

    assert materialized_event.current_capabilities["native_decimation?"] == true

    assert has_element?(
             view,
             ~s(#dashboard-data-source-events [data-event-type="changed"]),
             "customer-telemetry-questdb"
           )

    assert {:ok, _updated_source} =
             DataSources.persist_data_source(%DataSource{
               materialized_source
               | capabilities: %{range_scan?: false}
             })

    view
    |> element("#probe-source-customer-telemetry-questdb")
    |> render_click()

    assert has_element?(
             view,
             ~s(#data-source-customer-telemetry-questdb[data-source-probe-metadata*="source_capability_drift?=true"])
           )

    assert has_element?(
             view,
             ~s(#dashboard-source-health-events [data-event-type="recovered"]),
             "source_probe_succeeded"
           )

    assert has_element?(
             view,
             ~s(#dashboard-source-health-events [data-event-type="recovered"][data-event-probe-kind="adapter"][data-event-probe-metadata*="storage=questdb"])
           )

    assert has_element?(
             view,
             ~s(#dashboard-source-health-events [data-event-type="recovered"][data-event-connection-test-result="succeeded"][data-event-connection-test-kind="adapter_io"])
           )

    assert has_element?(
             view,
             ~s(#dashboard-source-health-events [data-event-type="recovered"][data-event-probe-metadata*="source_capability_fingerprint=source-capability:"])
           )

    view
    |> element("#disable-source-customer-telemetry-questdb")
    |> render_click()

    assert has_element?(
             view,
             ~s(#data-source-customer-telemetry-questdb[data-source-status="disabled"])
           )

    assert {:ok, disabled_source} = DataSources.fetch_data_source("customer-telemetry-questdb")
    assert disabled_source.status == :disabled
    assert disabled_source.disabled_at

    assert [disabled_event | _events] =
             DataSources.list_data_source_events(org.organization_id, mission.mission_id,
               data_source_id: "customer-telemetry-questdb"
             )

    assert disabled_event.event_type == :disabled
    assert disabled_event.actor_id == user.user_id
    assert disabled_event.payload["source"] == "ops_data_sources_live"

    view
    |> element("#change-binding-flight-telemetry-binding")
    |> render_click()

    refute has_element?(
             view,
             ~s(#change-binding-form-flight-telemetry-binding option[value="customer-telemetry-questdb"])
           )

    view
    |> element("#cancel-change-binding-flight-telemetry-binding")
    |> render_click()

    view
    |> element("#enable-source-customer-telemetry-questdb")
    |> render_click()

    assert has_element?(
             view,
             ~s(#data-source-customer-telemetry-questdb[data-source-status="active"])
           )

    assert {:ok, enabled_source} = DataSources.fetch_data_source("customer-telemetry-questdb")
    assert enabled_source.status == :active
    assert enabled_source.disabled_at == nil

    assert [enabled_event | _events] =
             DataSources.list_data_source_events(org.organization_id, mission.mission_id,
               data_source_id: "customer-telemetry-questdb"
             )

    assert enabled_event.event_type == :enabled
    assert enabled_event.actor_id == user.user_id
    assert enabled_event.payload["source"] == "ops_data_sources_live"

    view
    |> element("#change-binding-flight-telemetry-binding")
    |> render_click()

    assert has_element?(
             view,
             ~s(#change-binding-form-flight-telemetry-binding option[value="customer-telemetry-questdb"])
           )
  end

  defp questdb_probe_exec_fun(test_pid) do
    fn sql, opts ->
      send(test_pid, {:questdb_probe_sql, sql, opts})
      questdb_probe_response(sql)
    end
  end

  defp questdb_probe_response("SELECT 1"),
    do: {:ok, %{"columns" => [%{"name" => "1"}], "dataset" => [[1]]}}

  defp questdb_probe_response(sql) do
    if String.contains?(sql, "FROM telemetry_observations") do
      {:ok, %{"columns" => questdb_probe_columns(), "dataset" => []}}
    else
      flunk("Unexpected QuestDB probe SQL:\n#{sql}")
    end
  end

  defp questdb_probe_columns do
    writer_columns =
      ObservationRow.columns()
      |> Enum.map(&Atom.to_string/1)

    (ObservationReader.select_columns() ++ writer_columns)
    |> Enum.uniq()
    |> Enum.map(&%{"name" => &1})
  end
end
