defmodule CadenceSimulator.DynamicsProvider do
  @moduledoc """
  Behaviour for simulator telemetry generation providers.

  Providers emit converted telemetry values keyed by qualified point name. A
  later encoding/runtime layer can turn those values into packets or frames.
  """

  @type telemetry_values :: %{String.t() => number() | String.t() | binary() | boolean()}

  @doc """
  Initialize the provider with provider-specific configuration.
  """
  @callback init(config :: map()) :: {:ok, state :: term()} | {:error, reason :: term()}

  @doc """
  Generate values for a simulation step.
  """
  @callback generate_values(state :: term(), step :: non_neg_integer()) ::
              {:ok, telemetry_values(), new_state :: term()}
              | {:error, reason :: term(), state :: term()}

  @doc """
  Return human-readable provider status.
  """
  @callback status(state :: term()) :: map()

  @doc """
  Whether the provider can safely run in parallel generation mode.
  """
  @callback parallel_safe?(config :: map()) :: boolean()

  @optional_callbacks [status: 1, parallel_safe?: 1]
end
