defmodule CadenceWeb.OpsDataSourcesLiveTest do
  use CadenceWeb.ConnCase, async: false

  import CadenceWeb.OpsDashboardShowLive.ViewTestSupport
  import CadenceWeb.OpsNavTestSupport
  import Phoenix.LiveViewTest

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias Cadence.Dashboards.Sources.Telemetry
  alias Cadence.DataSources.{DataBinding, DataSource}
  alias Cadence.Management.DataSources
  alias Cadence.Management.DataSources.Credentials, as: SourceCredentials
  alias Cadence.Projections.DataSources.Health, as: SourceHealth
  alias Cadence.Projections.DataSources.Watermarks, as: SourceWatermarks
  alias CadenceWeb.TestFixtures
  alias LiveVue.Test
  alias Phoenix.LiveView.JS

  defp signed_in_org_and_mission do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org, role: :organization_admin)
    mission = TestFixtures.persist_mission!(org, slug: "ops", display_name: "Ops Mission")

    {TestFixtures.member_conn(user), user, org, mission}
  end

  defp change_binding_to_managed!(view, user) do
    render_hook(view, "open_change_binding", %{
      "binding-id" => "rehearsal-telemetry-binding"
    })

    binding_form = ops_data_sources_page(view)["admin"]["binding_form"]

    assert binding_form["binding_id"] == "rehearsal-telemetry-binding"
    assert binding_form["form_id"] == "change-binding-form-rehearsal-telemetry-binding"
    assert binding_form["data_source_id"] == "rehearsal-questdb"

    render_hook(view, "change_binding", %{
      "binding" => %{"data_source_id" => "managed-rehearsal-telemetry"}
    })

    assert binding_row(ops_data_sources_page(view), "rehearsal-telemetry-binding")[
             "data_source_id"
           ] ==
             "managed-rehearsal-telemetry"

    assert {:ok, updated_binding} = DataSources.fetch_data_binding("rehearsal-telemetry-binding")
    assert updated_binding.data_source_id == "managed-rehearsal-telemetry"

    assert [changed_event | _events] =
             DataSources.list_data_binding_events("rehearsal-telemetry-binding")

    assert changed_event.event_type == :changed
    assert changed_event.actor_id == user.user_id
    assert changed_event.previous_data_source_id == "rehearsal-questdb"
    assert changed_event.current_data_source_id == "managed-rehearsal-telemetry"
    assert changed_event.payload["source"] == "ops_data_sources_live"
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
               adapter: Telemetry,
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
               adapter: Telemetry,
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
               adapter: Telemetry,
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
      await_live_result(
        live(
          conn,
          ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}"
        )
      )

    {:ok, view, _html} = live(conn, ~p"/missions/#{mission.mission_id}/ops/data-sources")
    track_dashboard_view(view)

    assert has_element?(view, "#ops-data-sources-component.contents")
    refute has_element?(view, "#ops-data-sources-page")

    vue = ops_data_sources_vue(view)
    page = vue.props["page"]

    assert vue.component == "OpsDataSources"
    assert vue.class == "contents"
    assert vue.ssr == false
    assert Map.keys(vue.props) == ["page"]

    assert vue.handlers == %{
             "cancel-change-binding" => JS.push("cancel_change_binding"),
             "cancel-register-source" => JS.push("cancel_register_source"),
             "change-binding" => JS.push("change_binding"),
             "deprovision-tsdb-backend" => JS.push("deprovision_tsdb_backend"),
             "disable-source" => JS.push("disable_source"),
             "enable-source" => JS.push("enable_source"),
             "open-change-binding" => JS.push("open_change_binding"),
             "open-register-source" => JS.push("open_register_source"),
             "probe-source" => JS.push("probe_source"),
             "provision-tsdb-backend" => JS.push("provision_tsdb_backend"),
             "reconcile-tsdb-backend" => JS.push("reconcile_tsdb_backend"),
             "register-source" => JS.push("register_source"),
             "requeue-deployment-run" => JS.push("requeue_deployment_run"),
             "retry-deployment-run" => JS.push("retry_deployment_run"),
             "rotate-source-credential" => JS.push("rotate_source_credential")
           }

    assert page["id"] == "ops-data-sources-page"
    assert page["mode"] == "reader"
    refute Map.has_key?(page, "admin")

    assert ops_nav_item(ops_nav_vue(view), "data_sources") == %{
             "active" => true,
             "href" => "/missions/#{mission.mission_id}/ops/data-sources",
             "icon" => "hero-circle-stack",
             "key" => "data_sources",
             "label" => "Data Sources"
           }

    assert page["header"]["readiness_policy"] == %{
             "id" => "source-readiness-policy",
             "label" => "readiness policy",
             "policy_id" => "default",
             "block_source_health" => "unavailable",
             "block_freshness" => "fresh",
             "block_connection_test" => "failed blocked",
             "connection_summary" => "conn failed blocked"
           }

    binding = binding_row(page, "rehearsal-telemetry-binding")
    assert binding["logical_source_text"] == "telemetry"
    assert binding["realm_text"] == "rehearsal"
    assert binding["data_source_id"] == "rehearsal-questdb"
    assert binding["health_status"] == "unknown"
    assert binding["source_readiness_status"] == "ready"
    assert binding["source_readiness_policy_id"] == "default"
    assert binding["health_reason_text"] == "source_health_stale"
    assert binding["credential_ref_text"] == "cred-rehearsal-questdb / active v1"
    refute Map.has_key?(binding, "change_action")

    source = source_row(page, "rehearsal-questdb")
    assert source["kind_text"] == "byo_tsdb"
    assert source["credential_state_text"] == "active"
    assert source["credential_provider_text"] == "questdb"
    assert source["credential_version_text"] == "1"
    assert source["credential_material_state_text"] == "resolved"
    assert source["credential_endpoint_text"] == "http://customer-rehearsal-questdb:9000"
    assert source["credential_secret_fields_text"] == "bearer_token headers"
    assert source["watermark_text"] == "2026-06-21T12:04:00.000000Z"
    assert source["watermark_confidence_text"] == "best_effort"
    refute Map.has_key?(source, "actions")

    encoded_page = Jason.encode!(page)
    refute encoded_page =~ "cadence/rehearsal/questdb"
    refute encoded_page =~ user.user_id
    assert page == Jason.decode!(encoded_page)

    managed_source = source_row(page, "managed-rehearsal-telemetry")
    assert managed_source["health_status"] == "unavailable"
    assert managed_source["source_readiness_status"] == "blocked"
    assert managed_source["source_readiness_reason_text"] == "source_unavailable"
    assert managed_source["source_readiness_policy_id"] == "default"
    assert managed_source["health_reason_text"] == "source_connection_failed"

    failed_source = source_row(page, "failed-connection-telemetry")
    assert failed_source["health_status"] == "healthy"
    assert failed_source["source_readiness_status"] == "blocked"
    assert failed_source["source_readiness_reason_text"] == "connection_test_failed"
    assert failed_source["connection_test_result_text"] == "failed"
    assert failed_source["connection_test_kind_text"] == "adapter_io"
    assert failed_source["probe_diagnostic_kind_text"] == "connection_unreachable"
    assert failed_source["probe_diagnostic_stage_text"] == "connection_test"
    assert failed_source["probe_remediation_text"] == "check_questdb_endpoint"

    assert Enum.any?(page["activity"]["binding_events"]["rows"], fn event ->
             event["event_type"] == "registered" and
               String.contains?(event["title"], "rehearsal-telemetry-binding")
           end)

    health_events = page["activity"]["health_events"]["rows"]

    assert Enum.any?(health_events, fn event ->
             event["event_type"] == "degraded" and
               String.contains?(event["subtitle"], "source_probe_failed")
           end)

    assert Enum.find(health_events, fn event ->
             event["probe_diagnostic_kind"] == "connection_unreachable" and
               event["probe_diagnostic_stage"] == "connection_test" and
               event["probe_remediation"] == "check_questdb_endpoint"
           end)

    {:ok, settings_view, _html} =
      live(
        conn,
        ~p"/missions/#{mission.mission_id}/ops/data-sources/rehearsal-questdb/settings"
      )

    track_dashboard_view(settings_view)
    change_binding_to_managed!(settings_view, user)

    await_dashboard_resolved(dashboard_view)

    assert has_element?(
             dashboard_view,
             ~s(#ops-dashboard-show-page[data-runtime-last-invalidation-boundary="data_source_binding_changed"][data-runtime-last-invalidation-refresh-reason="runtime_invalidation"])
           )
  end

  defp ops_data_sources_vue(view_or_html) do
    Test.get_vue(view_or_html, id: "ops-data-sources-component")
  end

  defp ops_data_sources_page(view_or_html) do
    ops_data_sources_vue(view_or_html).props["page"]
  end

  defp binding_row(page, binding_id) do
    page["bindings"]["groups"]
    |> Enum.flat_map(& &1["rows"])
    |> Enum.find(&(&1["binding_id"] == binding_id))
  end

  defp source_row(page, data_source_id) do
    Enum.find(page["sources"]["rows"], &(&1["data_source_id"] == data_source_id))
  end
end
