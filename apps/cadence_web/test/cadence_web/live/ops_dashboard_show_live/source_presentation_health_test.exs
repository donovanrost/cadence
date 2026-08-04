defmodule CadenceWeb.OpsDashboardShowLive.SourcePresentationHealthTest do
  use ExUnit.Case, async: true

  alias Cadence.Dashboards.DashboardResolveResult
  alias CadenceWeb.OpsDashboardShowLive.SourcePresentation

  test "dashboard_degraded? reads explicit plan metadata degradation" do
    assert SourcePresentation.dashboard_degraded?(%{plan_metadata: %{"degraded?" => true}})
    refute SourcePresentation.dashboard_degraded?(%{plan_metadata: %{}})
    refute SourcePresentation.dashboard_degraded?(nil)
  end

  test "source_health_summaries expose redacted source probe diagnostics" do
    result = %DashboardResolveResult{
      watermarks: [
        %Cadence.DataSources.SourceWatermark{
          logical_source: :telemetry,
          request_id: "req-telemetry",
          source_binding_id: "binding-flight",
          data_source_id: "managed-questdb",
          realm: :flight,
          confidence: :authoritative,
          freshness_state: :fresh,
          latest_receipt_time: ~U[2026-06-24 01:00:00Z],
          meta: %{
            source_health_event_id: "source-health-event-1",
            source_health_reason: :source_adapter_probe_unsupported,
            source_health_probe_kind: "adapter_unsupported",
            source_health_probe_message: "adapter does not support active probes",
            source_health_probe_metadata: %{
              "storage" => "questdb",
              "password" => "plaintext"
            }
          }
        }
      ],
      planned_source_requests: []
    }

    assert [
             %{
               source_health_probe_kind_text: "adapter_unsupported",
               source_health_probe_message_text: "adapter does not support active probes",
               source_health_probe_metadata_text: probe_metadata,
               detail_rows: detail_rows
             }
           ] = SourcePresentation.source_health_summaries(result)

    assert probe_metadata =~ "storage=questdb"
    assert probe_metadata =~ "password=redacted"
    refute probe_metadata =~ "plaintext"

    assert %{label: "Source health event", value: "source-health-event-1"} in detail_rows
    assert %{label: "Probe kind", value: "adapter_unsupported"} in detail_rows
    assert %{label: "Probe metadata", value: probe_metadata} in detail_rows
  end

  test "source_health_summaries handles missing engine result" do
    assert SourcePresentation.source_health_summaries(%DashboardResolveResult{}) == []
  end
end
