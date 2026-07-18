defmodule Cadence.Dashboards.PlacementEditorTest do
  use Cadence.UnitCase, async: true

  alias Cadence.Dashboards.{Document, Placement, PlacementEditor, RenderItem, WidgetDef}

  test "builds a canonical value-tile placement from add-widget params" do
    assert {:ok, %Placement{} = placement} =
             PlacementEditor.build_placement(
               %{
                 "type" => "value_tile",
                 "title" => "Counter",
                 "mode" => "context",
                 "precision" => "1",
                 "window_seconds" => "300"
               },
               "HK.counter",
               :add_widget
             )

    assert placement.placement_id =~ "dash_widget_"
    assert placement.layout == %{x: nil, y: nil, w: 4, h: 2}
    assert placement.scope_override == nil
    assert placement.widget_def.widget_type_id == "cadence.value_tile"
    assert placement.widget_def.title == "Counter"

    assert placement.widget_def.binding == %{
             source: :telemetry,
             observables: ["HK.counter"],
             scope_mode: :context,
             data_mode: :context,
             value_type: :engineering,
             sampling: :latest,
             overlays: [:limits, :quality]
           }

    assert placement.widget_def.options == %{
             precision: 1,
             window_seconds: 300,
             show_unit: true
           }
  end

  test "builds fixed-scope placements with a canonical scope override" do
    assert {:ok, %Placement{} = placement} =
             PlacementEditor.build_placement(
               %{
                 "type" => "time_series",
                 "title" => "Counter Trend",
                 "mode" => "fixed",
                 "spacecraft_id" => "sc-alpha",
                 "precision" => "2",
                 "window_seconds" => "900"
               },
               "HK.counter",
               :add_widget
             )

    assert placement.layout == %{x: nil, y: nil, w: 4, h: 3}

    assert placement.scope_override == %{
             primary: %{kind: "spacecraft", mode: "one", ids: ["sc-alpha"]}
           }

    assert placement.widget_def.widget_type_id == "cadence.time_series"
    assert placement.widget_def.binding.scope_mode == :override
    assert placement.widget_def.binding.sampling == :raw_series
    assert placement.widget_def.binding.overlays == [:limits, :events, :quality]
    assert placement.widget_def.options == %{precision: 2, window_seconds: 900}
  end

  test "builds pinned non-spacecraft scope placements with a canonical scope override" do
    assert {:ok, %Placement{} = placement} =
             PlacementEditor.build_placement(
               %{
                 "type" => "time_series",
                 "title" => "Ground Counter Trend",
                 "mode" => "scope",
                 "scope_kind" => "ground_station",
                 "scope_id" => "ground-dss-14",
                 "precision" => "2",
                 "window_seconds" => "900"
               },
               "HK.counter",
               :add_widget
             )

    assert placement.scope_override == %{
             primary: %{kind: "ground_station", mode: "one", ids: ["ground-dss-14"]}
           }

    assert placement.widget_def.binding.scope_mode == :override
  end

  test "rejects pinned scope placements without an active dashboard context" do
    assert {:error, {:invalid_binding, "pinned scope requires an active dashboard context"}} =
             PlacementEditor.build_placement(
               %{
                 "type" => "time_series",
                 "title" => "Ground Counter Trend",
                 "mode" => "scope",
                 "precision" => "2",
                 "window_seconds" => "900"
               },
               "HK.counter",
               :add_widget
             )
  end

  test "builds status matrix placements with multiple observables" do
    assert {:ok, %Placement{} = placement} =
             PlacementEditor.build_placement(
               %{
                 "type" => "status_matrix",
                 "title" => "HK Matrix",
                 "mode" => "fixed",
                 "spacecraft_id" => "sc-alpha",
                 "precision" => "0",
                 "window_seconds" => "300"
               },
               ["HK.counter", "HK.voltage"],
               :add_widget
             )

    assert placement.layout == %{x: nil, y: nil, w: 4, h: 3}
    assert placement.widget_def.widget_type_id == "cadence.status_matrix"

    assert placement.widget_def.binding == %{
             source: :telemetry,
             observables: ["HK.counter", "HK.voltage"],
             scope_mode: :override,
             data_mode: :context,
             value_type: :engineering,
             sampling: :latest,
             overlays: [:limits, :quality]
           }

    assert placement.widget_def.options == %{precision: 0, window_seconds: 300}
  end

  test "builds data table placements with multiple observables" do
    assert {:ok, %Placement{} = placement} =
             PlacementEditor.build_placement(
               %{
                 "type" => "data_table",
                 "title" => "HK Table",
                 "mode" => "fixed",
                 "spacecraft_id" => "sc-alpha",
                 "precision" => "1",
                 "window_seconds" => "300"
               },
               ["HK.counter", "HK.voltage"],
               :add_widget
             )

    assert placement.layout == %{x: nil, y: nil, w: 6, h: 4}
    assert placement.widget_def.widget_type_id == "cadence.data_table"

    assert placement.widget_def.binding == %{
             source: :telemetry,
             observables: ["HK.counter", "HK.voltage"],
             scope_mode: :override,
             data_mode: :context,
             value_type: :engineering,
             sampling: :latest,
             overlays: [:limits, :quality]
           }

    assert placement.widget_def.options == %{precision: 1, window_seconds: 300}
  end

  test "render items preserve multi-observable placement bindings" do
    assert {:ok, %Placement{} = matrix} =
             PlacementEditor.build_placement(
               %{
                 "type" => "status_matrix",
                 "title" => "HK Matrix",
                 "mode" => "context",
                 "precision" => "0"
               },
               ["HK.counter", "HK.voltage"],
               :add_widget
             )

    assert {:ok, %Placement{} = table} =
             PlacementEditor.build_placement(
               %{
                 "type" => "data_table",
                 "title" => "HK Table",
                 "mode" => "context",
                 "precision" => "1"
               },
               ["HK.counter", "HK.voltage"],
               :add_widget
             )

    document =
      %Document{
        dashboard_id: "dashboard-1",
        organization_id: "org-1",
        mission_id: "mission-1",
        name: "Power",
        metadata: %{version: 1}
      }
      |> Document.put_placement(matrix)
      |> Document.put_placement(table)

    assert [
             %{widget: %{type: :status_matrix, binding: %{point_ids: matrix_points}}},
             %{widget: %{type: :data_table, binding: %{point_ids: table_points}}}
           ] = RenderItem.from_document(document)

    assert matrix_points == ["HK.counter", "HK.voltage"]
    assert table_points == ["HK.counter", "HK.voltage"]
  end

  test "builds event timeline placements without point bindings" do
    assert {:ok, %Placement{} = placement} =
             PlacementEditor.build_placement(
               %{
                 "type" => "event_timeline",
                 "title" => "Mission Events"
               },
               nil,
               :add_widget
             )

    assert placement.layout == %{x: nil, y: nil, w: 6, h: 4}
    assert placement.scope_override == nil
    assert placement.widget_def.widget_type_id == "cadence.event_timeline"

    assert placement.widget_def.binding == %{
             source: :events,
             observables: [],
             scope_mode: :context,
             data_mode: :context,
             value_type: nil,
             sampling: :event_history,
             overlays: []
           }

    assert placement.widget_def.options == %{}
  end

  test "builds state timeline placements from a selected telemetry point" do
    assert {:ok, %Placement{} = placement} =
             PlacementEditor.build_placement(
               %{
                 "type" => "state_timeline",
                 "title" => "Battery State",
                 "mode" => "fixed",
                 "spacecraft_id" => "sc-alpha",
                 "precision" => "0",
                 "window_seconds" => "300"
               },
               "HK.battery_voltage",
               :add_widget
             )

    assert placement.layout == %{x: nil, y: nil, w: 6, h: 3}

    assert placement.scope_override == %{
             primary: %{kind: "spacecraft", mode: "one", ids: ["sc-alpha"]}
           }

    assert placement.widget_def.widget_type_id == "cadence.state_timeline"

    assert placement.widget_def.binding == %{
             source: :limits,
             observables: ["HK.battery_voltage"],
             scope_mode: :override,
             data_mode: :context,
             value_type: :engineering,
             sampling: :event_history,
             overlays: [:quality]
           }

    assert placement.widget_def.options == %{precision: 0, window_seconds: 300}
  end

  test "builds state timeline placements from selected operational observables" do
    assert {:ok, %Placement{} = placement} =
             PlacementEditor.build_placement(
               %{
                 "type" => "state_timeline",
                 "title" => "Operations State",
                 "binding_source" => "operational_observables",
                 "mode" => "context"
               },
               ["contacts.phase", "comms.transport.connection_state"],
               :add_widget
             )

    assert placement.layout == %{x: nil, y: nil, w: 6, h: 3}
    assert placement.scope_override == nil
    assert placement.widget_def.widget_type_id == "cadence.state_timeline"

    assert placement.widget_def.binding == %{
             source: :operational_observables,
             observables: ["contacts.phase", "comms.transport.connection_state"],
             scope_mode: :context,
             data_mode: :context,
             value_type: :engineering,
             sampling: :event_history,
             overlays: []
           }
  end

  test "rejects metric operational observables for state timeline placements" do
    assert {:error, {:invalid_binding, "select operational observables supported by this widget"}} =
             PlacementEditor.build_placement(
               %{
                 "type" => "state_timeline",
                 "title" => "Bit Rate State",
                 "binding_source" => "operational_observables",
                 "mode" => "context"
               },
               "comms.transport.downlink_bitrate",
               :add_widget
             )
  end

  test "preserves placement identity and layout when editing" do
    existing = %Placement{
      placement_id: "placement-existing",
      layout: %{x: 2, y: 1, w: 6, h: 3},
      widget_def: %WidgetDef{
        widget_type_id: "cadence.value_tile",
        title: "Counter",
        binding: %{observables: ["HK.counter"]}
      }
    }

    assert {:ok, %Placement{} = placement} =
             PlacementEditor.build_placement(
               %{
                 "type" => "value_tile",
                 "title" => "Renamed Counter",
                 "mode" => "context",
                 "precision" => "3",
                 "window_seconds" => "300"
               },
               "HK.counter",
               {:edit_placement, "placement-existing"},
               existing
             )

    assert placement.placement_id == "placement-existing"
    assert placement.layout == %{x: 2, y: 1, w: 6, h: 3}
    assert placement.widget_def.title == "Renamed Counter"
  end

  test "prefills form params and selected point from an existing placement" do
    placement = %Placement{
      placement_id: "placement-fixed",
      scope_override: %{primary: %{kind: "spacecraft", mode: "one", ids: ["sc-alpha"]}},
      widget_def: %WidgetDef{
        widget_type_id: "cadence.time_series",
        title: "Counter Trend",
        binding: %{observables: ["HK.counter"], scope_mode: :override},
        options: %{precision: 4, window_seconds: 900}
      }
    }

    assert PlacementEditor.to_form_params(placement) == %{
             "type" => "time_series",
             "title" => "Counter Trend",
             "mode" => "fixed",
             "spacecraft_id" => "sc-alpha",
             "scope_kind" => "spacecraft",
             "scope_id" => "sc-alpha",
             "binding_source" => "telemetry",
             "precision" => "4",
             "window_seconds" => "900",
             "point_q" => ""
           }

    assert PlacementEditor.selected_observable(placement) == "HK.counter"
    assert PlacementEditor.selected_observables(placement) == ["HK.counter"]
  end

  test "prefills non-spacecraft scope overrides as pinned dashboard scope" do
    placement = %Placement{
      placement_id: "placement-ground",
      scope_override: %{primary: %{kind: "ground_station", mode: "one", ids: ["ground-dss-14"]}},
      widget_def: %WidgetDef{
        widget_type_id: "cadence.state_timeline",
        title: "Ground State",
        binding: %{
          source: :operational_observables,
          observables: ["ground.station.connection_state"],
          scope_mode: :override
        },
        options: %{precision: 2, window_seconds: 300}
      }
    }

    assert PlacementEditor.to_form_params(placement) == %{
             "type" => "state_timeline",
             "title" => "Ground State",
             "mode" => "scope",
             "spacecraft_id" => "",
             "scope_kind" => "ground_station",
             "scope_id" => "ground-dss-14",
             "binding_source" => "operational_observables",
             "precision" => "2",
             "window_seconds" => "300",
             "point_q" => ""
           }
  end

  test "rejects point widgets without a selected observable" do
    assert {:error, {:invalid_binding, "a telemetry point is required"}} =
             PlacementEditor.build_placement(
               %{"type" => "value_tile", "title" => "Counter", "mode" => "context"},
               nil,
               :add_widget
             )
  end

  test "rejects status matrix widgets outside the observable count range" do
    assert {:error, {:invalid_binding, "select 1 to 24 telemetry points"}} =
             PlacementEditor.build_placement(
               %{"type" => "status_matrix", "title" => "Matrix", "mode" => "context"},
               [],
               :add_widget
             )
  end

  test "builds operational observable status matrix placements" do
    assert {:ok, %Placement{} = placement} =
             PlacementEditor.build_placement(
               %{
                 "type" => "status_matrix",
                 "title" => "Contact Phase",
                 "binding_source" => "operational_observables",
                 "mode" => "context",
                 "precision" => "0",
                 "window_seconds" => "300"
               },
               ["contacts.phase"],
               :add_widget
             )

    assert placement.scope_override == nil

    assert placement.widget_def.binding == %{
             source: :operational_observables,
             observables: ["contacts.phase"],
             scope_mode: :context,
             data_mode: :context,
             value_type: :engineering,
             sampling: :latest,
             overlays: []
           }
  end

  test "builds operational observable data table placements" do
    assert {:ok, %Placement{} = placement} =
             PlacementEditor.build_placement(
               %{
                 "type" => "data_table",
                 "title" => "Ops Table",
                 "binding_source" => "operational_observables",
                 "mode" => "context",
                 "precision" => "0",
                 "window_seconds" => "300"
               },
               ["contacts.phase", "comms.transport.connection_state"],
               :add_widget
             )

    assert placement.scope_override == nil
    assert placement.widget_def.widget_type_id == "cadence.data_table"

    assert placement.widget_def.binding == %{
             source: :operational_observables,
             observables: ["contacts.phase", "comms.transport.connection_state"],
             scope_mode: :context,
             data_mode: :context,
             value_type: :engineering,
             sampling: :latest,
             overlays: []
           }
  end

  test "builds pinned-scope operational observable placements" do
    assert {:ok, %Placement{} = placement} =
             PlacementEditor.build_placement(
               %{
                 "type" => "state_timeline",
                 "title" => "Ground State",
                 "binding_source" => "operational_observables",
                 "mode" => "scope",
                 "scope_kind" => "ground_station",
                 "scope_id" => "ground-dss-14"
               },
               ["ground.station.connection_state"],
               :add_widget,
               nil,
               authoring_scope_context: %{
                 primary: %{kind: "ground_station", mode: "one", ids: ["ground-dss-14"]}
               }
             )

    assert placement.scope_override == %{
             primary: %{kind: "ground_station", mode: "one", ids: ["ground-dss-14"]}
           }

    assert placement.widget_def.binding.source == :operational_observables
    assert placement.widget_def.binding.scope_mode == :override
  end

  test "builds operational metric value tile placements" do
    assert {:ok, %Placement{} = placement} =
             PlacementEditor.build_placement(
               %{
                 "type" => "value_tile",
                 "title" => "Downlink Bitrate",
                 "binding_source" => "operational_observables",
                 "mode" => "context",
                 "precision" => "1",
                 "window_seconds" => "300"
               },
               ["comms.transport.downlink_bitrate"],
               :add_widget
             )

    assert placement.scope_override == nil
    assert placement.widget_def.widget_type_id == "cadence.value_tile"

    assert placement.widget_def.binding == %{
             source: :operational_observables,
             observables: ["comms.transport.downlink_bitrate"],
             scope_mode: :context,
             data_mode: :context,
             value_type: :engineering,
             sampling: :latest,
             overlays: []
           }

    assert placement.widget_def.options == %{
             precision: 1,
             window_seconds: 300,
             show_unit: true
           }
  end

  test "builds command queue depth value tile placements" do
    assert {:ok, %Placement{} = placement} =
             PlacementEditor.build_placement(
               %{
                 "type" => "value_tile",
                 "title" => "Command Queue",
                 "binding_source" => "operational_observables",
                 "mode" => "context"
               },
               ["commanding.queue_depth"],
               :add_widget
             )

    assert placement.widget_def.widget_type_id == "cadence.value_tile"

    assert placement.widget_def.binding == %{
             source: :operational_observables,
             observables: ["commanding.queue_depth"],
             scope_mode: :context,
             data_mode: :context,
             value_type: :engineering,
             sampling: :latest,
             overlays: []
           }
  end

  test "rejects operational observables outside the authoring scope context" do
    assert {:error, {:invalid_binding, message}} =
             PlacementEditor.build_placement(
               %{
                 "type" => "value_tile",
                 "title" => "Command Queue",
                 "binding_source" => "operational_observables",
                 "mode" => "context"
               },
               ["commanding.queue_depth"],
               :add_widget,
               nil,
               authoring_scope_context: %{
                 primary: %{kind: "transport", mode: "one", ids: ["transport-1"]}
               }
             )

    assert message =~ "selected context does not support operational observables"
    assert message =~ "commanding.queue_depth"
  end

  test "allows operational observables inside the authoring scope context" do
    assert {:ok, %Placement{} = placement} =
             PlacementEditor.build_placement(
               %{
                 "type" => "value_tile",
                 "title" => "Command Queue",
                 "binding_source" => "operational_observables",
                 "mode" => "context"
               },
               ["commanding.queue_depth"],
               :add_widget,
               nil,
               authoring_scope_context: %{
                 primary: %{kind: "mission", mode: "one", ids: ["mission-1"]}
               }
             )

    assert placement.widget_def.binding.observables == ["commanding.queue_depth"]
  end

  test "rejects operational state selections outside the authoring scope context" do
    assert {:error, {:invalid_binding, message}} =
             PlacementEditor.build_placement(
               %{
                 "type" => "state_timeline",
                 "title" => "Ground State",
                 "binding_source" => "operational_observables",
                 "mode" => "context"
               },
               ["ground.station.connection_state"],
               :add_widget,
               nil,
               authoring_scope_context: %{
                 primary: %{kind: "spacecraft", mode: "one", ids: ["sc-1"]}
               }
             )

    assert message =~ "ground.station.connection_state"
  end

  test "builds ingress latency value tile placements" do
    assert {:ok, %Placement{} = placement} =
             PlacementEditor.build_placement(
               %{
                 "type" => "value_tile",
                 "title" => "Ingress Latency",
                 "binding_source" => "operational_observables",
                 "mode" => "context"
               },
               ["ingress.processing_latency_ms"],
               :add_widget
             )

    assert placement.widget_def.widget_type_id == "cadence.value_tile"

    assert placement.widget_def.binding == %{
             source: :operational_observables,
             observables: ["ingress.processing_latency_ms"],
             scope_mode: :context,
             data_mode: :context,
             value_type: :engineering,
             sampling: :latest,
             overlays: []
           }
  end

  test "rejects operational observable value tile selections outside the widget frame contract" do
    assert {:error,
            {:invalid_binding, "select an operational observable supported by this widget"}} =
             PlacementEditor.build_placement(
               %{
                 "type" => "value_tile",
                 "title" => "Connection State",
                 "binding_source" => "operational_observables",
                 "mode" => "context"
               },
               ["comms.transport.connection_state"],
               :add_widget
             )
  end

  test "rejects unbacked operational observable value tile placements" do
    assert {:error, {:invalid_binding, "select one backed operational metric observable"}} =
             PlacementEditor.build_placement(
               %{
                 "type" => "value_tile",
                 "title" => "Ingress Latency",
                 "binding_source" => "operational_observables",
                 "mode" => "context"
               },
               ["mission.power_margin"],
               :add_widget
             )
  end

  test "rejects unbacked operational observable status matrix placements" do
    assert {:error, {:invalid_binding, "select backed operational observables"}} =
             PlacementEditor.build_placement(
               %{
                 "type" => "status_matrix",
                 "title" => "Ingress Latency",
                 "binding_source" => "operational_observables",
                 "mode" => "context"
               },
               ["mission.power_margin"],
               :add_widget
             )
  end

  test "builds operational metric time series placements" do
    assert {:ok, %Placement{} = placement} =
             PlacementEditor.build_placement(
               %{
                 "type" => "time_series",
                 "title" => "RF SNR Trend",
                 "binding_source" => "operational_observables",
                 "mode" => "context"
               },
               ["link.snr_db"],
               :add_widget
             )

    assert placement.widget_def.widget_type_id == "cadence.time_series"
    assert placement.widget_def.binding.source == :operational_observables
    assert placement.widget_def.binding.observables == ["link.snr_db"]
    assert placement.widget_def.binding.sampling == :raw_series
    assert placement.widget_def.binding.overlays == [:events, :quality]
  end

  test "rejects nonmetric operational observables for time series placements" do
    assert {:error,
            {:invalid_binding, "select operational metric observables supported by this widget"}} =
             PlacementEditor.build_placement(
               %{
                 "type" => "time_series",
                 "title" => "Contact Phase",
                 "binding_source" => "operational_observables",
                 "mode" => "context"
               },
               ["contacts.phase"],
               :add_widget
             )
  end
end
