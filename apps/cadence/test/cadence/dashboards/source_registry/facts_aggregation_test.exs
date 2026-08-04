defmodule Cadence.Dashboards.SourceRegistry.FactsAggregationTest do
  use Cadence.UnitCase, async: true

  alias Cadence.Dashboards.{PlannedSourceRequest, SourceFacts}
  alias Cadence.Dashboards.SourceRegistry.FactsAggregation
  alias Cadence.DataSources.SourceWatermark

  test "aggregates segment watermarks, health, posture, and common revision facts" do
    request = %PlannedSourceRequest{
      request_id: "request-aggregate",
      logical_source: :telemetry
    }

    segment_facts = [
      {:first,
       %SourceFacts{
         watermarks: [
           watermark(
             "request-first",
             ~U[2026-07-19 10:00:00Z],
             ~U[2026-07-19 10:01:00Z],
             ~U[2026-07-01 00:00:00Z],
             :authoritative,
             :fresh
           )
         ],
         data_revision: "revision-1",
         correction_cursor: "correction-1",
         source_health: :healthy,
         meta: %{
           capability_posture: %{status: :native},
           durable_source_health?: true
         }
       }},
      {:second,
       %SourceFacts{
         watermark:
           watermark(
             "request-second",
             ~U[2026-07-19 09:55:00Z],
             ~U[2026-07-19 10:03:00Z],
             ~U[2026-07-02 00:00:00Z],
             :best_effort,
             :stale
           ),
         data_revision: "revision-1",
         correction_cursor: "correction-2",
         source_health: :degraded,
         meta: %{
           source_health_reason: :provider_lag,
           capability_posture: %{
             status: :fallback,
             fallbacks: [%{capability: :time_axis}]
           }
         }
       }}
    ]

    facts = FactsAggregation.merge(request, segment_facts, &segment_metadata/1)

    assert facts.source_binding_segments == [
             %{binding_id: "binding-1", segment: :first},
             %{binding_id: "binding-2", segment: :second}
           ]

    assert facts.data_revision == "revision-1"
    assert facts.correction_cursor == nil
    assert facts.source_health == :degraded

    assert Enum.map(facts.watermarks, & &1.request_id) == [
             "request-aggregate",
             "request-aggregate"
           ]

    assert %SourceWatermark{
             request_id: "request-aggregate",
             complete_through: ~U[2026-07-19 09:55:00Z],
             latest_receipt_time: ~U[2026-07-19 10:03:00Z],
             retention_starts_at: ~U[2026-07-01 00:00:00Z],
             confidence: :best_effort,
             freshness_state: :stale
           } = facts.watermark

    assert facts.meta.durable_source_health?

    assert facts.meta.source_health_by_segment == [
             %{binding_id: "binding-1", segment: :first, source_health: :healthy},
             %{
               binding_id: "binding-2",
               segment: :second,
               source_health: :degraded,
               source_health_reason: :provider_lag
             }
           ]

    assert facts.meta.capability_posture == %{
             status: :fallback,
             segment_count: 2,
             fallbacks: [%{capability: :time_axis}]
           }
  end

  test "preserves empty-watermark and native-health semantics" do
    request = %PlannedSourceRequest{
      request_id: "request-no-watermark",
      logical_source: :events
    }

    facts =
      FactsAggregation.merge(
        request,
        [
          {:first,
           %SourceFacts{
             backfill_cursor: "backfill-1",
             source_health: :healthy,
             meta: %{capability_posture: %{status: :native}}
           }},
          {:second,
           %SourceFacts{
             backfill_cursor: "backfill-1",
             source_health: :healthy,
             meta: %{capability_posture: %{status: :native}}
           }}
        ],
        &segment_metadata/1
      )

    assert facts.watermark == nil
    assert facts.watermarks == []
    assert facts.backfill_cursor == "backfill-1"
    assert facts.source_health == :healthy
    assert facts.meta.capability_posture == %{status: :native, segment_count: 2}
  end

  defp watermark(
         request_id,
         complete_through,
         latest_receipt_time,
         retention_starts_at,
         confidence,
         freshness_state
       ) do
    %SourceWatermark{
      logical_source: :telemetry,
      request_id: request_id,
      complete_through: complete_through,
      latest_receipt_time: latest_receipt_time,
      retention_starts_at: retention_starts_at,
      confidence: confidence,
      freshness_state: freshness_state
    }
  end

  defp segment_metadata(:first), do: %{binding_id: "binding-1", segment: :first}
  defp segment_metadata(:second), do: %{binding_id: "binding-2", segment: :second}
end
