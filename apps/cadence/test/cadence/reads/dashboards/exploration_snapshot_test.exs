defmodule Cadence.Reads.Dashboards.ExplorationSnapshotTest do
  use Cadence.UnitCase, async: true
  alias Cadence.Dashboards.{DashboardResolveResult, Field, Frame, PlacementFrames, ResolveWarning}
  alias Cadence.Dashboards.{PlannedSourceRequest, SourceResult}
  alias Cadence.Dashboards.SourceRegistry.SegmentResultMerge
  alias Cadence.Reads.Dashboards.{ExplorationQuery, ExplorationRequest, ExplorationSnapshot}
  @now ~U[2026-09-07 12:00:00.123456Z]

  test "projects exact timestamps and real sample identities without raw metadata" do
    read = read()
    assert {:ok, model} = ExplorationSnapshot.build(read, @now)
    assert model.status == "ready"
    assert model.loaded_at == "2026-09-07T12:00:00.123456Z"
    assert [row] = model.rows
    assert row.time == "2026-09-07T11:59:59.654321Z"
    assert row.sample_id == "sample-a"
    assert row.value == 4.2
    assert row.source.source_binding_id == "binding-a"
    assert row.unit == "V"
    refute Jason.encode!(model) =~ "private-adapter-detail"
    refute Map.has_key?(model, :dashboard_id)
  end

  test "empty source results differ from failed or missing source execution" do
    read = read()
    [frame] = read.result.frames_by_placement["exploration"].primary
    [time, value] = frame.fields

    empty = %{
      frame
      | fields: [%{time | values: []}, %{value | values: [], metadata: %{sample_ids: []}}]
    }

    assert {:ok, %{status: "empty", rows: []}} = project(read, [empty])
    assert {:ok, %{status: "unavailable", rows: []}} = project(read, [])

    warning = %ResolveWarning{
      code: :missing_source_binding,
      severity: :error,
      message: "private-adapter-detail",
      details: %{password: "private-adapter-detail"}
    }

    result = %{
      read.result
      | frames_by_placement: %{"exploration" => %PlacementFrames{warnings: [warning]}}
    }

    assert {:ok, model} = ExplorationSnapshot.build(%{read | result: result}, @now)
    assert model.status == "unavailable"
    assert model.warnings == [%{code: "missing_source_binding", severity: "error"}]
    refute Jason.encode!(model) =~ "private-adapter-detail"
  end

  test "malformed, unaligned, oversized and foreign-shaped frames are not serialized" do
    read = read()
    [frame] = read.result.frames_by_placement["exploration"].primary
    [time, value] = frame.fields

    for invalid <- [
          %{frame | source: :events},
          %{frame | time_axis: nil},
          %{frame | fields: [time, %{value | values: [4.2, 4.3]}]},
          %{frame | fields: [time, %{value | metadata: %{sample_ids: []}}]},
          %{frame | fields: [time, %{value | values: [%{secret: "private-adapter-detail"}]}]},
          %{frame | meta: %{frame.meta | data_source_id: %{secret: "private-adapter-detail"}}}
        ] do
      assert {:error, :unavailable} = project(read, [invalid])
    end

    assert {:error, :unavailable} = project(read, List.duplicate(frame, 65))
    assert {:error, :unavailable} = project(read, [frame, frame])
    result = %{read.result | dashboard_id: "foreign"}
    assert {:error, :unavailable} = ExplorationSnapshot.build(%{read | result: result}, @now)
  end

  test "an omitted error warning cannot turn failed execution into an empty result" do
    read = read()
    [frame] = read.result.frames_by_placement["exploration"].primary
    [time, value] = frame.fields

    empty = %{
      frame
      | fields: [%{time | values: []}, %{value | values: [], metadata: %{sample_ids: []}}]
    }

    codes = ~w(w01 w02 w03 w04 w05 w06 w07 w08 w09 w10
               w11 w12 w13 w14 w15 w16 w17 w18 w19 w20
               w21 w22 w23 w24 w25 w26 w27 w28 w29 w30
               w31 w32 w33 w34 w35 w36 w37 w38 w39 w40
               w41 w42 w43 w44 w45 w46 w47 w48 w49 w50)a

    warnings = Enum.map(codes, &%ResolveWarning{code: &1, severity: :warning})

    result = %{
      read.result
      | frames_by_placement: %{
          "exploration" => %PlacementFrames{primary: [empty], warnings: warnings}
        },
        dashboard_warnings: [%ResolveWarning{code: :source_failed, severity: :error}]
    }

    assert {:ok, model} = ExplorationSnapshot.build(%{read | result: result}, @now)
    assert model.status == "unavailable"
    assert model.warnings_limited
    assert length(model.warnings) == 50
    refute Enum.any?(model.warnings, &(&1.severity == "error"))
  end

  test "merged segments are globally ordered and bounded without manufacturing sample IDs" do
    read = read(%{"limit" => "2", "order" => "desc"})
    [frame] = read.result.frames_by_placement["exploration"].primary
    [time, value] = frame.fields

    frames =
      for {id, instant} <- [
            {"old", ~U[2026-09-07 11:00:00Z]},
            {"new", @now},
            {"middle", ~U[2026-09-07 11:30:00Z]}
          ] do
        %{
          frame
          | frame_id: id,
            fields: [%{time | values: [instant]}, %{value | metadata: %{sample_ids: [nil]}}]
        }
      end

    assert {:ok, model} = project(read, frames)
    assert model.limited

    assert Enum.map(model.rows, & &1.time) == [
             "2026-09-07T12:00:00.123456Z",
             "2026-09-07T11:30:00Z"
           ]

    assert Enum.all?(model.rows, &is_nil(&1.sample_id))
    assert length(Enum.uniq_by(model.rows, & &1.key)) == 2
  end

  test "merged rows retain positional samples and sources even when clocks overlap" do
    read = read()
    [frame] = read.result.frames_by_placement["exploration"].primary
    [time, value] = frame.fields
    times = [~U[2026-09-07 11:59:59.654321Z], ~U[2026-09-07 11:59:59.654321Z]]

    frames =
      for source <- ["source-a", "source-b"] do
        %{
          frame
          | meta: %{frame.meta | data_source_id: source},
            fields: [
              %{time | values: times},
              %{value | values: [4.2, 4.3], metadata: %{sample_ids: ["same", nil]}}
            ]
        }
      end

    assert {:ok, merged} =
             SegmentResultMerge.merge(
               %PlannedSourceRequest{},
               Enum.map(frames, &{:binding, %SourceResult{frames: [&1]}}),
               fn _ -> %{} end
             )

    assert {:ok, model} = project(read, merged.frames)
    assert length(model.rows) == 4

    assert Enum.frequencies_by(model.rows, &{&1.sample_id, &1.source.data_source_id}) ==
             %{
               {"same", "source-a"} => 1,
               {nil, "source-a"} => 1,
               {"same", "source-b"} => 1,
               {nil, "source-b"} => 1
             }

    assert Enum.all?(model.rows, &(&1.source.source_binding_id == "binding-a"))
    refute Jason.encode!(model) =~ "private-adapter-detail"
  end

  test "missing or invalid source spans reject a merged projection instead of guessing" do
    read = read()
    [frame] = read.result.frames_by_placement["exploration"].primary
    source = Map.take(frame.meta, [:data_source_id, :source_binding_id, :dataset, :realm])

    for spans <- [
          nil,
          [],
          [%{count: 0, source: source}],
          [%{count: 2, source: source}],
          [%{count: -1, source: source}],
          [%{count: 1.0, source: source}],
          [%{count: 1, source: %{source | realm: :unknown}}],
          List.duplicate(%{count: 0, source: source}, 65)
        ] do
      meta =
        Map.merge(frame.meta, %{segmented_source_bindings?: true, source_binding_row_spans: spans})

      assert {:error, :unavailable} = project(read, [%{frame | meta: meta}])
    end
  end

  test "the row limit applies after merging and ordering source segments" do
    read = read(%{"limit" => "1", "order" => "desc"})
    [frame] = read.result.frames_by_placement["exploration"].primary
    [time, value] = frame.fields
    first = %{frame | fields: [%{time | values: [~U[2026-09-07 11:00:00Z]]}, value]}

    second = %{
      frame
      | meta: %{frame.meta | data_source_id: "source-b"},
        fields: [
          %{time | values: [~U[2026-09-07 11:59:00Z]]},
          %{value | metadata: %{sample_ids: ["sample-b"]}}
        ]
    }

    assert {:ok, merged} =
             SegmentResultMerge.merge(
               %PlannedSourceRequest{},
               [
                 {:first, %SourceResult{frames: [first]}},
                 {:second, %SourceResult{frames: [second]}}
               ],
               fn _ -> %{} end
             )

    assert {:ok, %{rows: [row], limited: true}} = project(read, merged.frames)
    assert row.sample_id == "sample-b"
    assert row.source.data_source_id == "source-b"
  end

  test "bounded segment batches can exceed the workspace frame limit before global selection" do
    read = read(%{"limit" => "1000"})
    [frame] = read.result.frames_by_placement["exploration"].primary
    [time, value] = frame.fields

    frames =
      for n <- 1..11 do
        %{
          frame
          | meta: %{frame.meta | data_source_id: "source-#{n}"},
            fields: [
              %{time | values: List.duplicate(DateTime.add(@now, -n, :second), 1000)},
              %{
                value
                | values: List.duplicate(4.2, 1000),
                  metadata: %{sample_ids: List.duplicate(nil, 1000)}
              }
            ]
        }
      end

    assert {:ok, merged} =
             SegmentResultMerge.merge(
               %PlannedSourceRequest{},
               Enum.map(frames, &{:binding, %SourceResult{frames: [&1]}}),
               fn _ -> %{} end
             )

    assert {:ok, model} = project(read, merged.frames)
    assert length(model.rows) == 1000
    assert model.limited

    assert Enum.all?(
             model.rows,
             &(&1.source.data_source_id == "source-1" and is_nil(&1.sample_id))
           )
  end

  defp project(read, frames) do
    result = %{
      read.result
      | frames_by_placement: %{"exploration" => %PlacementFrames{primary: frames}}
    }

    ExplorationSnapshot.build(%{read | result: result}, @now)
  end

  defp read(params \\ %{}) do
    {:ok, query} =
      ExplorationQuery.admit(
        Map.merge(%{"point_id" => "voltage", "time_mode" => "last_1h"}, params),
        @now
      )

    {:ok, request} = ExplorationRequest.build("org", "mission", query)

    frame = %Frame{
      frame_id: "frame-a",
      source: :telemetry,
      shape: :wide,
      time_axis: :receipt_time,
      fields: [
        %Field{name: "time", kind: :time, values: [~U[2026-09-07 11:59:59.654321Z]]},
        %Field{
          name: "voltage",
          kind: :number,
          values: [4.2],
          metadata: %{unit: "V", sample_ids: ["sample-a"], evidence: "private-adapter-detail"}
        }
      ],
      meta: %{
        realm: :flight,
        data_source_id: "source-a",
        source_binding_id: "binding-a",
        dataset: "flight",
        credentials: "private-adapter-detail"
      }
    }

    result = %DashboardResolveResult{
      dashboard_id: request.dashboard_id,
      frames_by_placement: %{"exploration" => %PlacementFrames{primary: [frame]}}
    }

    %{request: request, query: query.query, result: result}
  end
end
