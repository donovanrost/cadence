defmodule CadenceWeb.OpsDashboardShowLive.RenderWidgetModelComparisonTest do
  use ExUnit.Case, async: true

  alias Cadence.Dashboards.{Field, Frame, PlacementFrames, RenderWidget}
  alias CadenceWeb.OpsDashboardShowLive.RenderWidgetModel

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

  defp assigns(overrides) do
    Map.merge(
      %{
        dashboard_render_items: [],
        dashboard_data_view: "canonical",
        dashboard_compare_data_view: nil,
        dashboard_selected_data_ref: nil,
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
end
