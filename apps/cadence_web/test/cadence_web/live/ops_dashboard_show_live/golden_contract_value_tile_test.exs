defmodule CadenceWeb.OpsDashboardShowLive.GoldenContractValueTileTest do
  use ExUnit.Case, async: true

  alias Cadence.Dashboards

  alias Cadence.Dashboards.{
    DashboardResolveRequest,
    DataSources,
    Document,
    Engine,
    Frame,
    PlacementFrames,
    RenderItem,
    ResolveWarning
  }

  alias Cadence.Limits.Event
  alias Cadence.Telemetry.Sample
  alias CadenceWeb.OpsDashboardShowLive.{DataLinkSelection, WidgetPresentation}

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

  test "golden value tile fixture resolves through engine contract into presenter data" do
    document = load_fixture!("value_tile_latest.v1.json")

    assert %Dashboards.ValidationResult{valid?: true, errors: []} =
             Dashboards.validate_document(document)

    request = resolve_request(document)
    plan = Engine.plan(request, source_registry_opts(validate_dashboard_contract?: true))

    assert plan.dashboard_warnings == []
    assert plan.plan_metadata.source_request_count == 2

    assert plan.planned_source_requests
           |> Enum.map(&request_summary/1)
           |> Enum.sort_by(&request_sort_key/1) == [
             %{
               logical_source: :telemetry,
               observables: ["tlm.hk.battery_voltage"],
               sampling_mode: :latest,
               products: [],
               overlays: [:quality],
               target_points: 320,
               time_axis: "generation_time",
               data_source_id: "managed_questdb_primary",
               source_binding_id: "default_flight_telemetry"
             },
             %{
               logical_source: :limits,
               observables: ["tlm.hk.battery_voltage"],
               sampling_mode: :latest_state,
               products: [:latest_state],
               overlays: [],
               target_points: nil,
               time_axis: "generation_time",
               data_source_id: "managed_limits_projection",
               source_binding_id: "default_flight_limits"
             }
           ]

    result =
      Engine.resolve(
        request,
        source_registry_opts(
          validate_dashboard_contract?: true,
          source_opts: source_opts()
        )
      )

    assert result.plan_metadata.executed_source_request_count == 2
    assert result.plan_metadata.returned_frame_count == 2

    assert [%ResolveWarning{code: :capability_fallback, severity: :info} = warning] =
             result.dashboard_warnings

    assert warning.details.unresolved_capability == :overlays
    assert warning.details.requested_overlays == [:quality]
    assert warning.details.data_source_id == "managed_questdb_primary"
    assert warning.details.source_binding_id == "default_flight_telemetry"

    assert Enum.map(warning.details.actions, & &1.target) == [
             :telemetry_explore,
             :source_health,
             :source_inventory
           ]

    assert %{
             "placement_battery_voltage" =>
               %PlacementFrames{
                 primary: [%Frame{source: :telemetry, shape: :scalar} = telemetry_frame],
                 overlays: %{limits: [%Frame{source: :limits, shape: :scalar} = limits_frame]},
                 warnings: [%ResolveWarning{code: :capability_fallback}]
               } = placement_frames
           } = result.frames_by_placement

    assert field_values(telemetry_frame, "tlm.hk.battery_voltage") == [12.25]
    assert field_values(telemetry_frame, "time") == [~U[2026-06-17 12:00:00Z]]
    assert telemetry_frame.scope.spacecraft_id == "sc_001"
    assert telemetry_frame.meta.data_source_id == "managed_questdb_primary"
    assert telemetry_frame.meta.source_binding_id == "default_flight_telemetry"
    assert telemetry_frame.meta.warning_codes == [:capability_fallback]
    assert source_watermark_confidences(telemetry_frame) == [:best_effort]
    assert source_watermark_freshness_states(telemetry_frame) == [:fresh]
    assert link_targets(telemetry_frame) == [:telemetry_point, :telemetry_sample]

    telemetry_point_link = link_by_target(telemetry_frame, :telemetry_point)
    telemetry_sample_link = link_by_target(telemetry_frame, :telemetry_sample)

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
      source_request_id: telemetry_frame.meta.source_request_id
    )

    assert DataLinkSelection.selected_ref(telemetry_sample_link, %{
             "placement-id" => "placement_battery_voltage",
             "timestamp-ms" => "1781697600000"
           }) == %{
             "link_id" => telemetry_sample_link.link_id,
             "target" => "telemetry_sample",
             "target_id" => "sample-golden-1",
             "target_text" => "telemetry sample",
             "timestamp_ms" => 1_781_697_600_000,
             "placement_id" => "placement_battery_voltage",
             "source" => "frame",
             "scope_kind" => "spacecraft",
             "scope_id" => "sc_001",
             "spacecraft_id" => "sc_001",
             "realm" => "flight",
             "time_mode" => "live",
             "time_axis" => "generation_time",
             "data_source_id" => "managed_questdb_primary",
             "source_binding_id" => "default_flight_telemetry",
             "limit_mode" => "observed",
             "observable_id" => "tlm.hk.battery_voltage"
           }

    assert field_values(limits_frame, "normalized_state") == [:yellow]
    assert field_values(limits_frame, "limit_state") == [:yellow_high]
    assert field_values(limits_frame, "violation") == [true]
    assert limits_frame.meta.data_source_id == "managed_limits_projection"
    assert limits_frame.meta.source_binding_id == "default_flight_limits"
    assert limits_frame.meta.limit_event_id == "limit-event-golden-tlm-hk-battery-voltage"
    assert source_watermark_confidences(limits_frame) == [:best_effort]
    assert source_watermark_freshness_states(limits_frame) == [:fresh]

    assert link_targets(limits_frame) == [
             :telemetry_point,
             :limit_event,
             :limit_definition,
             :telemetry_sample
           ]

    assert_link_runtime_context(link_by_target(limits_frame, :limit_event),
      logical_source: "limits",
      observable_id: "tlm.hk.battery_voltage",
      scope_kind: "spacecraft",
      scope_id: "sc_001",
      time_mode: "live",
      time_axis: "generation_time",
      realm: "flight",
      data_source_id: "managed_limits_projection",
      source_binding_id: "default_flight_limits",
      source_request_id: limits_frame.meta.source_request_id
    )

    assert_link_runtime_context(hd(warning.links),
      logical_source: "telemetry",
      observable_id: "tlm.hk.battery_voltage",
      scope_kind: "spacecraft",
      scope_id: "sc_001",
      time_mode: "live",
      time_axis: "generation_time",
      realm: "flight",
      data_source_id: "managed_questdb_primary",
      source_binding_id: "default_flight_telemetry"
    )

    assert [render_item] = RenderItem.from_document(document)

    assert %{
             kind: :point,
             engine_backed?: true,
             unresolved?: false,
             stale?: false,
             lifecycle: %{state: :ready, severity: :ok},
             sample: %{
               sample_id: "sample-golden-1",
               raw_value: 12.25,
               engineering_value: 12.25,
               receipt_time: ~U[2026-06-17 12:00:00Z],
               generation_time: ~U[2026-06-17 12:00:00Z],
               quality_state: :good
             },
             limit_event: %{
               normalized_state: :yellow,
               limit_state: :yellow_high,
               limit_event_id: "limit-event-golden-tlm-hk-battery-voltage"
             }
           } = WidgetPresentation.data(nil, placement_frames, render_item.widget)
  end

  defp load_fixture!(name) do
    @fixture_dir
    |> Path.join(name)
    |> File.read!()
    |> Jason.decode!()
    |> Document.from_map()
  end

  defp resolve_request(%Document{} = document) do
    %DashboardResolveRequest{
      organization_id: document.organization_id,
      mission_id: document.mission_id,
      dashboard_id: document.dashboard_id,
      document: document,
      scope_context: %{primary: %{kind: "spacecraft", mode: "one", ids: ["sc_001"]}},
      interaction_context: %{
        placement_sizes: %{"placement_battery_voltage" => %{width_px: 320, height_px: 128}}
      }
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

  defp source_opts do
    %{
      telemetry: [
        latest_fun: &telemetry_sample/4,
        watermark_fun: &best_effort_watermark/4
      ],
      limits: [
        latest_fun: &limit_event/4,
        watermark_fun: &best_effort_watermark/4
      ]
    }
  end

  defp telemetry_sample(_organization_id, mission_id, point_id, _opts) do
    %Sample{
      sample_id: "sample-golden-1",
      mission_id: mission_id,
      spacecraft_id: "sc_001",
      point_id: point_id,
      point_name: point_id,
      packet_definition_id: "packet-def-1",
      packet_definition_version: 1,
      packet_id: "packet-1",
      evidence_id: "evidence-golden-1",
      raw_value: 12.25,
      engineering_value: 12.25,
      quality_state: :good,
      generation_time: ~U[2026-06-17 12:00:00Z],
      receipt_time: ~U[2026-06-17 12:00:01Z],
      provenance: %{}
    }
  end

  defp limit_event(_organization_id, mission_id, point_id, _opts) do
    stable_point_id = stable_point_id(point_id)

    %Event{
      limit_event_id: "limit-event-golden-#{stable_point_id}",
      mission_id: mission_id,
      spacecraft_id: "sc_001",
      point_id: point_id,
      point_name: point_id,
      source_sample_type: :telemetry_sample,
      sample_id: "sample-golden-1",
      limit_definition_id: "limit-def-golden-#{stable_point_id}",
      limit_definition_version: 3,
      limit_set_name: "ops",
      evaluated_value: 12.25,
      limit_state: :yellow_high,
      normalized_state: :yellow,
      violation: true,
      generation_time: ~U[2026-06-17 12:00:00Z],
      receipt_time: ~U[2026-06-17 12:00:01Z],
      provenance: %{}
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

  defp request_sort_key(%{
         logical_source: source,
         sampling_mode: sampling_mode,
         products: products
       }) do
    {source_sort_key(source), sampling_sort_key(sampling_mode), Enum.map(products, &to_string/1)}
  end

  defp source_sort_key(:telemetry), do: 0
  defp source_sort_key(:limits), do: 1
  defp source_sort_key(source), do: to_string(source)

  defp sampling_sort_key(:latest), do: 0
  defp sampling_sort_key(:latest_state), do: 1
  defp sampling_sort_key(sampling_mode), do: to_string(sampling_mode)

  defp stable_point_id(point_id) do
    point_id
    |> String.replace(".", "-")
    |> String.replace("_", "-")
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
