defmodule Cadence.Test.AlternateRegisteredSemanticAlgorithm do
  @moduledoc false
  @behaviour Cadence.SemanticRuntime.RegisteredImplementation

  @impl true
  def evaluate(inputs, state, _context), do: {:ok, inputs, state}
end
