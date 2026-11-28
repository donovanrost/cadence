defmodule Cadence.SemanticRuntime.RegisteredImplementation do
  @moduledoc """
  Allowlisted extension contract for algorithms that cannot be represented by
  the built-in typed expression AST.

  Implementations are selected by a configured key and version. Mission Model
  source is never permitted to supply an Elixir module name.

  `inputs` maps each input parameter id to its value. The `context` also carries the algorithm's
  inputs in their **declared order** (#454, #451 T4c): `input_parameter_ids` as declared, duplicates
  included, and `inputs_in_order`, their values in that order. An implementation whose inputs are
  positional (a difference, a ratio, the same parameter twice) reads `inputs_in_order`; the map
  loses both order and duplicates.
  """

  @callback evaluate(
              inputs :: %{required(binary()) => term()},
              state :: map(),
              context :: map()
            ) ::
              {:ok, outputs :: %{required(binary()) => term()}, next_state :: map()}
              | {:error, term()}
end
