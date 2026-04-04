defmodule CadenceSimulator.TestSupport.SlowCounterProvider do
  @behaviour CadenceSimulator.DynamicsProvider

  @impl true
  def init(config) do
    {:ok, %{sleep_ms: Map.get(config, :sleep_ms, 25)}}
  end

  @impl true
  def generate_values(state, step) do
    Process.sleep(state.sleep_ms)
    {:ok, %{"HK.uptime_seconds" => step}, state}
  end

  @impl true
  def parallel_safe?(_config), do: true
end
