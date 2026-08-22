defmodule CadenceWeb.OpsDashboardShowLive.GoldenContractTimeSeriesPlanningTest do
  use ExUnit.Case, async: true

  alias Cadence.Dashboards

  alias Cadence.Dashboards.{DashboardResolveRequest, Document, Engine}

  alias Cadence.Management.DataSources

  @fixture_dir Path.expand("../../../../../cadence/test/fixtures/dashboards", __DIR__)

  test "golden time-series fixture plans telemetry, limits, and event overlay requests" do
    document = load_fixture!("time_series_with_limits.v1.json")

    assert %Dashboards.ValidationResult{valid?: true, errors: []} =
             Dashboards.validate_document(document)

    request =
      resolve_request(document, %{
        "placement_power_trend" => %{width_px: 640, height_px: 256}
      })

    plan =
      Engine.plan(request, time_series_source_registry_opts(validate_dashboard_contract?: true))

    assert plan.dashboard_warnings == []
    assert plan.plan_metadata.source_request_count == 4

    assert plan.planned_source_requests
           |> Enum.map(&request_summary/1)
           |> Enum.sort_by(&request_sort_key/1) == [
             %{
               logical_source: :telemetry,
               observables: ["tlm.hk.battery_voltage", "tlm.hk.bus_current"],
               sampling_mode: :decimated_envelope,
               products: [],
               overlays: [:quality],
               target_points: 640,
               time_axis: "generation_time",
               data_source_id: "native-decimating-questdb",
               source_binding_id: "default_flight_telemetry"
             },
             %{
               logical_source: :limits,
               observables: ["tlm.hk.battery_voltage", "tlm.hk.bus_current"],
               sampling_mode: :definition_intervals,
               products: [:definition_intervals],
               overlays: [],
               target_points: nil,
               time_axis: :receipt_time,
               data_source_id: "managed_limits_projection",
               source_binding_id: "default_flight_limits"
             },
             %{
               logical_source: :limits,
               observables: ["tlm.hk.battery_voltage", "tlm.hk.bus_current"],
               sampling_mode: :analysis_buckets,
               products: [:analysis_buckets],
               overlays: [],
               target_points: nil,
               time_axis: :receipt_time,
               data_source_id: "managed_limits_projection",
               source_binding_id: "default_flight_limits"
             },
             %{
               logical_source: :events,
               observables: ["tlm.hk.battery_voltage", "tlm.hk.bus_current"],
               sampling_mode: :event_history,
               products: [
                 :contact_intervals,
                 :mission_timeline,
                 :source_health_transitions,
                 :source_watermark_events,
                 :source_capability_postures,
                 :telemetry_backfill_lifecycle,
                 :telemetry_revision_decisions
               ],
               overlays: [],
               target_points: nil,
               time_axis: :occurred_at,
               data_source_id: "managed_events_projection",
               source_binding_id: "default_flight_events"
             }
           ]
  end

  defp load_fixture!(name) do
    @fixture_dir
    |> Path.join(name)
    |> File.read!()
    |> Jason.decode!()
    |> Document.from_map()
  end

  defp resolve_request(%Document{} = document, placement_sizes) do
    %DashboardResolveRequest{
      organization_id: document.organization_id,
      mission_id: document.mission_id,
      dashboard_id: document.dashboard_id,
      document: document,
      scope_context: %{primary: %{kind: "spacecraft", mode: "one", ids: ["sc_001"]}},
      interaction_context: %{placement_sizes: placement_sizes}
    }
  end

  defp time_series_source_registry_opts(opts) do
    native_telemetry_source = %{
      DataSources.default_managed_data_source()
      | data_source_id: "native-decimating-questdb",
        capabilities:
          DataSources.default_managed_data_source().capabilities
          |> Map.put(:native_decimation?, true)
    }

    telemetry_binding = %{
      DataSources.default_flight_telemetry_binding()
      | data_source_id: "native-decimating-questdb"
    }

    Keyword.merge(
      [
        data_sources: [
          native_telemetry_source,
          DataSources.default_limits_data_source(),
          DataSources.default_events_data_source()
        ],
        data_bindings: [
          telemetry_binding,
          DataSources.default_flight_limits_binding(),
          DataSources.default_flight_events_binding()
        ]
      ],
      opts
    )
  end

  defp request_summary(request) do
    %{
      logical_source: request.logical_source,
      observables: request.observables,
      sampling_mode: request.sampling.mode,
      products: Map.get(request.sampling, :products, []),
      overlays: request.overlays,
      target_points: Map.get(request.sampling, :target_points),
      time_axis: request.time_context.axis,
      data_source_id: request.metadata.capability_provenance.data_source_id,
      source_binding_id: request.metadata.capability_provenance.binding_id
    }
  end

  defp request_sort_key(%{
         logical_source: source,
         sampling_mode: sampling_mode,
         products: products
       }) do
    {source_sort_key(source), sampling_sort_key(sampling_mode), Enum.map(products, &to_string/1)}
  end

  defp source_sort_key(:telemetry), do: 0
  defp source_sort_key(:limits), do: 1
  defp source_sort_key(:events), do: 2
  defp source_sort_key(source), do: to_string(source)

  defp sampling_sort_key(:latest), do: 0
  defp sampling_sort_key(:decimated_envelope), do: 1
  defp sampling_sort_key(:latest_state), do: 2
  defp sampling_sort_key(:event_history), do: 3
  defp sampling_sort_key(:definition_intervals), do: 4
  defp sampling_sort_key(sampling_mode), do: to_string(sampling_mode)
end
