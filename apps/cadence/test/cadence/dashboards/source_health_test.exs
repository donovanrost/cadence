defmodule Cadence.Dashboards.SourceHealthTest do
  use Cadence.RuntimeCase, async: false

  alias Cadence.Dashboards.{
    DataBinding,
    DataSource,
    DataSources,
    EvidenceRef,
    Frame,
    PlannedSourceRequest,
    RuntimeCache,
    RuntimeCacheKey,
    SourceFacts,
    SourceHealth,
    SourceHealthEvent,
    SourceRegistry,
    SourceResult,
    SourceResultPreflight
  }

  alias Cadence.Telemetry.Sample

  @organization_id "org-source-health"
  @mission_id "mission-source-health"
  @source_identity %{
    organization_id: @organization_id,
    mission_id: @mission_id,
    logical_source: :telemetry,
    data_source_id: "flight-questdb",
    source_binding_id: "flight-telemetry",
    realm: :flight,
    dataset: "flight"
  }

  setup do
    persist_mission_scope(@organization_id, @mission_id)
    :ok
  end

  test "records source health transitions and maintains latest status projection" do
    assert {:ok, unavailable_event, unavailable_status} =
             @source_identity
             |> Map.merge(%{
               source_health: :unavailable,
               reason: :timeout,
               observed_at: ~U[2026-06-21 12:00:00Z],
               payload: %{probe_id: "probe-1"}
             })
             |> SourceHealth.record_source_health(invalidate_runtime_cache?: false)

    assert unavailable_event.event_type == :unavailable
    assert unavailable_event.previous_source_health == nil
    assert unavailable_status.source_health == :unavailable
    assert unavailable_status.transition_count == 1
    assert unavailable_status.observed_at == ~U[2026-06-21 12:00:00.000000Z]
    assert unavailable_status.last_seen_at == ~U[2026-06-21 12:00:00.000000Z]

    assert {:ok, :unchanged, unchanged_status} =
             @source_identity
             |> Map.merge(%{
               source_health: :unavailable,
               reason: :timeout,
               observed_at: ~U[2026-06-21 12:01:00Z],
               payload: %{probe_id: "probe-2"}
             })
             |> SourceHealth.record_source_health(invalidate_runtime_cache?: false)

    assert unchanged_status.source_health_event_id == unavailable_event.source_health_event_id
    assert unchanged_status.transition_count == 1
    assert unchanged_status.observed_at == ~U[2026-06-21 12:00:00.000000Z]
    assert unchanged_status.last_seen_at == ~U[2026-06-21 12:01:00.000000Z]

    assert {:ok, recovered_event, recovered_status} =
             @source_identity
             |> Map.merge(%{
               source_health: :healthy,
               reason: :source_recovered,
               observed_at: ~U[2026-06-21 12:02:00Z],
               payload: %{probe_id: "probe-3"}
             })
             |> SourceHealth.record_source_health(invalidate_runtime_cache?: false)

    assert recovered_event.event_type == :recovered
    assert recovered_event.previous_source_health == :unavailable
    assert recovered_status.source_health == :healthy
    assert recovered_status.previous_source_health == :unavailable
    assert recovered_status.transition_count == 2

    assert [latest_status] =
             SourceHealth.list_source_health_statuses(@organization_id, @mission_id)

    assert latest_status.source_health == :healthy
    assert latest_status.transition_count == 2

    assert [latest_event, first_event] =
             SourceHealth.list_source_health_events(@organization_id, @mission_id)

    assert latest_event.source_health == :healthy
    assert first_event.source_health == :unavailable

    assert [operational_event] =
             Cadence.OperationalEvents.list_events(
               @organization_id,
               @mission_id,
               category: :data_source,
               kind: :source_health_unavailable,
               source_record_kind: :source_health_event,
               source_record_id: unavailable_event.source_health_event_id
             )

    assert operational_event.event_id ==
             "operational_event:source_health_event:#{unavailable_event.source_health_event_id}"

    assert operational_event.occurred_at == ~U[2026-06-21 12:00:00.000000Z]
    assert operational_event.effective_at == ~U[2026-06-21 12:00:00.000000Z]
    assert operational_event.severity == :error
    assert operational_event.subject == %{kind: :data_source, id: "flight-questdb"}
    assert operational_event.causality.source_record_kind == :source_health_event

    assert operational_event.causality.source_record_id ==
             unavailable_event.source_health_event_id

    assert operational_event.payload["source_health"] == "unavailable"
    assert operational_event.payload["reason"] == "timeout"
    assert operational_event.payload["logical_source"] == "telemetry"
    assert operational_event.current["source_health"] == "unavailable"
  end

  test "lists source health events by source identity and observed-time window" do
    assert {:ok, _event, _status} =
             @source_identity
             |> Map.merge(%{
               source_health: :degraded,
               reason: :source_probe_failed,
               observed_at: ~U[2026-06-21 12:00:00Z]
             })
             |> SourceHealth.record_source_health(invalidate_runtime_cache?: false)

    assert {:ok, _event, _status} =
             @source_identity
             |> Map.merge(%{
               source_health: :healthy,
               reason: :source_recovered,
               observed_at: ~U[2026-06-21 12:05:00Z]
             })
             |> SourceHealth.record_source_health(invalidate_runtime_cache?: false)

    assert {:ok, _event, _status} =
             @source_identity
             |> Map.merge(%{
               data_source_id: "rehearsal-questdb",
               source_binding_id: "rehearsal-telemetry",
               realm: :rehearsal,
               dataset: "rehearsal",
               source_health: :unavailable,
               reason: :source_probe_failed,
               observed_at: ~U[2026-06-21 12:06:00Z]
             })
             |> SourceHealth.record_source_health(invalidate_runtime_cache?: false)

    assert [event] =
             SourceHealth.list_source_health_events(@organization_id, @mission_id,
               logical_source: :telemetry,
               data_source_id: "flight-questdb",
               source_binding_id: "flight-telemetry",
               realm: :flight,
               dataset: "flight",
               from_observed_at: ~U[2026-06-21 12:04:00Z],
               to_observed_at: ~U[2026-06-21 12:06:00Z],
               order: :asc
             )

    assert event.source_health == :healthy
    assert event.observed_at == ~U[2026-06-21 12:05:00.000000Z]
  end

  test "recorded transitions invalidate matching live source and frame cache entries" do
    cache = start_supervised!({RuntimeCache, name: nil})
    source_key = source_result_key()
    frame_key = frame_key(source_key)
    source_result = %SourceResult{request_id: "source-request-health"}
    frames = [%Frame{frame_id: "frame-health", source: :telemetry, shape: :scalar}]

    assert :ok = RuntimeCache.put_source_result(source_key, source_result, cache)
    assert :ok = RuntimeCache.put_frame(frame_key, frames, cache)

    assert {:ok, _event, _status} =
             @source_identity
             |> Map.merge(%{
               source_health: :degraded,
               reason: :source_probe_failed,
               observed_at: ~U[2026-06-21 13:00:00Z]
             })
             |> SourceHealth.record_source_health(runtime_cache: cache)

    assert RuntimeCache.get_source_result(source_key, cache) == :miss
    assert RuntimeCache.get_frame(frame_key, cache) == :miss
  end

  test "source registry records unavailable and recovered source health transitions" do
    failing_opts = source_registry_opts(:error_result)

    assert %SourceResult{warnings: [%{code: :source_unavailable}]} =
             SourceRegistry.resolve(source_request(), failing_opts)

    assert [unavailable_status] =
             SourceHealth.list_source_health_statuses(@organization_id, @mission_id)

    assert unavailable_status.source_health == :unavailable
    assert unavailable_status.reason == :source_unavailable

    ok_opts = source_registry_opts(:ok)

    assert %SourceResult{warnings: []} = SourceRegistry.resolve(source_request(), ok_opts)

    assert [recovered_status] =
             SourceHealth.list_source_health_statuses(@organization_id, @mission_id)

    assert recovered_status.source_health == :healthy
    assert recovered_status.previous_source_health == :unavailable
    assert recovered_status.transition_count == 2

    assert [recovered_event, unavailable_event] =
             SourceHealth.list_source_health_events(@organization_id, @mission_id)

    assert recovered_event.event_type == :recovered
    assert unavailable_event.event_type == :unavailable
  end

  test "telemetry history query failures record unavailable source health transitions" do
    history_fun = fn _organization_id, _mission_id, _point_id, _opts ->
      {:error, {:http_error, 400, %{"error" => "Invalid column: observation_identity_id"}}}
    end

    opts = telemetry_registry_opts(history_fun: history_fun)
    request = source_request(sampling: %{mode: :raw_series})

    assert %SourceResult{warnings: [%{code: :source_unavailable} = warning]} =
             SourceRegistry.resolve(request, opts)

    assert warning.details.source_query_kind == :bounded_history
    assert warning.details.source_empty_reason == :source_query_failed

    assert [unavailable_status] =
             SourceHealth.list_source_health_statuses(@organization_id, @mission_id,
               logical_source: :telemetry,
               data_source_id: "flight-questdb",
               source_binding_id: "flight-telemetry",
               realm: :flight,
               dataset: "flight"
             )

    assert unavailable_status.source_health == :unavailable
    assert unavailable_status.reason == :source_unavailable
    assert unavailable_status.payload["warning_codes"] == ["source_unavailable"]

    assert [unavailable_event] =
             SourceHealth.list_source_health_events(@organization_id, @mission_id,
               logical_source: :telemetry,
               data_source_id: "flight-questdb",
               source_binding_id: "flight-telemetry",
               realm: :flight,
               dataset: "flight"
             )

    assert unavailable_event.event_type == :unavailable
    assert unavailable_event.source_health == :unavailable
    assert unavailable_event.payload["warning_codes"] == ["source_unavailable"]
  end

  test "source registry facts use durable health for source-result preflight and recovery" do
    request = source_request()
    opts = telemetry_registry_opts()

    assert {:ok, %SourceFacts{} = missing_facts} = SourceRegistry.facts(request, opts)
    assert missing_facts.source_health == :unknown
    assert missing_facts.meta.source_health_freshness == :missing
    assert missing_facts.meta.source_health_reason == :source_health_missing

    assert {:ok, _event, _status} =
             @source_identity
             |> Map.merge(%{
               source_health: :healthy,
               reason: :source_probe_succeeded,
               observed_at: ~U[2026-06-21 13:59:30Z]
             })
             |> SourceHealth.record_source_health(invalidate_runtime_cache?: false)

    assert {:ok, %SourceFacts{} = healthy_facts} = SourceRegistry.facts(request, opts)
    assert healthy_facts.source_health == :healthy
    assert healthy_facts.meta.source_health_freshness == :fresh

    cache_key = source_result_key(request, healthy_facts)

    cached_result = %SourceResult{
      request_id: request.request_id,
      watermarks: [healthy_facts.watermark]
    }

    assert %SourceResultPreflight{status: :usable, reasons: []} =
             SourceResultPreflight.evaluate(cache_key, cached_result, cache_key,
               source_health: healthy_facts.source_health
             )

    assert {:ok, _event, _status} =
             @source_identity
             |> Map.merge(%{
               source_health: :unavailable,
               reason: :source_probe_failed,
               observed_at: ~U[2026-06-21 14:00:00Z]
             })
             |> SourceHealth.record_source_health(invalidate_runtime_cache?: false)

    assert {:ok, %SourceFacts{} = unavailable_facts} = SourceRegistry.facts(request, opts)
    assert unavailable_facts.source_health == :unavailable
    assert unavailable_facts.meta.durable_source_health?
    assert unavailable_facts.meta.source_health_reason == :source_probe_failed

    unavailable_key = source_result_key(request, unavailable_facts)

    assert %SourceResultPreflight{status: :stale, reasons: reasons} =
             SourceResultPreflight.evaluate(cache_key, cached_result, unavailable_key,
               source_health: unavailable_facts.source_health
             )

    assert :source_degraded in reasons

    assert %SourceResult{warnings: [], frames: [%Frame{} = frame]} =
             result = SourceRegistry.resolve(request, opts)

    assert {:ok, %SourceFacts{} = recovered_facts} = SourceRegistry.facts(request, opts)
    assert recovered_facts.source_health == :healthy
    assert recovered_facts.meta.durable_source_health?
    assert recovered_facts.meta.source_health_reason == :source_recovered

    assert result.meta.source_health == :healthy
    assert result.meta.durable_source_health?
    assert result.meta.source_health_reason == :source_recovered

    assert %EvidenceRef{
             kind: :source_health_event,
             id: result.meta.source_health_event_id,
             observed_at: result.meta.source_health_observed_at,
             source: :events,
             confidence: :direct
           } in frame.meta.evidence

    recovered_key = source_result_key(request, recovered_facts)

    assert %SourceResultPreflight{status: :usable, reasons: []} =
             SourceResultPreflight.evaluate(cache_key, cached_result, recovered_key,
               source_health: recovered_facts.source_health
             )
  end

  test "source registry facts treat stale durable health as unknown" do
    request = source_request()

    opts =
      telemetry_registry_opts(
        now: ~U[2026-06-21 14:02:00Z],
        source_health_freshness: [default_max_age_ms: 60_000]
      )

    assert {:ok, _event, _status} =
             @source_identity
             |> Map.merge(%{
               source_health: :healthy,
               reason: :source_probe_succeeded,
               observed_at: ~U[2026-06-21 14:00:00Z]
             })
             |> SourceHealth.record_source_health(invalidate_runtime_cache?: false)

    assert {:ok, %SourceFacts{} = stale_facts} = SourceRegistry.facts(request, opts)
    assert stale_facts.source_health == :unknown
    assert stale_facts.meta.durable_source_health?
    assert stale_facts.meta.source_health_freshness == :stale
    assert stale_facts.meta.source_health_reason == :source_health_stale
    assert stale_facts.meta.source_health_raw_source_health == :healthy
    assert stale_facts.meta.source_health_raw_reason == :source_probe_succeeded
    assert stale_facts.meta.source_health_age_ms == 120_000
    assert stale_facts.meta.source_health_max_age_ms == 60_000

    cache_key =
      source_result_key(request, %SourceFacts{
        source_binding: data_binding(),
        data_source: data_source(),
        source_health: :healthy
      })

    current_key = source_result_key(request, stale_facts)

    assert %SourceResultPreflight{status: :stale, reasons: reasons} =
             SourceResultPreflight.evaluate(cache_key, %SourceResult{}, current_key,
               source_health: stale_facts.source_health
             )

    assert :source_degraded in reasons
  end

  test "source registry facts keep durable health isolated by source identity" do
    rehearsal_identity =
      @source_identity
      |> Map.merge(%{
        data_source_id: "rehearsal-questdb",
        source_binding_id: "rehearsal-telemetry",
        realm: :rehearsal,
        dataset: "rehearsal"
      })

    assert {:ok, _event, _status} =
             rehearsal_identity
             |> Map.merge(%{
               source_health: :unavailable,
               reason: :rehearsal_source_failed,
               observed_at: ~U[2026-06-21 15:00:00Z]
             })
             |> SourceHealth.record_source_health(invalidate_runtime_cache?: false)

    assert {:ok, %SourceFacts{} = flight_facts} =
             SourceRegistry.facts(source_request(), telemetry_registry_opts())

    assert flight_facts.source_health == :unknown
    assert flight_facts.meta.source_health_freshness == :missing
    assert flight_facts.meta.source_health_reason == :source_health_missing
    refute Map.get(flight_facts.meta, :durable_source_health?)

    rehearsal_request = source_request(data_context: %{realm: :rehearsal})

    assert {:ok, %SourceFacts{} = rehearsal_facts} =
             SourceRegistry.facts(
               rehearsal_request,
               telemetry_registry_opts(realm: :rehearsal, data_source_id: "rehearsal-questdb")
             )

    assert rehearsal_facts.source_health == :unavailable
    assert rehearsal_facts.meta.durable_source_health?
    assert rehearsal_facts.meta.source_health_reason == :rehearsal_source_failed
  end

  test "source registry facts keep durable health isolated by replay run" do
    replay_identity =
      @source_identity
      |> Map.merge(%{
        data_source_id: "replay-questdb",
        source_binding_id: "replay-telemetry",
        realm: :replay,
        replay_run_id: "replay-run-1",
        dataset: "replay"
      })

    other_replay_identity = Map.put(replay_identity, :replay_run_id, "replay-run-2")

    assert {:ok, event, status} =
             replay_identity
             |> Map.merge(%{
               source_health: :unavailable,
               reason: :replay_source_failed,
               observed_at: ~U[2026-06-21 15:00:00Z]
             })
             |> SourceHealth.record_source_health(invalidate_runtime_cache?: false)

    assert event.replay_run_id == "replay-run-1"
    assert status.replay_run_id == "replay-run-1"

    assert {:ok, _event, _status} =
             other_replay_identity
             |> Map.merge(%{
               source_health: :healthy,
               reason: :other_replay_source_ok,
               observed_at: ~U[2026-06-21 15:00:00Z]
             })
             |> SourceHealth.record_source_health(invalidate_runtime_cache?: false)

    assert [listed_status] =
             SourceHealth.list_source_health_statuses(@organization_id, @mission_id,
               realm: :replay,
               replay_run_id: "replay-run-1"
             )

    assert listed_status.source_health == :unavailable
    assert listed_status.replay_run_id == "replay-run-1"

    assert [listed_event] =
             SourceHealth.list_source_health_events(@organization_id, @mission_id,
               realm: :replay,
               replay_run_id: "replay-run-1"
             )

    assert listed_event.source_health == :unavailable
    assert listed_event.replay_run_id == "replay-run-1"

    replay_request =
      source_request(
        data_context: %{realm: :replay, replay_run_id: "replay-run-1"},
        time_context: %{mode: :replay_run, replay_run_id: "replay-run-1"}
      )

    assert {:ok, %SourceFacts{} = replay_facts} =
             SourceRegistry.facts(
               replay_request,
               telemetry_registry_opts(realm: :replay, data_source_id: "replay-questdb")
             )

    assert replay_facts.source_health == :unavailable
    assert replay_facts.meta.durable_source_health?
    assert replay_facts.meta.source_health_reason == :replay_source_failed

    other_replay_request =
      source_request(
        data_context: %{realm: :replay, replay_run_id: "replay-run-2"},
        time_context: %{mode: :replay_run, replay_run_id: "replay-run-2"}
      )

    assert {:ok, %SourceFacts{} = other_replay_facts} =
             SourceRegistry.facts(
               other_replay_request,
               telemetry_registry_opts(realm: :replay, data_source_id: "replay-questdb")
             )

    assert other_replay_facts.source_health == :healthy
    assert other_replay_facts.meta.source_health_reason == :other_replay_source_ok
  end

  test "persisted source registry loads only candidate replay health while preserving source fallback" do
    data_source_id = "persisted-replay-questdb"
    source_binding_id = "persisted-replay-telemetry"
    dataset = "persisted-replay"

    assert {:ok, _data_source} =
             DataSources.persist_data_source(
               data_source(Cadence.Dashboards.Sources.Telemetry, data_source_id)
             )

    assert {:ok, _binding} =
             DataSources.persist_data_binding(%DataBinding{
               binding_id: source_binding_id,
               organization_id: @organization_id,
               mission_id: @mission_id,
               realm: :replay,
               logical_source: :telemetry,
               data_source_id: data_source_id,
               dataset: dataset
             })

    replay_identity =
      @source_identity
      |> Map.merge(%{
        data_source_id: data_source_id,
        source_binding_id: source_binding_id,
        realm: :replay,
        replay_run_id: "replay-run-1",
        dataset: dataset
      })

    assert {:ok, _event, _status} =
             replay_identity
             |> Map.merge(%{
               source_health: :degraded,
               reason: :replay_source_degraded,
               observed_at: ~U[2026-06-21 15:00:00Z]
             })
             |> SourceHealth.record_source_health(invalidate_runtime_cache?: false)

    assert {:ok, _event, _status} =
             replay_identity
             |> Map.put(:replay_run_id, "replay-run-2")
             |> Map.merge(%{
               source_health: :healthy,
               reason: :other_replay_source_ok,
               observed_at: ~U[2026-06-21 15:00:00Z]
             })
             |> SourceHealth.record_source_health(invalidate_runtime_cache?: false)

    assert {:ok, _event, _status} =
             replay_identity
             |> Map.merge(%{
               source_binding_id: nil,
               realm: nil,
               replay_run_id: nil,
               dataset: nil,
               source_health: :degraded,
               reason: :source_probe_failed,
               observed_at: ~U[2026-06-21 15:00:00Z]
             })
             |> SourceHealth.record_source_health(invalidate_runtime_cache?: false)

    source_level_key =
      replay_identity
      |> Map.merge(%{source_binding_id: nil, realm: nil, replay_run_id: nil, dataset: nil})
      |> SourceHealthEvent.source_health_key()

    assert {:ok, source_level_status} = SourceHealth.fetch_source_health_status(source_level_key)
    assert source_level_status.source_health == :degraded

    assert {:ok, %SourceFacts{} = replay_facts} =
             SourceRegistry.facts(
               source_request(
                 data_context: %{
                   realm: :replay,
                   data_source_id: data_source_id,
                   source_binding_id: source_binding_id,
                   replay_run_id: "replay-run-1",
                   dataset: dataset
                 },
                 time_context: %{mode: :replay_run, replay_run_id: "replay-run-1"}
               ),
               persisted_replay_registry_opts()
             )

    assert replay_facts.source_health == :degraded
    assert replay_facts.meta.durable_source_health?
    assert replay_facts.meta.source_health_reason == :replay_source_degraded

    assert {:ok, %SourceFacts{} = fallback_facts} =
             SourceRegistry.facts(
               source_request(
                 data_context: %{
                   realm: :replay,
                   data_source_id: data_source_id,
                   source_binding_id: source_binding_id,
                   replay_run_id: "replay-run-3",
                   dataset: dataset
                 },
                 time_context: %{mode: :replay_run, replay_run_id: "replay-run-3"}
               ),
               persisted_replay_registry_opts()
             )

    assert fallback_facts.source_health == :degraded
    assert fallback_facts.meta.durable_source_health?
    assert fallback_facts.meta.source_health_reason == :source_probe_failed
  end

  defp source_result_key do
    source_result_key(source_request(), %SourceFacts{
      source_binding: data_binding(),
      data_source: data_source()
    })
  end

  defp source_result_key(%PlannedSourceRequest{} = request, %SourceFacts{} = facts) do
    SourceFacts.runtime_cache_key(request, facts,
      cache_policy: :live,
      freshness_policy: %{stale_after_ms: 5_000}
    )
  end

  defp frame_key(%RuntimeCacheKey{} = source_key) do
    RuntimeCacheKey.frame(source_key,
      placement_id: "placement-health",
      placement_size: %{width_px: 320, height_px: 120},
      display: %{density: :normal},
      frame_shape: :scalar
    )
  end

  defp source_request(overrides \\ []) do
    attrs = %{
      request_id: "source-request-health",
      organization_id: @organization_id,
      mission_id: @mission_id,
      logical_source: :telemetry,
      observables: ["HK.counter"],
      data_context: %{realm: :flight},
      sampling: %{mode: :latest}
    }

    struct!(PlannedSourceRequest, Keyword.merge(Map.to_list(attrs), overrides))
  end

  defp source_registry_opts(mode) do
    [
      source_health_events?: true,
      invalidate_runtime_cache?: false,
      source_circuit_breaker?: false,
      data_sources: [data_source(Cadence.Support.DashboardSourceTestAdapter)],
      data_bindings: [data_binding()],
      source_opts: %{
        telemetry: [
          test_pid: self(),
          mode: mode
        ]
      }
    ]
  end

  defp telemetry_registry_opts(opts \\ []) do
    realm = Keyword.get(opts, :realm, :flight)
    data_source_id = Keyword.get(opts, :data_source_id, "#{realm}-questdb")

    [
      source_health_events?: true,
      invalidate_runtime_cache?: false,
      source_circuit_breaker?: false,
      now: Keyword.get(opts, :now, ~U[2026-06-21 14:00:30Z]),
      source_health_freshness:
        Keyword.get(opts, :source_health_freshness, default_max_age_ms: 60_000),
      data_sources: [data_source(Cadence.Dashboards.Sources.Telemetry, data_source_id)],
      data_bindings: [data_binding(realm, data_source_id)],
      source_opts: %{
        telemetry: [
          latest_fun: Keyword.get(opts, :latest_fun, &telemetry_sample/4),
          history_fun: Keyword.get(opts, :history_fun, &default_history/4),
          watermark_fun: Keyword.get(opts, :watermark_fun, &best_effort_watermark/4)
        ]
      }
    ]
  end

  defp default_history(_organization_id, _mission_id, _point_id, _opts), do: []

  defp persisted_replay_registry_opts do
    [
      persisted?: true,
      source_health_events?: true,
      invalidate_runtime_cache?: false,
      source_circuit_breaker?: false,
      now: ~U[2026-06-21 15:00:30Z],
      source_health_freshness: [default_max_age_ms: 60_000],
      source_opts: %{
        telemetry: [
          latest_fun: &telemetry_sample/4,
          watermark_fun: &best_effort_watermark/4
        ]
      }
    ]
  end

  defp data_binding, do: data_binding(:flight, "flight-questdb")

  defp data_binding(realm, data_source_id) do
    %DataBinding{
      binding_id: "#{realm}-telemetry",
      organization_id: @organization_id,
      mission_id: @mission_id,
      realm: realm,
      logical_source: :telemetry,
      data_source_id: data_source_id,
      dataset: Atom.to_string(realm)
    }
  end

  defp data_source(
         adapter \\ Cadence.Dashboards.Sources.Telemetry,
         data_source_id \\ "flight-questdb"
       ) do
    %DataSource{
      data_source_id: data_source_id,
      adapter: adapter,
      organization_id: @organization_id,
      mission_id: @mission_id,
      capabilities: %{latest?: true, range_scan?: true, watermarks?: true}
    }
  end

  defp telemetry_sample(_organization_id, mission_id, point_id, _opts) do
    %Sample{
      sample_id: "sample-source-health",
      mission_id: mission_id,
      spacecraft_id: "sc_001",
      point_id: point_id,
      point_name: point_id,
      packet_definition_id: "packet-def-source-health",
      packet_definition_version: 1,
      packet_id: "packet-source-health",
      evidence_id: "evidence-source-health",
      raw_value: 12.25,
      engineering_value: 12.25,
      quality_state: :good,
      generation_time: ~U[2026-06-21 13:59:59Z],
      receipt_time: ~U[2026-06-21 14:00:00Z],
      provenance: %{}
    }
  end

  defp best_effort_watermark(_organization_id, _mission_id, _point_id, _opts) do
    {:ok,
     %{
       complete_through: ~U[2026-06-21 14:00:00Z],
       latest_receipt_time: ~U[2026-06-21 14:00:00Z],
       retention_starts_at: ~U[2026-06-21 13:00:00Z],
       sample_count: 1,
       confidence: :best_effort
     }}
  end
end
