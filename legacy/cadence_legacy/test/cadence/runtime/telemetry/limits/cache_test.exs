defmodule Cadence.Runtime.Telemetry.Limits.CacheTest do
  use Cadence.PureCase, async: false

  alias Cadence.Harness.Time
  alias Cadence.Runtime.Telemetry.Limits.Cache

  setup_virtual_time(start_time: ~U[2024-01-01 00:00:00Z])
  setup_limits_cache()

  test "evicts stale entries after virtual time advances" do
    mission_id = random_id()
    target_id = "SAT-1"
    cached_at = Cadence.Time.monotonic(:millisecond)

    :ets.insert(:limits_cache, {{mission_id, target_id}, %{}, "NOMINAL", cached_at})

    assert :ets.lookup(:limits_cache, {mission_id, target_id}) != []

    :ok = Time.advance(:timer.minutes(6))

    cache_pid = Process.whereis(Cache)
    assert is_pid(cache_pid)
    send(cache_pid, :cleanup)

    assert_eventually(
      fn -> :ets.lookup(:limits_cache, {mission_id, target_id}) == [] end,
      timeout: 1000
    )
  end
end
