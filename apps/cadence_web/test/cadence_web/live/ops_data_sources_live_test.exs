defmodule CadenceWeb.OpsDataSourcesLiveTest do
  use CadenceWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias Cadence.Dashboards.{
    DataBinding,
    DataSource,
    DataSources,
    SourceCredentials,
    SourceHealth,
    SourceWatermarks
  }

  alias CadenceWeb.TestFixtures

  defp signed_in_org_and_mission do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org)
    mission = TestFixtures.persist_mission!(org, slug: "ops", display_name: "Ops Mission")

    {TestFixtures.member_conn(user), user, org, mission}
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
end
