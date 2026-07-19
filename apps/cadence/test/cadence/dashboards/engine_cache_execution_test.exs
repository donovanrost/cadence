defmodule Cadence.Dashboards.EngineCacheExecutionTest do
  use Cadence.UnitCase, async: true

  import Cadence.Dashboards.EngineFixtures

  alias Cadence.Dashboards.{
    DataBinding,
    DataSource,
    DataSources,
    Document,
    Engine,
    Frame,
    RuntimeCache,
    SourceCircuitBreaker
  }

  test "source result cache opt-in reuses cached adapter results" do
    cache = start_supervised!({RuntimeCache, name: nil})
    document = load_fixture!("value_tile_latest.v1.json")
    parent = self()

    telemetry_latest_fun = fn _organization_id, mission_id, point_id, _opts ->
      send(parent, {:telemetry_latest, point_id})
      telemetry_sample(mission_id, point_id)
    end

    limits_latest_fun = fn _organization_id, mission_id, point_id, _opts ->
      send(parent, {:limits_latest, point_id})
      limit_event(mission_id, point_id)
    end

    telemetry_watermark_fun = fn _organization_id, _mission_id, point_id, _opts ->
      send(parent, {:telemetry_watermark, point_id})
      best_effort_watermark(~U[2026-06-17 12:00:01Z])
    end

    limits_watermark_fun = fn _organization_id, _mission_id, point_id, _opts ->
      send(parent, {:limits_watermark, point_id})
      best_effort_watermark(~U[2026-06-17 12:00:01Z])
    end

    request = resolve_request(document)

    first =
      Engine.resolve(request,
        runtime_cache: cache,
        source_result_cache?: true,
        freshness_now: ~U[2026-06-17 12:00:02Z],
        source_opts: %{
          telemetry: [latest_fun: telemetry_latest_fun, watermark_fun: telemetry_watermark_fun],
          limits: [latest_fun: limits_latest_fun, watermark_fun: limits_watermark_fun]
        }
      )

    assert source_cache_statuses(first) == [:miss, :miss]
    telemetry_request = request_by_source(first.planned_source_requests, :telemetry)
    limits_request = request_by_source(first.planned_source_requests, :limits)
    telemetry_provenance = telemetry_request.metadata.capability_provenance
    limits_provenance = limits_request.metadata.capability_provenance

    assert source_cache_entry_by_source(first, :telemetry).capability_provenance ==
             telemetry_provenance

    assert source_cache_entry_by_source(first, :limits).capability_provenance ==
             limits_provenance

    assert_receive {:telemetry_latest, "tlm.hk.battery_voltage"}
    assert_receive {:limits_latest, "tlm.hk.battery_voltage"}

    second =
      Engine.resolve(request,
        runtime_cache: cache,
        source_result_cache?: true,
        freshness_now: ~U[2026-06-17 12:00:02Z],
        source_opts: %{
          telemetry: [latest_fun: telemetry_latest_fun, watermark_fun: telemetry_watermark_fun],
          limits: [latest_fun: limits_latest_fun, watermark_fun: limits_watermark_fun]
        }
      )

    assert source_cache_statuses(second) == [:hit, :hit]

    assert source_cache_entry_by_source(second, :telemetry).capability_provenance ==
             telemetry_provenance

    assert source_cache_entry_by_source(second, :limits).capability_provenance ==
             limits_provenance

    refute_receive {:telemetry_latest, _point_id}, 20
    refute_receive {:limits_latest, _point_id}, 20

    assert %{"placement_battery_voltage" => placement_frames} = second.frames_by_placement

    assert [
             %Frame{
               source: :telemetry,
               meta: %{capability_provenance: ^telemetry_provenance}
             }
           ] = placement_frames.primary

    assert %{
             limits: [
               %Frame{
                 source: :limits,
                 meta: %{capability_provenance: ^limits_provenance}
               }
             ]
           } = placement_frames.overlays
  end

  test "source result cache preflight rejects cached result when source is degraded" do
    cache = start_supervised!({RuntimeCache, name: nil})

    document =
      "value_tile_latest.v1.json"
      |> load_fixture_map!()
      |> put_in(["placements", Access.at(0), "content", "widget_def", "binding", "overlays"], [])
      |> Document.from_map()

    parent = self()

    latest_fun = fn _organization_id, mission_id, point_id, _opts ->
      send(parent, {:telemetry_latest, point_id})
      telemetry_sample(mission_id, point_id)
    end

    watermark_fun = fn _organization_id, _mission_id, point_id, _opts ->
      send(parent, {:telemetry_watermark, point_id})
      best_effort_watermark(~U[2026-06-17 12:00:01Z])
    end

    request = resolve_request(document)

    first =
      Engine.resolve(request,
        runtime_cache: cache,
        source_result_cache?: true,
        freshness_now: ~U[2026-06-17 12:00:02Z],
        source_opts: %{telemetry: [latest_fun: latest_fun, watermark_fun: watermark_fun]}
      )

    assert source_cache_statuses(first) == [:miss]
    assert_receive {:telemetry_latest, "tlm.hk.battery_voltage"}

    second =
      Engine.resolve(request,
        runtime_cache: cache,
        source_result_cache?: true,
        freshness_now: ~U[2026-06-17 12:00:02Z],
        source_opts: %{
          telemetry: [
            latest_fun: latest_fun,
            watermark_fun: watermark_fun,
            source_health: :degraded
          ]
        }
      )

    assert source_cache_statuses(second) == [:stale]
    assert [%{reasons: [:source_degraded]}] = source_cache_entries(second)
    assert_receive {:telemetry_latest, "tlm.hk.battery_voltage"}
  end

  test "frame cache refreshes when source result preflight rejects cached result" do
    cache = start_supervised!({RuntimeCache, name: nil})

    document =
      "value_tile_latest.v1.json"
      |> load_fixture_map!()
      |> put_in(["placements", Access.at(0), "content", "widget_def", "binding", "overlays"], [])
      |> Document.from_map()

    counter = start_supervised!({Agent, fn -> 0 end})

    latest_fun = fn _organization_id, mission_id, point_id, _opts ->
      value =
        Agent.get_and_update(counter, fn count ->
          {if(count == 0, do: 12.25, else: 99.0), count + 1}
        end)

      telemetry_sample(mission_id, point_id, value)
    end

    watermark_fun = fn _organization_id, _mission_id, _point_id, _opts ->
      best_effort_watermark(~U[2026-06-17 12:00:01Z])
    end

    request = resolve_request(document)

    first =
      Engine.resolve(request,
        runtime_cache: cache,
        source_result_cache?: true,
        frame_cache?: true,
        freshness_now: ~U[2026-06-17 12:00:02Z],
        source_opts: %{telemetry: [latest_fun: latest_fun, watermark_fun: watermark_fun]}
      )

    assert source_cache_statuses(first) == [:miss]
    assert frame_cache_statuses(first) == [:miss]
    assert telemetry_latest_values(first) == [12.25]

    second =
      Engine.resolve(request,
        runtime_cache: cache,
        source_result_cache?: true,
        frame_cache?: true,
        freshness_now: ~U[2026-06-17 12:00:02Z],
        source_opts: %{
          telemetry: [
            latest_fun: latest_fun,
            watermark_fun: watermark_fun,
            source_health: :degraded
          ]
        }
      )

    assert source_cache_statuses(second) == [:stale]
    assert frame_cache_statuses(second) == [:refresh]
    assert telemetry_latest_values(second) == [99.0]
    assert Agent.get(counter, & &1) == 2
  end

  test "snapshot source and frame caches ignore moved watermark and source health" do
    cache = start_supervised!({RuntimeCache, name: nil})

    document =
      "value_tile_latest.v1.json"
      |> load_fixture_map!()
      |> put_in(["placements", Access.at(0), "content", "widget_def", "binding", "overlays"], [])
      |> Document.from_map()

    parent = self()

    sample_counter =
      start_supervised!(%{id: :sample_counter, start: {Agent, :start_link, [fn -> 0 end]}})

    watermark_counter =
      start_supervised!(%{id: :watermark_counter, start: {Agent, :start_link, [fn -> 0 end]}})

    latest_fun = fn _organization_id, mission_id, point_id, _opts ->
      send(parent, {:telemetry_latest, point_id})

      value =
        Agent.get_and_update(sample_counter, fn count ->
          {if(count == 0, do: 12.25, else: 99.0), count + 1}
        end)

      telemetry_sample(mission_id, point_id, value)
    end

    watermark_fun = fn _organization_id, _mission_id, point_id, _opts ->
      send(parent, {:telemetry_watermark, point_id})

      cursor =
        Agent.get_and_update(watermark_counter, fn count ->
          cursor =
            if count == 0 do
              ~U[2026-06-17 12:05:00Z]
            else
              ~U[2026-06-17 12:10:00Z]
            end

          {cursor, count + 1}
        end)

      best_effort_watermark(cursor)
    end

    request =
      resolve_request(document,
        time_context: %{
          mode: :archive,
          axis: :receipt_time,
          from: ~U[2026-06-17 12:00:00Z],
          to: ~U[2026-06-17 12:05:00Z]
        }
      )

    first =
      Engine.resolve(request,
        runtime_cache: cache,
        source_result_cache?: true,
        frame_cache?: true,
        freshness_now: ~U[2026-06-17 12:10:00Z],
        source_opts: %{telemetry: [latest_fun: latest_fun, watermark_fun: watermark_fun]}
      )

    assert source_cache_statuses(first) == [:miss]
    assert frame_cache_statuses(first) == [:miss]
    assert telemetry_latest_values(first) == [12.25]
    assert [%{key: first_key}] = source_cache_entries(first)
    assert first_key.parts.cache_policy == :snapshot
    refute Map.has_key?(first_key.parts, :watermark_cursor)
    refute Map.has_key?(first_key.parts, :freshness_policy)
    assert [%{key: first_frame_key}] = frame_cache_entries(first)
    assert first_frame_key.parts.cache_policy == :snapshot
    assert first_frame_key.parts.source_result_fingerprint == first_key.fingerprint
    assert_receive {:telemetry_latest, "tlm.hk.battery_voltage"}
    assert_receive {:telemetry_watermark, "tlm.hk.battery_voltage"}

    second =
      Engine.resolve(request,
        runtime_cache: cache,
        source_result_cache?: true,
        frame_cache?: true,
        freshness_now: ~U[2026-06-17 12:15:00Z],
        source_opts: %{
          telemetry: [
            latest_fun: latest_fun,
            watermark_fun: watermark_fun,
            source_health: :degraded
          ]
        }
      )

    assert source_cache_statuses(second) == [:hit]
    assert frame_cache_statuses(second) == [:hit]
    assert telemetry_latest_values(second) == [12.25]
    assert [%{key: second_key}] = source_cache_entries(second)
    assert second_key.fingerprint == first_key.fingerprint
    assert [%{key: second_frame_key}] = frame_cache_entries(second)
    assert second_frame_key.fingerprint == first_frame_key.fingerprint
    assert_receive {:telemetry_watermark, "tlm.hk.battery_voltage"}
    refute_receive {:telemetry_latest, _point_id}, 20
    assert Agent.get(sample_counter, & &1) == 1
  end

  test "replay-run source and frame caches are snapshot-scoped and never labeled flight" do
    cache = start_supervised!({RuntimeCache, name: nil})

    document =
      "value_tile_latest.v1.json"
      |> load_fixture_map!()
      |> put_in(["placements", Access.at(0), "content", "widget_def", "binding", "overlays"], [])
      |> Document.from_map()

    parent = self()

    latest_fun = fn _organization_id, mission_id, point_id, opts ->
      send(parent, {:telemetry_latest, point_id, opts})
      telemetry_sample(mission_id, point_id)
    end

    watermark_fun = fn _organization_id, _mission_id, point_id, opts ->
      send(parent, {:telemetry_watermark, point_id, opts})
      best_effort_watermark(~U[2026-06-17 12:05:00Z])
    end

    replay_source = %DataSource{
      DataSources.default_managed_data_source()
      | data_source_id: "replay_questdb",
        capabilities: %{latest?: true, watermarks?: true}
    }

    replay_binding = %DataBinding{
      DataSources.default_flight_telemetry_binding()
      | binding_id: "replay_flight_telemetry",
        data_source_id: "replay_questdb",
        realm: :replay,
        dataset: "replay-run-1"
    }

    request =
      resolve_request(document,
        time_context: %{
          mode: :replay_run,
          axis: :generation_time,
          replay_run_id: "replay-run-1"
        },
        data_context: %{}
      )

    result =
      Engine.resolve(request,
        runtime_cache: cache,
        source_result_cache?: true,
        frame_cache?: true,
        data_sources: [DataSources.default_managed_data_source(), replay_source],
        data_bindings: [DataSources.default_flight_telemetry_binding(), replay_binding],
        source_opts: %{telemetry: [latest_fun: latest_fun, watermark_fun: watermark_fun]}
      )

    assert source_cache_statuses(result) == [:miss]
    assert frame_cache_statuses(result) == [:miss]

    assert [%{key: source_key}] = source_cache_entries(result)
    assert source_key.parts.cache_policy == :snapshot
    refute Map.has_key?(source_key.parts, :watermark_cursor)
    refute Map.has_key?(source_key.parts, :freshness_policy)
    assert source_key.parts.source_binding.realm == :replay
    assert source_key.parts.request.time_context.replay_run_id == "replay-run-1"

    assert [%{key: frame_key}] = frame_cache_entries(result)
    assert frame_key.parts.cache_policy == :snapshot
    assert frame_key.parts.source_result_binding.realm == :replay

    assert %Frame{meta: meta} =
             result.frames_by_placement["placement_battery_voltage"].primary |> List.first()

    assert meta.realm == :replay
    assert meta.dataset == "replay-run-1"
    assert meta.replay_run_id == "replay-run-1"
    assert meta.source_request_context.requested_realm == :replay
    assert meta.source_request_context.time_mode == :replay_run
    refute meta.realm == :flight

    telemetry_request = request_by_source(result.planned_source_requests, :telemetry)

    assert %{
             requested_realm: :replay,
             requested_time_mode: :replay_run,
             replay_run_id: "replay-run-1",
             selected_source_binding_id: "replay_flight_telemetry",
             selected_data_source_id: "replay_questdb",
             selected_dataset: "replay-run-1"
           } = result.plan_metadata.source_selection_by_request_id[telemetry_request.request_id]

    assert_receive {:telemetry_latest, "tlm.hk.battery_voltage", telemetry_opts}
    assert telemetry_opts[:data_source_id] == "replay_questdb"
    assert telemetry_opts[:dataset] == "replay-run-1"

    assert_receive {:telemetry_watermark, "tlm.hk.battery_voltage", watermark_opts}
    assert watermark_opts[:data_source_id] == "replay_questdb"
    assert watermark_opts[:dataset] == "replay-run-1"
  end

  test "frame cache opt-in reuses materialized frames" do
    cache = start_supervised!({RuntimeCache, name: nil})

    document =
      "value_tile_latest.v1.json"
      |> load_fixture_map!()
      |> put_in(["placements", Access.at(0), "content", "widget_def", "binding", "overlays"], [])
      |> Document.from_map()

    counter = start_supervised!({Agent, fn -> 0 end})

    latest_fun = fn _organization_id, mission_id, point_id, _opts ->
      value =
        Agent.get_and_update(counter, fn count ->
          value =
            case count do
              0 -> 12.25
              _count -> 99.0
            end

          {value, count + 1}
        end)

      telemetry_sample(mission_id, point_id, value)
    end

    watermark_fun = fn _organization_id, _mission_id, _point_id, _opts ->
      best_effort_watermark(~U[2026-06-17 12:00:01Z])
    end

    request = resolve_request(document)

    first =
      Engine.resolve(request,
        runtime_cache: cache,
        frame_cache?: true,
        freshness_now: ~U[2026-06-17 12:00:02Z],
        source_opts: %{telemetry: [latest_fun: latest_fun, watermark_fun: watermark_fun]}
      )

    assert frame_cache_statuses(first) == [:miss]
    telemetry_request = request_by_source(first.planned_source_requests, :telemetry)
    telemetry_provenance = telemetry_request.metadata.capability_provenance
    assert [%{capability_provenance: ^telemetry_provenance}] = frame_cache_entries(first)
    assert telemetry_latest_values(first) == [12.25]

    assert [
             %Frame{
               source: :telemetry,
               meta: %{capability_provenance: ^telemetry_provenance}
             }
           ] = first.frames_by_placement["placement_battery_voltage"].primary

    second =
      Engine.resolve(request,
        runtime_cache: cache,
        frame_cache?: true,
        freshness_now: ~U[2026-06-17 12:00:02Z],
        source_opts: %{telemetry: [latest_fun: latest_fun, watermark_fun: watermark_fun]}
      )

    assert frame_cache_statuses(second) == [:hit]
    assert [%{capability_provenance: ^telemetry_provenance}] = frame_cache_entries(second)
    assert telemetry_latest_values(second) == [12.25]

    assert [
             %Frame{
               source: :telemetry,
               meta: %{capability_provenance: ^telemetry_provenance}
             }
           ] = second.frames_by_placement["placement_battery_voltage"].primary

    assert Agent.get(counter, & &1) == 2
  end

  test "source execution timeouts degrade the timed-out request while other requests complete" do
    document = mixed_telemetry_execution_document()
    breaker = start_supervised!({SourceCircuitBreaker, name: nil})

    result =
      Engine.resolve(resolve_request(document),
        data_sources: [test_adapter_data_source("flight-questdb")],
        data_bindings: [telemetry_binding("flight-questdb")],
        source_opts: %{
          telemetry: [
            test_pid: self(),
            sleep_ms_by_sampling: %{latest: 500}
          ]
        },
        source_execution_timeout_ms: 200,
        source_execution_max_concurrency: 2,
        source_circuit_breaker: breaker,
        source_circuit_failure_threshold: 1,
        source_circuit_backoff_ms: 60_000
      )

    assert result.plan_metadata.source_execution_policy == %{
             max_concurrency: 2,
             timeout_ms: 200
           }

    source_policies = Map.values(result.plan_metadata.source_execution_policies_by_request_id)
    assert length(source_policies) == 2
    assert Enum.all?(source_policies, &(&1.timeout_ms == 200))
    assert Enum.all?(source_policies, &(&1.circuit_failure_threshold == 1))
    assert Enum.all?(source_policies, & &1.provenance.explicit_opts?)

    assert result.plan_metadata.executed_source_request_count == 2
    assert result.plan_metadata.degraded?
    assert source_cache_statuses(result) == [:disabled, :source_execution_failed]

    assert Enum.any?(result.dashboard_warnings, fn warning ->
             warning.code == :source_unavailable and
               warning.details.reason == "timeout after 200ms" and
               warning.details.data_source_id == "flight-questdb"
           end)

    assert %{state: :open, failure_count: 1} =
             SourceCircuitBreaker.status(
               breaker,
               {"org_dashboards", "mission_dashboards", :telemetry, "flight-questdb", :flight,
                "flight"},
               []
             )

    assert_received {:dashboard_source_test_adapter_request, "flight-questdb", :latest}
    assert_received {:dashboard_source_test_adapter_request, "flight-questdb", :raw_series}
  end

  test "source execution uses binding timeout policy before global timeout" do
    document = mixed_telemetry_execution_document()
    breaker = start_supervised!({SourceCircuitBreaker, name: nil})

    binding = %DataBinding{
      telemetry_binding("flight-questdb")
      | metadata: %{
          dashboard_policy: %{
            execution: %{timeout_ms: 200},
            circuit_breaker: %{failure_threshold: 1, backoff_ms: 15_000}
          }
        }
    }

    result =
      Engine.resolve(resolve_request(document),
        data_sources: [test_adapter_data_source("flight-questdb")],
        data_bindings: [binding],
        source_opts: %{
          telemetry: [
            test_pid: self(),
            sleep_ms_by_sampling: %{latest: 500}
          ]
        },
        source_execution_max_concurrency: 2,
        source_circuit_breaker: breaker
      )

    assert result.plan_metadata.source_execution_policy == %{
             max_concurrency: 2,
             timeout_ms: 5_000
           }

    source_policies = Map.values(result.plan_metadata.source_execution_policies_by_request_id)
    assert length(source_policies) == 2
    assert Enum.all?(source_policies, &(&1.timeout_ms == 200))
    assert Enum.all?(source_policies, &(&1.circuit_failure_threshold == 1))
    assert Enum.all?(source_policies, &(&1.circuit_backoff_ms == 15_000))
    assert Enum.all?(source_policies, & &1.provenance.binding_policy?)

    assert result.plan_metadata.degraded?
    assert source_cache_statuses(result) == [:disabled, :source_execution_failed]

    assert Enum.any?(result.dashboard_warnings, fn warning ->
             warning.code == :source_unavailable and
               warning.details.reason == "timeout after 200ms" and
               warning.details.data_source_id == "flight-questdb"
           end)

    assert %{state: :open, failure_count: 1, failure_threshold: 1, backoff_ms: 15_000} =
             SourceCircuitBreaker.status(
               breaker,
               {"org_dashboards", "mission_dashboards", :telemetry, "flight-questdb", :flight,
                "flight"},
               failure_threshold: 1,
               backoff_ms: 15_000
             )
  end

  test "source execution policy caps concurrent adapter resolves" do
    document = mixed_telemetry_execution_document()
    concurrency_agent = start_supervised!({Agent, fn -> %{current: 0, max: 0} end})

    result =
      Engine.resolve(resolve_request(document),
        data_sources: [test_adapter_data_source("flight-questdb")],
        data_bindings: [telemetry_binding("flight-questdb")],
        source_opts: %{
          telemetry: [
            test_pid: self(),
            sleep_ms: 40,
            concurrency_agent: concurrency_agent
          ]
        },
        source_execution_timeout_ms: 500,
        source_execution_max_concurrency: 1
      )

    assert result.plan_metadata.executed_source_request_count == 2
    refute result.plan_metadata.degraded?
    assert Agent.get(concurrency_agent, & &1.max) == 1

    assert_received {:dashboard_source_test_adapter_request, "flight-questdb", :latest}
    assert_received {:dashboard_source_test_adapter_request, "flight-questdb", :raw_series}
  end

  test "validation mode rejects malformed source results at the adapter boundary" do
    document = mixed_telemetry_execution_document()

    assert_raise ArgumentError, ~r/dashboard source_result contract violated/, fn ->
      Engine.resolve(resolve_request(document),
        data_sources: [test_adapter_data_source("flight-questdb")],
        data_bindings: [telemetry_binding("flight-questdb")],
        source_opts: %{telemetry: [mode: :invalid_result]},
        source_execution_max_concurrency: 1,
        source_execution_timeout_ms: :infinity,
        validate_dashboard_contract?: true
      )
    end
  end
end
