defmodule Cadence.Dashboards.RuntimeCacheResilienceTest do
  use Cadence.UnitCase, async: false

  import ExUnit.CaptureLog

  alias Cadence.Dashboards.{RuntimeCache, RuntimeCacheKey}

  setup do
    previous_config = Application.get_env(:cadence, :dashboard_runtime_cache)
    config = Keyword.put(previous_config || [], :call_timeout_ms, 10)
    Application.put_env(:cadence, :dashboard_runtime_cache, config)

    on_exit(fn ->
      case previous_config do
        nil -> Application.delete_env(:cadence, :dashboard_runtime_cache)
        config -> Application.put_env(:cadence, :dashboard_runtime_cache, config)
      end
    end)

    :ok
  end

  test "cache timeouts fail open instead of terminating callers" do
    blocked_cache = spawn(fn -> receive do: (:stop -> :ok) end)

    on_exit(fn ->
      if Process.alive?(blocked_cache), do: Process.exit(blocked_cache, :kill)
    end)

    key = %RuntimeCacheKey{layer: :frame, fingerprint: "blocked-cache", parts: %{}}

    log =
      capture_log(fn ->
        assert RuntimeCache.get_frame(key, blocked_cache) == :miss

        assert RuntimeCache.invalidate_frames(blocked_cache, mission_id: "mission-one") ==
                 {:ok, 0}
      end)

    assert log =~ "Dashboard runtime cache get failed open"
    assert log =~ "Dashboard runtime cache invalidate failed open"
  end
end
