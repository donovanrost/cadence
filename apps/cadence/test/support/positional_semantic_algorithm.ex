defmodule Cadence.Test.PositionalSemanticAlgorithm do
  @moduledoc false

  # Order-sensitive on purpose: the first declared input minus the second, plus how many inputs
  # were declared (duplicates included), so a test sees both the order and the duplicates.
  @behaviour Cadence.SemanticRuntime.RegisteredImplementation

  @impl true
  def evaluate(_inputs, state, %{inputs_in_order: [first, second | _rest] = values}) do
    {:ok, %{"parameter:difference" => first - second + length(values) * 1000}, state}
  end
end
