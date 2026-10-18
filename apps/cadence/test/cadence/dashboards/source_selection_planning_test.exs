defmodule Cadence.Dashboards.SourceSelectionPlanningTest do
  use Cadence.UnitCase, async: true
  import Cadence.Dashboards.EngineFixtures
  alias Cadence.Dashboards.{DashboardResolveRequest, DataContext, Engine}
  alias Cadence.Reads.DataSources

  test "primary requests retain explicit source identity without imposing it on overlays" do
    binding = DataSources.default_flight_telemetry_binding()

    result =
      Engine.plan(
        request(%{
          source_mode: :specific,
          source_binding_id: binding.binding_id,
          data_source_id: binding.data_source_id,
          dataset: binding.dataset
        })
      )

    telemetry = Enum.find(result.planned_source_requests, &(&1.logical_source == :telemetry))
    limits = Enum.find(result.planned_source_requests, &(&1.logical_source == :limits))
    assert telemetry && limits
    assert telemetry.data_context.source_binding_id == binding.binding_id
    assert telemetry.data_context.data_source_id == binding.data_source_id
    assert telemetry.data_context.dataset == binding.dataset
    assert limits.data_context.source_binding_id == nil
    assert limits.data_context.data_source_id == nil
    assert limits.data_context.dataset == nil
  end

  test "explicit per-source overlay selection survives removal of primary selectors" do
    telemetry = DataSources.default_flight_telemetry_binding()
    limits = DataSources.default_flight_limits_binding()

    result =
      Engine.plan(
        request(%{
          source_binding_id: telemetry.binding_id,
          source_contexts: %{limits: %{source_binding_id: limits.binding_id}}
        })
      )

    planned = Enum.find(result.planned_source_requests, &(&1.logical_source == :limits))
    assert planned

    assert DataContext.source_value(planned.data_context, :limits, :source_binding_id) ==
             limits.binding_id
  end

  test "unknown primary selectors produce a warning and no default telemetry request" do
    for selection <- [
          %{source_binding_id: "missing-binding"},
          %{data_source_id: "missing-source"},
          %{dataset: "missing-dataset"}
        ] do
      result = Engine.plan(request(selection))
      refute Enum.any?(result.planned_source_requests, &(&1.logical_source == :telemetry))
      assert result.frames_by_placement["placement_battery_voltage"].warnings != []
    end
  end

  defp request(data) do
    document = load_fixture!("value_tile_latest.v1.json")

    DashboardResolveRequest.new(%{
      organization_id: document.organization_id,
      mission_id: document.mission_id,
      dashboard_id: document.dashboard_id,
      document: document,
      data_context: data
    })
  end
end
