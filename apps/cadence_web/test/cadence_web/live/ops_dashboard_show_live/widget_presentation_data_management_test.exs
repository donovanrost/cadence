defmodule CadenceWeb.OpsDashboardShowLive.WidgetPresentationDataManagementTest do
  use ExUnit.Case, async: true

  alias Cadence.Dashboards.{Field, Frame, PlacementFrames, RenderWidget}
  alias CadenceWeb.OpsDashboardShowLive.WidgetPresentation

  test "widget data carries data-management view and revision badges" do
    placement_frames = %PlacementFrames{
      primary: [
        %Frame{
          frame_id: "source-request-1:HK.counter",
          source: :telemetry,
          shape: :scalar,
          fields: [
            %Field{name: "time", kind: :time, values: [~U[2026-06-17 12:00:00Z]]},
            %Field{
              name: "HK.counter",
              kind: :number,
              values: [41],
              metadata: %{sample_ids: ["sample-1"], quality_states: [:good]}
            }
          ],
          meta: %{
            logical_source: :telemetry,
            observable_id: "HK.counter",
            data_view: :all_revisions,
            realm: :simulation,
            warning_codes: [:all_revisions_view, :corrected_range, :late_arrival]
          }
        }
      ]
    }

    assert %{
             data_management: %{
               data_view: "all_revisions",
               warning_codes: ["all_revisions_view", "corrected_range", "late_arrival"],
               badges: badges
             }
           } =
             WidgetPresentation.data(nil, placement_frames, %RenderWidget{
               type: :value_tile,
               binding: %{mode: :fixed}
             })

    assert Enum.map(badges, & &1.value) == [
             "all_revisions",
             "simulation",
             "corrected",
             "late"
           ]

    assert Enum.any?(badges, &match?(%{label: "Corrected", code: "corrected_range"}, &1))
  end

  test "widget data carries active historical workflow badges" do
    placement_frames = %PlacementFrames{
      primary: [
        %Frame{
          frame_id: "source-request-1:HK.counter",
          source: :telemetry,
          shape: :scalar,
          fields: [
            %Field{name: "time", kind: :time, values: [~U[2026-06-17 12:00:00Z]]},
            %Field{
              name: "HK.counter",
              kind: :number,
              values: [41],
              metadata: %{sample_ids: ["sample-1"], quality_states: [:good]}
            }
          ],
          meta: %{
            logical_source: :telemetry,
            observable_id: "HK.counter",
            warning_codes: [],
            historical_workflows: [
              %{category: :telemetry_backfill, kind: :backfill_started}
            ],
            active_historical_workflows: [
              %{category: :telemetry_revision, kind: :mark_conflict}
            ]
          }
        }
      ]
    }

    assert %{
             data_management: %{
               badges: badges
             }
           } =
             WidgetPresentation.data(nil, placement_frames, %RenderWidget{
               type: :value_tile,
               binding: %{mode: :fixed}
             })

    assert Enum.any?(
             badges,
             &match?(%{kind: :historical_workflow, value: "backfill_started"}, &1)
           )

    assert Enum.any?(
             badges,
             &match?(%{kind: :historical_workflow, value: "correction_conflict"}, &1)
           )
  end
end
