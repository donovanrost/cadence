defmodule Cadence.Dashboards.DataSourcesCachePolicyTest do
  use Cadence.ConfigCase, async: false

  import Cadence.Dashboards.DataSourcesFixtures

  alias Cadence.Dashboards.{
    DashboardResolveRequest,
    DataBinding,
    DataSource,
    DataSourceRegistry,
    DataSources,
    Engine,
    EvidenceRef,
    Frame,
    RuntimeCache,
    SourceRegistry
  }

  alias Cadence.OperationalEvents
  alias Cadence.OperationalEvents.Event

  setup do
    persist_mission_scope("org-dash-source", "mission-dash-source")
    :ok
  end

  test "engine source result cache reuses segmented historical telemetry results" do
    cache = start_supervised!({RuntimeCache, name: nil})
    from_time = ~U[2026-06-21 20:15:00Z]
    boundary_time = ~U[2026-06-21 21:00:00Z]
    to_time = ~U[2026-06-21 21:15:00Z]
    parent = self()

    persist_watermarked_source("mission-questdb-v1")
    persist_watermarked_source("mission-questdb-v2")

    binding = %DataBinding{
      binding_id: "mission-flight-telemetry",
      organization_id: "org-dash-source",
      mission_id: "mission-dash-source",
      realm: :flight,
      logical_source: :telemetry,
      data_source_id: "mission-questdb-v1",
      dataset: "flight-v1",
      priority: 0
    }

    assert {:ok, first_binding} =
             DataSources.persist_data_binding(binding,
               occurred_at: ~U[2026-06-21 20:00:00Z]
             )

    assert {:ok, second_binding} =
             DataSources.persist_data_binding(
               %DataBinding{binding | data_source_id: "mission-questdb-v2", dataset: "flight-v2"},
               occurred_at: boundary_time
             )

    history_fun = fn _organization_id, _mission_id, point_id, opts ->
      data_source_id = Keyword.fetch!(opts, :data_source_id)
      send(parent, {:history_opts, data_source_id, opts})

      {value, receipt_time} =
        case data_source_id do
          "mission-questdb-v1" -> {11.0, ~U[2026-06-21 20:30:00Z]}
          "mission-questdb-v2" -> {22.0, ~U[2026-06-21 21:05:00Z]}
        end

      [
        sample(
          point_id,
          "sample-#{data_source_id}",
          value,
          receipt_time,
          "evidence-#{data_source_id}",
          %{}
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

    assert_receive {:history_opts, "mission-questdb-v1", first_opts}
    assert_receive {:history_opts, "mission-questdb-v2", second_opts}
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
    refute_receive {:history_opts, _data_source_id, _opts}, 20

    assert %{"placement_power_trend" => placement_frames} = second.frames_by_placement
    assert [%Frame{} = frame] = placement_frames.primary
    assert frame.meta.segmented_source_bindings?

    assert Enum.map(frame.meta.source_binding_segments, & &1.data_source_id) == [
             "mission-questdb-v1",
             "mission-questdb-v2"
           ]

    assert [
             %{name: "time", values: [~U[2026-06-21 20:30:00Z], ~U[2026-06-21 21:05:00Z]]},
             %{name: "HK.counter", values: [11.0, 22.0]}
           ] = frame.fields
  end

  test "source results and frames include historical source binding provenance" do
    persist_source("mission-questdb-v1", :mission_isolated)
    persist_source("mission-questdb-v2", :mission_isolated)

    binding = %DataBinding{
      binding_id: "mission-flight-telemetry",
      organization_id: "org-dash-source",
      mission_id: "mission-dash-source",
      realm: :flight,
      logical_source: :telemetry,
      data_source_id: "mission-questdb-v1",
      dataset: "flight-v1",
      priority: 0
    }

    assert {:ok, registered} =
             DataSources.persist_data_binding(binding,
               occurred_at: ~U[2026-06-21 20:00:00Z]
             )

    assert {:ok, _changed} =
             DataSources.persist_data_binding(
               %DataBinding{binding | data_source_id: "mission-questdb-v2", dataset: "flight-v2"},
               occurred_at: ~U[2026-06-21 21:00:00Z]
             )

    latest_fun = fn _organization_id, _mission_id, point_id, _opts ->
      sample(point_id, "sample-historical", 12.4, ~U[2026-06-21 20:30:00Z], "evidence-1",
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
    assert result.meta.source_binding_id == "mission-flight-telemetry"
    assert result.meta.source_binding_version == 1
    assert result.meta.source_binding_event_id == registered.current_event_id
    assert result.meta.source_binding_interval.data_source_id == "mission-questdb-v1"
    assert result.meta.source_binding_interval.dataset == "flight-v1"

    assert [%Frame{} = frame] = result.frames
    assert frame.meta.source_binding_id == "mission-flight-telemetry"
    assert frame.meta.source_binding_version == 1
    assert frame.meta.source_binding_event_id == registered.current_event_id
    assert frame.meta.source_binding_interval.data_source_id == "mission-questdb-v1"

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
             %EvidenceRef{kind: :source_binding, id: "mission-flight-telemetry"} -> true
             _other -> false
           end)
  end

  test "source result frames include selected operational interval evidence" do
    persist_source("mission-questdb-v1", :mission_isolated)
    persist_source_endpoint_scope("endpoint-sc-001")

    assert {:ok, _event} =
             catalog_revision("catalog-revision-a", revision_number: 1)
             |> Event.from_catalog_revision(~U[2026-06-21 20:00:00Z])
             |> OperationalEvents.persist_event()

    binding_set =
      application_binding_set("runtime-apps-a",
        source_endpoint_ref: "endpoint-sc-001",
        apid: 42,
        metric_name: "packets_v1"
      )

    assert {:ok, _binding_set} = Cadence.persist_binding_set("org-dash-source", binding_set)

    assert {:ok, _activation} =
             Cadence.activate_binding_set(
               "org-dash-source",
               "mission-dash-source",
               binding_set.binding_set_id,
               binding_set.version,
               activated_at: ~U[2026-06-21 20:00:00Z]
             )

    binding = %DataBinding{
      binding_id: "mission-flight-telemetry",
      organization_id: "org-dash-source",
      mission_id: "mission-dash-source",
      realm: :flight,
      logical_source: :telemetry,
      data_source_id: "mission-questdb-v1",
      dataset: "flight-v1",
      priority: 0
    }

    assert {:ok, _registered} =
             DataSources.persist_data_binding(binding,
               occurred_at: ~U[2026-06-21 20:00:00Z]
             )

    latest_fun = fn _organization_id, _mission_id, point_id, _opts ->
      sample(point_id, "sample-historical", 12.4, ~U[2026-06-21 20:30:00Z], "evidence-1",
        generation_time: ~U[2026-06-21 20:29:59Z]
      )
    end

    result =
      SourceRegistry.resolve(
        source_request(
          sampling: %{mode: :latest},
          scope_context: %{source_endpoint_id: "endpoint-sc-001"}
        ),
        persisted?: true,
        source_binding_at: ~U[2026-06-21 20:30:00Z],
        source_opts: %{telemetry: [latest_fun: latest_fun]}
      )

    assert [%Frame{} = frame] = result.frames

    assert [
             %{kind: :application_binding, subject_id: "runtime-apps-a-packet-counter-rule"},
             %{kind: :binding_set, subject_id: "runtime-apps-a"},
             %{kind: :catalog_revision, subject_id: "catalog-revision-a"}
           ] =
             frame.meta.selected_operational_intervals
             |> Enum.sort_by(& &1.kind)
             |> Enum.map(&Map.take(&1, [:kind, :subject_id]))

    assert Enum.any?(frame.meta.evidence, fn
             %EvidenceRef{kind: :binding_set_interval, id: "effective_interval:binding_set:" <> _} ->
               true

             _other ->
               false
           end)

    assert Enum.any?(frame.meta.evidence, fn
             %EvidenceRef{
               kind: :application_binding_interval,
               id: "effective_interval:application_binding:" <> _
             } ->
               true

             _other ->
               false
           end)

    assert Enum.any?(frame.meta.evidence, fn
             %EvidenceRef{
               kind: :catalog_revision_interval,
               id: "effective_interval:catalog_revision:" <> _
             } ->
               true

             _other ->
               false
           end)
  end

  test "persists dashboard policy metadata and uses it for concrete source execution policy" do
    data_source = %DataSource{
      data_source_id: "policy-questdb",
      owner: :cadence,
      kind: :managed_tsdb,
      adapter: Cadence.Dashboards.Sources.Telemetry,
      organization_id: "org-dash-source",
      mission_id: "mission-dash-source",
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

    assert {:ok, persisted_source} = DataSources.persist_data_source(data_source)
    assert persisted_source.metadata["dashboard_policy"]["execution"]["timeout_ms"] == "infinity"

    assert persisted_source.metadata["dashboard_policy"]["adapter_extension"]["query_pool"] ==
             "questdb-dashboard"

    binding = %DataBinding{
      binding_id: "policy-flight-telemetry",
      organization_id: "org-dash-source",
      mission_id: "mission-dash-source",
      realm: :flight,
      logical_source: :telemetry,
      data_source_id: "policy-questdb",
      dataset: "flight",
      priority: 0,
      metadata: %{
        dashboard_policy: %{
          circuit_breaker: %{failure_threshold: 2}
        }
      }
    }

    assert {:ok, _persisted_binding} = DataSources.persist_data_binding(binding)

    policy = SourceRegistry.execution_policy(source_request(), persisted?: true)

    assert policy.timeout_ms == :infinity
    assert policy.circuit_failure_threshold == 2
    assert policy.circuit_backoff_ms == 10_000
    assert policy.provenance.data_source_policy?
    assert policy.provenance.binding_policy?
    assert policy.provenance.data_source_id == "policy-questdb"
    assert policy.provenance.source_binding_id == "policy-flight-telemetry"
  end

  test "rejects malformed data source dashboard policy metadata" do
    data_source = %DataSource{
      data_source_id: "bad-policy-questdb",
      owner: :cadence,
      kind: :managed_tsdb,
      adapter: Cadence.Dashboards.Sources.Telemetry,
      organization_id: "org-dash-source",
      mission_id: "mission-dash-source",
      isolation_level: :mission_isolated,
      capabilities: %{range_scan?: true},
      metadata: %{
        dashboard_policy: %{
          execution: %{timeout_ms: -1},
          circuit_breaker: %{failure_threshold: 0, backoff_ms: -5}
        }
      }
    }

    assert {:error, %Ecto.Changeset{} = changeset} = DataSources.persist_data_source(data_source)

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
    persist_source("binding-policy-questdb", :mission_isolated)

    binding = %DataBinding{
      binding_id: "bad-policy-flight-telemetry",
      organization_id: "org-dash-source",
      mission_id: "mission-dash-source",
      realm: :flight,
      logical_source: :telemetry,
      data_source_id: "binding-policy-questdb",
      dataset: "flight",
      priority: 0,
      metadata: %{
        dashboard_policy: %{
          execution: "slow",
          circuit_breaker: %{backoff_ms: -1}
        }
      }
    }

    assert {:error, %Ecto.Changeset{} = changeset} = DataSources.persist_data_binding(binding)

    assert "dashboard_policy.execution must be a map" in metadata_errors(changeset)

    assert "dashboard_policy.circuit_breaker.backoff_ms must be a non-negative integer" in metadata_errors(
             changeset
           )
  end

  test "lists active telemetry data realms for dashboard controls" do
    persist_source("mission-questdb", :mission_isolated)

    assert {:ok, _binding} =
             DataSources.persist_data_binding(%DataBinding{
               binding_id: "mission-rehearsal-telemetry",
               organization_id: "org-dash-source",
               mission_id: "mission-dash-source",
               realm: :rehearsal,
               logical_source: :telemetry,
               data_source_id: "mission-questdb",
               dataset: "rehearsal",
               active_from: ~U[2026-01-01 00:00:00Z],
               active_to: ~U[2027-01-01 00:00:00Z],
               priority: 0
             })

    assert {:ok, _binding} =
             DataSources.persist_data_binding(%DataBinding{
               binding_id: "mission-replay-limits",
               organization_id: "org-dash-source",
               mission_id: "mission-dash-source",
               realm: :replay,
               logical_source: :limits,
               data_source_id: "mission-questdb",
               dataset: "replay-limits",
               priority: 0
             })

    assert {:ok, _binding} =
             DataSources.persist_data_binding(%DataBinding{
               binding_id: "mission-future-replay-telemetry",
               organization_id: "org-dash-source",
               mission_id: "mission-dash-source",
               realm: :replay,
               logical_source: :telemetry,
               data_source_id: "mission-questdb",
               dataset: "future-replay",
               active_from: ~U[2028-01-01 00:00:00Z],
               priority: 0
             })

    assert DataSources.list_data_realms("org-dash-source", "mission-dash-source",
             now: ~U[2026-06-01 00:00:00Z]
           ) == ["rehearsal"]
  end

  test "persisted registry honors binding activation windows" do
    persist_source("mission-questdb", :mission_isolated)

    assert {:ok, _binding} =
             DataSources.persist_data_binding(%DataBinding{
               binding_id: "mission-flight-telemetry",
               organization_id: "org-dash-source",
               mission_id: "mission-dash-source",
               realm: :flight,
               logical_source: :telemetry,
               data_source_id: "mission-questdb",
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

    assert resolved.binding.binding_id == "mission-flight-telemetry"
  end

  test "data realm listing falls back to flight when no telemetry bindings exist" do
    assert DataSources.list_data_realms("org-dash-source", "mission-dash-source") == ["flight"]
  end

  test "persisted registry selection prefers mission-specific bindings" do
    persist_source("org-questdb", :org_isolated)
    persist_source("mission-questdb", :mission_isolated)

    assert {:ok, _binding} =
             DataSources.persist_data_binding(%DataBinding{
               binding_id: "org-flight-telemetry",
               organization_id: "org-dash-source",
               realm: :flight,
               logical_source: :telemetry,
               data_source_id: "org-questdb",
               dataset: "org-flight",
               priority: 0
             })

    assert {:ok, _binding} =
             DataSources.persist_data_binding(%DataBinding{
               binding_id: "mission-flight-telemetry",
               organization_id: "org-dash-source",
               mission_id: "mission-dash-source",
               realm: :flight,
               logical_source: :telemetry,
               data_source_id: "mission-questdb",
               dataset: "mission-flight",
               priority: 0
             })

    assert {:ok, resolved} = DataSourceRegistry.resolve(source_request(), persisted?: true)
    assert resolved.binding.binding_id == "mission-flight-telemetry"
    assert resolved.data_source.data_source_id == "mission-questdb"
    assert resolved.data_source.isolation_level == :mission_isolated
    assert resolved.dataset == "mission-flight"

    assert {:ok, context_resolved} = DataSources.resolve_binding(source_request())
    assert context_resolved.binding.binding_id == "mission-flight-telemetry"
  end

  test "bootstraps default managed telemetry source idempotently" do
    assert %{data_source: data_source, data_binding: data_binding} =
             DataSources.ensure_default_managed_sources!()

    assert data_source.data_source_id == "managed_questdb_primary"
    assert data_source.kind == :managed_tsdb
    assert data_source.adapter == Cadence.Dashboards.Sources.Telemetry
    assert data_source.isolation_level == :shared
    assert data_source.metadata["bootstrap_default?"]

    assert data_binding.binding_id == "default_flight_telemetry"
    assert data_binding.realm == :flight
    assert data_binding.logical_source == :telemetry
    assert data_binding.data_source_id == "managed_questdb_primary"
    assert data_binding.dataset == "flight"
    assert data_binding.metadata["bootstrap_default?"]

    assert limits_source =
             Enum.find(
               DataSources.list_data_sources("org-dash-source", "mission-dash-source"),
               &(&1.data_source_id == "managed_limits_projection")
             )

    assert limits_source.kind == :projection
    assert limits_source.adapter == Cadence.Dashboards.Sources.Limits
    assert limits_source.capabilities["latest_state?"]
    assert limits_source.capabilities["definition_intervals?"]
    assert limits_source.metadata["bootstrap_default?"]

    assert limits_binding =
             Enum.find(
               DataSources.list_data_bindings("org-dash-source", "mission-dash-source"),
               &(&1.binding_id == "default_flight_limits")
             )

    assert limits_binding.realm == :flight
    assert limits_binding.logical_source == :limits
    assert limits_binding.data_source_id == "managed_limits_projection"
    assert limits_binding.dataset == "telemetry_latest_limit_states"
    assert limits_binding.metadata["bootstrap_default?"]

    assert events_source =
             Enum.find(
               DataSources.list_data_sources("org-dash-source", "mission-dash-source"),
               &(&1.data_source_id == "managed_events_projection")
             )

    assert events_source.kind == :projection
    assert events_source.adapter == Cadence.Dashboards.Sources.Events
    assert events_source.capabilities["contact_intervals?"]
    assert events_source.capabilities["mission_timeline?"]
    assert events_source.capabilities["source_health_transitions?"]
    assert events_source.metadata["bootstrap_default?"]

    assert events_binding =
             Enum.find(
               DataSources.list_data_bindings("org-dash-source", "mission-dash-source"),
               &(&1.binding_id == "default_flight_events")
             )

    assert events_binding.realm == :flight
    assert events_binding.logical_source == :events
    assert events_binding.data_source_id == "managed_events_projection"
    assert events_binding.dataset == "mission_events"
    assert events_binding.metadata["bootstrap_default?"]

    assert %{data_source: second_source, data_binding: second_binding} =
             DataSources.ensure_default_managed_sources!()

    assert second_source.data_source_id == data_source.data_source_id
    assert second_binding.binding_id == data_binding.binding_id
  end

  test "persisted registry resolves from bootstrapped defaults" do
    _defaults = DataSources.ensure_default_managed_sources!()

    assert {:ok, resolved} = DataSourceRegistry.resolve(source_request(), persisted?: true)
    assert resolved.binding.binding_id == "default_flight_telemetry"
    assert resolved.data_source.data_source_id == "managed_questdb_primary"
    assert resolved.realm == :flight
    assert resolved.dataset == "flight"

    assert {:ok, limits_resolved} =
             DataSourceRegistry.resolve(
               source_request(logical_source: :limits, sampling: %{mode: :latest_state}),
               persisted?: true
             )

    assert limits_resolved.binding.binding_id == "default_flight_limits"
    assert limits_resolved.data_source.data_source_id == "managed_limits_projection"
    assert limits_resolved.realm == :flight
    assert limits_resolved.dataset == "telemetry_latest_limit_states"

    assert {:ok, events_resolved} =
             DataSourceRegistry.resolve(
               source_request(logical_source: :events, sampling: %{mode: :event_history}),
               persisted?: true
             )

    assert events_resolved.binding.binding_id == "default_flight_events"
    assert events_resolved.data_source.data_source_id == "managed_events_projection"
    assert events_resolved.realm == :flight
    assert events_resolved.dataset == "mission_events"
  end

  test "persisted registry returns missing binding warning when scoped rows exist but no binding matches" do
    persist_source("rehearsal-questdb", :mission_isolated)

    assert {:error, warning} =
             DataSourceRegistry.resolve(
               source_request(data_context: %{realm: :rehearsal}),
               persisted?: true
             )

    assert warning.code == :missing_source_binding
    assert warning.details.realm == :rehearsal
  end

  test "persisting a data binding invalidates matching dashboard runtime caches only" do
    cache = start_supervised!({RuntimeCache, name: nil})
    use_dashboard_runtime_cache!(cache)
    persist_source("mission-questdb", :mission_isolated)
    persist_limits_source("mission-limits")

    matching_key =
      dashboard_source_result_key(:telemetry,
        binding_id: "mission-flight-telemetry",
        data_source_id: "mission-questdb",
        realm: :flight,
        dataset: "mission-flight"
      )

    matching_frame_key = dashboard_frame_key(matching_key, "frame-mission-flight")

    other_realm_key =
      dashboard_source_result_key(:telemetry,
        binding_id: "mission-rehearsal-telemetry",
        data_source_id: "mission-questdb",
        realm: :rehearsal,
        dataset: "mission-rehearsal"
      )

    other_realm_frame_key = dashboard_frame_key(other_realm_key, "frame-rehearsal")

    limits_key =
      dashboard_source_result_key(:limits,
        binding_id: "mission-flight-limits",
        data_source_id: "mission-limits",
        realm: :flight,
        dataset: "telemetry_latest_limit_states"
      )

    limits_frame_key = dashboard_frame_key(limits_key, "frame-limits")

    matching_result = dashboard_source_result(matching_key)
    matching_frames = dashboard_frames(:telemetry, "frame-mission-flight")
    other_realm_result = dashboard_source_result(other_realm_key)
    other_realm_frames = dashboard_frames(:telemetry, "frame-rehearsal")
    limits_result = dashboard_source_result(limits_key)
    limits_frames = dashboard_frames(:limits, "frame-limits")

    assert :ok = RuntimeCache.put_source_result(matching_key, matching_result, cache)
    assert :ok = RuntimeCache.put_frame(matching_frame_key, matching_frames, cache)
    assert :ok = RuntimeCache.put_source_result(other_realm_key, other_realm_result, cache)
    assert :ok = RuntimeCache.put_frame(other_realm_frame_key, other_realm_frames, cache)
    assert :ok = RuntimeCache.put_source_result(limits_key, limits_result, cache)
    assert :ok = RuntimeCache.put_frame(limits_frame_key, limits_frames, cache)

    assert {:ok, binding} =
             DataSources.persist_data_binding(%DataBinding{
               binding_id: "mission-flight-telemetry",
               organization_id: "org-dash-source",
               mission_id: "mission-dash-source",
               realm: :flight,
               logical_source: :telemetry,
               data_source_id: "mission-questdb",
               dataset: "mission-flight",
               priority: 0,
               metadata: %{reason: :updated_primary}
             })

    assert RuntimeCache.get_source_result(matching_key, cache) == :miss
    assert RuntimeCache.get_frame(matching_frame_key, cache) == :miss
    assert {:ok, ^other_realm_result} = RuntimeCache.get_source_result(other_realm_key, cache)
    assert {:ok, ^other_realm_frames} = RuntimeCache.get_frame(other_realm_frame_key, cache)
    assert {:ok, ^limits_result} = RuntimeCache.get_source_result(limits_key, cache)
    assert {:ok, ^limits_frames} = RuntimeCache.get_frame(limits_frame_key, cache)

    assert [event] = DataSources.list_data_binding_events("mission-flight-telemetry")
    assert event.event_type == :registered
    assert binding.current_event_id == event.data_binding_event_id
  end

  test "persisting a data source invalidates all dashboard caches for that source id" do
    cache = start_supervised!({RuntimeCache, name: nil})
    use_dashboard_runtime_cache!(cache)
    persist_source("mission-questdb", :mission_isolated)
    persist_limits_source("mission-limits")

    flight_key =
      dashboard_source_result_key(:telemetry,
        binding_id: "mission-flight-telemetry",
        data_source_id: "mission-questdb",
        realm: :flight,
        dataset: "mission-flight"
      )

    flight_frame_key = dashboard_frame_key(flight_key, "frame-flight")

    rehearsal_key =
      dashboard_source_result_key(:telemetry,
        binding_id: "mission-rehearsal-telemetry",
        data_source_id: "mission-questdb",
        realm: :rehearsal,
        dataset: "mission-rehearsal"
      )

    rehearsal_frame_key = dashboard_frame_key(rehearsal_key, "frame-rehearsal")

    limits_key =
      dashboard_source_result_key(:limits,
        binding_id: "mission-flight-limits",
        data_source_id: "mission-limits",
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
             DataSources.persist_data_source(%DataSource{
               data_source_id: "mission-questdb",
               owner: :cadence,
               kind: :managed_tsdb,
               adapter: Cadence.Dashboards.Sources.Telemetry,
               organization_id: "org-dash-source",
               mission_id: "mission-dash-source",
               isolation_level: :mission_isolated,
               capabilities: %{range_scan?: true, watermarks?: true},
               metadata: %{storage: :questdb, reason: :updated_capabilities}
             })

    assert RuntimeCache.get_source_result(flight_key, cache) == :miss
    assert RuntimeCache.get_frame(flight_frame_key, cache) == :miss
    assert RuntimeCache.get_source_result(rehearsal_key, cache) == :miss
    assert RuntimeCache.get_frame(rehearsal_frame_key, cache) == :miss
    assert {:ok, ^limits_result} = RuntimeCache.get_source_result(limits_key, cache)
    assert {:ok, ^limits_frames} = RuntimeCache.get_frame(limits_frame_key, cache)
  end
end
