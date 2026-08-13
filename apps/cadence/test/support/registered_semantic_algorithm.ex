defmodule Cadence.Test.RegisteredSemanticAlgorithm do
  @moduledoc false

  @behaviour Cadence.SemanticRuntime.RegisteredImplementation

  @impl true
  def evaluate(inputs, state, _context) do
    value = Map.fetch!(inputs, "parameter:raw")
    count = Map.get(state, :count, 0) + 1
    {:ok, %{"parameter:registered" => value * 3}, %{count: count}}
  end
end
