defmodule CadenceWeb.OpsDashboardShowLive.GoldenContractRepeatedLayoutTest do
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
  alias CadenceWeb.OpsDashboardShowLive.WidgetPresentation

  @fixture_dir Path.expand("../../../../../cadence/test/fixtures/dashboards", __DIR__)

  test "golden repeated fixture expands into scoped placement instances" do
    document = load_fixture!("repeated_spacecraft_status.v1.json")

    assert %Dashboards.ValidationResult{valid?: true, errors: []} =
             Dashboards.validate_document(document)

    request =
      document
      |> resolve_request(%{"placement_status_repeat" => %{width_px: 480, height_px: 192}})
      |> Map.put(:scope_context, %{})

    plan = Engine.plan(request, source_registry_opts(validate_dashboard_contract?: true))

    assert plan.dashboard_warnings == []
    assert plan.plan_metadata.source_request_count == 6

    telemetry_requests =
      Enum.filter(plan.planned_source_requests, &(&1.logical_source == :telemetry))

    limit_requests =
      Enum.filter(plan.planned_source_requests, &(&1.logical_source == :limits))

    assert telemetry_requests
           |> Enum.map(& &1.scope_context.primary.ids)
           |> Enum.sort() == [
             ["sc_001"],
             ["sc_002"],
             ["sc_003"]
           ]

    assert Enum.all?(telemetry_requests, fn request ->
             request.scope_context.primary.mode == "one" and
               request.observables == ["tlm.hk.battery_voltage", "tlm.hk.bus_current"] and
               request.sampling.mode == :latest and
               request.sampling.target_points == 480 and
               request.overlays == [:quality]
           end)

    assert limit_requests
           |> Enum.map(& &1.scope_context.primary.ids)
           |> Enum.sort() == [
             ["sc_001"],
             ["sc_002"],
             ["sc_003"]
           ]

    assert Enum.all?(limit_requests, fn request ->
             request.scope_context.primary.mode == "one" and
               request.observables == ["tlm.hk.battery_voltage", "tlm.hk.bus_current"] and
               request.sampling.mode == :latest_state and
               request.sampling.products == [:latest_state]
           end)

    result =
      Engine.resolve(
        request,
        source_registry_opts(
          validate_dashboard_contract?: true,
          source_opts: source_opts()
        )
      )

    assert Enum.map(result.dashboard_warnings, & &1.code) == [
             :capability_fallback,
             :capability_fallback,
             :capability_fallback
           ]

    assert result.plan_metadata.executed_source_request_count == 6
    assert result.plan_metadata.returned_frame_count == 12

    assert result.frames_by_placement
           |> Map.keys()
           |> Enum.sort() == [
             "placement_status_repeat__repeat__spacecraft__sc_001",
             "placement_status_repeat__repeat__spacecraft__sc_002",
             "placement_status_repeat__repeat__spacecraft__sc_003"
           ]

    assert %{
             "placement_status_repeat__repeat__spacecraft__sc_001" =>
               %PlacementFrames{
                 primary: [
                   %Frame{source: :telemetry, shape: :scalar} = voltage_frame,
                   %Frame{source: :telemetry, shape: :scalar} = current_frame
                 ],
                 overlays: %{limits: limit_frames},
                 warnings: [%ResolveWarning{code: :capability_fallback}]
               } = placement_frames
           } = result.frames_by_placement

    assert length(limit_frames) == 2
    assert voltage_frame.scope.primary.ids == ["sc_001"]
    assert voltage_frame.scope.primary.mode == "one"
    assert current_frame.scope.primary.ids == ["sc_001"]
    assert field_values(voltage_frame, "tlm.hk.battery_voltage") == [12.25]
    assert field_values(current_frame, "tlm.hk.bus_current") == [12.25]

    telemetry_link = link_by_target(voltage_frame, :telemetry_point, "tlm.hk.battery_voltage")

    assert context_value(telemetry_link.context, [:scope, :primary, :ids]) == ["sc_001"]

    assert context_text(context_value(telemetry_link.context, [:scope, :primary, :mode])) ==
             "one"

    [render_item, _second_item, _third_item] = RenderItem.from_document(document)
    assert render_item.placement_id == "placement_status_repeat__repeat__spacecraft__sc_001"

    data = WidgetPresentation.data(nil, placement_frames, render_item.widget)

    assert data.kind == :status_matrix
    assert data.lifecycle_state == :ready

    assert Enum.map(data.rows, & &1.observable_id) == [
             "tlm.hk.battery_voltage",
             "tlm.hk.bus_current"
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

  defp link_by_target(%Frame{meta: meta}, target, target_id) do
    Enum.find(
      Map.get(meta, :links, []),
      &(&1.target == target and &1.target_id == target_id)
    )
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
