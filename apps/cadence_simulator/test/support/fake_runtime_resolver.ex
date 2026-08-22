defmodule CadenceSimulator.TestSupport.FakeRuntimeResolver do
  @moduledoc false

  @spec next(Agent.agent()) :: {:ok, keyword()} | {:error, term()}
  def next(agent) when is_pid(agent) do
    Agent.get_and_update(agent, fn
      [response | rest] -> {response, rest}
      [] -> {{:error, :missing_fake_runtime_update}, []}
    end)
  end
end
