defmodule Cadence.Dashboards.SourceRegistry.SegmentResultMergeTest do
  use Cadence.UnitCase, async: true

  alias Cadence.Dashboards.{Field, Frame, PlannedSourceRequest, ResolveWarning, SourceResult}

  alias Cadence.DataSources.SourceWatermark

  alias Cadence.Dashboards.SourceRegistry.SegmentResultMerge

  test "merges compatible frame fields, metadata, warnings, and watermarks" do
    request = request()

    segment_results = [
      {:first,
       %SourceResult{
         frames: [
           frame([~U[2026-07-19 10:00:00Z]], [41.0],
             data_source_id: "source-1",
             dataset: "first",
             returned_points: 1,
             tags: ["first"]
           )
         ],
         warnings: [warning(:watermark_unknown, :warning)],
         watermarks: [%SourceWatermark{request_id: "first", logical_source: :telemetry}]
       }},
      {:second,
       %SourceResult{
         frames: [
           frame([~U[2026-07-19 10:01:00Z]], [42.0],
             data_source_id: "source-2",
             dataset: "second",
             returned_points: 1,
             tags: ["second"],
             truncated?: true
           )
         ],
         warnings: [warning(:source_degraded, :error)],
         watermarks: [%SourceWatermark{request_id: "second", logical_source: :telemetry}]
       }}
    ]

    assert {:ok, %SourceResult{} = result} =
             SegmentResultMerge.merge(request, segment_results, &segment_metadata/1)

    assert result.request_id == request.request_id
    assert Enum.map(result.warnings, & &1.code) == [:watermark_unknown, :source_degraded]
    assert Enum.map(result.watermarks, & &1.request_id) == ["first", "second"]
    assert result.meta.returned_frame_count == 1
    assert result.meta.degraded?
    assert result.meta.source_binding_segment_count == 2

    assert [%Frame{} = frame] = result.frames
    assert Enum.at(frame.fields, 0).values == [~U[2026-07-19 10:00:00Z], ~U[2026-07-19 10:01:00Z]]
    assert Enum.at(frame.fields, 1).values == [41.0, 42.0]
    assert Enum.at(frame.fields, 1).metadata.tags == ["first", "second"]

    assert frame.meta.source_binding_segments == [
             segment_metadata(:first),
             segment_metadata(:second)
           ]

    assert frame.meta.data_source_ids == ["source-1", "source-2"]
    assert frame.meta.datasets == ["first", "second"]
    assert frame.meta.returned_points == 2
    assert frame.meta.truncated?
    refute Map.has_key?(frame.meta, :source_binding_id)
    refute Map.has_key?(frame.meta, :data_source_id)
  end

  test "returns a structured warning for incompatible segment frames" do
    segment_results = [
      {:first, %SourceResult{frames: [frame([~U[2026-07-19 10:00:00Z]], [41.0])]}},
      {:second,
       %SourceResult{
         frames: [
           %Frame{
             frame([~U[2026-07-19 10:01:00Z]], [42.0])
             | shape: :wide
           }
         ]
       }}
    ]

    assert {:error,
            %ResolveWarning{
              code: :source_binding_segment_merge_unsupported,
              severity: :error,
              details: %{frame_shapes: [:long, :wide]}
            }} = SegmentResultMerge.merge(request(), segment_results, &segment_metadata/1)
  end

  defp request do
    %PlannedSourceRequest{
      request_id: "request-1",
      logical_source: :telemetry,
      observables: ["battery.voltage"]
    }
  end

  defp frame(times, values, opts \\ []) do
    %Frame{
      frame_id: "telemetry-series",
      source: :telemetry,
      shape: :long,
      time_axis: :generation_time,
      fields: [
        %Field{name: "time", kind: :time, values: times},
        %Field{
          name: "battery.voltage",
          kind: :number,
          values: values,
          metadata: %{tags: Keyword.get(opts, :tags, [])}
        }
      ],
      meta: %{
        source_binding_id: "binding-#{Keyword.get(opts, :dataset, "first")}",
        source_binding_segment:
          segment_metadata(if(Keyword.get(opts, :dataset) == "second", do: :second, else: :first)),
        data_source_id: Keyword.get(opts, :data_source_id, "source-1"),
        dataset: Keyword.get(opts, :dataset, "first"),
        returned_points: Keyword.get(opts, :returned_points, 1),
        truncated?: Keyword.get(opts, :truncated?, false)
      }
    }
  end

  defp warning(code, severity) do
    %ResolveWarning{
      code: code,
      severity: severity,
      scope: :dashboard,
      message: Atom.to_string(code)
    }
  end

  defp segment_metadata(:first), do: %{binding_id: "binding-1", segment: :first}
  defp segment_metadata(:second), do: %{binding_id: "binding-2", segment: :second}
end
