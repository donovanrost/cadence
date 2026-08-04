defmodule CadenceWeb.OpsDashboardShowLive.GoldenContractTimeSeriesTest do
  use ExUnit.Case, async: true

  alias Cadence.Dashboards

  alias Cadence.Dashboards.{
    DashboardResolveRequest,
    Document,
    Engine,
    Frame,
    PlacementFrames,
    RenderItem
  }

  alias Cadence.Management.DataSources

  alias Cadence.Limits.DefinitionInterval
  alias Cadence.Limits.Event
  alias Cadence.MissionEvents.Entry
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

  test "golden time-series fixture resolves history, overlays, markers, and chart data" do
    document = load_fixture!("time_series_with_limits.v1.json")

    assert %Dashboards.ValidationResult{valid?: true, errors: []} =
             Dashboards.validate_document(document)

    request =
      resolve_request(document, %{
        "placement_power_trend" => %{width_px: 640, height_px: 256}
      })

    result =
      Engine.resolve(
        request,
        time_series_source_registry_opts(
          validate_dashboard_contract?: true,
          source_opts: time_series_source_opts()
        )
      )

    assert result.plan_metadata.executed_source_request_count == 4
    assert result.plan_metadata.returned_frame_count == 13

    assert result.dashboard_warnings
           |> Enum.map(& &1.code)
           |> Enum.sort() == [
             :capability_fallback,
             :physical_aggregate_semantics
           ]

    assert %{
             "placement_power_trend" =>
               %PlacementFrames{
                 primary: [
                   %Frame{source: :telemetry, shape: :wide} = voltage_frame,
                   %Frame{source: :telemetry, shape: :wide} = current_frame
                 ],
                 overlays: %{limits: limit_frames, events: event_frames},
                 warnings: placement_warnings
               } = placement_frames
           } = result.frames_by_placement

    assert placement_warnings
           |> Enum.map(& &1.code)
           |> Enum.sort() == [
             :capability_fallback,
             :physical_aggregate_semantics
           ]

    assert voltage_frame.meta.sampling == :decimated_envelope
    assert voltage_frame.meta.decimation == :native_min_max_envelope
    assert voltage_frame.meta.target_points == 640
    assert voltage_frame.meta.data_source_id == "native-decimating-questdb"
    assert voltage_frame.meta.source_binding_id == "default_flight_telemetry"
    assert field_values(voltage_frame, "bucket_start") == [~U[2026-06-16 00:00:00Z]]
    assert field_values(voltage_frame, "tlm.hk.battery_voltage_min") == [11.5]
    assert field_values(voltage_frame, "tlm.hk.battery_voltage_max") == [12.75]
    assert field_values(voltage_frame, "tlm.hk.battery_voltage_value") == [12.25]
    assert source_watermark_confidences(voltage_frame) == [:best_effort]
    assert source_watermark_freshness_states(voltage_frame) == [:fresh]
    assert link_targets(voltage_frame) == [:telemetry_point]

    voltage_link = link_by_target(voltage_frame, :telemetry_point)

    assert_link_runtime_context(voltage_link,
      logical_source: "telemetry",
      observable_id: "tlm.hk.battery_voltage",
      scope_kind: "spacecraft",
      scope_id: "sc_001",
      time_mode: "archive",
      time_axis: "generation_time",
      realm: "flight",
      data_source_id: "native-decimating-questdb",
      source_binding_id: "default_flight_telemetry",
      source_request_id: voltage_frame.meta.source_request_id
    )

    assert current_frame.meta.observable_id == "tlm.hk.bus_current"
    assert field_values(current_frame, "tlm.hk.bus_current_value") == [4.5]

    assert Enum.any?(limit_frames, &match?(%Frame{source: :limits, shape: :events}, &1))
    assert Enum.any?(limit_frames, &match?(%Frame{source: :limits, shape: :intervals}, &1))
    assert Enum.any?(event_frames, &match?(%Frame{source: :events, shape: :events}, &1))

    limit_markers = WidgetPresentation.limit_markers(placement_frames, render_widget(document))
    event_markers = WidgetPresentation.event_markers(placement_frames, render_widget(document))

    assert Enum.any?(limit_markers, fn marker ->
             Map.get(marker, :limit_event_id) ==
               "limit-event-golden-tlm-hk-battery-voltage"
           end)

    assert Enum.any?(limit_markers, fn marker ->
             Map.get(marker, :marker_type) == "limit_definition_interval" and
               marker.limit_definition_id == "limit-def-golden-tlm-hk-battery-voltage"
           end)

    assert Enum.any?(event_markers, fn marker ->
             marker.marker_type == "mission_event" and
               marker.target_id == "mission-event-golden-1" and
               marker.event_kind == "limit_violation"
           end)

    assert %{
             version: 1,
             series: [
               %{
                 id: "tlm.hk.battery_voltage",
                 label: "tlm.hk.battery_voltage",
                 observable_id: "tlm.hk.battery_voltage",
                 unit: "V",
                 source: :telemetry,
                 field: "tlm.hk.battery_voltage_value",
                 time_axis: :generation_time,
                 sampling: :decimated_envelope,
                 decimation: :native_min_max_envelope,
                 data_source_id: "native-decimating-questdb",
                 source_binding_id: "default_flight_telemetry",
                 envelope: %{
                   kind: :min_max,
                   lower_field: "tlm.hk.battery_voltage_min",
                   upper_field: "tlm.hk.battery_voltage_max",
                   sample_count_field: "tlm.hk.battery_voltage_sample_count",
                   points: [[1_781_568_000_000, 11.5, 12.75, %{sample_count: 120}]]
                 },
                 points: [[1_781_568_000_000, 12.25]]
               },
               %{
                 id: "tlm.hk.bus_current",
                 label: "tlm.hk.bus_current",
                 observable_id: "tlm.hk.bus_current",
                 unit: "A",
                 source: :telemetry,
                 field: "tlm.hk.bus_current_value",
                 time_axis: :generation_time,
                 sampling: :decimated_envelope,
                 decimation: :native_min_max_envelope,
                 data_source_id: "native-decimating-questdb",
                 source_binding_id: "default_flight_telemetry",
                 envelope: %{
                   kind: :min_max,
                   lower_field: "tlm.hk.bus_current_min",
                   upper_field: "tlm.hk.bus_current_max",
                   sample_count_field: "tlm.hk.bus_current_sample_count",
                   points: [[1_781_568_000_000, 4.0, 4.8, %{sample_count: 120}]]
                 },
                 points: [[1_781_568_000_000, 4.5]]
               }
             ]
           } = WidgetPresentation.backfill(nil, placement_frames, render_widget(document))

    assert %{
             kind: :point,
             engine_backed?: true,
             unresolved?: false,
             stale?: false,
             lifecycle: %{state: :ready, severity: :ok},
             sample: %{
               sample_id: nil,
               raw_value: 12.25,
               engineering_value: 12.25,
               receipt_time: ~U[2026-06-16 00:00:00Z],
               generation_time: ~U[2026-06-16 00:00:00Z],
               quality_state: :good
             }
           } = WidgetPresentation.data(nil, placement_frames, render_widget(document))
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

  defp time_series_source_opts do
    %{
      telemetry: [
        decimated_history_fun: &decimated_history_buckets/4,
        watermark_fun: &best_effort_watermark/4
      ],
      limits: [
        history_fun: &limit_history_events/4,
        interval_fun: &limit_definition_intervals/4,
        watermark_fun: &best_effort_watermark/4
      ],
      events: [
        scheduled_contacts_fun: &empty_events/3,
        realized_contacts_fun: &empty_events/3,
        mission_events_fun: &mission_events/3,
        source_health_events_fun: &empty_events/3,
        source_watermark_events_fun: &empty_events/3,
        source_capability_posture_events_fun: &empty_events/3,
        telemetry_backfill_lifecycle_events_fun: &empty_events/3,
        telemetry_revision_decision_events_fun: &empty_events/3
      ]
    }
  end

  defp decimated_history_buckets(_organization_id, _mission_id, point_id, _opts) do
    value = if point_id == "tlm.hk.bus_current", do: 4.5, else: 12.25
    min = if point_id == "tlm.hk.bus_current", do: 4.0, else: 11.5
    max = if point_id == "tlm.hk.bus_current", do: 4.8, else: 12.75
    unit = if point_id == "tlm.hk.bus_current", do: "A", else: "V"

    [
      %{
        bucket_start: ~U[2026-06-16 00:00:00Z],
        bucket_end: ~U[2026-06-16 00:05:00Z],
        min: min,
        max: max,
        mean: value,
        unit: unit,
        sample_count: 120,
        worst_quality_state: :good
      }
    ]
  end

  defp limit_history_events(_organization_id, mission_id, point_id, _opts) do
    [limit_event(mission_id, point_id)]
  end

  defp limit_definition_intervals(_organization_id, mission_id, point_id, _opts) do
    [limit_definition_interval(mission_id, point_id)]
  end

  defp empty_events(_organization_id, _mission_id, _opts), do: []

  defp mission_events(_organization_id, mission_id, _opts) do
    [
      Entry.new(%{
        mission_event_id: "mission-event-golden-1",
        mission_id: mission_id,
        occurred_at: ~U[2026-06-16 00:03:00Z],
        category: :health,
        kind: :limit_violation,
        severity: :warning,
        title: "Battery voltage yellow high",
        source_record_kind: :limit_event,
        source_record_id: "limit-event-golden-tlm-hk-battery-voltage",
        subject_kind: :telemetry_point,
        subject_id: "tlm.hk.battery_voltage",
        spacecraft_id: "sc_001"
      })
    ]
  end

  defp limit_event(mission_id, point_id) do
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

  defp limit_definition_interval(mission_id, point_id) do
    stable_point_id = stable_point_id(point_id)

    %DefinitionInterval{
      definition_activation_key: "limit-activation-golden-#{stable_point_id}",
      limit_definition_lifecycle_event_id: "limit-lifecycle-golden-#{stable_point_id}",
      organization_id: "org_dashboards",
      mission_id: mission_id,
      point_id: point_id,
      limit_set_name: "ops",
      event_type: :registered,
      limit_definition_id: "limit-def-golden-#{stable_point_id}",
      limit_definition_version: 3,
      active_from: ~U[2026-06-16 00:00:00Z],
      active_to: ~U[2026-06-16 00:30:00Z],
      observed_at: ~U[2026-06-16 00:00:00Z],
      thresholds: %{"yellow_high" => 15, "red_high" => 25},
      metadata: %{},
      complete?: true
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

  defp render_widget(%Document{} = document) do
    [render_item] = RenderItem.from_document(document)
    render_item.widget
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
