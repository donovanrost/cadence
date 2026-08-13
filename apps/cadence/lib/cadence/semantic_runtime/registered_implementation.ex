defmodule Cadence.SemanticRuntime.RegisteredImplementation do
  @moduledoc """
  Allowlisted extension contract for algorithms that cannot be represented by
  the built-in typed expression AST.

  Implementations are selected by a configured key and version. Mission Model
  source is never permitted to supply an Elixir module name.
  """

  @callback evaluate(
              inputs :: %{required(binary()) => term()},
              state :: map(),
              context :: map()
            ) ::
              {:ok, outputs :: %{required(binary()) => term()}, next_state :: map()}
              | {:error, term()}
end
