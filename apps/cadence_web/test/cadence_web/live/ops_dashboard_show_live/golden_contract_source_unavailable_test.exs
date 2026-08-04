defmodule CadenceWeb.OpsDashboardShowLive.GoldenContractSourceUnavailableTest do
  use ExUnit.Case, async: true

  alias Cadence.Dashboards

  alias Cadence.Dashboards.{
    DashboardResolveRequest,
    Document,
    Engine,
    PlacementFrames,
    RenderItem,
    ResolveWarning,
    SourceCircuitBreaker,
    SourceExecutionSemantics
  }

  alias Cadence.DataSources.{DataBinding, DataSource}

  alias CadenceWeb.OpsDashboardShowLive.WidgetPresentation

  @fixture_dir Path.expand("../../../../../cadence/test/fixtures/dashboards", __DIR__)
  @optional_link_context_paths [
    logical_source: [:logical_source],
    observable_id: [:observable_id],
    scope_kind: [:scope, :primary, :kind],
    time_mode: [:time, :mode],
    time_axis: [:time, :axis],
    realm: [:data, :realm],
    data_source_id: [:data, :data_source_id],
    source_binding_id: [:data, :source_binding_id]
  ]

  test "golden source unavailable fixture carries degraded source contract into presenter lifecycle" do
    document = load_fixture!("source_unavailable_value_tile.v1.json")
    breaker = start_supervised!({SourceCircuitBreaker, name: nil})

    assert %Dashboards.ValidationResult{valid?: true, errors: []} =
             Dashboards.validate_document(document)

    request =
      resolve_request(document, %{
        "placement_battery_voltage_unavailable" => %{width_px: 320, height_px: 128}
      })

    plan = Engine.plan(request, failing_telemetry_source_registry_opts())

    assert plan.dashboard_warnings == []
    assert plan.plan_metadata.source_request_count == 1

    assert [
             %{
               logical_source: :telemetry,
               observables: ["tlm.hk.battery_voltage"],
               sampling_mode: :latest,
               products: [],
               overlays: [],
               target_points: 320,
               time_axis: "generation_time",
               data_source_id: "flight-questdb",
               source_binding_id: "flight-telemetry"
             }
           ] = Enum.map(plan.planned_source_requests, &request_summary/1)

    result =
      Engine.resolve(
        request,
        failing_telemetry_source_registry_opts(
          source_circuit_breaker: breaker,
          source_circuit_failure_threshold: 2,
          source_opts: %{telemetry: [test_pid: self(), mode: :raise]},
          validate_dashboard_contract?: true
        )
      )

    assert_received {:dashboard_source_test_adapter_resolve, "flight-questdb"}
    assert_received {:dashboard_source_test_adapter_request, "flight-questdb", :latest}

    assert result.plan_metadata.degraded?
    assert result.plan_metadata.executed_source_request_count == 1
    assert result.plan_metadata.returned_frame_count == 0

    assert %{status_counts: %{source_unavailable: 1}, outcomes: [outcome], degraded?: true} =
             SourceExecutionSemantics.summarize(result)

    assert outcome.actionable?
    assert outcome.retryable?
    assert outcome.operator_action == :inspect_source_health
    assert outcome.runtime_action == :wait_for_source_health
    assert outcome.warning_codes == [:source_unavailable]

    assert [%ResolveWarning{code: :source_unavailable, severity: :error} = warning] =
             result.dashboard_warnings

    assert warning.details.reason == "test source failure"
    assert warning.details.logical_source == :telemetry
    assert warning.details.data_source_id == "flight-questdb"
    assert warning.details.source_binding_id == "flight-telemetry"
    assert Enum.map(warning.details.actions, & &1.target) == [:source_health, :source_inventory]
    assert link_targets(warning) == [:telemetry_point]

    assert_link_runtime_context(link_by_target(warning, :telemetry_point),
      logical_source: "telemetry",
      observable_id: "tlm.hk.battery_voltage",
      scope_kind: "spacecraft",
      scope_id: "sc_001",
      time_mode: "live",
      time_axis: "generation_time",
      realm: "flight",
      data_source_id: "flight-questdb",
      source_binding_id: "flight-telemetry"
    )

    assert %{
             "placement_battery_voltage_unavailable" =>
               %PlacementFrames{
                 primary: [],
                 overlays: %{},
                 warnings: [
                   %ResolveWarning{
                     code: :source_unavailable,
                     severity: :error,
                     scope: :placement,
                     placement_id: "placement_battery_voltage_unavailable"
                   }
                 ]
               } = placement_frames
           } = result.frames_by_placement

    [render_item] = RenderItem.from_document(document)
    data = WidgetPresentation.data(nil, placement_frames, render_item.widget)

    assert data.unresolved? == false
    assert data.engine_backed?
    assert data.lifecycle_state == :error
    assert data.lifecycle.warning_codes == [:source_unavailable]

    assert %{
             state: :unavailable,
             severity: :error,
             data_state: :no_data,
             warning_codes: [:source_unavailable],
             logical_sources: [:telemetry],
             data_source_ids: ["flight-questdb"],
             source_binding_ids: ["flight-telemetry"],
             realms: [:flight],
             time_modes: ["live"],
             time_axes: ["generation_time"]
           } = data.source_status
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

  defp failing_telemetry_source_registry_opts(opts \\ []) do
    Keyword.merge(
      [
        source_result_cache?: false,
        data_sources: [test_adapter_data_source("flight-questdb")],
        data_bindings: [test_telemetry_binding("flight-questdb")]
      ],
      opts
    )
  end

  defp test_adapter_data_source(data_source_id) do
    %DataSource{
      data_source_id: data_source_id,
      adapter: Cadence.Support.DashboardSourceTestAdapter,
      capabilities: %{latest?: true, range_scan?: true}
    }
  end

  defp test_telemetry_binding(data_source_id) do
    %DataBinding{
      binding_id: "flight-telemetry",
      organization_id: "org_dashboards",
      mission_id: "mission_dashboards",
      realm: :flight,
      logical_source: :telemetry,
      data_source_id: data_source_id,
      dataset: "flight"
    }
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

  defp link_targets(%ResolveWarning{links: links}) do
    Enum.map(links, & &1.target)
  end

  defp link_by_target(%ResolveWarning{links: links}, target) do
    Enum.find(links, &(&1.target == target))
  end

  defp assert_link_runtime_context(link, opts) do
    refute is_nil(link)

    assert_context_texts(link, [
      {[:organization_id], "org_dashboards"},
      {[:mission_id], "mission_dashboards"}
    ])

    assert_context_texts(link, optional_context_texts(opts))

    assert context_value(link.context, [:scope, :primary, :ids]) == [
             Keyword.fetch!(opts, :scope_id)
           ]
  end

  defp optional_context_texts(opts) do
    for {key, path} <- @optional_link_context_paths,
        expected = Keyword.get(opts, key),
        not is_nil(expected),
        do: {path, expected}
  end

  defp assert_context_texts(link, expected_values) do
    Enum.each(expected_values, fn {path, expected} ->
      assert context_text(context_value(link.context, path)) == expected
    end)
  end

  defp context_value(context, path) when is_map(context) and is_list(path) do
    Enum.reduce(path, context, fn key, acc ->
      case acc do
        %{} -> Map.get(acc, key, Map.get(acc, Atom.to_string(key)))
        _other -> nil
      end
    end)
  end

  defp context_text(nil), do: nil
  defp context_text(value) when is_atom(value), do: Atom.to_string(value)
  defp context_text(value) when is_binary(value), do: value
end
