defmodule CadenceWeb.OpsDataSourcesCapabilityRemediationLiveTest do
  use CadenceWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias Cadence.Management.DataSources

  alias Cadence.Management.DataSources.Credentials, as: SourceCredentials

  alias Cadence.DataSources.{DataBinding, DataSource}
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

    page = ops_data_sources_page(view)
    remediation = page["focus"]["remediation"]

    assert remediation["kind"] == "unsupported_source_capability"
    assert remediation["target"] == "binding"
    assert remediation["target_id"] == "focus-rehearsal-telemetry-binding"
    assert remediation["action"]["id"] == "source-focus-review-binding"

    assert remediation["action"]["href"] ==
             "#source-binding-focus-rehearsal-telemetry-binding"

    assert remediation["dashboard_return"]["dashboard_id"] == "dashboard-return-1"
    assert remediation["dashboard_return"]["href"] =~ "/ops/dashboards/dashboard-return-1"
    assert remediation["dashboard_return"]["href"] =~ "activity_filter=publish_readiness"
    assert binding_row(page, "focus-rehearsal-telemetry-binding")["focused"] == true

    sampling = capability_row(remediation, "sampling")
    assert sampling["requested"] == "bounded_history"
    assert sampling["supported"] == "latest"

    products = capability_row(remediation, "products")
    assert products["requested"] == "bounded_receipt_time_history"
    assert products["supported"] == "latest_value"

    value_kinds = capability_row(remediation, "value_kinds")
    assert value_kinds["requested"] == "engineering"
    assert value_kinds["supported"] == "raw"

    compatible = candidate_row(remediation, "focus-history-telemetry-alt")
    assert compatible["compatible"] == true
    assert compatible["missing_text"] == "none"

    blocked = candidate_row(remediation, "focus-latest-only-telemetry")
    assert blocked["compatible"] == false
    assert blocked["missing_text"] =~ "sampling=bounded_history"
  end

  test "shows operational metric history capability products in source remediation" do
    {conn, _user, org, mission} = signed_in_org_and_mission()
    persist_operational_history_focus_inventory!(org, mission)

    {:ok, view, _html} =
      live(
        conn,
        ~p"/missions/#{mission.mission_id}/ops/data-sources/focus-operational-latest-rf-history/settings?#{%{source_binding_id: "focus-operational-observables-binding", logical_source: "operational_observables", realm: "flight", source_dashboard_id: "dashboard-return-1", source_empty_reason: "unsupported_source_capability", source_return_activity_filter: "publish_readiness", source_return_panel: "versions", requested_sampling: "raw_series", supported_sampling: "latest,event_history", requested_products: "link_rf", requested_source_products: "link_rf_metric_history", supported_products: "link_rf_metric_history", requested_product_families: "link_rf", supported_product_families: "link_rf"}}"
      )

    page = ops_data_sources_page(view)
    focus = page["focus"]
    remediation = focus["remediation"]

    assert focus["requested_source_products"] == "link_rf_metric_history"
    assert focus["requested_product_families"] == "link_rf"

    history_source = source_row(page, "focus-operational-rf-history")
    assert history_source["supported_sampling_text"] =~ "raw_series"
    assert history_source["supported_metric_history_products_text"] == "link_rf_metric_history"
    assert history_source["supported_product_families_text"] == "link_rf"

    bitrate_source = source_row(page, "focus-operational-bitrate-history")

    assert bitrate_source["supported_metric_history_products_text"] ==
             "transport_bitrate_history"

    assert bitrate_source["supported_product_families_text"] == "transport_bitrate"

    assert capability_row(remediation, "source_products")["requested"] ==
             "link_rf_metric_history"

    assert capability_row(remediation, "product_families")["requested"] == "link_rf"

    compatible = candidate_row(remediation, "focus-operational-rf-history")
    assert compatible["compatible"] == true
    assert compatible["missing_text"] == "none"

    latest = candidate_row(remediation, "focus-operational-latest-rf-history")
    assert latest["compatible"] == false
    assert latest["missing_text"] =~ "sampling=raw_series"

    bitrate = candidate_row(remediation, "focus-operational-bitrate-history")
    assert bitrate["compatible"] == false
    assert bitrate["missing_text"] =~ "source_products=link_rf_metric_history"
    assert bitrate["missing_text"] =~ "product_families=link_rf"

    render_hook(view, "open_change_binding", %{
      "binding-id" => "focus-operational-observables-binding"
    })

    option_values = binding_option_values(view)
    assert "focus-operational-rf-history" in option_values
    refute "focus-operational-latest-rf-history" in option_values
    refute "focus-operational-bitrate-history" in option_values
  end

  test "shows operational latest aggregate capability products in source remediation" do
    {conn, _user, org, mission} = signed_in_org_and_mission()
    persist_operational_history_focus_inventory!(org, mission)

    {:ok, view, _html} =
      live(
        conn,
        ~p"/missions/#{mission.mission_id}/ops/data-sources?#{%{data_source_id: "focus-operational-rf-history", source_binding_id: "focus-operational-observables-binding", logical_source: "operational_observables", realm: "flight", source_dashboard_id: "dashboard-return-1", source_empty_reason: "unsupported_source_capability", source_return_activity_filter: "publish_readiness", source_return_panel: "versions", requested_sampling: "latest", supported_sampling: "raw_series", requested_products: "link_rf", requested_source_products: "link_rf_metric", supported_products: "link_rf_metric_history", requested_product_families: "link_rf", supported_product_families: "link_rf"}}"
      )

    page = ops_data_sources_page(view)
    latest = source_row(page, "focus-operational-latest-aggregate")
    remediation = page["focus"]["remediation"]

    assert latest["supported_products_text"] == "operational_latest"
    assert latest["supported_product_families_text"] =~ "link_rf"

    compatible = candidate_row(remediation, "focus-operational-latest-aggregate")
    assert compatible["compatible"] == true
    assert compatible["missing_text"] == "none"

    blocked = candidate_row(remediation, "focus-operational-rf-history")
    assert blocked["compatible"] == false
    assert blocked["missing_text"] =~ "source_products=link_rf_metric"
  end

  test "filters focused capability blocker binding changes to sources that satisfy the request" do
    {conn, _user, org, mission} = signed_in_org_and_mission()
    persist_telemetry_capability_focus_inventory!(org, mission)

    {:ok, view, _html} =
      live(
        conn,
        ~p"/missions/#{mission.mission_id}/ops/data-sources/focus-rehearsal-questdb/settings?#{%{source_binding_id: "focus-rehearsal-telemetry-binding", logical_source: "telemetry", realm: "rehearsal", source_dashboard_id: "dashboard-return-1", source_empty_reason: "unsupported_source_capability", source_return_activity_event: "dashboard-readiness-event-2", source_return_activity_filter: "publish_readiness", source_return_panel: "versions", requested_sampling: "bounded_history", supported_sampling: "latest", requested_products: "bounded_receipt_time_history", supported_products: "latest_value", requested_value_kinds: "engineering", supported_value_kinds: "raw"}}"
      )

    render_hook(view, "open_change_binding", %{
      "binding-id" => "focus-rehearsal-telemetry-binding"
    })

    option_values = binding_option_values(view)
    assert "focus-history-telemetry-alt" in option_values
    assert "focus-rehearsal-questdb" in option_values
    refute "focus-latest-only-telemetry" in option_values

    render_hook(view, "change_binding", %{
      "binding" => %{"data_source_id" => "focus-history-telemetry-alt"}
    })

    assert binding_row(ops_data_sources_page(view), "focus-rehearsal-telemetry-binding")[
             "data_source_id"
           ] == "focus-history-telemetry-alt"

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

  defp capability_row(remediation, key) do
    Enum.find(remediation["capability_rows"], &(&1["key"] == key))
  end

  defp candidate_row(remediation, data_source_id) do
    Enum.find(remediation["candidate_rows"], &(&1["data_source_id"] == data_source_id))
  end

  defp binding_option_values(view_or_html) do
    view_or_html
    |> ops_data_sources_page()
    |> get_in(["admin", "binding_form", "source_options"])
    |> Enum.map(& &1["value"])
  end
end
