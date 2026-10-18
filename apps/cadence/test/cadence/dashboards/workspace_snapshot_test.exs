defmodule Cadence.Dashboards.WorkspaceSnapshotTest do
  use Cadence.UnitCase, async: true

  alias Cadence.Dashboards.{
    Annotation,
    AnnotationSpan,
    DashboardResolveRequest,
    DashboardResolveResult,
    Document,
    Field,
    Frame,
    Placement,
    PlacementFrames,
    ResolveWarning,
    Section,
    WidgetDef,
    WidgetRegistry
  }

  alias Cadence.Reads.Dashboards.{WorkspaceFrame, WorkspaceSnapshot}

  test "projects all registered widget kinds and crosses the actual TypeScript boundary" do
    models =
      for type <- WidgetRegistry.list_types() do
        {document, request, result} = fixture(type.widget_type_id)
        assert {:ok, model} = WorkspaceSnapshot.build(document, result, request, false)

        assert [%{status: "ready", frames: [%{fields: [_, _]}]}] =
                 model.placements

        refute Jason.encode!(model) =~ "secret"
        model
      end

    script =
      Path.expand(
        "../../../../../frontend/modules/dashboards-and-exploration/src/features/workspace/producer-contract-check.mjs",
        __DIR__
      )

    assert {output, 0} =
             System.cmd(
               System.find_executable("node"),
               ["--no-warnings", script, Jason.encode!(models)],
               stderr_to_stdout: true
             )

    assert output =~ "Workspace producer/consumer contract passed"
  end

  test "unavailable definitions and malformed frame buckets never erase placements" do
    {document, request, result} = fixture("unavailable_library_reference")

    assert {:ok, %{placements: [%{status: "unavailable", reason: "unsupported_widget"}]}} =
             WorkspaceSnapshot.build(document, result, request, false)

    {document, request, result} = fixture("cadence.value_tile")

    assert {:ok, %{placements: [%{reason: "missing_result"}]}} =
             WorkspaceSnapshot.build(
               document,
               %{result | frames_by_placement: %{}},
               request,
               false
             )

    bad = %PlacementFrames{
      primary: [
        %Frame{
          shape: :scalar,
          fields: [%Field{name: "bad", kind: :number, values: [%{secret: "raw"}]}]
        }
      ]
    }

    assert {:ok, %{placements: [%{reason: "invalid_frame", frames: []}]}} =
             WorkspaceSnapshot.build(
               document,
               %{result | frames_by_placement: %{"battery" => bad}},
               request,
               false
             )
  end

  test "authored chart styles cross the actual producer and presentation boundary" do
    models =
      for legend <- ~w(auto always hidden), width <- ~w(thin normal bold) do
        {document, request, result} = fixture("cadence.time_series")
        [placement] = document.placements
        options = %{legend_mode: legend, line_width: width, fill_opacity: 30}
        placement = %{placement | widget_def: %{placement.widget_def | options: options}}
        document = %{document | placements: [placement]}
        assert {:ok, model} = WorkspaceSnapshot.build(document, result, request, true)
        assert hd(model.placements).widget.options.legend_mode == legend
        assert hd(model.placements).widget.options.line_width == width
        model
      end

    script =
      Path.expand(
        "../../../../../frontend/modules/dashboards-and-exploration/src/features/workspace/producer-contract-check.mjs",
        __DIR__
      )

    assert {output, 0} =
             System.cmd(
               System.find_executable("node"),
               ["--no-warnings", script, Jason.encode!(models)],
               stderr_to_stdout: true
             )

    assert output =~ "contract passed"
  end

  test "frame projection enforces alignment, types, bounds and annotation geometry" do
    for fields <- [
          [
            %Field{name: "x", kind: :number, values: [1, 2]},
            %Field{name: "y", kind: :number, values: [3]}
          ],
          [%Field{name: "x", kind: :number, values: [9_007_199_254_740_992]}],
          [%Field{name: "x", kind: :number, values: [1.0e20]}],
          [%Field{name: "x", kind: :number, values: Enum.to_list(1..10_001)}],
          [%Field{name: "x", kind: :number}, %Field{name: "x", kind: :number}],
          [%Field{name: "x", kind: :boolean, values: ["true"]}]
        ],
        do:
          assert(
            {:error, :invalid_frame} =
              WorkspaceFrame.project(%Frame{shape: :scalar, fields: fields})
          )

    annotation = %Annotation{
      annotation_id: "contact",
      title: "Contact",
      span: %AnnotationSpan{
        kind: :interval,
        starts_at: ~U[2026-09-07 00:00:00Z],
        ends_at: ~U[2026-09-07 00:01:00Z]
      },
      metadata: %{secret: "raw"}
    }

    assert {:ok, projected} = WorkspaceFrame.annotation(annotation)
    assert projected.ends_at_ms - projected.starts_at_ms == 60_000
    refute Map.has_key?(projected, :metadata)
  end

  test "repeats use the engine's identities and cross-dashboard joins fail closed" do
    {document, request, result} = fixture("cadence.value_tile")

    assert {:error, _} =
             WorkspaceSnapshot.build(
               document,
               %{result | dashboard_id: "foreign"},
               request,
               false
             )

    repeated = %{
      hd(document.placements)
      | repeat: %{axis: :scope, over: :spacecraft, max_instances: 2}
    }

    document = %{document | placements: [repeated]}

    request = %{
      request
      | scope_context: %{primary: %{kind: :spacecraft, mode: :many, ids: ["sc-1", "sc-2"]}}
    }

    assert {:ok, %{placements: placements}} =
             WorkspaceSnapshot.build(document, result, request, false)

    assert Enum.map(placements, & &1.id) == [
             "battery__repeat__spacecraft__sc-1",
             "battery__repeat__spacecraft__sc-2"
           ]

    assert Enum.all?(placements, &(&1.reason == "missing_result"))
  end

  defp fixture(type) do
    document = %Document{
      organization_id: "org",
      mission_id: "mission",
      dashboard_id: "dashboard",
      name: "Flight telemetry",
      metadata: %{version: 3},
      sections: [%Section{section_id: "power", title: "Power"}],
      placements: [
        %Placement{
          placement_id: "battery",
          section_id: "power",
          widget_def: %WidgetDef{
            widget_type_id: type,
            title: "Battery",
            binding: %{observables: []}
          }
        }
      ]
    }

    request = %DashboardResolveRequest{
      organization_id: "org",
      mission_id: "mission",
      dashboard_id: "dashboard",
      document: document,
      document_mode: :published
    }

    {shape, fields} = frame_fields(type)

    frame = %Frame{
      shape: shape,
      source: :telemetry,
      time_axis: :generation_time,
      fields: fields,
      meta: %{credentials: "secret"}
    }

    warning = %ResolveWarning{
      code: :source_unavailable,
      message: "secret",
      details: %{endpoint: "secret"}
    }

    result = %DashboardResolveResult{
      dashboard_id: "dashboard",
      frames_by_placement: %{"battery" => %PlacementFrames{primary: [frame], warnings: [warning]}}
    }

    {document, request, result}
  end

  defp frame_fields("cadence.constellation_health") do
    {:matrix,
     [
       %Field{name: "spacecraft_id", kind: :string, values: ["sc-1"]},
       %Field{name: "worst_state", kind: :enum, values: [:red]}
     ]}
  end

  defp frame_fields("cadence.event_timeline") do
    {:events,
     [
       %Field{name: "occurred_at", kind: :time, values: [~U[2026-09-07 00:00:00Z]]},
       %Field{name: "title", kind: :string, values: ["Contact acquired"]}
     ]}
  end

  defp frame_fields("cadence.state_timeline") do
    {:events,
     [
       %Field{name: "time", kind: :time, values: [~U[2026-09-07 00:00:00Z]]},
       %Field{name: "normalized_state", kind: :enum, values: [:green]}
     ]}
  end

  defp frame_fields(type) do
    {if(type == "cadence.time_series", do: :wide, else: :scalar),
     [
       %Field{name: "time", kind: :time, values: [~U[2026-09-07 00:00:00Z]]},
       %Field{
         name: "voltage",
         kind: :number,
         values: [28.4],
         metadata: %{unit: "V", secret: "secret"}
       }
     ]}
  end
end
