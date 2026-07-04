defmodule Cadence.Telemetry.RuntimeHealthTest do
  use ExUnit.Case, async: true

  alias Cadence.Dashboards.RuntimeInvalidation
  alias Cadence.Dashboards.RuntimeInvalidation.Event
  alias Cadence.Ingress.RawEvidence
  alias Cadence.Telemetry.Profiler
  alias Cadence.Telemetry.RuntimeHealth

  test "collects runtime scheduler and dispatcher telemetry in memory" do
    server = start_runtime_health!(recent_limit: 3)

    emit([:cadence, :contacts, :scheduler, :notification], %{count: 1}, %{
      mission_id: "mission-health",
      contact_kind: :scheduled
    })

    emit([:cadence, :contacts, :scheduler, :safety_reconcile], %{count: 1}, %{
      mission_id: "mission-health",
      reason: :safety
    })

    emit([:cadence, :commanding, :lane_dispatcher, :dispatch_attempt], %{count: 1}, %{
      mission_id: "mission-health",
      queue_lane_key: "lane-a",
      reason: :notification
    })

    emit([:cadence, :commanding, :lane_dispatcher, :stale_timer], %{count: 1}, %{
      mission_id: "mission-health",
      queue_lane_key: "lane-a"
    })

    emit([:cadence, :jobs, :dispatcher, :safety_dispatch_scheduled], %{count: 1}, %{
      reason: :safety
    })

    snapshot = wait_for_total_events(server, 5)

    assert snapshot.total_events == 5
    assert snapshot.stale_timer_count == 1
    assert snapshot.safety_activity_count == 2
    assert length(snapshot.recent_events) == 3

    assert snapshot.sources.contacts_scheduler.total_events == 2
    assert snapshot.sources.contacts_scheduler.events.notification == 1
    assert snapshot.sources.contacts_scheduler.events.safety_reconcile == 1
    assert snapshot.sources.contacts_scheduler.reasons.safety == 1

    assert snapshot.sources.commanding_lane_dispatcher.total_events == 2
    assert snapshot.sources.commanding_lane_dispatcher.events.dispatch_attempt == 1
    assert snapshot.sources.commanding_lane_dispatcher.events.stale_timer == 1
    assert snapshot.sources.commanding_lane_dispatcher.reasons.notification == 1

    assert snapshot.sources.jobs_dispatcher.total_events == 1
    assert snapshot.sources.jobs_dispatcher.events.safety_dispatch_scheduled == 1
    assert snapshot.sources.jobs_dispatcher.reasons.safety == 1

    assert Enum.map(snapshot.recent_events, & &1.event) == [
             :dispatch_attempt,
             :stale_timer,
             :safety_dispatch_scheduled
           ]
  end

  test "reset clears the process-local runtime health view" do
    server = start_runtime_health!()

    emit([:cadence, :commanding, :verifier_scheduler, :timer_fired], %{count: 1}, %{
      mission_id: "mission-health"
    })

    assert wait_for_total_events(server, 1).total_events == 1

    assert :ok = RuntimeHealth.reset(server)

    snapshot = RuntimeHealth.snapshot(server)
    assert snapshot.total_events == 0
    assert snapshot.stale_timer_count == 0
    assert snapshot.safety_activity_count == 0
    assert snapshot.sources == %{}
    assert snapshot.recent_events == []
  end

  test "subscribes to the data-plane scheduler and dispatcher events" do
    assert [:cadence, :contacts, :scheduler, :notification] in RuntimeHealth.events()
    assert [:cadence, :commanding, :dispatcher, :reconcile] in RuntimeHealth.events()
    assert [:cadence, :commanding, :lane_dispatcher, :dispatch_result] in RuntimeHealth.events()

    assert [:cadence, :commanding, :verifier_scheduler, :safety_reconcile] in RuntimeHealth.events()

    assert [:cadence, :jobs, :dispatcher, :worker_started] in RuntimeHealth.events()

    assert [:cadence, :runtime, :provider_ingress_executor, :backpressure_entered] in RuntimeHealth.events()

    assert Profiler.ingress_result_event() in RuntimeHealth.events()

    assert [
             :cadence,
             :runtime,
             :ingress_persistence_projector,
             :capacity_waiter_registered
           ] in RuntimeHealth.events()

    assert RuntimeInvalidation.telemetry_event() in RuntimeHealth.events()
    assert RuntimeInvalidation.decision_telemetry_event() in RuntimeHealth.events()
  end

  test "collects runtime queue and backpressure telemetry" do
    server = start_runtime_health!(recent_limit: 5)

    emit([:cadence, :runtime, :provider_ingress_executor, :backpressure_entered], %{count: 1}, %{
      mission_id: "mission-health",
      provider_binding_id: "provider-health",
      downstream: :ingress_persistence_projector
    })

    emit(
      [:cadence, :runtime, :ingress_persistence_projector, :capacity_waiter_registered],
      %{queue_depth: 10},
      %{
        mission_id: "mission-health",
        provider_binding_id: "provider-health"
      }
    )

    snapshot = wait_for_total_events(server, 2)

    assert snapshot.sources.provider_ingress_executor.total_events == 1
    assert snapshot.sources.provider_ingress_executor.events.backpressure_entered == 1

    assert snapshot.sources.ingress_persistence_projector.total_events == 1
    assert snapshot.sources.ingress_persistence_projector.events.capacity_waiter_registered == 1
  end

  test "collects latest ingress processing latency metrics by source endpoint" do
    server = start_runtime_health!(recent_limit: 5)

    Profiler.record_ingress_result(
      RawEvidence.new(%{
        mission_id: "mission-health",
        source_endpoint_ref: "endpoint-alpha",
        spacecraft_id: "spacecraft-alpha",
        raw: <<1, 2, 3>>
      }),
      resolve_us: 1_000,
      runtime_us: 2_000,
      end_to_end_us: 3_250,
      error?: false
    )

    Profiler.record_ingress_result(
      RawEvidence.new(%{
        mission_id: "mission-health",
        source_endpoint_ref: "endpoint-alpha",
        spacecraft_id: "spacecraft-alpha",
        transport_id: "transport-alpha",
        ground_station_id: "dss-14",
        link_id: "link-alpha",
        adapter_key: :tcp_socket,
        raw: <<4, 5, 6>>
      }),
      resolve_us: 1_000,
      runtime_us: 3_000,
      end_to_end_us: 4_500,
      transport_id: "transport-alpha",
      ground_station_id: "dss-14",
      link_id: "link-alpha",
      adapter_key: :tcp_socket,
      error?: true
    )

    snapshot = wait_for_total_events(server, 2)

    assert snapshot.sources.telemetry_ingress.total_events == 2
    assert snapshot.sources.telemetry_ingress.events.processing_result == 2

    assert [
             %{
               observable_id: "ingress.processing_latency_ms",
               mission_id: "mission-health",
               source_endpoint_id: "endpoint-alpha",
               spacecraft_id: "spacecraft-alpha",
               transport_id: "transport-alpha",
               ground_station_id: "dss-14",
               link_id: "link-alpha",
               adapter_key: :tcp_socket,
               value: 4.5,
               unit: "ms",
               error?: true
             } = sample
           ] = snapshot.metrics.ingress_processing_latency_ms

    assert sample.measurements.end_to_end_us == 4_500
    assert sample.metadata.protocol_family == :space_packet
  end

  test "collects dashboard runtime invalidation telemetry" do
    server = start_runtime_health!(recent_limit: 5)

    emit(
      RuntimeInvalidation.telemetry_event(),
      %{source_results: 2, frames: 3, plans: 0, total: 5},
      %{
        boundary: :source_watermark_changed,
        domain_fact: :source_watermark_changed,
        layers: [:source_result, :frame],
        filters: %{
          organization_id: "org-health",
          mission_id: "mission-health",
          logical_source: :telemetry,
          data_source_id: "managed_questdb_primary"
        },
        layer_filters: %{
          source_result: %{mission_id: "mission-health", logical_source: :telemetry},
          frame: %{mission_id: "mission-health", logical_source: :telemetry}
        }
      }
    )

    snapshot = wait_for_total_events(server, 1)

    assert snapshot.sources.dashboards_runtime_invalidation.total_events == 1
    assert snapshot.sources.dashboards_runtime_invalidation.events.invalidate == 1

    assert snapshot.sources.dashboards_runtime_invalidation.boundaries.source_watermark_changed ==
             1

    assert [%{source: :dashboards_runtime_invalidation} = event] = snapshot.recent_events
    assert event.event == :invalidate
    assert event.event_name == RuntimeInvalidation.telemetry_event()
    assert event.measurements.total == 5
    assert event.metadata.boundary == :source_watermark_changed
    assert event.metadata.filters.mission_id == "mission-health"
    assert event.metadata.filters.logical_source == :telemetry
    assert %Event{} = event.runtime_event
    assert event.runtime_event.boundary == :source_watermark_changed
    assert event.runtime_event.filters.mission_id == "mission-health"
    assert event.runtime_event.filters.logical_source == :telemetry
    assert event.runtime_event.measurements.total == 5
    assert %DateTime{} = event.runtime_event.occurred_at
  end

  test "collects dashboard runtime invalidation decision telemetry" do
    server = start_runtime_health!(recent_limit: 5)

    invalidation =
      Event.new(
        :source_watermark_changed,
        [:source_result, :frame],
        %{
          organization_id: "org-health",
          mission_id: "mission-health",
          logical_source: :telemetry,
          data_source_id: "managed_questdb_primary"
        },
        %{
          source_result: %{mission_id: "mission-health", logical_source: :telemetry},
          frame: %{mission_id: "mission-health", logical_source: :telemetry}
        },
        %{source_results: 2, frames: 3, total: 5},
        occurred_at: ~U[2026-06-24 12:00:00Z]
      )

    RuntimeInvalidation.emit_decision(
      invalidation,
      %{
        dashboard_id: "dashboard-health",
        organization_id: "org-health",
        mission_id: "mission-health",
        matches?: false,
        dashboard_matches?: true,
        context_matches?: false,
        context_reason: :replay_run_mismatch,
        refresh_allowed?: false,
        refresh_reason: :stale_for_context,
        affected_placement_count: 2,
        affected_placement_ids: ["placement-counter", "placement-trend"],
        affected_widget_type_ids: ["cadence.value_tile", "cadence.trend_chart"],
        affected_impact_reasons: [:primary_source, :secondary_source],
        decision_status: :filtered
      },
      invalidation_event_id: "source-watermark-decision-1"
    )

    snapshot = wait_for_total_events(server, 1)

    assert snapshot.sources.dashboards_runtime_invalidation.total_events == 1
    assert snapshot.sources.dashboards_runtime_invalidation.events.decision == 1
    assert snapshot.sources.dashboards_runtime_invalidation.boundaries == %{}

    assert [%{source: :dashboards_runtime_invalidation} = event] = snapshot.recent_events
    assert event.event == :decision
    assert event.event_name == RuntimeInvalidation.decision_telemetry_event()
    assert event.measurements.total == 1
    assert event.metadata.invalidation_event_id == "source-watermark-decision-1"
    assert event.metadata.decision.context_reason == :replay_run_mismatch
    assert event.metadata.decision.refresh_reason == :stale_for_context

    assert event.metadata.decision.affected_placement_ids == [
             "placement-counter",
             "placement-trend"
           ]

    assert event.metadata.context_reason == :replay_run_mismatch
    assert event.metadata.refresh_allowed? == false
    assert event.metadata.affected_placement_count == 2
    assert event.metadata.affected_placement_ids == ["placement-counter", "placement-trend"]

    assert event.metadata.affected_widget_type_ids == [
             "cadence.value_tile",
             "cadence.trend_chart"
           ]

    assert event.metadata.affected_impact_reasons == [:primary_source, :secondary_source]
    refute Map.has_key?(event, :runtime_event)
  end

  test "collector stays process-local and does not depend on Repo writes" do
    source =
      __DIR__
      |> Path.join("../../../lib/cadence/telemetry/runtime_health.ex")
      |> Path.expand()
      |> File.read!()

    refute source =~ "Cadence.Repo"
    refute source =~ "Repo."
  end

  defp start_runtime_health!(opts \\ []) do
    name = :"runtime_health_test_#{System.unique_integer([:positive])}"

    start_supervised!(
      {RuntimeHealth,
       Keyword.merge(
         [
           name: name,
           handler_id: "runtime-health-test-#{System.unique_integer([:positive])}"
         ],
         opts
       )}
    )

    name
  end

  defp emit(event_name, measurements, metadata) do
    :telemetry.execute(event_name, measurements, metadata)
  end

  defp wait_for_total_events(server, expected_count, attempts_left \\ 20)

  defp wait_for_total_events(server, expected_count, attempts_left) when attempts_left > 0 do
    snapshot = RuntimeHealth.snapshot(server)

    if snapshot.total_events == expected_count do
      snapshot
    else
      Process.sleep(10)
      wait_for_total_events(server, expected_count, attempts_left - 1)
    end
  end

  defp wait_for_total_events(server, expected_count, 0) do
    snapshot = RuntimeHealth.snapshot(server)

    flunk(
      "expected #{expected_count} runtime health events, got #{snapshot.total_events}: #{inspect(snapshot)}"
    )
  end
end
