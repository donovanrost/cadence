defmodule Cadence.Dashboards.PlannedSourceRequestTest do
  use Cadence.UnitCase, async: false

  alias Cadence.Dashboards.{Frame, PlannedSourceRequest, WidgetDef}
  alias Cadence.DataSources.SourceCapabilities

  test "derives logical sources and normalization from the adapter registry" do
    original_adapters = Application.fetch_env!(:cadence, :data_source_adapters)
    synthetic_adapter = Keyword.fetch!(original_adapters, :events)

    on_exit(fn ->
      Application.put_env(:cadence, :data_source_adapters, original_adapters)
    end)

    Application.put_env(
      :cadence,
      :data_source_adapters,
      Keyword.put(original_adapters, :synthetic_events, synthetic_adapter)
    )

    assert :synthetic_events in PlannedSourceRequest.logical_sources()
    assert PlannedSourceRequest.logical_source?(:synthetic_events)

    assert %PlannedSourceRequest{logical_source: :synthetic_events} =
             PlannedSourceRequest.new(%{logical_source: "synthetic_events"})

    assert %PlannedSourceRequest{
             source_dependencies: [%{logical_source: :synthetic_events}]
           } =
             PlannedSourceRequest.new(%{
               source_dependencies: [%{"logical_source" => "synthetic_events"}]
             })

    assert %Frame{source: :synthetic_events} =
             Frame.normalize(%{source: "synthetic_events", shape: "events"})

    assert %WidgetDef{binding: %{source: :synthetic_events}} =
             WidgetDef.from_map(%{
               widget_type_id: "widget_time_series",
               binding: %{source: "synthetic_events"}
             })

    assert %SourceCapabilities{logical_source: :synthetic_events} =
             SourceCapabilities.normalize(%{logical_source: "synthetic_events"})
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
