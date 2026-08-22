defmodule CadenceWeb.OpsDashboardShowLive.TimeSeriesDataTest do
  use ExUnit.Case, async: true

  alias Cadence.Dashboards.{DataLink, Field, Frame, PlacementFrames}
  alias CadenceWeb.OpsDashboardShowLive.TimeSeriesData

  test "backfill renders wide telemetry series with envelope metadata" do
    frame = wide_frame()

    assert %{
             version: 1,
             series: [
               %{
                 id: "tlm.hk.battery_voltage",
                 label: "Battery voltage",
                 observable_id: "tlm.hk.battery_voltage",
                 unit: "V",
                 source: :telemetry,
                 frame_id: "frame-voltage",
                 field: "tlm.hk.battery_voltage_value",
                 time_axis: :receipt_time,
                 sampling: :decimated_envelope,
                 decimation: :native_min_max_envelope,
                 data_source_id: "questdb-flight",
                 source_binding_id: "binding-flight",
                 data_management: %{
                   data_view: "all_revisions",
                   warning_codes: ["corrected_range"],
                   badges: [
                     %{kind: :data_view, value: "all_revisions"},
                     %{kind: :revision_state, value: "corrected"}
                   ]
                 },
                 envelope: %{
                   kind: :min_max,
                   lower_field: "tlm.hk.battery_voltage_min",
                   upper_field: "tlm.hk.battery_voltage_max",
                   sample_count_field: "tlm.hk.battery_voltage_sample_count",
                   points: [[1_781_568_000_000, 11.5, 12.75, %{sample_count: 120}]]
                 },
                 points: [[1_781_568_000_000, 12.25, %{sample_id: "sample-1"}]]
               }
             ]
           } = TimeSeriesData.backfill(%PlacementFrames{primary: [frame]})

    assert %{
             data_management: %{
               data_view: "all_revisions",
               warning_codes: ["corrected_range"]
             }
           } = TimeSeriesData.backfill(%PlacementFrames{primary: [frame]})
  end

  test "backfill annotates decimated envelope buckets with recomputed limit rollups" do
    placement_frames = %PlacementFrames{
      primary: [wide_frame_with_bucket_end()],
      overlays: %{
        limits: [
          %Frame{
            source: :limits,
            shape: :events,
            fields: [
              %Field{name: "time", kind: :time, values: [~U[2026-06-16 00:02:00Z]]},
              %Field{name: "sample_id", kind: :string, values: ["sample-limit-1"]},
              %Field{name: "normalized_state", kind: :enum, values: [:yellow]},
              %Field{name: "limit_state", kind: :enum, values: [:yellow_high]},
              %Field{name: "violation", kind: :boolean, values: [true]},
              %Field{name: "observed_limit_event_id", kind: :string, values: ["limit-event-1"]},
              %Field{name: "observed_normalized_state", kind: :enum, values: [:green]},
              %Field{name: "limit_state_diverged", kind: :boolean, values: [true]}
            ],
            meta: %{
              semantics_mode: :compare,
              analysis_basis: :limit_comparison_analysis,
              selected_limit_clock: %{
                observed: :limit_event_receipt_time,
                requested_time_axis: :receipt_time
              },
              selected_limit_definition_intervals: [
                %{definition_id: "limit-def-compare", active_from: ~U[2026-06-16 00:00:00Z]}
              ],
              synthetic_limit_analysis?: true,
              links: [
                %DataLink{
                  link_id: "limit-event-link-1",
                  target: :limit_event,
                  target_id: "limit-event-1"
                },
                %DataLink{
                  link_id: "sample-link-limit-1",
                  target: :telemetry_sample,
                  target_id: "sample-limit-1"
                }
              ]
            }
          }
        ]
      }
    }

    assert %{
             series: [
               %{
                 envelope: %{
                   points: [
                     [
                       1_781_568_000_000,
                       11.5,
                       12.75,
                       %{
                         sample_count: 120,
                         worst_limit_normalized_state: "yellow",
                         worst_limit_state: "yellow_high",
                         limit_divergence_count: 1,
                         limit_event_ids: ["limit-event-1"],
                         limit_sample_ids: ["sample-limit-1"],
                         limit_semantics_modes: ["compare"],
                         limit_analysis_bases: ["limit_comparison_analysis"],
                         limit_selected_clocks: [
                           %{
                             observed: :limit_event_receipt_time,
                             requested_time_axis: :receipt_time
                           }
                         ],
                         limit_selected_definition_intervals: [
                           [
                             %{
                               definition_id: "limit-def-compare",
                               active_from: ~U[2026-06-16 00:00:00Z]
                             }
                           ]
                         ]
                       }
                     ]
                   ]
                 }
               }
             ]
           } = TimeSeriesData.backfill(placement_frames)
  end

  test "data renders latest wide telemetry point with data-management lifecycle" do
    assert %{
             kind: :point,
             spacecraft_id: "spacecraft-alpha",
             sample: %{
               sample_id: "sample-1",
               raw_value: 12.25,
               engineering_value: 12.25,
               receipt_time: ~U[2026-06-16 00:00:00Z],
               generation_time: ~U[2026-06-16 00:00:00Z],
               quality_state: :good
             },
             lifecycle_state: :partial,
             lifecycle: %{
               state: :partial,
               severity: :warning,
               warning_codes: [:corrected_range]
             },
             data_management: %{
               data_view: "all_revisions",
               warning_codes: ["corrected_range"]
             },
             query_scope_kind: "spacecraft",
             query_scope_id: "spacecraft-alpha",
             query_scope_ids: ["spacecraft-alpha"],
             engine_backed?: true
           } = TimeSeriesData.data(%PlacementFrames{primary: [wide_frame()]})
  end

  test "data preserves source diagnostics for empty engine-backed frames" do
    assert %{
             kind: :point,
             sample: nil,
             lifecycle_state: :no_data,
             source_status: %{
               state: :no_data,
               data_state: :no_data,
               scope_kinds: [:contact],
               scope_ids: ["contact-alpha"],
               contact_ids: ["contact-alpha"],
               source_endpoint_ids: ["endpoint-alpha"],
               empty_reason: :contact_scope_no_data
             },
             engine_backed?: true
           } = TimeSeriesData.data(%PlacementFrames{primary: [empty_contact_frame()]})
  end

  test "append emits only new scalar telemetry samples" do
    frame = scalar_frame("sample-2", 12.5)

    assert %{
             version: 1,
             series: [
               %{
                 id: "tlm.hk.battery_voltage",
                 points: [
                   [
                     1_781_568_001_000,
                     12.5,
                     %{sample_id: "sample-2", link_id: "sample-link:sample-2"}
                   ]
                 ]
               }
             ]
           } =
             TimeSeriesData.append(%PlacementFrames{primary: [frame]}, %{
               sample: %{sample_id: "sample-1"}
             })

    assert TimeSeriesData.append(%PlacementFrames{primary: [frame]}, %{
             sample: %{sample_id: "sample-2"}
           }) ==
             nil
  end

  test "scalar data includes sample link metadata" do
    assert %{
             time: ~U[2026-06-16 00:00:01Z],
             value: 12.5,
             sample_id: "sample-2",
             sample_link_id: "sample-link:sample-2",
             quality_state: :good
           } = TimeSeriesData.scalar_data(scalar_frame("sample-2", 12.5))
  end

  defp wide_frame do
    %Frame{
      frame_id: "frame-voltage",
      source: :telemetry,
      shape: :wide,
      time_axis: :receipt_time,
      scope: %{primary: %{kind: :spacecraft, ids: ["spacecraft-alpha"]}},
      fields: [
        %Field{name: "bucket_start", kind: :time, values: [~U[2026-06-16 00:00:00Z]]},
        %Field{name: "tlm.hk.battery_voltage_min", kind: :number, values: [11.5]},
        %Field{name: "tlm.hk.battery_voltage_max", kind: :number, values: [12.75]},
        %Field{name: "tlm.hk.battery_voltage_sample_count", kind: :number, values: [120]},
        %Field{
          name: "tlm.hk.battery_voltage_value",
          kind: :number,
          values: [12.25],
          metadata: %{
            observable_id: "tlm.hk.battery_voltage",
            label: "Battery voltage",
            unit: "V",
            sample_ids: ["sample-1"],
            quality_states: [:good]
          }
        }
      ],
      meta: %{
        observable_id: "tlm.hk.battery_voltage",
        unit: "V",
        sampling: :decimated_envelope,
        decimation: :native_min_max_envelope,
        data_source_id: "questdb-flight",
        source_binding_id: "binding-flight",
        data_view: :all_revisions,
        warning_codes: [:corrected_range],
        links: []
      }
    }
  end

  defp wide_frame_with_bucket_end do
    frame = wide_frame()

    %Frame{
      frame
      | fields: [
          %Field{name: "bucket_end", kind: :time, values: [~U[2026-06-16 00:05:00Z]]}
          | frame.fields
        ]
    }
  end

  defp empty_contact_frame do
    %Frame{
      frame_id: "frame-empty-contact",
      source: :telemetry,
      shape: :wide,
      time_axis: :receipt_time,
      fields: [
        %Field{name: "time", kind: :time, values: []},
        %Field{name: "tlm.hk.battery_voltage", kind: :number, values: []}
      ],
      meta: %{
        source_endpoint_ids: ["endpoint-alpha"],
        source_request_context: %{
          requested_scope_kind: :contact,
          requested_scope_ids: ["contact-alpha"],
          requested_contact_id: "contact-alpha"
        },
        warning_codes: [],
        links: []
      }
    }
  end

  defp scalar_frame(sample_id, value) do
    %Frame{
      frame_id: "frame-voltage-latest",
      source: :telemetry,
      shape: :scalar,
      time_axis: :receipt_time,
      fields: [
        %Field{name: "time", kind: :time, values: [~U[2026-06-16 00:00:01Z]]},
        %Field{
          name: "tlm.hk.battery_voltage",
          kind: :number,
          values: [value],
          metadata: %{
            observable_id: "tlm.hk.battery_voltage",
            unit: "V",
            sample_ids: [sample_id],
            quality_states: [:good],
            links: [
              %DataLink{
                link_id: "sample-link:#{sample_id}",
                target: :telemetry_sample,
                target_id: sample_id
              }
            ]
          }
        }
      ],
      meta: %{observable_id: "tlm.hk.battery_voltage", unit: "V", links: []}
    }
  end
end
