defmodule CadenceWeb.OpsDataSourcesCapabilityRemediationLiveTest do
  use CadenceWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias Cadence.Dashboards.{DataBinding, DataSource, DataSources, SourceCredentials}
  alias CadenceWeb.TestFixtures

  defp signed_in_org_and_mission do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org, role: :organization_admin)
    mission = TestFixtures.persist_mission!(org, slug: "ops", display_name: "Ops Mission")

    {TestFixtures.member_conn(user), user, org, mission}
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

  defp persist_telemetry_capability_focus_inventory!(org, mission) do
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

  test "shows telemetry history capability mismatch in source remediation" do
    {conn, _user, org, mission} = signed_in_org_and_mission()
    persist_telemetry_capability_focus_inventory!(org, mission)

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

  test "shows operational metric history capability products in source remediation" do
    {conn, _user, org, mission} = signed_in_org_and_mission()
    persist_operational_history_focus_inventory!(org, mission)

    {:ok, view, _html} =
      live(
        conn,
        ~p"/missions/#{mission.mission_id}/ops/data-sources/focus-operational-latest-rf-history/settings?#{%{source_binding_id: "focus-operational-observables-binding", logical_source: "operational_observables", realm: "flight", source_dashboard_id: "dashboard-return-1", source_empty_reason: "unsupported_source_capability", source_return_activity_filter: "publish_readiness", source_return_panel: "versions", requested_sampling: "raw_series", supported_sampling: "latest,event_history", requested_products: "link_rf", requested_source_products: "link_rf_metric_history", supported_products: "link_rf_metric_history", requested_product_families: "link_rf", supported_product_families: "link_rf"}}"
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

  test "filters focused capability blocker binding changes to sources that satisfy the request" do
    {conn, _user, org, mission} = signed_in_org_and_mission()
    persist_telemetry_capability_focus_inventory!(org, mission)

    {:ok, view, _html} =
      live(
        conn,
        ~p"/missions/#{mission.mission_id}/ops/data-sources/focus-rehearsal-questdb/settings?#{%{source_binding_id: "focus-rehearsal-telemetry-binding", logical_source: "telemetry", realm: "rehearsal", source_dashboard_id: "dashboard-return-1", source_empty_reason: "unsupported_source_capability", source_return_activity_event: "dashboard-readiness-event-2", source_return_activity_filter: "publish_readiness", source_return_panel: "versions", requested_sampling: "bounded_history", supported_sampling: "latest", requested_products: "bounded_receipt_time_history", supported_products: "latest_value", requested_value_kinds: "engineering", supported_value_kinds: "raw"}}"
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
end
