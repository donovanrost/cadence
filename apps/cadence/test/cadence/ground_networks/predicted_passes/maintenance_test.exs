defmodule Cadence.GroundNetworks.PredictedPasses.MaintenanceTest do
  @moduledoc """
  The daily predicted-pass check (#891) survives a failing tick: a raise or an exit (a database
  outage) is logged and retried, never a crash, so it can't take the `:cadence` app down.
  """
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias Cadence.GroundNetworks.PredictedPasses.Maintenance

  test "a failing check is logged, the process stays up, and the next check runs" do
    test = self()
    {:ok, calls} = Agent.start_link(fn -> 0 end)

    check = fn ->
      n = Agent.get_and_update(calls, &{&1 + 1, &1 + 1})
      send(test, {:checked, n})

      case n do
        1 -> raise DBConnection.ConnectionError, "connection not available"
        2 -> exit(:timeout)
        _ -> :ok
      end
    end

    log =
      capture_log(fn ->
        {:ok, pid} =
          start_supervised(
            {Maintenance,
             name: :"maintenance_#{System.unique_integer([:positive])}",
             check: check,
             first_check_ms: 0,
             interval_ms: 10}
          )

        assert_receive {:checked, 1}, 1_000
        assert_receive {:checked, 2}, 1_000
        assert_receive {:checked, 3}, 1_000
        assert Process.alive?(pid)
      end)

    assert log =~ "connection not available"
    assert log =~ ":timeout"
  end

  test "the first check is scheduled, not run during init" do
    test = self()

    {:ok, _pid} =
      start_supervised(
        {Maintenance,
         name: :"maintenance_#{System.unique_integer([:positive])}",
         check: fn -> send(test, :checked) && :ok end,
         first_check_ms: 200,
         interval_ms: 60_000}
      )

    refute_received :checked
    assert_receive :checked, 1_000
  end
end
