defmodule Cadence.Dashboards.DataSourcesCachePolicyTest do
  use Cadence.DataCase, async: true

  import Cadence.DataSourcesFixtures,
    only: [
      dashboard_frame_key: 2,
      dashboard_frames: 2,
      dashboard_source_result: 1,
      load_fixture_map!: 1,
      metadata_errors: 1,
      sample: 6,
      source_cache_entries: 1,
      source_cache_statuses: 1
    ]

  alias Cadence.Dashboards.{
    DashboardResolveRequest,
    DataSourceRegistry,
    Document,
    Engine,
    EvidenceRef,
    Frame,
    PlannedSourceRequest,
    RuntimeCache,
    RuntimeCacheKey,
    RuntimeFactConsumer,
    SourceRegistry
  }

  alias Cadence.DataSources.SourceWatermark
  alias Cadence.Management.DataSources

  alias Cadence.DataSources.{DataBinding, DataSource}

  alias Cadence.Platform.EventBus
  alias Cadence.Projections.DataSourceBindings

  @organization_id "org-cache-policy"
  @mission_id "mission-cache-policy"
  @no_event_bus __MODULE__.NoEventBus

  setup do
    persist_mission_scope(@organization_id, @mission_id)
    :ok
  end

  test "engine source result cache reuses segmented historical telemetry results" do
    cache = start_supervised!({RuntimeCache, name: nil})
    from_time = ~U[2026-06-21 20:15:00Z]
    boundary_time = ~U[2026-06-21 21:00:00Z]
    to_time = ~U[2026-06-21 21:15:00Z]
    parent = self()

    persist_watermarked_source("cache-policy-questdb-v1")
    persist_watermarked_source("cache-policy-questdb-v2")

    binding = %DataBinding{
      binding_id: "cache-policy-flight-telemetry",
      organization_id: @organization_id,
      mission_id: @mission_id,
      realm: :flight,
      logical_source: :telemetry,
      data_source_id: "cache-policy-questdb-v1",
      dataset: "flight-v1",
      priority: 0
    }

    assert {:ok, first_binding} =
             persist_data_binding(binding,
               occurred_at: ~U[2026-06-21 20:00:00Z]
             )

    assert {:ok, second_binding} =
             persist_data_binding(
               %DataBinding{
                 binding
                 | data_source_id: "cache-policy-questdb-v2",
                   dataset: "flight-v2"
               },
               occurred_at: boundary_time
             )

    history_fun = fn _organization_id, _mission_id, point_id, opts ->
      data_source_id = Keyword.fetch!(opts, :data_source_id)
      send(parent, {:history_opts, data_source_id, opts})

      {value, receipt_time} =
        case data_source_id do
          "cache-policy-questdb-v1" -> {11.0, ~U[2026-06-21 20:30:00Z]}
          "cache-policy-questdb-v2" -> {22.0, ~U[2026-06-21 21:05:00Z]}
        end

      [
        sample(
          point_id,
          "sample-#{data_source_id}",
          value,
          receipt_time,
          "evidence-#{data_source_id}",
          %{mission_id: @mission_id}
        )
      ]
    end

    watermark_fun = fn _organization_id, _mission_id, point_id, opts ->
      send(parent, {:watermark_opts, point_id, opts})

      %{
        complete_through: Keyword.fetch!(opts, :to_receipt_time),
        latest_receipt_time: Keyword.fetch!(opts, :to_receipt_time),
        retention_starts_at: Keyword.fetch!(opts, :from_receipt_time),
        point_id: point_id,
        confidence: :best_effort
      }
    end

    document = segmented_history_document()

    request = %DashboardResolveRequest{
      organization_id: document.organization_id,
      mission_id: document.mission_id,
      dashboard_id: document.dashboard_id,
      document: document,
      time_context: %{mode: :range, axis: :receipt_time, from: from_time, to: to_time},
      scope_context: %{primary: %{kind: "spacecraft", mode: "one", ids: ["sc_001"]}}
    }

    source_opts = %{telemetry: [history_fun: history_fun, watermark_fun: watermark_fun]}

    first =
      Engine.resolve(request,
        runtime_cache: cache,
        source_result_cache?: true,
        persisted?: true,
        freshness_now: ~U[2026-06-21 21:16:00Z],
        source_opts: source_opts
      )

    assert source_cache_statuses(first) == [:miss]
    assert [%{key: first_key}] = source_cache_entries(first)
    assert first_key.parts.cache_policy == :snapshot
    refute Map.has_key?(first_key.parts, :source_binding)
    refute Map.has_key?(first_key.parts, :data_source)

    assert Enum.map(first_key.parts.source_binding_segments, & &1.data_binding_event_id) == [
             first_binding.current_event_id,
             second_binding.current_event_id
           ]

    assert_receive {:history_opts, "cache-policy-questdb-v1", first_opts}
    assert_receive {:history_opts, "cache-policy-questdb-v2", second_opts}
    assert Keyword.fetch!(first_opts, :from_receipt_time) == from_time
    assert DateTime.compare(Keyword.fetch!(first_opts, :to_receipt_time), boundary_time) == :eq
    assert DateTime.compare(Keyword.fetch!(second_opts, :from_receipt_time), boundary_time) == :eq
    assert Keyword.fetch!(second_opts, :to_receipt_time) == to_time

    second =
      Engine.resolve(request,
        runtime_cache: cache,
        source_result_cache?: true,
        persisted?: true,
        freshness_now: ~U[2026-06-21 21:20:00Z],
        source_opts: source_opts
      )

    assert source_cache_statuses(second) == [:hit]
    assert [%{key: second_key}] = source_cache_entries(second)
    assert second_key.fingerprint == first_key.fingerprint
    refute_received {:history_opts, _data_source_id, _opts}

    assert %{"placement_power_trend" => placement_frames} = second.frames_by_placement
    assert [%Frame{} = frame] = placement_frames.primary
    assert frame.meta.segmented_source_bindings?

    assert Enum.map(frame.meta.source_binding_segments, & &1.data_source_id) == [
             "cache-policy-questdb-v1",
             "cache-policy-questdb-v2"
           ]

    assert [
             %{name: "time", values: [~U[2026-06-21 20:30:00Z], ~U[2026-06-21 21:05:00Z]]},
             %{name: "HK.counter", values: [11.0, 22.0]}
           ] = frame.fields
  end

  test "source results and frames include historical source binding provenance" do
    persist_source("cache-policy-questdb-v1", :mission_isolated)
    persist_source("cache-policy-questdb-v2", :mission_isolated)

    binding = %DataBinding{
      binding_id: "cache-policy-flight-telemetry",
      organization_id: @organization_id,
      mission_id: @mission_id,
      realm: :flight,
      logical_source: :telemetry,
      data_source_id: "cache-policy-questdb-v1",
      dataset: "flight-v1",
      priority: 0
    }

    assert {:ok, registered} =
             persist_data_binding(binding,
               occurred_at: ~U[2026-06-21 20:00:00Z]
             )

    assert {:ok, _changed} =
             persist_data_binding(
               %DataBinding{
                 binding
                 | data_source_id: "cache-policy-questdb-v2",
                   dataset: "flight-v2"
               },
               occurred_at: ~U[2026-06-21 21:00:00Z]
             )

    latest_fun = fn _organization_id, _mission_id, point_id, _opts ->
      sample(point_id, "sample-historical", 12.4, ~U[2026-06-21 20:30:00Z], "evidence-1",
        mission_id: @mission_id,
        generation_time: ~U[2026-06-21 20:29:59Z]
      )
    end

    result =
      SourceRegistry.resolve(
        source_request(sampling: %{mode: :latest}),
        persisted?: true,
        source_binding_at: ~U[2026-06-21 20:30:00Z],
        source_opts: %{telemetry: [latest_fun: latest_fun]}
      )

    refute Enum.any?(result.warnings, &(&1.severity == :error))
    assert result.meta.source_binding_id == "cache-policy-flight-telemetry"
    assert result.meta.source_binding_version == 1
    assert result.meta.source_binding_event_id == registered.current_event_id
    assert result.meta.source_binding_interval.data_source_id == "cache-policy-questdb-v1"
    assert result.meta.source_binding_interval.dataset == "flight-v1"

    assert [%Frame{} = frame] = result.frames
    assert frame.meta.source_binding_id == "cache-policy-flight-telemetry"
    assert frame.meta.source_binding_version == 1
    assert frame.meta.source_binding_event_id == registered.current_event_id
    assert frame.meta.source_binding_interval.data_source_id == "cache-policy-questdb-v1"

    assert %EvidenceRef{
             kind: :source_binding_event,
             id: event_id,
             observed_at: observed_at,
             source: :telemetry
           } =
             Enum.find(
               frame.meta.evidence,
               &match?(%EvidenceRef{kind: :source_binding_event}, &1)
             )

    assert event_id == registered.current_event_id
    assert DateTime.compare(observed_at, ~U[2026-06-21 20:00:00Z]) == :eq

    assert Enum.any?(frame.meta.evidence, fn
             %EvidenceRef{kind: :source_binding, id: "cache-policy-flight-telemetry"} -> true
             _other -> false
           end)
  end

  test "persists dashboard policy metadata and uses it for concrete source execution policy" do
    data_source = %DataSource{
      data_source_id: "cache-policy-policy-questdb",
      owner: :cadence,
      kind: :managed_tsdb,
      adapter: Cadence.Dashboards.Sources.Telemetry,
      organization_id: @organization_id,
      mission_id: @mission_id,
      isolation_level: :mission_isolated,
      capabilities: %{range_scan?: true},
      metadata: %{
        storage: :questdb,
        dashboard_policy: %{
          execution: %{timeout_ms: :infinity},
          circuit_breaker: %{backoff_ms: 10_000},
          adapter_extension: %{query_pool: "questdb-dashboard"}
        }
      }
    }

    assert {:ok, persisted_source} = persist_data_source(data_source)
    assert persisted_source.metadata["dashboard_policy"]["execution"]["timeout_ms"] == "infinity"

    assert persisted_source.metadata["dashboard_policy"]["adapter_extension"]["query_pool"] ==
             "questdb-dashboard"

    binding = %DataBinding{
      binding_id: "cache-policy-policy-flight-telemetry",
      organization_id: @organization_id,
      mission_id: @mission_id,
      realm: :flight,
      logical_source: :telemetry,
      data_source_id: "cache-policy-policy-questdb",
      dataset: "flight",
      priority: 0,
      metadata: %{
        dashboard_policy: %{
          circuit_breaker: %{failure_threshold: 2}
        }
      }
    }

    assert {:ok, _persisted_binding} = persist_data_binding(binding)

    policy = SourceRegistry.execution_policy(source_request(), persisted?: true)

    assert policy.timeout_ms == :infinity
    assert policy.circuit_failure_threshold == 2
    assert policy.circuit_backoff_ms == 10_000
    assert policy.provenance.data_source_policy?
    assert policy.provenance.binding_policy?
    assert policy.provenance.data_source_id == "cache-policy-policy-questdb"
    assert policy.provenance.source_binding_id == "cache-policy-policy-flight-telemetry"
  end

  test "rejects malformed data source dashboard policy metadata" do
    data_source = %DataSource{
      data_source_id: "cache-policy-bad-policy-questdb",
      owner: :cadence,
      kind: :managed_tsdb,
      adapter: Cadence.Dashboards.Sources.Telemetry,
      organization_id: @organization_id,
      mission_id: @mission_id,
      isolation_level: :mission_isolated,
      capabilities: %{range_scan?: true},
      metadata: %{
        dashboard_policy: %{
          execution: %{timeout_ms: -1},
          circuit_breaker: %{failure_threshold: 0, backoff_ms: -5}
        }
      }
    }

    assert {:error, %Ecto.Changeset{} = changeset} = persist_data_source(data_source)

    assert "dashboard_policy.execution.timeout_ms must be a non-negative integer or \"infinity\"" in metadata_errors(
             changeset
           )

    assert "dashboard_policy.circuit_breaker.failure_threshold must be a positive integer" in metadata_errors(
             changeset
           )

    assert "dashboard_policy.circuit_breaker.backoff_ms must be a non-negative integer" in metadata_errors(
             changeset
           )
  end

  test "rejects malformed data binding dashboard policy metadata" do
    persist_source("cache-policy-binding-policy-questdb", :mission_isolated)

    binding = %DataBinding{
      binding_id: "cache-policy-bad-policy-flight-telemetry",
      organization_id: @organization_id,
      mission_id: @mission_id,
      realm: :flight,
      logical_source: :telemetry,
      data_source_id: "cache-policy-binding-policy-questdb",
      dataset: "flight",
      priority: 0,
      metadata: %{
        dashboard_policy: %{
          execution: "slow",
          circuit_breaker: %{backoff_ms: -1}
        }
      }
    }

    assert {:error, %Ecto.Changeset{} = changeset} = persist_data_binding(binding)

    assert "dashboard_policy.execution must be a map" in metadata_errors(changeset)

    assert "dashboard_policy.circuit_breaker.backoff_ms must be a non-negative integer" in metadata_errors(
             changeset
           )
  end

  test "lists active telemetry data realms for dashboard controls" do
    persist_source("cache-policy-mission-questdb", :mission_isolated)

    assert {:ok, _binding} =
             persist_data_binding(%DataBinding{
               binding_id: "cache-policy-rehearsal-telemetry",
               organization_id: @organization_id,
               mission_id: @mission_id,
               realm: :rehearsal,
               logical_source: :telemetry,
               data_source_id: "cache-policy-mission-questdb",
               dataset: "rehearsal",
               active_from: ~U[2026-01-01 00:00:00Z],
               active_to: ~U[2027-01-01 00:00:00Z],
               priority: 0
             })

    assert {:ok, _binding} =
             persist_data_binding(%DataBinding{
               binding_id: "cache-policy-replay-limits",
               organization_id: @organization_id,
               mission_id: @mission_id,
               realm: :replay,
               logical_source: :limits,
               data_source_id: "cache-policy-mission-questdb",
               dataset: "replay-limits",
               priority: 0
             })

    assert {:ok, _binding} =
             persist_data_binding(%DataBinding{
               binding_id: "cache-policy-future-replay-telemetry",
               organization_id: @organization_id,
               mission_id: @mission_id,
               realm: :replay,
               logical_source: :telemetry,
               data_source_id: "cache-policy-mission-questdb",
               dataset: "future-replay",
               active_from: ~U[2028-01-01 00:00:00Z],
               priority: 0
             })

    assert DataSources.list_data_realms(@organization_id, @mission_id,
             now: ~U[2026-06-01 00:00:00Z]
           ) == ["rehearsal"]
  end

  test "persisted registry honors binding activation windows" do
    persist_source("cache-policy-mission-questdb", :mission_isolated)

    assert {:ok, _binding} =
             persist_data_binding(%DataBinding{
               binding_id: "cache-policy-flight-telemetry",
               organization_id: @organization_id,
               mission_id: @mission_id,
               realm: :flight,
               logical_source: :telemetry,
               data_source_id: "cache-policy-mission-questdb",
               dataset: "flight",
               active_from: ~U[2028-01-01 00:00:00Z],
               priority: 0
             })

    assert {:error, warning} =
             DataSourceRegistry.resolve(source_request(),
               persisted?: true,
               now: ~U[2026-06-01 00:00:00Z]
             )

    assert warning.code == :missing_source_binding

    assert {:ok, resolved} =
             DataSourceRegistry.resolve(source_request(),
               persisted?: true,
               now: ~U[2028-01-01 00:00:01Z]
             )

    assert resolved.binding.binding_id == "cache-policy-flight-telemetry"
  end

  test "data realm listing falls back to flight when no telemetry bindings exist" do
    assert DataSources.list_data_realms(@organization_id, @mission_id) == ["flight"]
  end

  test "persisted registry selection prefers mission-specific bindings" do
    persist_source("cache-policy-org-questdb", :org_isolated)
    persist_source("cache-policy-mission-questdb", :mission_isolated)

    assert {:ok, _binding} =
             persist_data_binding(%DataBinding{
               binding_id: "cache-policy-org-flight-telemetry",
               organization_id: @organization_id,
               realm: :flight,
               logical_source: :telemetry,
               data_source_id: "cache-policy-org-questdb",
               dataset: "org-flight",
               priority: 0
             })

    assert {:ok, _binding} =
             persist_data_binding(%DataBinding{
               binding_id: "cache-policy-flight-telemetry",
               organization_id: @organization_id,
               mission_id: @mission_id,
               realm: :flight,
               logical_source: :telemetry,
               data_source_id: "cache-policy-mission-questdb",
               dataset: "mission-flight",
               priority: 0
             })

    assert {:ok, resolved} = DataSourceRegistry.resolve(source_request(), persisted?: true)
    assert resolved.binding.binding_id == "cache-policy-flight-telemetry"
    assert resolved.data_source.data_source_id == "cache-policy-mission-questdb"
    assert resolved.data_source.isolation_level == :mission_isolated
    assert resolved.dataset == "mission-flight"

    assert {:ok, context_resolved} =
             DataSourceBindings.resolve(source_request())

    assert context_resolved.binding.binding_id == "cache-policy-flight-telemetry"
  end

  test "persisted registry returns missing binding warning when scoped rows exist but no binding matches" do
    persist_source("cache-policy-rehearsal-questdb", :mission_isolated)

    assert {:error, warning} =
             DataSourceRegistry.resolve(
               source_request(data_context: %{realm: :rehearsal}),
               persisted?: true
             )

    assert warning.code == :missing_source_binding
    assert warning.details.realm == :rehearsal
  end

  test "persisting a data source invalidates all dashboard caches for that source id" do
    cache = start_supervised!({RuntimeCache, name: nil})
    event_bus = start_cache_invalidation_runtime!(cache)

    persist_source("cache-policy-mission-questdb", :mission_isolated, event_bus: event_bus)
    persist_limits_source("cache-policy-mission-limits", event_bus: event_bus)

    flight_key =
      dashboard_source_result_key(:telemetry,
        binding_id: "cache-policy-flight-telemetry",
        data_source_id: "cache-policy-mission-questdb",
        realm: :flight,
        dataset: "mission-flight"
      )

    flight_frame_key = dashboard_frame_key(flight_key, "frame-flight")

    rehearsal_key =
      dashboard_source_result_key(:telemetry,
        binding_id: "cache-policy-rehearsal-telemetry",
        data_source_id: "cache-policy-mission-questdb",
        realm: :rehearsal,
        dataset: "mission-rehearsal"
      )

    rehearsal_frame_key = dashboard_frame_key(rehearsal_key, "frame-rehearsal")

    limits_key =
      dashboard_source_result_key(:limits,
        binding_id: "cache-policy-flight-limits",
        data_source_id: "cache-policy-mission-limits",
        realm: :flight,
        dataset: "telemetry_latest_limit_states"
      )

    limits_frame_key = dashboard_frame_key(limits_key, "frame-limits")

    flight_result = dashboard_source_result(flight_key)
    flight_frames = dashboard_frames(:telemetry, "frame-flight")
    rehearsal_result = dashboard_source_result(rehearsal_key)
    rehearsal_frames = dashboard_frames(:telemetry, "frame-rehearsal")
    limits_result = dashboard_source_result(limits_key)
    limits_frames = dashboard_frames(:limits, "frame-limits")

    assert :ok = RuntimeCache.put_source_result(flight_key, flight_result, cache)
    assert :ok = RuntimeCache.put_frame(flight_frame_key, flight_frames, cache)
    assert :ok = RuntimeCache.put_source_result(rehearsal_key, rehearsal_result, cache)
    assert :ok = RuntimeCache.put_frame(rehearsal_frame_key, rehearsal_frames, cache)
    assert :ok = RuntimeCache.put_source_result(limits_key, limits_result, cache)
    assert :ok = RuntimeCache.put_frame(limits_frame_key, limits_frames, cache)

    assert {:ok, _source} =
             persist_data_source(
               %DataSource{
                 data_source_id: "cache-policy-mission-questdb",
                 owner: :cadence,
                 kind: :managed_tsdb,
                 adapter: Cadence.Dashboards.Sources.Telemetry,
                 organization_id: @organization_id,
                 mission_id: @mission_id,
                 isolation_level: :mission_isolated,
                 capabilities: %{range_scan?: true, watermarks?: true},
                 metadata: %{storage: :questdb, reason: :updated_capabilities}
               },
               event_bus: event_bus
             )

    assert RuntimeCache.get_source_result(flight_key, cache) == :miss
    assert RuntimeCache.get_frame(flight_frame_key, cache) == :miss
    assert RuntimeCache.get_source_result(rehearsal_key, cache) == :miss
    assert RuntimeCache.get_frame(rehearsal_frame_key, cache) == :miss
    assert {:ok, ^limits_result} = RuntimeCache.get_source_result(limits_key, cache)
    assert {:ok, ^limits_frames} = RuntimeCache.get_frame(limits_frame_key, cache)
  end

  defp persist_source(data_source_id, isolation_level, opts \\ []) do
    mission_id = if isolation_level == :mission_isolated, do: @mission_id

    data_source = %DataSource{
      data_source_id: data_source_id,
      owner: :cadence,
      kind: :managed_tsdb,
      adapter: Cadence.Dashboards.Sources.Telemetry,
      organization_id: @organization_id,
      mission_id: mission_id,
      isolation_level: isolation_level,
      capabilities: %{range_scan?: true},
      metadata: %{storage: :questdb}
    }

    assert {:ok, persisted} = persist_data_source(data_source, opts)
    persisted
  end

  defp persist_watermarked_source(data_source_id) do
    data_source = %DataSource{
      data_source_id: data_source_id,
      owner: :cadence,
      kind: :managed_tsdb,
      adapter: Cadence.Dashboards.Sources.Telemetry,
      organization_id: @organization_id,
      mission_id: @mission_id,
      isolation_level: :mission_isolated,
      capabilities: %{range_scan?: true, watermarks?: true},
      metadata: %{storage: :questdb}
    }

    assert {:ok, persisted} = persist_data_source(data_source)
    persisted
  end

  defp persist_limits_source(data_source_id, opts) do
    data_source = %DataSource{
      data_source_id: data_source_id,
      owner: :cadence,
      kind: :projection,
      adapter: Cadence.Dashboards.Sources.Limits,
      organization_id: @organization_id,
      mission_id: @mission_id,
      isolation_level: :mission_isolated,
      capabilities: %{
        latest_state?: true,
        event_history?: true,
        definition_intervals?: true,
        watermarks?: true
      },
      metadata: %{storage: :postgres_projection}
    }

    assert {:ok, persisted} = persist_data_source(data_source, opts)
    persisted
  end

  defp persist_data_source(%DataSource{} = data_source, opts \\ []) do
    DataSources.persist_data_source(data_source, with_event_bus(opts))
  end

  defp persist_data_binding(%DataBinding{} = data_binding, opts \\ []) do
    DataSources.persist_data_binding(data_binding, with_event_bus(opts))
  end

  defp with_event_bus(opts), do: Keyword.put_new(opts, :event_bus, @no_event_bus)

  defp segmented_history_document do
    "time_series_with_limits.v1.json"
    |> load_fixture_map!()
    |> Map.put("organization_id", @organization_id)
    |> Map.put("mission_id", @mission_id)
    |> put_in(["placements", Access.at(0), "content", "widget_def", "binding", "observables"], [
      "HK.counter"
    ])
    |> put_in(
      ["placements", Access.at(0), "content", "widget_def", "binding", "sampling"],
      "raw_series"
    )
    |> put_in(["placements", Access.at(0), "content", "widget_def", "binding", "overlays"], [])
    |> Document.from_map()
  end

  defp source_request(overrides \\ []) do
    attrs = %{
      request_id: "cache-policy-source-request-1",
      organization_id: @organization_id,
      mission_id: @mission_id,
      logical_source: :telemetry,
      observables: ["HK.counter"],
      data_context: %{realm: :flight},
      sampling: %{mode: :raw_series}
    }

    struct!(PlannedSourceRequest, Keyword.merge(Map.to_list(attrs), overrides))
  end

  defp dashboard_source_result_key(logical_source, opts) do
    request = dashboard_source_request(logical_source, opts)

    RuntimeCacheKey.source_result(request,
      source_binding: dashboard_source_binding(logical_source, opts),
      data_source: dashboard_data_source(logical_source, opts),
      watermark: dashboard_watermark(logical_source, opts)
    )
  end

  defp dashboard_source_request(logical_source, opts) do
    binding_id = Keyword.fetch!(opts, :binding_id)

    %PlannedSourceRequest{
      request_id: "source-request-#{binding_id}",
      organization_id: @organization_id,
      mission_id: @mission_id,
      logical_source: logical_source,
      observables: [Keyword.get(opts, :observable, "HK.counter")],
      data_context: %{realm: Keyword.fetch!(opts, :realm)},
      sampling: %{mode: :latest}
    }
  end

  defp dashboard_source_binding(logical_source, opts) do
    %DataBinding{
      binding_id: Keyword.fetch!(opts, :binding_id),
      organization_id: @organization_id,
      mission_id: @mission_id,
      realm: Keyword.fetch!(opts, :realm),
      logical_source: logical_source,
      data_source_id: Keyword.fetch!(opts, :data_source_id),
      dataset: Keyword.fetch!(opts, :dataset),
      priority: 0
    }
  end

  defp dashboard_data_source(logical_source, opts) do
    %DataSource{
      data_source_id: Keyword.fetch!(opts, :data_source_id),
      owner: :cadence,
      kind: dashboard_source_kind(logical_source),
      adapter: dashboard_source_adapter(logical_source),
      organization_id: @organization_id,
      mission_id: @mission_id,
      isolation_level: :mission_isolated,
      capabilities: %{latest?: true, latest_state?: true, event_history?: true, watermarks?: true}
    }
  end

  defp dashboard_watermark(logical_source, opts) do
    %SourceWatermark{
      logical_source: logical_source,
      request_id: "source-request-#{Keyword.fetch!(opts, :binding_id)}",
      source_binding_id: Keyword.fetch!(opts, :binding_id),
      data_source_id: Keyword.fetch!(opts, :data_source_id),
      realm: Keyword.fetch!(opts, :realm),
      dataset: Keyword.fetch!(opts, :dataset),
      complete_through: ~U[2026-06-17 12:00:00Z],
      latest_receipt_time: ~U[2026-06-17 12:00:00Z],
      retention_starts_at: ~U[2026-06-17 11:00:00Z],
      confidence: :best_effort,
      freshness_state: :fresh
    }
  end

  defp dashboard_source_kind(:limits), do: :projection
  defp dashboard_source_kind(_logical_source), do: :managed_tsdb

  defp dashboard_source_adapter(:limits), do: Cadence.Dashboards.Sources.Limits
  defp dashboard_source_adapter(:telemetry), do: Cadence.Dashboards.Sources.Telemetry

  defp start_cache_invalidation_runtime!(cache) do
    event_bus = start_supervised!({EventBus, name: nil, delivery: :sync, before_notify: nil})

    start_supervised!(
      {RuntimeFactConsumer,
       name: nil, event_bus: event_bus, enabled?: true, runtime_cache: RuntimeCache.client(cache)}
    )

    event_bus
  end
end
