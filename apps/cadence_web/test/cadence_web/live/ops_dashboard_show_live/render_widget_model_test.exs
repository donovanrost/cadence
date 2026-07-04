defmodule CadenceWeb.OpsDashboardShowLive.RenderWidgetModelTest do
  use ExUnit.Case, async: true

  import CadenceWeb.DashboardReviewFixtures

  alias Cadence.Dashboards.{
    ComparisonReviewQueue,
    DashboardResolveRequest,
    DataLink,
    Document,
    Engine,
    Field,
    Frame,
    Placement,
    PlacementFrames,
    RenderWidget,
    ResolveWarning,
    WidgetDef
  }

  alias CadenceWeb.OpsDashboardShowLive.RenderWidgetModel

  test "selected_data_ref_for_placement keeps global selections and matching placement selections" do
    global_ref = %{"target" => "telemetry_sample"}
    placement_ref = %{"target" => "telemetry_sample", "placement_id" => "placement-1"}

    assert RenderWidgetModel.selected_data_ref_for_placement(global_ref, "placement-1") ==
             global_ref

    assert RenderWidgetModel.selected_data_ref_for_placement(placement_ref, "placement-1") ==
             placement_ref

    assert RenderWidgetModel.selected_data_ref_for_placement(placement_ref, "placement-2") == nil
    assert RenderWidgetModel.selected_data_ref_for_placement(nil, "placement-1") == nil
  end

  test "widget_items prepares shell attrs and edit mode classes" do
    [widget_item] =
      assigns(%{
        edit_mode?: true,
        dashboard_render_items: [
          render_item("placement-1", %{layout: %{x: nil, y: 2, w: 5, h: 4}})
        ]
      })
      |> RenderWidgetModel.widget_items()

    assert widget_item.shell_attrs == %{
             :id => "widget-placement-1",
             :class => "grid-stack-item",
             :"gs-id" => "placement-1",
             :"gs-x" => nil,
             :"gs-y" => 2,
             :"gs-w" => 5,
             :"gs-h" => 4,
             :"gs-auto-position" => "true",
             "data-widget-lifecycle-state" => "no_data",
             "data-widget-lifecycle-severity" => "info",
             "data-widget-lifecycle-reasons" => "no_data",
             "data-widget-lifecycle-warning-codes" => "",
             "data-widget-placement-warning-codes" => "",
             "data-widget-source-state" => "",
             "data-widget-source-severity" => "",
             "data-widget-source-data-state" => "",
             "data-widget-source-stale" => "",
             "data-widget-source-warning-codes" => "",
             "data-widget-source-freshness-states" => "",
             "data-widget-source-confidences" => "",
             "data-widget-source-logical-sources" => "",
             "data-widget-source-request-ids" => "",
             "data-widget-source-data-source-ids" => "",
             "data-widget-source-binding-ids" => "",
             "data-widget-source-realms" => "",
             "data-widget-source-time-modes" => "",
             "data-widget-source-time-axes" => "",
             "data-widget-source-replay-run-ids" => "",
             "data-widget-source-scope-kinds" => "",
             "data-widget-source-scope-ids" => "",
             "data-widget-source-contact-ids" => "",
             "data-widget-source-source-endpoint-ids" => "",
             "data-widget-source-empty-reason" => ""
           }

    assert Enum.member?(
             widget_item.content_class,
             "grid-stack-item-content bg-base-200 border flex flex-col overflow-hidden"
           )

    assert Enum.member?(
             widget_item.content_class,
             "border-primary/40 ring-1 ring-primary/20 cursor-move"
           )

    [locked_widget_item] =
      assigns(%{
        edit_mode?: false,
        dashboard_render_items: [render_item("placement-2", %{layout: %{x: 1, y: 0, w: 4, h: 3}})]
      })
      |> RenderWidgetModel.widget_items()

    assert locked_widget_item.shell_attrs["gs-auto-position"] == nil

    assert Enum.member?(
             locked_widget_item.content_class,
             "border-base-300 hover:border-primary/60"
           )
  end

  test "widget_items prepares widget props with legacy data when no engine frame exists" do
    point = %{point_id: "HK.temp"}
    legacy_data = %{kind: :legacy_point}
    selected_ref = %{"target" => "telemetry_sample"}

    [widget_item] =
      assigns(%{
        dashboard_render_items: [render_item("placement-1")],
        widget_data: %{"placement-1" => legacy_data},
        points_by_id: %{"HK.temp" => point},
        dashboard_selected_data_ref: selected_ref,
        dashboard_time_mode: "replay_run",
        dashboard_time_context: %{"mode" => "replay_run", "axis" => "receipt_time"},
        dashboard_replay_run_id: "replay-run-1",
        dashboard_data_realm: "rehearsal",
        context_spacecraft_id: "SC-1",
        dashboard_data_source_id: "questdb-rehearsal",
        dashboard_source_binding_id: "binding-rehearsal",
        chart_epoch: 3,
        edit_mode?: true
      })
      |> RenderWidgetModel.widget_items()

    assert widget_item.item.placement_id == "placement-1"
    assert widget_item.props.data == legacy_data
    assert widget_item.props.compare_data == nil
    assert widget_item.props.point == point
    assert widget_item.props.backfill == nil
    assert widget_item.props.limit_markers == []
    assert widget_item.props.event_markers == []
    assert widget_item.props.selected_data_ref == selected_ref
    assert widget_item.props.context_spacecraft_id == "SC-1"
    assert widget_item.props.chart_epoch == 3
    assert widget_item.props.edit_mode == true
    assert widget_item.props.warnings == []

    assert widget_item.component_props == %{
             widget: widget_item.item.widget,
             placement_id: "placement-1",
             mission_id: nil,
             data: legacy_data,
             compare_data: nil,
             point: point,
             spacecraft: [],
             backfill: nil,
             compare_backfill: nil,
             limit_markers: [],
             event_markers: [],
             selected_data_ref: selected_ref,
             time_mode: "replay_run",
             time_axis: "receipt_time",
             replay_run_id: "replay-run-1",
             data_realm: "rehearsal",
             data_view: "canonical",
             compare_data_view: nil,
             data_source_id: "questdb-rehearsal",
             source_binding_id: "binding-rehearsal",
             comparison_summary: nil,
             context_spacecraft_id: "SC-1",
             chart_epoch: 3,
             edit_mode?: true,
             warnings: []
           }
  end

  test "widget_items prepares engine-backed widget props and placement warnings" do
    legacy_data = %{kind: :legacy_point}

    placement_frames = %PlacementFrames{
      warnings: [
        %ResolveWarning{
          code: :watermark_unknown,
          severity: :warning,
          scope: :placement,
          message: "Watermark unavailable",
          details: %{source_binding_id: "flight-binding"}
        }
      ]
    }

    [widget_item] =
      assigns(%{
        dashboard_render_items: [render_item("placement-1")],
        widget_data: %{"placement-1" => legacy_data},
        dashboard_engine_frames_by_placement: %{"placement-1" => placement_frames}
      })
      |> RenderWidgetModel.widget_items()

    assert widget_item.props.data.kind == :point
    assert widget_item.props.data.lifecycle_state == :no_data
    refute Map.equal?(widget_item.props.data, legacy_data)

    assert [
             %{
               code: :watermark_unknown,
               severity: :warning,
               message: "Watermark unavailable"
             }
           ] = widget_item.props.warnings
  end

  test "widget_items prepares comparison data from comparison frames" do
    [widget_item] =
      assigns(%{
        dashboard_render_items: [render_item("placement-1")],
        dashboard_data_view: "all_revisions",
        dashboard_compare_data_view: "canonical",
        dashboard_engine_frames_by_placement: %{
          "placement-1" =>
            scalar_frames(42,
              sample_id: "primary-sample-1",
              link_id: "primary-link-1",
              data_source_id: "questdb-primary",
              source_binding_id: "binding-primary",
              scope_context: %{
                scope_kind: :transport,
                scope_id: "transport-alpha",
                resource_id: "transport-alpha",
                transport_id: "transport-alpha",
                source_endpoint_id: "endpoint-alpha",
                ground_station_id: "dss-14",
                scope_link_id: "link-alpha"
              },
              meta: %{analysis_basis: :recomputed_analysis}
            )
        },
        dashboard_compare_engine_frames_by_placement: %{
          "placement-1" =>
            scalar_frames(40,
              sample_id: "compare-sample-1",
              link_id: "compare-link-1",
              data_source_id: "questdb-compare",
              source_binding_id: "binding-compare",
              meta: %{
                source_health: :degraded,
                source_health_reason: :source_schema_probe_failed,
                source_health_event_id: "source-health-event-compare"
              }
            )
        }
      })
      |> RenderWidgetModel.widget_items()

    assert widget_item.props.data.sample.engineering_value == 42
    assert widget_item.props.compare_data.sample.engineering_value == 40
    assert widget_item.props.comparison_summary.state == "increased"
    assert widget_item.props.comparison_summary.delta == "+2"
    assert widget_item.props.comparison_summary.primary_sample_id == "primary-sample-1"
    assert widget_item.props.comparison_summary.compare_sample_id == "compare-sample-1"
    assert widget_item.props.comparison_summary.primary_data_link.link_id == "primary-link-1"
    assert widget_item.props.comparison_summary.compare_data_link.link_id == "compare-link-1"

    assert widget_item.props.comparison_summary.primary_data_link.context.data.data_source_id ==
             "questdb-primary"

    assert widget_item.props.comparison_summary.compare_data_link.context.data.source_binding_id ==
             "binding-compare"

    assert widget_item.props.comparison_summary.scope_kind == "transport"
    assert widget_item.props.comparison_summary.scope_id == "transport-alpha"
    assert widget_item.props.comparison_summary.resource_id == "transport-alpha"
    assert widget_item.props.comparison_summary.transport_id == "transport-alpha"
    assert widget_item.props.comparison_summary.source_endpoint_id == "endpoint-alpha"
    assert widget_item.props.comparison_summary.ground_station_id == "dss-14"
    assert widget_item.props.comparison_summary.scope_link_id == "link-alpha"

    assert %{
             badges: [%{kind: :analysis_basis, value: "recomputed_analysis"}]
           } = widget_item.props.comparison_summary.primary_data_management

    assert %{
             badges: [%{kind: :source_health, value: "degraded"}]
           } = widget_item.props.comparison_summary.compare_data_management

    assert widget_item.component_props.compare_data == widget_item.props.compare_data
    assert widget_item.component_props.comparison_summary == widget_item.props.comparison_summary
  end

  test "widget_items prepares time-series comparison backfill from comparison frames" do
    [widget_item] =
      assigns(%{
        dashboard_render_items: [
          render_item("placement-1", %{widget: render_widget(%{type: :time_series})})
        ],
        dashboard_data_view: "all_revisions",
        dashboard_compare_data_view: "canonical",
        dashboard_engine_frames_by_placement: %{"placement-1" => wide_frames(42)},
        dashboard_compare_engine_frames_by_placement: %{"placement-1" => wide_frames(40)}
      })
      |> RenderWidgetModel.widget_items()

    assert %{series: [%{points: [[_, 42]]}]} = widget_item.props.backfill
    assert %{series: [%{points: [[_, 40]]}]} = widget_item.props.compare_backfill
    assert widget_item.props.comparison_summary.state == "available"
    assert widget_item.props.comparison_summary.primary_count == 1
    assert widget_item.props.comparison_summary.compare_count == 1
    assert widget_item.component_props.compare_backfill == widget_item.props.compare_backfill
    assert widget_item.component_props.comparison_summary == widget_item.props.comparison_summary
  end

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

  test "widget_items prepares operational matrix comparison metadata" do
    [widget_item] =
      assigns(%{
        dashboard_render_items: [
          render_item("placement-ops", %{
            widget:
              render_widget(%{
                type: :status_matrix,
                title: "Transport State",
                binding: %{
                  source: :operational_observables,
                  mode: :context,
                  point_id: "comms.transport.connection_state",
                  point_ids: ["comms.transport.connection_state"]
                }
              })
          })
        ],
        dashboard_data_view: "all_revisions",
        dashboard_compare_data_view: "canonical",
        dashboard_engine_frames_by_placement: %{
          "placement-ops" => operational_matrix_frames(:connected)
        },
        dashboard_compare_engine_frames_by_placement: %{
          "placement-ops" => operational_matrix_frames(:disconnected)
        }
      })
      |> RenderWidgetModel.widget_items()

    assert widget_item.props.data.kind == :status_matrix
    assert widget_item.props.compare_data.kind == :status_matrix
    assert widget_item.props.comparison_summary.state == "available"
    assert widget_item.props.comparison_summary.primary_count == 1
    assert widget_item.props.comparison_summary.compare_count == 1
    assert widget_item.props.comparison_summary.widget_type == "status_matrix"
    assert widget_item.props.comparison_summary.widget_source == "operational_observables"
    assert widget_item.props.comparison_summary.primary_kind == "status_matrix"
    assert widget_item.props.comparison_summary.compare_kind == "status_matrix"

    assert widget_item.props.comparison_summary.primary_observable_ids == [
             "comms.transport.connection_state:transport-alpha"
           ]

    assert widget_item.props.comparison_summary.compare_observable_ids == [
             "comms.transport.connection_state:transport-alpha"
           ]

    assert widget_item.props.comparison_summary.scope_kind == "transport"
    assert widget_item.props.comparison_summary.scope_id == "transport-alpha"
    assert widget_item.props.comparison_summary.source_endpoint_id == "endpoint-alpha"
    assert widget_item.component_props.comparison_summary == widget_item.props.comparison_summary
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

  test "widget_items marks placements affected by focused comparison reviews" do
    lifecycle_events = [
      comparison_review_request_event(
        event_id: "review-request-1",
        placement_ids: ["placement-1"]
      )
    ]

    [focused_widget_item, ordinary_widget_item] =
      assigns(%{
        dashboard_activity_filter: :open_comparison_reviews,
        dashboard_review_placement_id: "placement-1",
        dashboard_lifecycle_events: lifecycle_events,
        dashboard_comparison_review_queue: ComparisonReviewQueue.open_summary(lifecycle_events),
        dashboard_render_items: [
          render_item("placement-1"),
          render_item("placement-2")
        ]
      })
      |> RenderWidgetModel.widget_items()

    assert focused_widget_item.shell_attrs[:class] ==
             "grid-stack-item dashboard-review-placement-focus dashboard-review-placement-selected"

    assert focused_widget_item.shell_attrs["data-dashboard-review-placement-focus"] ==
             "open_comparison_reviews"

    assert focused_widget_item.shell_attrs["data-dashboard-review-placement-id"] == "placement-1"

    assert focused_widget_item.shell_attrs["data-dashboard-review-request-ids"] ==
             "review-request-1"

    assert focused_widget_item.shell_attrs["data-dashboard-review-placement-selected"] == "true"
    assert focused_widget_item.props.review_focus.request_ids == ["review-request-1"]
    assert focused_widget_item.props.review_focus.selected_placement_id == "placement-1"

    assert ordinary_widget_item.shell_attrs[:class] == "grid-stack-item"
    refute Map.has_key?(ordinary_widget_item.shell_attrs, "data-dashboard-review-placement-focus")
    assert ordinary_widget_item.props.review_focus == nil
  end

  test "widget_items carries stale operational source warnings into lifecycle attrs" do
    document = operational_command_queue_document()

    result =
      Engine.resolve(
        %DashboardResolveRequest{
          organization_id: document.organization_id,
          mission_id: document.mission_id,
          dashboard_id: document.dashboard_id,
          document: document
        },
        freshness_now: ~U[2026-06-17 12:05:02Z],
        source_freshness_policies: %{operational_observables: %{stale_after_ms: 1_000}},
        source_opts: %{
          operational_observables: [
            command_queue_entries_fun: fn _organization_id, _mission_id, _opts -> [] end,
            read_time: ~U[2026-06-17 12:05:00Z]
          ]
        }
      )

    [widget_item] =
      assigns(%{
        dashboard_document: document,
        dashboard_render_items: [
          render_item("placement-command-queue", %{
            widget:
              render_widget(%{
                type: :value_tile,
                title: "Command Queue",
                binding: %{
                  source: :operational_observables,
                  mode: :context,
                  point_id: "commanding.queue_depth",
                  point_ids: ["commanding.queue_depth"]
                }
              })
          })
        ],
        dashboard_engine_frames_by_placement: result.frames_by_placement
      })
      |> RenderWidgetModel.widget_items()

    assert widget_item.shell_attrs["data-widget-lifecycle-state"] == "stale"
    assert widget_item.shell_attrs["data-widget-lifecycle-severity"] == "warning"
    assert widget_item.shell_attrs["data-widget-lifecycle-reasons"] == "stale,stale_data"
    assert widget_item.shell_attrs["data-widget-lifecycle-warning-codes"] == "stale_data"
    assert widget_item.shell_attrs["data-widget-placement-warning-codes"] == "stale_data"
    assert widget_item.shell_attrs["data-widget-source-state"] == "stale"
    assert widget_item.shell_attrs["data-widget-source-severity"] == "warning"
    assert widget_item.shell_attrs["data-widget-source-data-state"] == "ready"
    assert widget_item.shell_attrs["data-widget-source-stale"] == "true"
    assert widget_item.shell_attrs["data-widget-source-warning-codes"] == "stale_data"

    assert widget_item.shell_attrs["data-widget-source-logical-sources"] ==
             "operational_observables"

    assert widget_item.shell_attrs["data-widget-source-data-source-ids"] ==
             "managed_operational_observables"

    assert widget_item.shell_attrs["data-widget-source-binding-ids"] ==
             "default_flight_operational_observables"

    assert widget_item.shell_attrs["data-widget-source-realms"] == "flight"
    assert widget_item.component_props.mission_id == "mission-render-widget"

    assert widget_item.props.data.lifecycle_state == :stale
    assert widget_item.props.data.sample.engineering_value == 0
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
    sample_id = Keyword.get(opts, :sample_id)

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
              metadata:
                %{}
                |> maybe_put_sample_ids(sample_id)
                |> maybe_put_links(scalar_data_link(opts, sample_id))
            }
          ],
          meta:
            %{observable_id: "HK.temp", warning_codes: Keyword.get(opts, :warning_codes, [])}
            |> Map.merge(Keyword.get(opts, :meta, %{}))
        }
      ]
    }
  end

  defp maybe_put_sample_ids(metadata, nil), do: metadata
  defp maybe_put_sample_ids(metadata, sample_id), do: Map.put(metadata, :sample_ids, [sample_id])

  defp maybe_put_links(metadata, nil), do: metadata
  defp maybe_put_links(metadata, link), do: Map.put(metadata, :links, [link])

  defp scalar_data_link(opts, sample_id) do
    case Keyword.get(opts, :link_id) do
      nil ->
        nil

      link_id ->
        %{
          link_id: link_id,
          label: "Telemetry sample",
          target: :telemetry_sample,
          target_id: sample_id,
          context: %{
            data: %{
              realm: :flight,
              view: "canonical",
              data_source_id: Keyword.get(opts, :data_source_id),
              source_binding_id: Keyword.get(opts, :source_binding_id)
            },
            scope: Keyword.get(opts, :scope_context, %{}),
            time: %{mode: "archive", axis: "receipt_time"}
          }
        }
    end
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

  defp wide_frames(value) do
    %PlacementFrames{
      primary: [
        %Frame{
          source: :telemetry,
          shape: :wide,
          scope: %{primary: %{ids: ["spacecraft-alpha"]}},
          fields: [
            %Field{name: "time", kind: :time, values: [~U[2026-06-17 12:00:00Z]]},
            %Field{name: "HK.temp", kind: :number, values: [value]}
          ],
          meta: %{observable_id: "HK.temp", warning_codes: []}
        }
      ]
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

  defp operational_matrix_frames(connection_state) do
    %PlacementFrames{
      primary: [
        %Frame{
          source: :operational_observables,
          shape: :matrix,
          fields: [
            %Field{
              name: "observable_id",
              kind: :string,
              values: ["comms.transport.connection_state"]
            },
            %Field{name: "resource_id", kind: :string, values: ["transport-alpha"]},
            %Field{name: "label", kind: :string, values: ["Lab TCP"]},
            %Field{name: "scope_kind", kind: :enum, values: [:transport]},
            %Field{name: "transport_id", kind: :string, values: ["transport-alpha"]},
            %Field{name: "source_endpoint_id", kind: :string, values: ["endpoint-alpha"]},
            %Field{name: "ground_station_id", kind: :string, values: ["dss-14"]},
            %Field{name: "connection_state", kind: :enum, values: [connection_state]},
            %Field{name: "observed_at", kind: :time, values: [~U[2026-06-17 12:03:00Z]]}
          ],
          meta: %{
            observable_ids: ["comms.transport.connection_state"],
            logical_source: :operational_observables,
            links: []
          }
        }
      ]
    }
  end

  defp operational_command_queue_document do
    %Document{
      dashboard_id: "dashboard-command-queue",
      organization_id: "org-render-widget",
      mission_id: "mission-render-widget",
      name: "Command Queue",
      placements: [
        %Placement{
          placement_id: "placement-command-queue",
          layout: %{x: nil, y: nil, w: 3, h: 2},
          widget_def: %WidgetDef{
            widget_type_id: "cadence.value_tile",
            widget_type_version: 1,
            title: "Command Queue",
            binding: %{
              source: :operational_observables,
              observables: ["commanding.queue_depth"],
              scope_mode: :context,
              data_mode: :context,
              value_type: :engineering,
              sampling: :latest,
              overlays: []
            },
            options: %{precision: 0}
          }
        }
      ]
    }
  end
end
