defmodule Cadence.Telemetry.RuntimeHealthTest do
  use ExUnit.Case, async: true

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
