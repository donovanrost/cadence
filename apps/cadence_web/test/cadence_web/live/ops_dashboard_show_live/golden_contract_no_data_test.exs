defmodule CadenceWeb.OpsDashboardShowLive.GoldenContractNoDataTest do
  use ExUnit.Case, async: true

  alias Cadence.Dashboards

  alias Cadence.Dashboards.{
    DashboardResolveRequest,
    DataSources,
    Document,
    Engine,
    Frame,
    PlacementFrames,
    RenderItem
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
    source_binding_id: [:data, :source_binding_id],
    source_request_id: [:source_request_id]
  ]

  test "golden no-data fixture carries healthy empty source contract into presenter lifecycle" do
    document = load_fixture!("no_data_value_tile.v1.json")

    assert %Dashboards.ValidationResult{valid?: true, errors: []} =
             Dashboards.validate_document(document)

    request =
      resolve_request(document, %{
        "placement_battery_voltage_no_data" => %{width_px: 320, height_px: 128}
      })

    plan = Engine.plan(request, source_registry_opts(validate_dashboard_contract?: true))

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
               data_source_id: "managed_questdb_primary",
               source_binding_id: "default_flight_telemetry"
             }
           ] = Enum.map(plan.planned_source_requests, &request_summary/1)

    result =
      Engine.resolve(
        request,
        source_registry_opts(
          validate_dashboard_contract?: true,
          source_opts: no_data_source_opts()
        )
      )

    refute result.plan_metadata.degraded?
    assert result.plan_metadata.executed_source_request_count == 1
    assert result.plan_metadata.returned_frame_count == 1
    assert result.dashboard_warnings == []

    assert %{
             "placement_battery_voltage_no_data" =>
               %PlacementFrames{
                 primary: [
                   %Frame{source: :telemetry, shape: :scalar, meta: meta} = frame
                 ],
                 overlays: %{},
                 warnings: []
               } = placement_frames
           } = result.frames_by_placement

    assert field_values(frame, "tlm.hk.battery_voltage") == []
    assert field_values(frame, "time") == []
    assert meta.returned_points == 0
    assert meta.data_source_id == "managed_questdb_primary"
    assert meta.source_binding_id == "default_flight_telemetry"
    assert meta.warning_codes == []
    assert source_watermark_confidences(frame) == [:best_effort]
    assert source_watermark_freshness_states(frame) == [:fresh]
    assert link_targets(frame) == [:telemetry_point]

    telemetry_point_link = link_by_target(frame, :telemetry_point)

    assert_link_runtime_context(telemetry_point_link,
      logical_source: "telemetry",
      observable_id: "tlm.hk.battery_voltage",
      scope_kind: "spacecraft",
      scope_id: "sc_001",
      time_mode: "live",
      time_axis: "generation_time",
      realm: "flight",
      data_source_id: "managed_questdb_primary",
      source_binding_id: "default_flight_telemetry",
      source_request_id: frame.meta.source_request_id
    )

    [render_item] = RenderItem.from_document(document)
    data = WidgetPresentation.data(nil, placement_frames, render_item.widget)

    assert %{
             kind: :point,
             engine_backed?: true,
             unresolved?: false,
             sample: nil,
             lifecycle_state: :no_data,
             lifecycle: %{state: :no_data, severity: :info, warning_codes: []},
             source_status: %{
               state: :no_data,
               severity: :info,
               data_state: :no_data,
               warning_codes: [],
               logical_sources: [:telemetry],
               data_source_ids: ["managed_questdb_primary"],
               source_binding_ids: ["default_flight_telemetry"],
               time_modes: ["live"],
               time_axes: ["generation_time"],
               scope_kinds: ["spacecraft"],
               scope_ids: ["sc_001"],
               empty_reason: :scope_no_data
             }
           } = data

    assert :flight in data.source_status.realms
    assert "flight" in data.source_status.realms
    assert [%{confidence: :best_effort, freshness_state: :fresh}] = data.source_status.watermarks
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

  defp source_registry_opts(opts) do
    Keyword.merge(
      [
        data_sources: [
          DataSources.default_managed_data_source(),
          DataSources.default_limits_data_source()
        ],
        data_bindings: [
          DataSources.default_flight_telemetry_binding(),
          DataSources.default_flight_limits_binding()
        ]
      ],
      opts
    )
  end

  defp no_data_source_opts do
    %{
      telemetry: [
        latest_fun: fn _organization_id, _mission_id, _point_id, _opts -> nil end,
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

  defp field_values(%Frame{fields: fields}, name) do
    fields
    |> Enum.find(&(&1.name == name))
    |> then(&(&1 && &1.values))
  end

  defp link_targets(%Frame{meta: meta}) do
    meta
    |> Map.get(:links, [])
    |> Enum.map(& &1.target)
  end

  defp link_by_target(%Frame{meta: meta}, target) do
    Enum.find(Map.get(meta, :links, []), &(&1.target == target))
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

  defp source_watermark_confidences(%Frame{meta: meta}) do
    meta
    |> Map.get(:source_watermarks, [])
    |> Enum.map(&Map.fetch!(&1, :confidence))
  end

  defp source_watermark_freshness_states(%Frame{meta: meta}) do
    meta
    |> Map.get(:source_watermarks, [])
    |> Enum.map(&Map.fetch!(&1, :freshness_state))
  end
end
