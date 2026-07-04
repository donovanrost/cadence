defmodule CadenceWeb.OpsDashboardShowLive.TimeSeriesLimitMarkersTest do
  use ExUnit.Case, async: true

  alias Cadence.Dashboards.{Field, Frame, PlacementFrames}
  alias CadenceWeb.OpsDashboardShowLive.TimeSeriesLimitMarkers

  test "limit_markers projects visible event markers and filters nominal states" do
    placement_frames = %PlacementFrames{
      overlays: %{
        limits: [
          %Frame{
            source: :limits,
            shape: :events,
            fields: [
              %Field{
                name: "time",
                kind: :time,
                values: [~U[2026-06-17 12:00:00Z], ~U[2026-06-17 12:01:00Z]]
              },
              %Field{name: "sample_id", kind: :string, values: ["sample-red", "sample-green"]},
              %Field{name: "normalized_state", kind: :enum, values: [:red, :green]},
              %Field{name: "limit_state", kind: :enum, values: [:high_red, :nominal]},
              %Field{name: "violation", kind: :boolean, values: [true, false]}
            ],
            meta: %{links: [limit_event_link("limit-link-red", "limit-event-red")]}
          }
        ]
      }
    }

    assert [
             %{
               timestamp_ms: 1_781_697_600_000,
               link_id: "limit-link-red",
               limit_event_id: "limit-event-red",
               normalized_state: "red",
               limit_state: "high_red",
               violation: true,
               sample_id: "sample-red"
             }
           ] = TimeSeriesLimitMarkers.limit_markers(placement_frames)
  end

  test "limit_markers projects scalar limit event marker" do
    placement_frames = %PlacementFrames{
      overlays: %{
        limits: [
          %Frame{
            source: :limits,
            shape: :scalar,
            fields: [
              %Field{name: "time", kind: :time, values: [~U[2026-06-17 12:00:00Z]]},
              %Field{name: "normalized_state", kind: :enum, values: ["yellow"]},
              %Field{name: "limit_state", kind: :enum, values: ["low_yellow"]},
              %Field{name: "violation", kind: :boolean, values: [false]}
            ],
            meta: %{
              sample_id: "sample-yellow",
              links: [limit_event_link("limit-link-yellow", "limit-event-yellow")]
            }
          }
        ]
      }
    }

    assert [
             %{
               timestamp_ms: 1_781_697_600_000,
               link_id: "limit-link-yellow",
               limit_event_id: "limit-event-yellow",
               normalized_state: "yellow",
               sample_id: "sample-yellow"
             }
           ] = TimeSeriesLimitMarkers.limit_markers(placement_frames)
  end

  test "limit_markers projects recomputed synthetic analysis markers with sample links" do
    placement_frames = %PlacementFrames{
      overlays: %{
        limits: [
          %Frame{
            source: :limits,
            shape: :events,
            fields: [
              %Field{name: "time", kind: :time, values: [~U[2026-06-17 12:02:00Z]]},
              %Field{name: "sample_id", kind: :string, values: ["sample-yellow"]},
              %Field{name: "normalized_state", kind: :enum, values: [:yellow]},
              %Field{name: "limit_state", kind: :enum, values: [:yellow_high]},
              %Field{name: "violation", kind: :boolean, values: [true]}
            ],
            meta: %{
              semantics_mode: :recomputed,
              analysis_basis: :recomputed_analysis,
              synthetic_limit_analysis?: true,
              links: [telemetry_sample_link("sample-link-yellow", "sample-yellow")]
            }
          }
        ]
      }
    }

    assert [
             %{
               marker_id: "limit-analysis:recomputed:sample-yellow:1781697720000",
               marker_type: "limit_analysis",
               timestamp_ms: 1_781_697_720_000,
               link_id: "sample-link-yellow",
               normalized_state: "yellow",
               limit_state: "yellow_high",
               violation: true,
               sample_id: "sample-yellow",
               semantics_mode: "recomputed",
               analysis_basis: "recomputed_analysis",
               synthetic_limit_analysis: true
             }
           ] = TimeSeriesLimitMarkers.limit_markers(placement_frames)
  end

  test "limit_markers projects source-native analysis bucket metadata" do
    placement_frames = %PlacementFrames{
      overlays: %{
        limits: [
          %Frame{
            source: :limits,
            shape: :events,
            fields: [
              %Field{name: "time", kind: :time, values: [~U[2026-06-17 12:00:00Z]]},
              %Field{name: "bucket_end", kind: :time, values: [~U[2026-06-17 12:01:00Z]]},
              %Field{name: "event_count", kind: :number, values: [2]},
              %Field{name: "limit_event_id", kind: :string, values: ["limit-event-worst"]},
              %Field{name: "sample_id", kind: :string, values: ["sample-worst"]},
              %Field{
                name: "limit_event_ids",
                kind: :string,
                values: [["limit-event-1", "limit-event-worst"]]
              },
              %Field{
                name: "sample_ids",
                kind: :string,
                values: [["sample-1", "sample-worst"]]
              },
              %Field{name: "normalized_state", kind: :enum, values: [:red]},
              %Field{name: "limit_state", kind: :enum, values: [:red_high]},
              %Field{name: "violation", kind: :boolean, values: [true]},
              %Field{name: "limit_definition_id", kind: :string, values: ["limit-def-2"]},
              %Field{name: "limit_definition_version", kind: :number, values: [2]},
              %Field{name: "limit_set_name", kind: :string, values: ["ops-red"]},
              %Field{name: "observed_normalized_state", kind: :enum, values: [:green]},
              %Field{name: "limit_state_diverged", kind: :boolean, values: [true]},
              %Field{name: "limit_divergence_count", kind: :number, values: [1]}
            ],
            meta: %{
              semantics_mode: :compare,
              analysis_basis: :limit_comparison_analysis,
              selected_limit_clock: %{
                observed: :limit_event_receipt_time,
                requested_time_axis: :receipt_time
              },
              selected_limit_definition_intervals: [
                %{definition_id: "limit-def-2", active_from: ~U[2026-06-17 12:00:00Z]}
              ],
              synthetic_limit_analysis?: true,
              links: [telemetry_sample_link("sample-link-worst", "sample-worst")]
            }
          }
        ]
      }
    }

    assert [
             %{
               marker_id: "limit-analysis-bucket:compare:1781697600000:1781697660000",
               marker_type: "limit_analysis_bucket",
               timestamp_ms: 1_781_697_600_000,
               starts_at_ms: 1_781_697_600_000,
               ends_at_ms: 1_781_697_660_000,
               bucket_end_ms: 1_781_697_660_000,
               link_id: "sample-link-worst",
               limit_event_id: "limit-event-worst",
               limit_event_ids: ["limit-event-1", "limit-event-worst"],
               limit_definition_id: "limit-def-2",
               limit_definition_version: 2,
               limit_set_name: "ops-red",
               normalized_state: "red",
               observed_normalized_state: "green",
               limit_state: "red_high",
               violation: true,
               sample_id: "sample-worst",
               sample_ids: ["sample-1", "sample-worst"],
               event_count: 2,
               limit_divergence_count: 1,
               limit_state_diverged: true,
               semantics_mode: "compare",
               analysis_basis: "limit_comparison_analysis",
               selected_limit_clock: %{
                 observed: :limit_event_receipt_time,
                 requested_time_axis: :receipt_time
               },
               selected_limit_definition_intervals: [
                 %{definition_id: "limit-def-2", active_from: ~U[2026-06-17 12:00:00Z]}
               ],
               synthetic_limit_analysis: true
             }
           ] = TimeSeriesLimitMarkers.limit_markers(placement_frames)
  end

  test "limit_markers projects compare divergence metadata" do
    placement_frames = %PlacementFrames{
      overlays: %{
        limits: [
          %Frame{
            source: :limits,
            shape: :events,
            fields: [
              %Field{name: "time", kind: :time, values: [~U[2026-06-17 12:02:00Z]]},
              %Field{name: "sample_id", kind: :string, values: ["sample-compare"]},
              %Field{name: "normalized_state", kind: :enum, values: [:yellow]},
              %Field{name: "limit_state", kind: :enum, values: [:yellow_high]},
              %Field{name: "violation", kind: :boolean, values: [true]},
              %Field{
                name: "observed_limit_event_id",
                kind: :string,
                values: ["observed-limit-event-1"]
              },
              %Field{name: "observed_normalized_state", kind: :enum, values: [:green]},
              %Field{name: "limit_state_diverged", kind: :boolean, values: [true]}
            ],
            meta: %{
              semantics_mode: :compare,
              analysis_basis: :limit_comparison_analysis,
              synthetic_limit_analysis?: true,
              links: [
                limit_event_link("observed-limit-link", "observed-limit-event-1"),
                telemetry_sample_link("sample-link-compare", "sample-compare")
              ]
            }
          }
        ]
      }
    }

    assert [
             %{
               marker_id: "limit-analysis:compare:sample-compare:1781697720000",
               marker_type: "limit_analysis",
               link_id: "observed-limit-link",
               limit_event_id: "observed-limit-event-1",
               observed_limit_event_id: "observed-limit-event-1",
               normalized_state: "yellow",
               observed_normalized_state: "green",
               limit_state_diverged: true,
               semantics_mode: "compare",
               analysis_basis: "limit_comparison_analysis"
             }
           ] = TimeSeriesLimitMarkers.limit_markers(placement_frames)
  end

  test "limit_markers projects definition intervals and deduplicates by link" do
    frame = %Frame{
      source: :limits,
      shape: :intervals,
      fields: [
        %Field{
          name: "active_from",
          kind: :time,
          values: [~U[2026-06-17 12:00:00Z], ~U[2026-06-17 12:00:00Z]]
        },
        %Field{
          name: "active_to",
          kind: :time,
          values: [~U[2026-06-17 12:10:00Z], ~U[2026-06-17 12:10:00Z]]
        },
        %Field{
          name: "limit_definition_id",
          kind: :string,
          values: ["counter-limits", "counter-limits"]
        },
        %Field{name: "limit_definition_version", kind: :number, values: [2, 2]},
        %Field{name: "limit_set_name", kind: :string, values: ["ops", "ops"]},
        %Field{name: "red_low", kind: :number, values: [0, 0]},
        %Field{name: "yellow_low", kind: :number, values: [5, 5]},
        %Field{name: "yellow_high", kind: :number, values: [10, 10]},
        %Field{name: "red_high", kind: :number, values: [20, 20]}
      ],
      meta: %{
        links: [
          limit_definition_link("limit-definition-link", "counter-limits"),
          limit_definition_link("limit-definition-link", "counter-limits")
        ]
      }
    }

    placement_frames = %PlacementFrames{overlays: %{limits: [frame]}}

    assert [
             %{
               marker_type: "limit_definition_interval",
               starts_at_ms: 1_781_697_600_000,
               ends_at_ms: 1_781_698_200_000,
               link_id: "limit-definition-link",
               target: "limit_definition",
               target_id: "counter-limits",
               limit_definition_id: "counter-limits",
               limit_definition_version: 2,
               limit_set_name: "ops",
               red_low: 0,
               yellow_low: 5,
               yellow_high: 10,
               red_high: 20
             }
           ] = TimeSeriesLimitMarkers.limit_markers(placement_frames)
  end

  test "limit_markers tolerates missing frames" do
    assert TimeSeriesLimitMarkers.limit_markers(nil) == []
    assert TimeSeriesLimitMarkers.limit_markers(%PlacementFrames{}) == []
  end

  defp limit_event_link(link_id, target_id) do
    %{
      "link_id" => link_id,
      "target" => "limit_event",
      "target_id" => target_id,
      "label" => "Limit event",
      "presentation" => "side_panel",
      "source" => "frame"
    }
  end

  defp limit_definition_link(link_id, target_id) do
    %{
      "link_id" => link_id,
      "target" => "limit_definition",
      "target_id" => target_id,
      "label" => "Limit definition",
      "presentation" => "side_panel",
      "source" => "frame"
    }
  end

  defp telemetry_sample_link(link_id, target_id) do
    %{
      "link_id" => link_id,
      "target" => "telemetry_sample",
      "target_id" => target_id,
      "label" => "Telemetry sample",
      "presentation" => "side_panel",
      "source" => "frame"
    }
  end
end
