defmodule CadenceWeb.OpsDashboardShowLive.GoldenContractSourceUnavailableTimeSeriesTest do
  use ExUnit.Case, async: true

  alias Cadence.Dashboards

  alias Cadence.Dashboards.{
    DashboardResolveRequest,
    DataSources,
    Document,
    Engine,
    PlacementFrames,
    RenderItem,
    ResolveWarning
  }

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

  test "golden source-unavailable time-series fixture carries failed range query into presenter lifecycle" do
    document = load_fixture!("source_unavailable_time_series.v1.json")

    assert %Dashboards.ValidationResult{valid?: true, errors: []} =
             Dashboards.validate_document(document)

    request =
      resolve_request(document, %{
        "placement_power_trend_unavailable" => %{width_px: 640, height_px: 256}
      })

    registry_opts = time_series_source_registry_opts(validate_dashboard_contract?: true)
    plan = Engine.plan(request, registry_opts)

    assert plan.dashboard_warnings == []
    assert plan.plan_metadata.source_request_count == 1

    assert [
             %{
               logical_source: :telemetry,
               observables: ["tlm.hk.battery_voltage", "tlm.hk.bus_current"],
               sampling_mode: :decimated_envelope,
               products: [],
               overlays: [],
               target_points: 640,
               time_axis: "receipt_time",
               data_source_id: "native-decimating-questdb",
               source_binding_id: "default_flight_telemetry"
             }
           ] = Enum.map(plan.planned_source_requests, &request_summary/1)

    result =
      Engine.resolve(
        request,
        time_series_source_registry_opts(
          validate_dashboard_contract?: true,
          source_opts: source_unavailable_time_series_source_opts()
        )
      )

    assert result.plan_metadata.degraded?
    assert result.plan_metadata.executed_source_request_count == 1
    assert result.plan_metadata.returned_frame_count == 0

    assert result.dashboard_warnings
           |> Enum.map(& &1.code)
           |> Enum.sort() == [
             :physical_aggregate_semantics,
             :source_unavailable
           ]

    assert [%ResolveWarning{code: :source_unavailable, severity: :error} = warning] =
             Enum.filter(result.dashboard_warnings, &(&1.code == :source_unavailable))

    assert warning.message == "Telemetry data source cannot execute native decimated history"
    assert warning.details.reason == ":test_decimated_history_failure"
    assert warning.details.source_empty_reason == :source_query_failed
    assert warning.details.source_query_kind == :native_decimated_history
    assert warning.details.unresolved_capability == :native_decimation
    assert warning.details.observable_id == "tlm.hk.battery_voltage"
    assert warning.details.requested_sampling == :decimated_envelope
    assert warning.details.data_source_id == "native-decimating-questdb"
    assert warning.details.source_binding_id == "default_flight_telemetry"

    assert Enum.map(warning.details.actions, & &1.target) == [
             :source_health,
             :source_inventory,
             :telemetry_explore
           ]

    assert link_targets(warning) == [:telemetry_point]

    assert_link_runtime_context(link_by_target(warning, :telemetry_point),
      logical_source: "telemetry",
      observable_id: "tlm.hk.battery_voltage",
      scope_kind: "spacecraft",
      scope_id: "sc_001",
      time_mode: "archive",
      time_axis: "receipt_time",
      realm: "flight",
      data_source_id: "native-decimating-questdb",
      source_binding_id: "default_flight_telemetry"
    )

    assert %{
             "placement_power_trend_unavailable" =>
               %PlacementFrames{
                 primary: [],
                 overlays: %{},
                 warnings: placement_warnings
               } = placement_frames
           } = result.frames_by_placement

    assert placement_warnings
           |> Enum.map(& &1.code)
           |> Enum.sort() == [
             :physical_aggregate_semantics,
             :source_unavailable
           ]

    assert WidgetPresentation.backfill(nil, placement_frames, render_widget(document)) == nil

    data = WidgetPresentation.data(nil, placement_frames, render_widget(document))

    assert %{
             kind: :point,
             engine_backed?: true,
             unresolved?: false,
             sample: nil,
             lifecycle_state: :error,
             lifecycle: %{
               state: :error,
               severity: :error,
               warning_codes: lifecycle_warnings
             },
             source_status: %{
               state: :unavailable,
               severity: :error,
               data_state: :no_data,
               warning_codes: source_warning_codes,
               logical_sources: [:telemetry],
               data_source_ids: ["native-decimating-questdb"],
               source_binding_ids: ["default_flight_telemetry"],
               time_modes: ["archive"],
               time_axes: ["receipt_time"]
             }
           } = data

    assert Enum.sort(lifecycle_warnings) == [
             :physical_aggregate_semantics,
             :source_unavailable
           ]

    assert Enum.sort(source_warning_codes) == [
             :physical_aggregate_semantics,
             :source_unavailable
           ]

    assert :flight in data.source_status.realms
    refute Map.has_key?(data.source_status, :empty_reason)
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

  defp source_unavailable_time_series_source_opts do
    %{
      telemetry: [
        decimated_history_fun: fn _organization_id, _mission_id, _point_id, _opts ->
          {:error, :test_decimated_history_failure}
        end,
        watermark_fun: &best_effort_watermark/4
      ]
    }
  end

  defp best_effort_watermark(_organization_id, _mission_id, _point_id, _opts) do
    {:ok,
     %{
       complete_through: ~U[2026-06-17 12:00:01Z],
       latest_receipt_time: ~U[2026-06-17 12:00:01Z],
       retention_starts_at: ~U[2026-06-15 00:00:00Z],
       sample_count: 1,
       confidence: :best_effort
     }}
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

  defp render_widget(%Document{} = document) do
    [render_item] = RenderItem.from_document(document)
    render_item.widget
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
    assert_scope_id(link, Keyword.get(opts, :scope_id))
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

  defp assert_scope_id(_link, nil), do: :ok

  defp assert_scope_id(link, expected) do
    assert context_value(link.context, [:scope, :primary, :ids]) == [expected]
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
  defp context_text(value) when is_integer(value), do: Integer.to_string(value)
end
