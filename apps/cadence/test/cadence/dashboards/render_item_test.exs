defmodule Cadence.Dashboards.RenderItemTest do
  use Cadence.UnitCase, async: true

  alias Cadence.Dashboards.{Document, Placement, RenderItem, RenderWidget, WidgetDef}

  test "builds render items from canonical placements" do
    placement = %Placement{
      placement_id: "placement-render",
      layout: %{x: 1, y: 2, w: 4, h: 2},
      widget_def: %WidgetDef{
        widget_type_id: "cadence.value_tile",
        widget_type_version: 1,
        title: "Counter",
        binding: %{
          observables: ["HK.counter"],
          scope_mode: :context,
          data_mode: :context,
          value_type: :engineering,
          sampling: :latest,
          overlays: [:limits, :quality]
        },
        options: %{precision: 3, window_seconds: 300}
      }
    }

    assert [
             %RenderItem{
               placement: ^placement,
               placement_id: "placement-render",
               layout: %{x: 1, y: 2, w: 4, h: 2},
               widget: %RenderWidget{
                 widget_id: "placement-render",
                 widget_type_id: "cadence.value_tile",
                 widget_type_version: 1,
                 type: :value_tile,
                 title: "Counter",
                 binding: %{
                   source: :telemetry,
                   mode: :context,
                   spacecraft_id: nil,
                   point_id: "HK.counter",
                   point_ids: ["HK.counter"]
                 },
                 options: %{precision: 3, window_seconds: 300}
               }
             }
           ] = RenderItem.from_document(%Document{placements: [placement]})
  end

  test "builds fixed-scope widget presenters from placement scope overrides" do
    placement = %Placement{
      placement_id: "placement-fixed",
      layout: %{x: 0, y: 0, w: 6, h: 3},
      scope_override: %{primary: %{kind: "spacecraft", mode: "one", ids: ["sc-alpha"]}},
      widget_def: %WidgetDef{
        widget_type_id: "cadence.time_series",
        title: "Trend",
        binding: %{observables: ["HK.counter"], scope_mode: :override},
        options: %{precision: 2, window_seconds: 900}
      }
    }

    assert [
             %RenderItem{
               widget: %RenderWidget{
                 type: :time_series,
                 binding: %{
                   source: :telemetry,
                   mode: :fixed,
                   spacecraft_id: "sc-alpha",
                   point_id: "HK.counter",
                   point_ids: ["HK.counter"]
                 },
                 options: %{precision: 2, window_seconds: 900}
               }
             }
           ] = RenderItem.from_document(%Document{placements: [placement]})
  end

  test "keeps all status matrix observable ids on the presenter" do
    placement = %Placement{
      placement_id: "placement-matrix",
      layout: %{x: 0, y: 0, w: 4, h: 3},
      widget_def: %WidgetDef{
        widget_type_id: "cadence.status_matrix",
        title: "Matrix",
        binding: %{observables: ["HK.counter", "HK.voltage"], scope_mode: :context},
        options: %{precision: 1, window_seconds: 300}
      }
    }

    assert [
             %RenderItem{
               widget: %RenderWidget{
                 type: :status_matrix,
                 binding: %{
                   source: :telemetry,
                   mode: :context,
                   spacecraft_id: nil,
                   point_id: "HK.counter",
                   point_ids: ["HK.counter", "HK.voltage"]
                 }
               }
             }
           ] = RenderItem.from_document(%Document{placements: [placement]})
  end

  test "expands repeated scope placements into concrete render items" do
    placement = %Placement{
      placement_id: "placement-repeat",
      layout: %{x: 0, y: 2, w: 4, h: 3},
      repeat: %{axis: :scope, over: :spacecraft, layout: :wrap_grid, max_instances: 12},
      widget_def: %WidgetDef{
        widget_type_id: "cadence.status_matrix",
        title: "Spacecraft Status",
        binding: %{observables: ["HK.counter"], scope_mode: :repeat}
      }
    }

    document = %Document{
      grid: %{columns: 12, row_height_px: 64, gap_px: 8},
      defaults: %{
        "scope" => %{
          "primary" => %{
            "kind" => "spacecraft",
            "mode" => "many",
            "ids" => ["sc-001", "sc-002", "sc-003"]
          }
        }
      },
      placements: [placement]
    }

    assert [
             %RenderItem{
               placement_id: "placement-repeat__repeat__spacecraft__sc-001",
               layout: %{x: 0, y: 2, w: 4, h: 3},
               widget: %RenderWidget{
                 widget_id: "placement-repeat__repeat__spacecraft__sc-001",
                 binding: %{mode: :fixed, spacecraft_id: "sc-001", point_ids: ["HK.counter"]}
               }
             },
             %RenderItem{
               placement_id: "placement-repeat__repeat__spacecraft__sc-002",
               layout: %{x: 4, y: 2, w: 4, h: 3},
               placement: %Placement{
                 scope_override: %{
                   primary: %{kind: "spacecraft", mode: "one", ids: ["sc-002"]}
                 }
               }
             },
             %RenderItem{
               placement_id: "placement-repeat__repeat__spacecraft__sc-003",
               layout: %{x: 8, y: 2, w: 4, h: 3}
             }
           ] = RenderItem.from_document(document)
  end

  test "keeps all data table observable ids on the presenter" do
    placement = %Placement{
      placement_id: "placement-table",
      layout: %{x: 0, y: 0, w: 6, h: 4},
      widget_def: %WidgetDef{
        widget_type_id: "cadence.data_table",
        title: "Table",
        binding: %{observables: ["HK.counter", "HK.voltage"], scope_mode: :context},
        options: %{precision: 1, window_seconds: 300}
      }
    }

    assert [
             %RenderItem{
               widget: %RenderWidget{
                 type: :data_table,
                 binding: %{
                   source: :telemetry,
                   mode: :context,
                   spacecraft_id: nil,
                   point_id: "HK.counter",
                   point_ids: ["HK.counter", "HK.voltage"]
                 }
               }
             }
           ] = RenderItem.from_document(%Document{placements: [placement]})
  end

  test "builds event timeline presenters without point bindings" do
    placement = %Placement{
      placement_id: "placement-events",
      layout: %{x: 0, y: 0, w: 6, h: 4},
      widget_def: %WidgetDef{
        widget_type_id: "cadence.event_timeline",
        title: "Events",
        binding: %{source: :events, observables: [], scope_mode: :context},
        options: %{}
      }
    }

    assert [
             %RenderItem{
               widget: %RenderWidget{
                 type: :event_timeline,
                 binding: %{
                   source: :events,
                   mode: :context,
                   spacecraft_id: nil,
                   point_id: nil,
                   point_ids: []
                 },
                 options: %{precision: 2, window_seconds: 300}
               }
             }
           ] = RenderItem.from_document(%Document{placements: [placement]})
  end

  test "builds state timeline presenters with limits source bindings" do
    placement = %Placement{
      placement_id: "placement-state",
      layout: %{x: 0, y: 0, w: 6, h: 3},
      widget_def: %WidgetDef{
        widget_type_id: "cadence.state_timeline",
        title: "Battery State",
        binding: %{
          source: :limits,
          observables: ["HK.battery_voltage"],
          scope_mode: :context,
          sampling: :event_history
        },
        options: %{precision: 0, window_seconds: 300}
      }
    }

    assert [
             %RenderItem{
               widget: %RenderWidget{
                 type: :state_timeline,
                 binding: %{
                   source: :limits,
                   mode: :context,
                   spacecraft_id: nil,
                   point_id: "HK.battery_voltage",
                   point_ids: ["HK.battery_voltage"]
                 }
               }
             }
           ] = RenderItem.from_document(%Document{placements: [placement]})
  end

  test "omits unknown widget types from the active render presenter" do
    placement = %Placement{
      placement_id: "placement-unknown",
      widget_def: %WidgetDef{widget_type_id: "partner.unknown", title: "Unknown"}
    }

    assert [] = RenderItem.from_document(%Document{placements: [placement]})
  end
end
