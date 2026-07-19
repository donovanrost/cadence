defmodule CadenceWeb.OpsDataSourcesLive.SourceActivityPresentationTest do
  use ExUnit.Case, async: true

  alias CadenceWeb.OpsDataSourcesLive.SourceActivityPresentation

  test "presents source health activity while redacting probe secrets" do
    profile = %{"http_endpoint" => "http://questdb.test", "secret_material?" => true}

    event = %{
      source_health_event_id: "health-1",
      event_type: :observed,
      source_health: :healthy,
      logical_source: :telemetry,
      data_source_id: "source-1",
      realm: :flight,
      reason: :source_probe_succeeded,
      observed_at: ~U[2026-07-19 12:00:00Z],
      payload: %{
        "probe_kind" => "questdb",
        "probe_message" => "connected",
        "connection_test_result" => "passed",
        "probe_metadata" => %{
          :api_token => "top-secret-token",
          "password" => "top-secret-password",
          "endpoint" => "http://questdb.test",
          "probe_diagnostic_kind" => "network",
          "source_connection_profile" => profile
        }
      }
    }

    row = SourceActivityPresentation.source_health_event_row(event)

    assert row.id == "source-health-event-health-1"
    assert row.probe_kind == "questdb"
    assert row.probe_diagnostic_kind == "network"
    assert row.connection_test_result == "passed"
    assert row.probe_metadata =~ "api_token=redacted"
    assert row.probe_metadata =~ "password=redacted"
    assert row.probe_metadata =~ "endpoint=http://questdb.test"
    refute row.probe_metadata =~ "top-secret"
    assert SourceActivityPresentation.connection_profile(event) == profile
  end

  test "presents binding and source event identities" do
    occurred_at = ~U[2026-07-19 12:00:00Z]

    assert %{
             id: "binding-event-binding-event-1",
             event_type: "changed",
             title: "changed binding-1",
             subtitle: "telemetry / flight -> source-2",
             occurred_at: "2026-07-19T12:00:00Z"
           } =
             SourceActivityPresentation.binding_event_row(%{
               data_binding_event_id: "binding-event-1",
               event_type: :changed,
               binding_id: "binding-1",
               current_logical_source: :telemetry,
               current_realm: :flight,
               current_data_source_id: "source-2",
               occurred_at: occurred_at
             })

    assert %{
             id: "source-event-source-event-1",
             subtitle: "Cadence.Dashboards.Sources.Telemetry / byo_tsdb / mission_isolated"
           } =
             SourceActivityPresentation.source_event_row(%{
               data_source_event_id: "source-event-1",
               event_type: :registered,
               data_source_id: "source-1",
               current_adapter: Cadence.Dashboards.Sources.Telemetry,
               current_kind: :byo_tsdb,
               current_isolation_level: :mission_isolated,
               occurred_at: occurred_at
             })
  end

  test "presents deployment run lifecycle fields" do
    assert %{
             job_id: "job-1",
             run_id: "run-1",
             attempt_count_text: "2",
             started_at_text: "2026-07-19T12:00:00Z",
             completed_at_text: "none"
           } =
             SourceActivityPresentation.deployment_run_row(%{
               job_id: "job-1",
               run_id: "run-1",
               data_source_id: "source-1",
               status_text: "running",
               mode_text: "managed",
               backend_text: "questdb",
               physical_boundary_text: "mission",
               attempt_count: 2,
               failure_summary: nil,
               started_at: ~U[2026-07-19 12:00:00Z],
               completed_at: nil,
               remediation: nil
             })
  end
end
