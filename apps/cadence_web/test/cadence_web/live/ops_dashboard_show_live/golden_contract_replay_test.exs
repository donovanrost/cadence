defmodule CadenceWeb.OpsDashboardShowLive.GoldenContractReplayTest do
  use ExUnit.Case, async: true

  alias Cadence.Dashboards

  alias Cadence.Dashboards.{DashboardResolveRequest, Document, Engine, Frame, PlacementFrames}

  alias Cadence.Management.DataSources

  alias Cadence.DataSources.{DataBinding, DataSource}

  alias Cadence.Limits.DefinitionInterval
  alias Cadence.Limits.Event
  alias Cadence.Telemetry.Sample
  alias CadenceWeb.OpsDashboardShowLive.DataLinkSelection

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
    dataset: [:data, :dataset],
    source_request_id: [:source_request_id]
  ]

  test "golden replay fixture preserves snapshot-scoped source context" do
    document = load_fixture!("replay_context.v1.json")

    assert %Dashboards.ValidationResult{valid?: true, errors: []} =
             Dashboards.validate_document(document)

    plan = Engine.plan(resolve_request(document), replay_source_registry_opts())

    assert plan.dashboard_warnings == []
    assert plan.plan_metadata.snapshot?
    refute plan.plan_metadata.live_append_eligible?

    telemetry_request = request_by_source(plan.planned_source_requests, :telemetry)

    assert telemetry_request.time_context.mode == "replay_run"
    assert telemetry_request.time_context.replay_run_id == "replay_run_001"
    assert telemetry_request.data_context.realm == "replay"
    assert telemetry_request.data_context.replay_run_id == "replay_run_001"
    assert telemetry_request.metadata.capability_provenance.data_source_id == "replay-questdb"

    assert telemetry_request.metadata.capability_provenance.binding_id ==
             "replay_flight_telemetry"

    assert telemetry_request.metadata.capability_provenance.dataset == "replay_run_001"

    assert Enum.all?(plan.planned_source_requests, fn request ->
             request.time_context.mode == "replay_run" and
               request.time_context.replay_run_id == "replay_run_001" and
               request.data_context.realm == "replay"
           end)

    result =
      Engine.resolve(
        resolve_request(document, %{
          "placement_replay_counter" => %{width_px: 640, height_px: 256}
        }),
        replay_source_registry_opts(
          source_opts: replay_source_opts(),
          validate_dashboard_contract?: true
        )
      )

    assert result.dashboard_warnings == []

    assert %{
             "placement_replay_counter" => %PlacementFrames{
               primary: [%Frame{source: :telemetry} = replay_frame],
               overlays: %{limits: replay_limit_frames}
             }
           } = result.frames_by_placement

    replay_sample_link = link_by_target(replay_frame, :telemetry_sample)

    assert_link_runtime_context(replay_sample_link,
      logical_source: "telemetry",
      observable_id: "tlm.hk.counter",
      scope_kind: "spacecraft",
      scope_id: "sc_001",
      time_mode: "replay_run",
      time_axis: "generation_time",
      replay_run_id: "replay_run_001",
      realm: "replay",
      data_source_id: "replay-questdb",
      source_binding_id: "replay_flight_telemetry",
      dataset: "replay_run_001",
      source_request_id: replay_frame.meta.source_request_id
    )

    assert DataLinkSelection.selected_ref(replay_sample_link, %{
             "placement-id" => "placement_replay_counter",
             "timestamp-ms" => "1781568000000"
           }) == %{
             "link_id" => replay_sample_link.link_id,
             "target" => "telemetry_sample",
             "target_id" => "sample-replay-1",
             "target_text" => "telemetry sample",
             "timestamp_ms" => 1_781_568_000_000,
             "placement_id" => "placement_replay_counter",
             "source" => "frame",
             "scope_kind" => "spacecraft",
             "scope_id" => "sc_001",
             "spacecraft_id" => "sc_001",
             "realm" => "replay",
             "time_mode" => "replay_run",
             "time_axis" => "generation_time",
             "replay_run_id" => "replay_run_001",
             "data_source_id" => "replay-questdb",
             "source_binding_id" => "replay_flight_telemetry",
             "limit_mode" => "observed",
             "observable_id" => "tlm.hk.counter"
           }

    assert Enum.all?(replay_limit_frames, fn frame ->
             frame.meta.realm == :replay and frame.meta.replay_run_id == "replay_run_001"
           end)
  end

  defp load_fixture!(name) do
    @fixture_dir
    |> Path.join(name)
    |> File.read!()
    |> Jason.decode!()
    |> Document.from_map()
  end

  defp resolve_request(%Document{} = document, placement_sizes \\ nil) do
    placement_sizes =
      placement_sizes ||
        %{"placement_battery_voltage" => %{width_px: 320, height_px: 128}}

    %DashboardResolveRequest{
      organization_id: document.organization_id,
      mission_id: document.mission_id,
      dashboard_id: document.dashboard_id,
      document: document,
      scope_context: %{primary: %{kind: "spacecraft", mode: "one", ids: ["sc_001"]}},
      interaction_context: %{placement_sizes: placement_sizes}
    }
  end

  defp replay_source_registry_opts(opts \\ []) do
    %DataSource{} = default_managed_source = DataSources.default_managed_data_source()
    %DataBinding{} = default_telemetry_binding = DataSources.default_flight_telemetry_binding()
    %DataBinding{} = default_limits_binding = DataSources.default_flight_limits_binding()

    replay_telemetry_source = %DataSource{
      default_managed_source
      | data_source_id: "replay-questdb",
        capabilities:
          default_managed_source.capabilities
          |> Map.put(:range_scan?, true)
    }

    replay_telemetry_binding = %DataBinding{
      default_telemetry_binding
      | binding_id: "replay_flight_telemetry",
        realm: :replay,
        data_source_id: "replay-questdb",
        dataset: "replay_run_001"
    }

    replay_limits_binding = %DataBinding{
      default_limits_binding
      | binding_id: "replay_limits",
        realm: :replay
    }

    Keyword.merge(
      [
        data_sources: [
          replay_telemetry_source,
          DataSources.default_limits_data_source()
        ],
        data_bindings: [
          replay_telemetry_binding,
          replay_limits_binding
        ]
      ],
      opts
    )
  end

  defp replay_source_opts do
    %{
      telemetry: [
        history_fun: &replay_history_samples/4,
        watermark_fun: &best_effort_watermark/4
      ],
      limits: [
        history_fun: &limit_history_events/4,
        interval_fun: &limit_definition_intervals/4,
        watermark_fun: &best_effort_watermark/4
      ]
    }
  end

  defp replay_history_samples(_organization_id, mission_id, point_id, _opts) do
    [
      %Sample{
        sample_id: "sample-replay-1",
        mission_id: mission_id,
        spacecraft_id: "sc_001",
        point_id: point_id,
        point_name: point_id,
        packet_definition_id: "packet-def-1",
        packet_definition_version: 1,
        packet_id: "packet-1",
        evidence_id: "evidence-replay-1",
        raw_value: 7,
        engineering_value: 7,
        quality_state: :good,
        generation_time: ~U[2026-06-16 00:00:00Z],
        receipt_time: ~U[2026-06-16 00:00:00Z],
        provenance: %{}
      }
    ]
  end

  defp limit_history_events(_organization_id, mission_id, point_id, _opts) do
    [limit_event(mission_id, point_id)]
  end

  defp limit_definition_intervals(_organization_id, mission_id, point_id, _opts) do
    [limit_definition_interval(mission_id, point_id)]
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

  defp request_by_source(requests, source) do
    Enum.find(requests, &(&1.logical_source == source))
  end

  defp stable_point_id(point_id) do
    point_id
    |> String.replace(".", "-")
    |> String.replace("_", "-")
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
    assert_replay_context(link, Keyword.get(opts, :replay_run_id))
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

  defp assert_replay_context(_link, nil), do: :ok

  defp assert_replay_context(link, expected) do
    assert context_text(context_value(link.context, [:time, :replay_run_id])) == expected
    assert context_text(context_value(link.context, [:data, :replay_run_id])) == expected
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
