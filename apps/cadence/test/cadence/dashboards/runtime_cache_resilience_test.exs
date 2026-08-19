defmodule Cadence.Dashboards.RuntimeCacheResilienceTest do
  use Cadence.UnitCase, async: true

  import ExUnit.CaptureLog

  alias Cadence.Dashboards.{RuntimeCache, RuntimeCacheKey}

  test "cache timeouts fail open instead of terminating callers" do
    blocked_cache = spawn(fn -> receive do: (:stop -> :ok) end)
    cache = RuntimeCache.client(blocked_cache, call_timeout_ms: 10)

    on_exit(fn ->
      if Process.alive?(blocked_cache), do: Process.exit(blocked_cache, :kill)
    end)

    key = %RuntimeCacheKey{layer: :frame, fingerprint: "blocked-cache", parts: %{}}

    log =
      capture_log(fn ->
        assert RuntimeCache.get_frame(key, cache) == :miss

        assert RuntimeCache.invalidate_frames(cache, mission_id: "mission-one") ==
                 {:ok, 0}
      end)

    assert log =~ "Dashboard runtime cache get failed open"
    assert log =~ "Dashboard runtime cache invalidate failed open"
  end
end
