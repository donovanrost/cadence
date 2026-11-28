defmodule Cadence.Control.Providers.EphemerisUploads.RetrierTest do
  @moduledoc """
  The ephemeris retry sweep (#968) retries every tick, reconciles on the first tick and every
  `reconcile_every` after it, and survives a sweep that raises.
  """
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias Cadence.Control.Providers.EphemerisUploads.Retrier

  test "retries every tick, reconciles every third, and survives a raising sweep" do
    test = self()

    log =
      capture_log(fn ->
        {:ok, pid} =
          start_supervised(
            {Retrier,
             name: :"retrier_#{System.unique_integer([:positive])}",
             first_check_ms: 0,
             interval_ms: 10,
             reconcile_every: 3,
             sweep: fn ->
               send(test, :retry)
               raise "pool unavailable"
             end,
             reconcile: fn -> send(test, :reconcile) end}
          )

        for _tick <- 1..4, do: assert_receive(:retry, 1_000)
        assert_received :reconcile
        assert_receive :reconcile, 1_000
        assert Process.alive?(pid)
      end)

    assert log =~ "pool unavailable"
  end
end
