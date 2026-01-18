defmodule Cadence.Runtime.Telemetry.DerivedItems.CacheTimerTest do
  use Cadence.PureCase, async: false

  alias Cadence.Harness.Time
  alias Cadence.Runtime.Telemetry.DerivedItems.Cache
  alias Cadence.Time, as: CadenceTime
  alias Cadence.Time.Timer, as: TimeTimer

  setup_virtual_time()

  setup do
    pid =
      case Process.whereis(Cache) do
        nil -> start_supervised!({Cache, []})
        existing -> existing
      end

    %{cache_pid: pid}
  end

  test "cleans stale entries after virtual time advances", %{cache_pid: cache_pid} do
    mission_id = random_id()
    cached_at = CadenceTime.monotonic(:millisecond) - :timer.minutes(4)

    :ets.insert(:derived_items_cache, {mission_id, {[], %{}}, cached_at})

    assert :ets.lookup(:derived_items_cache, mission_id) != []

    _timer_ref = TimeTimer.send_after(cache_pid, :cleanup, :timer.minutes(1))

    :ok = Time.advance(:timer.minutes(1))

    Cadence.PureCase.assert_eventually(
      fn -> :ets.lookup(:derived_items_cache, mission_id) == [] end,
      timeout: 1000
    )
  end
end
