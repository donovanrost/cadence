defmodule Cadence.CI.ScaleTestFormatter do
  @moduledoc false
  use GenServer

  @impl true
  def init(_opts) do
    {:ok, File.open!(System.fetch_env!("SCALE_TEST_TIMINGS"), [:write, :utf8])}
  end

  @impl true
  def handle_cast({:test_finished, %ExUnit.Test{state: state} = test}, output)
      when is_nil(state) or elem(state, 0) == :failed do
    timing = %{
      test: "#{inspect(test.module)}.#{test.name}",
      duration_ms: test.time / 1_000,
      passed: is_nil(state)
    }

    :ok = IO.binwrite(output, [JSON.encode_to_iodata!(timing), "\n"])
    {:noreply, output}
  end

  def handle_cast(_event, output), do: {:noreply, output}
end
