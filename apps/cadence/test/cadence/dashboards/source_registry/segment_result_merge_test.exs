defmodule Cadence.Dashboards.SourceRegistry.SegmentResultMergeTest do
  use Cadence.UnitCase, async: true

  alias Cadence.Dashboards.{
    Annotation,
    AnnotationSpan,
    Field,
    Frame,
    PlannedSourceRequest,
    ResolveWarning,
    SourceResult
  }

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
         annotations: [annotation("annotation-1", ~U[2026-07-19 10:00:00Z])],
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
         annotations: [annotation("annotation-2", ~U[2026-07-19 10:01:00Z])],
         warnings: [warning(:source_degraded, :error)],
         watermarks: [%SourceWatermark{request_id: "second", logical_source: :telemetry}]
       }}
    ]

    assert {:ok, %SourceResult{} = result} =
             SegmentResultMerge.merge(request, segment_results, &segment_metadata/1)

    assert result.request_id == request.request_id
    assert Enum.map(result.warnings, & &1.code) == [:watermark_unknown, :source_degraded]
    assert Enum.map(result.watermarks, & &1.request_id) == ["first", "second"]
    assert Enum.map(result.annotations, & &1.annotation_id) == ["annotation-1", "annotation-2"]
    assert result.meta.returned_frame_count == 1
    assert result.meta.returned_annotation_count == 2
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

  test "positional sample identities retain duplicates and nils across source segments" do
    times = [~U[2026-07-19 10:00:00Z], ~U[2026-07-19 10:00:01Z]]
    first = frame(times, [1, 2], data_source_id: "source-1") |> with_ids(["same", nil])
    second = frame(times, [3, 4], data_source_id: "source-2") |> with_ids(["same", nil])
    assert {:ok, result} = merge_frames([first, second])
    [merged] = result.frames
    assert Enum.at(merged.fields, 1).metadata.sample_ids == ["same", nil, "same", nil]
    assert Enum.at(merged.fields, 1).values == [1, 2, 3, 4]
    assert Enum.map(merged.meta.source_binding_row_spans, & &1.count) == [2, 2]

    assert Enum.map(merged.meta.source_binding_row_spans, & &1.source.data_source_id) ==
             ["source-1", "source-2"]

    refute Map.has_key?(merged.meta, :data_source_id)
  end

  test "missing positional metadata represents unknown IDs without shifting later rows" do
    times = [~U[2026-07-19 10:00:00Z]]
    first = frame(times, [1])
    second = frame(times, [2]) |> with_ids(["known"])
    assert {:ok, result} = merge_frames([first, second, first])
    [merged] = result.frames
    assert Enum.at(merged.fields, 1).metadata.sample_ids == [nil, "known", nil]
  end

  test "malformed positional metadata cannot silently shift identities" do
    valid = frame([~U[2026-07-19 10:00:00Z]], [1]) |> with_ids(["known"])

    for ids <- [[], ["one", "two"], nil, "not-a-list"] do
      assert {:error, %{code: :source_binding_segment_merge_unsupported}} =
               merge_frames([valid, with_ids(valid, ids)])
    end
  end

  test "nested segment merges preserve the original row spans in observation order" do
    times = [~U[2026-07-19 10:00:00Z]]
    first = frame(times, [1], data_source_id: "source-1") |> with_ids(["same"])
    second = frame(times, [2], data_source_id: "source-2") |> with_ids(["same"])
    assert {:ok, result} = merge_frames([first, second])
    assert {:ok, nested} = merge_frames(result.frames ++ [first])
    [merged] = nested.frames
    assert Enum.at(merged.fields, 1).metadata.sample_ids == ["same", "same", "same"]

    assert Enum.map(merged.meta.source_binding_row_spans, & &1.source.data_source_id) ==
             ["source-1", "source-2", "source-1"]
  end

  test "opposite per-segment field misalignment cannot cancel out in a merged frame" do
    instant = ~U[2026-07-19 10:00:00Z]
    first = frame([instant], [1, 2]) |> with_ids(["a", "b"])
    second = frame([instant, instant], [3]) |> with_ids(["c"])

    assert {:error, %{code: :source_binding_segment_merge_unsupported}} =
             merge_frames([first, second])
  end

  defp merge_frames(frames) do
    SegmentResultMerge.merge(
      request(),
      Enum.map(frames, &{:first, %SourceResult{frames: [&1]}}),
      &segment_metadata/1
    )
  end

  defp with_ids(frame, ids) do
    [time, value] = frame.fields
    %{frame | fields: [time, %{value | metadata: Map.put(value.metadata, :sample_ids, ids)}]}
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

  defp annotation(annotation_id, starts_at) do
    %Annotation{
      annotation_id: annotation_id,
      provider_id: "test-provider",
      layer_id: "test-layer",
      title: annotation_id,
      span: %AnnotationSpan{kind: :point, starts_at: starts_at}
    }
  end

  defp segment_metadata(:first), do: %{binding_id: "binding-1", segment: :first}
  defp segment_metadata(:second), do: %{binding_id: "binding-2", segment: :second}
end
