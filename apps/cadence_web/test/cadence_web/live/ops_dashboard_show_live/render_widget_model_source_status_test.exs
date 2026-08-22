defmodule CadenceWeb.OpsDashboardShowLive.RenderWidgetModelSourceStatusTest do
  use ExUnit.Case, async: true

  alias Cadence.Dashboards.{
    ComparisonReviewQueue,
    DataLink,
    Field,
    Frame,
    PlacementFrames,
    RenderWidget
  }

  alias CadenceWeb.OpsDashboardShowLive.RenderWidgetModel

  test "widget_items preserves stale operational metric-history lifecycle attrs for charts" do
    [widget_item] =
      assigns(%{
        dashboard_render_items: [
          render_item("placement-rf-snr-history", %{
            widget:
              render_widget(%{
                type: :time_series,
                title: "RF SNR",
                binding: %{
                  source: :operational_observables,
                  mode: :context,
                  point_id: "link.snr_db",
                  point_ids: ["link.snr_db"]
                }
              })
          })
        ],
        dashboard_engine_frames_by_placement: %{
          "placement-rf-snr-history" => stale_operational_metric_frames()
        }
      })
      |> RenderWidgetModel.widget_items()

    assert %{
             lifecycle_state: :stale,
             lifecycle: %{state: :stale, severity: :warning, warning_codes: [:stale_data]},
             source_status: %{
               state: :stale,
               severity: :warning,
               data_state: :ready,
               stale?: true
             }
           } = widget_item.props.data

    assert %{
             series: [
               %{
                 source: :operational_observables,
                 observable_id: "link.snr_db",
                 data_source_id: "managed-operational",
                 source_binding_id: "ops-binding",
                 points: [
                   [_, 10.5, %{target: "transport", target_id: "transport-alpha"}],
                   [_, 12.75, %{target: "transport", target_id: "transport-alpha"}]
                 ]
               }
             ]
           } = widget_item.props.backfill

    assert widget_item.shell_attrs["data-widget-lifecycle-state"] == "stale"
    assert widget_item.shell_attrs["data-widget-lifecycle-severity"] == "warning"
    assert widget_item.shell_attrs["data-widget-lifecycle-warning-codes"] == "stale_data"
    assert widget_item.shell_attrs["data-widget-source-state"] == "stale"
    assert widget_item.shell_attrs["data-widget-source-severity"] == "warning"
    assert widget_item.shell_attrs["data-widget-source-data-state"] == "ready"
    assert widget_item.shell_attrs["data-widget-source-stale"] == "true"
    assert widget_item.shell_attrs["data-widget-source-warning-codes"] == "stale_data"
    assert widget_item.shell_attrs["data-widget-source-freshness-states"] == "stale"

    assert widget_item.shell_attrs["data-widget-source-logical-sources"] ==
             "operational_observables"

    assert widget_item.shell_attrs["data-widget-source-request-ids"] == "ops-request-1"
    assert widget_item.shell_attrs["data-widget-source-data-source-ids"] == "managed-operational"
    assert widget_item.shell_attrs["data-widget-source-binding-ids"] == "ops-binding"
    assert widget_item.shell_attrs["data-widget-source-realms"] == "replay"
    assert widget_item.shell_attrs["data-widget-source-time-modes"] == "replay_run"
    assert widget_item.shell_attrs["data-widget-source-time-axes"] == "occurred_at"
    assert widget_item.shell_attrs["data-widget-source-replay-run-ids"] == "replay-run-1"
    assert widget_item.shell_attrs["data-widget-source-scope-kinds"] == "link"
    assert widget_item.shell_attrs["data-widget-source-scope-ids"] == "link-alpha"

    assert widget_item.shell_attrs["data-widget-source-source-endpoint-ids"] ==
             "endpoint-alpha"

    assert widget_item.component_props.backfill == widget_item.props.backfill
    assert widget_item.component_props.data == widget_item.props.data
  end

  test "widget_items stamps lifecycle state and warning summaries on shell attrs" do
    placement_frames = scalar_frames(42, warning_codes: [:partial_data])

    [widget_item] =
      assigns(%{
        dashboard_render_items: [render_item("placement-1")],
        dashboard_engine_frames_by_placement: %{"placement-1" => placement_frames}
      })
      |> RenderWidgetModel.widget_items()

    assert widget_item.shell_attrs["data-widget-lifecycle-state"] == "partial"
    assert widget_item.shell_attrs["data-widget-lifecycle-severity"] == "warning"
    assert widget_item.shell_attrs["data-widget-lifecycle-reasons"] == "partial,partial_data"
    assert widget_item.shell_attrs["data-widget-lifecycle-warning-codes"] == "partial_data"
  end

  test "widget shell attrs preserve full no-data source context" do
    shell_attrs =
      RenderWidgetModel.widget_shell_attrs(
        render_item("placement-rf-snr-history"),
        %{
          data: %{lifecycle_state: :no_data, source_status: no_data_source_status()},
          warnings: []
        }
      )

    assert shell_attrs["data-widget-lifecycle-state"] == "no_data"
    assert shell_attrs["data-widget-lifecycle-severity"] == "info"
    assert shell_attrs["data-widget-lifecycle-reasons"] == "no_data"
    assert shell_attrs["data-widget-source-state"] == "no_data"
    assert shell_attrs["data-widget-source-severity"] == "info"
    assert shell_attrs["data-widget-source-data-state"] == "no_data"
    assert shell_attrs["data-widget-source-stale"] == "false"
    assert shell_attrs["data-widget-source-warning-codes"] == ""
    assert shell_attrs["data-widget-source-logical-sources"] == "operational_observables"
    assert shell_attrs["data-widget-source-request-ids"] == "source-request-empty"

    assert shell_attrs["data-widget-source-data-source-ids"] ==
             "managed_operational_observables"

    assert shell_attrs["data-widget-source-binding-ids"] ==
             "default_flight_operational_observables"

    assert shell_attrs["data-widget-source-realms"] == "flight"
    assert shell_attrs["data-widget-source-time-modes"] == "archive"
    assert shell_attrs["data-widget-source-time-axes"] == "generation_time"
    assert shell_attrs["data-widget-source-scope-kinds"] == "link"
    assert shell_attrs["data-widget-source-scope-ids"] == "link-alpha"
    assert shell_attrs["data-widget-source-source-endpoint-ids"] == "source-endpoint-alpha"
    assert shell_attrs["data-widget-source-empty-reason"] == "scope_no_data"
  end

  defp assigns(overrides) do
    Map.merge(
      %{
        dashboard_render_items: [],
        dashboard_activity_filter: nil,
        dashboard_review_placement_id: nil,
        dashboard_lifecycle_events: [],
        dashboard_comparison_review_queue: ComparisonReviewQueue.open_summary([]),
        dashboard_selected_data_ref: nil,
        dashboard_data_view: "canonical",
        dashboard_compare_data_view: nil,
        context_spacecraft_id: nil,
        edit_mode?: false,
        spacecraft: [],
        chart_epoch: 1,
        widget_data: %{},
        backfills: %{},
        dashboard_engine_frames_by_placement: %{},
        dashboard_compare_engine_frames_by_placement: %{},
        points_by_id: %{}
      },
      overrides
    )
  end

  defp render_item(placement_id, attrs \\ %{}) do
    Map.merge(
      %{
        placement_id: placement_id,
        layout: %{x: 0, y: 0, w: 4, h: 3},
        widget: render_widget()
      },
      attrs
    )
  end

  defp render_widget(attrs \\ %{}) do
    attrs =
      Map.merge(
        %{
          widget_id: "widget-1",
          type: :value_tile,
          title: "Temperature",
          binding: %{
            source: :telemetry,
            mode: :context,
            spacecraft_id: nil,
            point_id: "HK.temp",
            point_ids: ["HK.temp"]
          },
          options: %{precision: 2, window_seconds: 300}
        },
        attrs
      )

    struct!(RenderWidget, attrs)
  end

  defp scalar_frames(value, opts) do
    %PlacementFrames{
      primary: [
        %Frame{
          source: :telemetry,
          shape: :scalar,
          scope: %{primary: %{ids: ["spacecraft-alpha"]}},
          fields: [
            %Field{name: "time", kind: :time, values: [~U[2026-06-17 12:00:00Z]]},
            %Field{
              name: "HK.temp",
              kind: :number,
              values: [value],
              metadata: %{}
            }
          ],
          meta:
            %{observable_id: "HK.temp", warning_codes: Keyword.get(opts, :warning_codes, [])}
            |> Map.merge(Keyword.get(opts, :meta, %{}))
        }
      ]
    }
  end

  defp no_data_source_status do
    %{
      state: :no_data,
      severity: :info,
      data_state: :no_data,
      stale?: false,
      warning_codes: [],
      source_request_ids: ["source-request-empty"],
      logical_sources: [:operational_observables],
      data_source_ids: ["managed_operational_observables"],
      source_binding_ids: ["default_flight_operational_observables"],
      realms: [:flight],
      time_modes: [:archive],
      time_axes: [:generation_time],
      scope_kinds: [:link],
      scope_ids: ["link-alpha"],
      source_endpoint_ids: ["source-endpoint-alpha"],
      empty_reason: :scope_no_data
    }
  end

  defp stale_operational_metric_frames do
    %PlacementFrames{
      primary: [
        %Frame{
          frame_id: "frame-rf-snr",
          source: :operational_observables,
          shape: :wide,
          time_axis: :occurred_at,
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
            ],
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
      ]
    }
  end
end
