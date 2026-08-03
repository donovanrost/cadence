defmodule CadenceWeb.OpsDashboardShowLive.WidgetLifecyclePresentationTest do
  use ExUnit.Case, async: true

  alias Cadence.Dashboards.{Frame, PlacementFrames, ResolveWarning}
  alias CadenceWeb.OpsDashboardShowLive.WidgetLifecyclePresentation

  test "put attaches ready lifecycle fields and preserves false stale state" do
    data = %{kind: :point, stale?: false}

    frame =
      %Frame{
        meta: %{
          warning_codes: [],
          source_watermarks: [
            %{
              logical_source: :telemetry,
              request_id: "source_req_telemetry_1",
              data_source_id: "questdb-flight",
              source_binding_id: "binding-flight",
              freshness_state: :fresh,
              confidence: :authoritative
            }
          ],
          source_request_context: %{
            source_request_id: "source_req_telemetry_1",
            logical_source: :telemetry,
            time_mode: :live,
            time_axis: :generation_time,
            requested_realm: :flight
          }
        }
      }

    placement_frames = %PlacementFrames{primary: [frame]}

    assert %{
             lifecycle_state: :ready,
             lifecycle: %{state: :ready, severity: :ok},
             stale?: false,
             source_status: %{
               state: :fresh,
               severity: :ok,
               data_state: :ready,
               stale?: false,
               warning_codes: [],
               freshness_states: [:fresh],
               confidences: [:authoritative],
               logical_sources: [:telemetry],
               source_request_ids: ["source_req_telemetry_1"],
               data_source_ids: ["questdb-flight"],
               source_binding_ids: ["binding-flight"],
               realms: [:flight],
               time_modes: [:live],
               time_axes: [:generation_time]
             }
           } = WidgetLifecyclePresentation.put(data, placement_frames, frame, :ready, false)
  end

  test "put promotes stale lifecycle from frame warning codes" do
    frame = %Frame{meta: %{"warning_codes" => ["watermark-unknown"]}}
    placement_frames = %PlacementFrames{primary: [frame]}

    assert %{
             lifecycle_state: :stale,
             lifecycle: %{state: :stale, severity: :warning},
             stale?: true,
             source_status: %{
               state: :stale,
               severity: :warning,
               stale?: true,
               warning_codes: [:watermark_unknown]
             }
           } =
             WidgetLifecyclePresentation.put(
               %{kind: :point},
               placement_frames,
               [frame],
               :ready,
               false
             )
  end

  test "put marks degraded source health while preserving ready widget data" do
    frame = %Frame{
      meta: %{
        data_source_id: "managed-operational",
        source_binding_id: "flight-operational",
        source_health: "degraded",
        source_health_reason: "source_schema_probe_failed",
        source_health_event_id: "source-health-event-1"
      }
    }

    placement_frames = %PlacementFrames{primary: [frame]}

    assert %{
             lifecycle_state: :ready,
             lifecycle: %{state: :ready, severity: :ok},
             stale?: false,
             source_status: %{
               state: :degraded,
               severity: :warning,
               data_state: :ready,
               stale?: false,
               warning_codes: [:source_degraded],
               data_source_ids: ["managed-operational"],
               source_binding_ids: ["flight-operational"],
               source_health_states: ["degraded"],
               source_health_reasons: ["source_schema_probe_failed"],
               source_health_event_ids: ["source-health-event-1"]
             }
           } =
             WidgetLifecyclePresentation.put(
               %{kind: :data_table},
               placement_frames,
               [frame],
               :ready,
               false
             )
  end

  test "put preserves unknown source status when unknown watermark also marks widget stale" do
    frame = %Frame{
      meta: %{
        warning_codes: [:watermark_unknown],
        source_watermarks: [
          %{
            logical_source: :telemetry,
            request_id: "source_req_telemetry_unknown",
            data_source_id: "questdb-flight",
            source_binding_id: "binding-flight",
            freshness_state: :unknown,
            confidence: :unknown
          }
        ]
      }
    }

    placement_frames = %PlacementFrames{primary: [frame]}

    assert %{
             lifecycle_state: :stale,
             lifecycle: %{state: :stale, severity: :warning},
             stale?: true,
             source_status: %{
               state: :unknown,
               severity: :warning,
               stale?: true,
               freshness_states: [:unknown],
               confidences: [:unknown],
               warning_codes: [:watermark_unknown]
             }
           } =
             WidgetLifecyclePresentation.put(
               %{kind: :point},
               placement_frames,
               [frame],
               :ready,
               true
             )
  end

  test "put includes placement warnings in lifecycle classification" do
    placement_frames = %PlacementFrames{
      warnings: [
        %ResolveWarning{
          code: :unsupported_source_capability,
          severity: :error,
          message: "Unsupported"
        }
      ]
    }

    assert %{
             lifecycle_state: :unsupported,
             lifecycle: %{
               state: :unsupported,
               severity: :error,
               reason_codes: [:unsupported, :no_data, :unsupported_source_capability]
             },
             source_status: %{
               state: :no_data,
               severity: :info,
               data_state: :no_data,
               warning_codes: [:unsupported_source_capability]
             }
           } =
             WidgetLifecyclePresentation.put(
               %{kind: :point},
               placement_frames,
               nil,
               :no_data,
               false
             )
  end

  test "put marks source status unavailable for source execution failures" do
    placement_frames = %PlacementFrames{
      warnings: [
        %ResolveWarning{
          code: :source_unavailable,
          severity: :error,
          message: "Source unavailable",
          details: %{
            source_request_id: "source-req-1",
            logical_source: :telemetry,
            binding_id: "binding-flight",
            data_source_id: "questdb-flight",
            realm: :flight,
            time_mode: :live,
            time_axis: :receipt_time
          }
        }
      ]
    }

    assert %{
             lifecycle_state: :error,
             source_status: %{
               state: :unavailable,
               severity: :error,
               data_state: :no_data,
               warning_codes: [:source_unavailable],
               logical_sources: [:telemetry],
               source_request_ids: ["source-req-1"],
               data_source_ids: ["questdb-flight"],
               source_binding_ids: ["binding-flight"],
               realms: [:flight],
               time_modes: [:live],
               time_axes: [:receipt_time]
             }
           } =
             WidgetLifecyclePresentation.put(
               %{kind: :point},
               placement_frames,
               nil,
               :no_data,
               false
             )
  end

  test "put keeps healthy primary telemetry ready when an optional limits overlay is unavailable" do
    telemetry_frame =
      %Frame{
        meta: %{
          data_source_id: "questdb-flight",
          source_binding_id: "binding-flight",
          source_request_context: %{
            source_request_id: "source-req-telemetry",
            logical_source: :telemetry
          }
        }
      }

    placement_frames = %PlacementFrames{
      primary: [telemetry_frame],
      warnings: [
        %ResolveWarning{
          code: :source_unavailable,
          severity: :error,
          message: "Limits source unavailable",
          details: %{
            source_request_id: "source-req-limits",
            logical_source: :limits,
            data_source_id: "managed-limits",
            source_binding_id: "binding-limits"
          }
        }
      ]
    }

    assert %{
             lifecycle_state: :ready,
             lifecycle: %{state: :ready, severity: :ok, warning_codes: []},
             source_status: %{
               state: :fresh,
               severity: :ok,
               warning_codes: [],
               logical_sources: [:telemetry],
               data_source_ids: ["questdb-flight"],
               source_binding_ids: ["binding-flight"]
             }
           } =
             WidgetLifecyclePresentation.put(
               %{kind: :point},
               placement_frames,
               telemetry_frame,
               :ready,
               false
             )
  end

  test "aggregate row data state only returns no-data when all rows are no-data" do
    assert WidgetLifecyclePresentation.aggregate_row_data_state([
             %{normalized_state: :no_data},
             %{normalized_state: :no_data}
           ]) == :no_data

    assert WidgetLifecyclePresentation.aggregate_row_data_state([
             %{normalized_state: :no_data},
             %{normalized_state: :connected}
           ]) == :ready
  end

  test "frame warning codes normalizes atom and dashed string codes" do
    frames = [
      %Frame{meta: %{warning_codes: [:partial_data, "watermark-unknown", "unknown-code"]}},
      %Frame{meta: %{"warning_codes" => ["partial-data"]}}
    ]

    assert WidgetLifecyclePresentation.frame_warning_codes(frames) == [
             :partial_data,
             :watermark_unknown
           ]
  end
end
