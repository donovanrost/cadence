defmodule Cadence.Dashboards.SourceRegistry.HealthMergeTest do
  use Cadence.UnitCase, async: true

  alias Cadence.Dashboards.SourceFacts
  alias Cadence.Dashboards.SourceRegistry.HealthMerge
  alias Cadence.DataSources.SourceWatermark
  alias Cadence.OperationalEvents.EffectiveInterval

  test "applies durable health, diagnostics, and interval evidence to facts and watermarks" do
    status = %{
      source_health_event_id: "health-event-1",
      payload: %{
        "probe_kind" => "http",
        "probe_message" => "reachable",
        "probe_metadata" => %{"status" => 204},
        "connection_test_result" => "passed",
        "connection_test_kind" => "http",
        "connection_test_message" => "HTTP 204"
      }
    }

    classification = %{
      source_health: :degraded,
      freshness: :stale,
      reason: :provider_lag,
      observed_at: ~U[2026-07-19 10:00:00Z],
      last_seen_at: ~U[2026-07-19 09:59:00Z],
      age_ms: 60_000,
      max_age_ms: 30_000,
      raw_source_health: :healthy,
      raw_reason: "delayed",
      status: status
    }

    interval = %EffectiveInterval{
      interval_id: "source-health-interval-1",
      mission_id: "mission-1",
      kind: :source_health,
      subject_kind: :data_source,
      subject_id: "source-1",
      starts_at: ~U[2026-07-19 09:55:00Z],
      source_event_id: "health-event-1",
      payload: %{"source_health" => "degraded"}
    }

    facts = %SourceFacts{
      watermark: watermark("primary"),
      watermarks: [watermark("historical")],
      meta: %{adapter: :telemetry}
    }

    merged = HealthMerge.merge_facts(facts, classification, interval)

    assert merged.source_health == :degraded
    assert merged.meta.adapter == :telemetry
    assert merged.meta.durable_source_health?
    assert merged.meta.source_health_event_id == "health-event-1"
    assert merged.meta.source_health_probe_kind == "http"
    assert merged.meta.source_health_probe_metadata == %{"status" => 204}
    assert merged.meta.source_health_connection_test_result == "passed"
    assert merged.meta.source_health_interval_id == "source-health-interval-1"
    assert merged.meta.source_health_interval_source_event_id == "health-event-1"
    assert merged.meta.source_health_interval.kind == :source_health

    assert merged.watermark.meta.source_health_reason == :provider_lag
    assert merged.watermark.meta.source_health_probe_message == "reachable"
    assert merged.watermark.meta.source_health_connection_test_message == "HTTP 204"

    assert [historical] = merged.watermarks
    assert historical.meta.source_health_event_id == "health-event-1"
    assert historical.meta.source_health_connection_test_kind == "http"
  end

  test "records classified fallback health without inventing durable evidence" do
    classification = %{
      source_health: :unknown,
      freshness: :unknown,
      reason: :status_missing,
      observed_at: nil,
      last_seen_at: nil,
      age_ms: nil,
      max_age_ms: 30_000,
      raw_source_health: nil,
      raw_reason: nil,
      status: nil
    }

    merged = HealthMerge.merge_facts(%SourceFacts{}, classification, nil)

    assert merged.source_health == :unknown
    assert merged.meta.source_health_reason == :status_missing
    refute merged.meta.durable_source_health?
    refute Map.has_key?(merged.meta, :source_health_event_id)
    refute Map.has_key?(merged.meta, :source_health_interval)
  end

  defp watermark(request_id) do
    %SourceWatermark{
      request_id: request_id,
      logical_source: :telemetry,
      confidence: :authoritative,
      meta: %{}
    }
  end
end
