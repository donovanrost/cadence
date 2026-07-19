defmodule Cadence.Dashboards.SourceRegistry.WatermarkMergeTest do
  use Cadence.UnitCase, async: true

  alias Cadence.Dashboards.{
    Frame,
    PlannedSourceRequest,
    ResolveWarning,
    SourceFacts,
    SourceResult,
    SourceWatermarkStatus
  }

  alias Cadence.Dashboards.SourceRegistry.WatermarkMerge

  test "replaces source facts with the durable watermark projection" do
    facts = %SourceFacts{data_revision: "revision-1", meta: %{adapter: :telemetry}}
    request = request()

    merged = WatermarkMerge.merge_facts(facts, status(:authoritative), request)

    assert merged.data_revision == "revision-1"
    assert merged.meta.adapter == :telemetry
    assert merged.meta.durable_source_watermark?
    assert merged.meta.source_watermark_event_id == "watermark-event-1"
    assert merged.meta.source_watermark_reason == :provider_observed
    assert merged.watermark.request_id == request.request_id
    assert merged.watermark.scope == request.scope_context
    assert merged.watermarks == [merged.watermark]
  end

  test "authoritative result watermarks clear unknown warnings and frame warning codes" do
    result = %SourceResult{
      warnings: [
        warning(:watermark_unknown),
        %{"code" => "watermark-unknown", "severity" => "warning"},
        warning(:stale_data)
      ],
      frames: [
        %Frame{
          frame_id: "frame-1",
          source: :telemetry,
          shape: :long,
          meta: %{
            warning_codes: [:watermark_unknown, "watermark-unknown", :stale_data]
          }
        }
      ],
      meta: %{returned_frame_count: 1}
    }

    merged = WatermarkMerge.merge_result(result, status(:authoritative), request())

    assert Enum.map(merged.warnings, & &1.code) == [:stale_data]
    assert [frame] = merged.frames
    assert frame.meta.warning_codes == [:stale_data]
    assert merged.meta.returned_frame_count == 1
    assert merged.meta.durable_source_watermark?
    assert [watermark] = merged.watermarks
    assert watermark.confidence == :authoritative
  end

  test "unknown durable watermarks preserve uncertainty warnings" do
    result = %SourceResult{
      warnings: [warning(:watermark_unknown)],
      frames: [
        %Frame{
          frame_id: "frame-1",
          source: :telemetry,
          shape: :long,
          meta: %{warning_codes: [:watermark_unknown]}
        }
      ]
    }

    merged = WatermarkMerge.merge_result(result, status(:unknown), request())

    assert Enum.map(merged.warnings, & &1.code) == [:watermark_unknown]
    assert [frame] = merged.frames
    assert frame.meta.warning_codes == [:watermark_unknown]
    assert [watermark] = merged.watermarks
    assert watermark.confidence == :unknown
  end

  defp request do
    %PlannedSourceRequest{
      request_id: "request-1",
      mission_id: "mission-1",
      logical_source: :telemetry
    }
  end

  defp status(confidence) do
    %SourceWatermarkStatus{
      source_watermark_key: "source-1",
      source_watermark_event_id: "watermark-event-1",
      mission_id: "mission-1",
      logical_source: :telemetry,
      data_source_id: "source-1",
      source_binding_id: "binding-1",
      confidence: confidence,
      reason: :provider_observed,
      observed_at: ~U[2026-07-19 10:00:00Z],
      last_seen_at: ~U[2026-07-19 10:00:00Z]
    }
  end

  defp warning(code) do
    %ResolveWarning{
      code: code,
      severity: :warning,
      scope: :dashboard,
      message: Atom.to_string(code)
    }
  end
end
