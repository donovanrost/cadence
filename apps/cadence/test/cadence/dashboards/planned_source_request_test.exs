defmodule Cadence.Dashboards.PlannedSourceRequestTest do
  use Cadence.UnitCase, async: true

  alias Cadence.Dashboards.{Frame, PlannedSourceRequest, WidgetDef}
  alias Cadence.DataSources.{AdapterRegistry, SourceCapabilities}

  test "derives logical sources and normalization from the adapter registry" do
    default_policy = AdapterRegistry.default_policy()
    events = Map.fetch!(default_policy.by_logical_source, :events)
    synthetic_events = %{events | logical_source: :synthetic_events}

    adapter_policy = %{
      definitions: [synthetic_events | default_policy.definitions],
      by_logical_source:
        Map.put(default_policy.by_logical_source, :synthetic_events, synthetic_events)
    }

    opts = [data_source_adapter_policy: adapter_policy]

    assert :synthetic_events in PlannedSourceRequest.logical_sources(opts)
    assert PlannedSourceRequest.logical_source?(:synthetic_events, opts)

    assert %PlannedSourceRequest{logical_source: :synthetic_events} =
             PlannedSourceRequest.new(%{logical_source: "synthetic_events"}, opts)

    assert %PlannedSourceRequest{
             source_dependencies: [%{logical_source: :synthetic_events}]
           } =
             PlannedSourceRequest.new(
               %{source_dependencies: [%{"logical_source" => "synthetic_events"}]},
               opts
             )

    assert %Frame{source: :synthetic_events} =
             Frame.normalize(%{source: "synthetic_events", shape: "events"}, opts)

    assert %WidgetDef{binding: %{source: :synthetic_events}} =
             WidgetDef.from_map(
               %{
                 widget_type_id: "widget_time_series",
                 binding: %{source: "synthetic_events"}
               },
               opts
             )

    assert %SourceCapabilities{logical_source: :synthetic_events} =
             SourceCapabilities.normalize(%{logical_source: "synthetic_events"}, opts)
  end

  test "normalizes annotation-layer composition on placement consumers" do
    assert %PlannedSourceRequest{
             consumers: [
               %{
                 placement_id: "placement-1",
                 role: :events,
                 widget_type_id: "cadence.time_series",
                 annotation_layer_ids: ["mission-contacts", "source-status"]
               }
             ]
           } =
             PlannedSourceRequest.new(%{
               consumers: [
                 %{
                   "placement_id" => "placement-1",
                   "role" => "events",
                   "widget_type_id" => "cadence.time_series",
                   "annotation_layer_ids" => ["mission-contacts", "source-status"]
                 }
               ]
             })
  end
end
