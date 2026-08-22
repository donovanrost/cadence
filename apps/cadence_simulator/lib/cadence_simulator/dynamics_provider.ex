defmodule CadenceSimulator.DynamicsProvider do
  @moduledoc """
  Behaviour for simulator telemetry generation providers.

  Providers emit converted telemetry values keyed by qualified point name. A
  later encoding/runtime layer can turn those values into packets or frames.

  Providers may optionally emit packet-scoped values directly to avoid
  rebuilding a flat point map and then rediscovering packet membership during
  encoding.
  """

  @type telemetry_value :: number() | String.t() | binary() | boolean()
  @type telemetry_values :: %{String.t() => telemetry_value()}
  @type packet_item_values :: %{String.t() => telemetry_value()} | [telemetry_value()]
  @type packet_values :: [{String.t(), packet_item_values()}]

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
  Generate packet-scoped values for a simulation step.
  """
  @callback generate_packet_values(state :: term(), step :: non_neg_integer()) ::
              {:ok, packet_values(), new_state :: term()}
              | {:error, reason :: term(), state :: term()}

  @doc """
  Return human-readable provider status.
  """
  @callback status(state :: term()) :: map()

  @doc """
  Whether the provider can safely run in parallel generation mode.
  """
  @callback parallel_safe?(config :: map()) :: boolean()

  @doc """
  Applies one command invocation to provider state.
  """
  @callback execute_command(state :: term(), command_ref :: binary(), arguments :: map()) ::
              {:ok, result :: map(), new_state :: term()}
              | {:error, reason :: term(), state :: term()}

  @doc """
  Decodes and applies one encoded command payload to provider state.
  """
  @callback execute_encoded_command(state :: term(), payload :: binary()) ::
              {:ok, result :: map(), new_state :: term()}
              | {:error, reason :: term(), state :: term()}

  @optional_callbacks [
    execute_command: 3,
    execute_encoded_command: 2,
    generate_packet_values: 2,
    status: 1,
    parallel_safe?: 1
  ]
end
