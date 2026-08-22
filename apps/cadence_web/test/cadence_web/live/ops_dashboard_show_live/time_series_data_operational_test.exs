defmodule CadenceWeb.OpsDashboardShowLive.TimeSeriesDataOperationalTest do
  use ExUnit.Case, async: true

  alias Cadence.Dashboards.{DataLink, Field, Frame, PlacementFrames}
  alias CadenceWeb.OpsDashboardShowLive.TimeSeriesData

  test "backfill renders operational metric wide series" do
    frame = operational_metric_frame()

    assert %{
             version: 1,
             series: [
               %{
                 id: "link.snr_db",
                 label: "RF SNR / link-alpha",
                 observable_id: "link.snr_db",
                 unit: "dB",
                 source: :operational_observables,
                 frame_id: "frame-rf-snr",
                 field: "link.snr_db",
                 time_axis: :occurred_at,
                 sampling: :raw_series,
                 data_source_id: "managed-operational",
                 source_binding_id: "ops-binding",
                 links: [
                   %{
                     link_id: "transport:transport-alpha:request-ops",
                     target: :transport,
                     target_id: "transport-alpha"
                   }
                 ],
                 points: [
                   [
                     1_781_697_660_000,
                     10.5,
                     %{
                       link_id: "transport:transport-alpha:request-ops",
                       target: "transport",
                       target_id: "transport-alpha"
                     }
                   ],
                   [
                     1_781_697_720_000,
                     12.75,
                     %{
                       link_id: "transport:transport-alpha:request-ops",
                       target: "transport",
                       target_id: "transport-alpha"
                     }
                   ]
                 ]
               }
             ]
           } = TimeSeriesData.backfill(%PlacementFrames{primary: [frame]})
  end

  test "zero-point operational metric wide series renders as chartable no-data" do
    frame = empty_operational_metric_frame()
    placement_frames = %PlacementFrames{primary: [frame]}

    assert TimeSeriesData.backfill(placement_frames) == nil

    assert %{
             kind: :point,
             sample: nil,
             lifecycle_state: :no_data,
             lifecycle: %{state: :no_data, severity: :info, warning_codes: []},
             source_status: %{
               state: :no_data,
               severity: :info,
               data_state: :no_data,
               logical_sources: [:operational_observables],
               source_request_ids: ["ops-request-1"],
               data_source_ids: ["managed-operational"],
               source_binding_ids: ["ops-binding"],
               scope_kinds: [:link],
               scope_ids: ["link-alpha"],
               empty_reason: :scope_no_data
             },
             engine_backed?: true
           } = TimeSeriesData.data(placement_frames)
  end

  test "data renders latest operational metric series point" do
    assert %{
             kind: :point,
             spacecraft_id: nil,
             source_request_id: "ops-request-1",
             logical_source: :operational_observables,
             observable_id: "link.snr_db",
             realm: :replay,
             data_source_id: "managed-operational",
             source_binding_id: "ops-binding",
             replay_run_id: "replay-run-1",
             dataset: "operational_observables_replay",
             query_scope_kind: "link",
             query_scope_id: "link-alpha",
             query_scope_ids: ["link-alpha"],
             sample: %{
               sample_id: nil,
               raw_value: 12.75,
               engineering_value: 12.75,
               receipt_time: ~U[2026-06-17 12:02:00Z],
               generation_time: ~U[2026-06-17 12:02:00Z],
               quality_state: nil
             },
             engine_backed?: true
           } = TimeSeriesData.data(%PlacementFrames{primary: [operational_metric_frame()]})
  end

  test "data preserves stale operational metric source status for chart widgets" do
    frame = stale_operational_metric_frame()

    assert %{
             version: 1,
             series: [
               %{
                 source: :operational_observables,
                 observable_id: "link.snr_db",
                 data_source_id: "managed-operational",
                 source_binding_id: "ops-binding",
                 points: [
                   [
                     1_781_697_660_000,
                     10.5,
                     %{target: "transport", target_id: "transport-alpha"}
                   ],
                   [
                     1_781_697_720_000,
                     12.75,
                     %{target: "transport", target_id: "transport-alpha"}
                   ]
                 ]
               }
             ]
           } = TimeSeriesData.backfill(%PlacementFrames{primary: [frame]})

    assert %{
             lifecycle_state: :stale,
             lifecycle: %{
               state: :stale,
               severity: :warning,
               warning_codes: [:stale_data]
             },
             stale?: true,
             source_status: %{
               state: :stale,
               severity: :warning,
               data_state: :ready,
               stale?: true,
               warning_codes: [:stale_data],
               freshness_states: [:stale],
               logical_sources: [:operational_observables],
               source_request_ids: ["ops-request-1"],
               data_source_ids: ["managed-operational"],
               source_binding_ids: ["ops-binding"],
               realms: [:replay],
               time_modes: [:replay_run],
               time_axes: [:occurred_at],
               replay_run_ids: ["replay-run-1"],
               scope_kinds: [:link],
               scope_ids: ["link-alpha"],
               source_endpoint_ids: ["endpoint-alpha"]
             },
             sample: %{
               raw_value: 12.75,
               engineering_value: 12.75
             }
           } = TimeSeriesData.data(%PlacementFrames{primary: [frame]})
  end

  defp operational_metric_frame do
    %Frame{
      frame_id: "frame-rf-snr",
      source: :operational_observables,
      shape: :wide,
      time_axis: :occurred_at,
      scope: %{primary: %{kind: :link, ids: ["link-alpha"]}},
      fields: [
        %Field{
          name: "time",
          kind: :time,
          values: [~U[2026-06-17 12:01:00Z], ~U[2026-06-17 12:02:00Z]]
        },
        %Field{
          name: "link.snr_db",
          kind: :number,
          values: [10.5, 12.75],
          metadata: %{
            observable_id: "link.snr_db",
            label: "RF SNR / link-alpha",
            unit: "dB",
            resource_link_id: "transport:transport-alpha:request-ops",
            links: [
              %DataLink{
                link_id: "transport:transport-alpha:request-ops",
                label: "Transport",
                target: :transport,
                target_id: "transport-alpha"
              }
            ]
          }
        }
      ],
      meta: %{
        observable_id: "link.snr_db",
        unit: "dB",
        sampling: :raw_series,
        source_request_id: "ops-request-1",
        realm: :replay,
        data_source_id: "managed-operational",
        source_binding_id: "ops-binding",
        replay_run_id: "replay-run-1",
        dataset: "operational_observables_replay",
        links: [
          %DataLink{
            link_id: "transport:transport-alpha:request-ops",
            label: "Transport",
            target: :transport,
            target_id: "transport-alpha"
          }
        ]
      }
    }
  end

  defp stale_operational_metric_frame do
    frame = operational_metric_frame()

    %Frame{
      frame
      | meta:
          Map.merge(frame.meta, %{
            warning_codes: [:stale_data],
            source_endpoint_ids: ["endpoint-alpha"],
            freshness_state: :stale,
            source_request_context: %{
              logical_source: :operational_observables,
              source_request_id: "ops-request-1",
              data_source_id: "managed-operational",
              source_binding_id: "ops-binding",
              realm: :replay,
              time_mode: :replay_run,
              time_axis: :occurred_at,
              replay_run_id: "replay-run-1",
              requested_scope_kind: :link,
              requested_scope_ids: ["link-alpha"],
              source_endpoint_ids: ["endpoint-alpha"]
            },
            source_watermarks: [
              %{
                request_id: "ops-request-1",
                logical_source: :operational_observables,
                data_source_id: "managed-operational",
                source_binding_id: "ops-binding",
                realm: :replay,
                time_mode: :replay_run,
                time_axis: :occurred_at,
                replay_run_id: "replay-run-1",
                scope_kind: :link,
                scope_ids: ["link-alpha"],
                source_endpoint_ids: ["endpoint-alpha"],
                freshness_state: :stale,
                confidence: :observed
              }
            ]
          })
    }
  end

  defp empty_operational_metric_frame do
    frame = operational_metric_frame()
    %Field{} = value_field = Enum.find(frame.fields, &(&1.name == "link.snr_db"))

    %Frame{
      frame
      | fields: [
          %Field{name: "time", kind: :time, values: [], metadata: %{axis: :occurred_at}},
          %Field{value_field | values: []}
        ],
        meta:
          Map.merge(frame.meta, %{
            returned_points: 0,
            source_request_id: "ops-request-1",
            source_request_context: %{
              logical_source: :operational_observables,
              source_request_id: "ops-request-1",
              data_source_id: "managed-operational",
              source_binding_id: "ops-binding",
              requested_scope_kind: :link,
              requested_scope_ids: ["link-alpha"]
            },
            warning_codes: []
          })
    }
  end
end
