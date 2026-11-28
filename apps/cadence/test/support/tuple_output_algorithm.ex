defmodule Cadence.Test.TupleOutputAlgorithm do
  @moduledoc false

  # A registered algorithm whose output has no canonical form (a tuple): the derived update id
  # refuses it with a reason (#950).
  @behaviour Cadence.SemanticRuntime.RegisteredImplementation

  @impl true
  def evaluate(_inputs, state, _context), do: {:ok, %{"parameter:out" => {:a, 1}}, state}
end
