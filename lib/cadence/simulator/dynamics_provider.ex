defmodule Cadence.Simulator.DynamicsProvider do
  @moduledoc """
  Behaviour for spacecraft dynamics/telemetry generation.

  Providers generate CONVERTED telemetry values on each simulation step.
  The Coordinator handles encoding these values into raw binary packets
  using packet definitions.

  ## Implementing a Provider

  Providers must implement at least `init/1` and `generate_values/2`:

      defmodule MyProvider do
        @behaviour Cadence.Simulator.DynamicsProvider

        @impl true
        def init(config) do
          {:ok, %{step: 0, config: config}}
        end

        @impl true
        def generate_values(state, step) do
          values = %{
            "HEALTH.cpu_temp" => 25.0 + :math.sin(step / 10.0) * 5.0,
            "HEALTH.battery_voltage" => 14.5
          }
          {:ok, values, %{state | step: step}}
        end
      end

  ## Value Format

  Providers return a map of qualified item names to converted values:

      %{
        "HEALTH.cpu_temp" => 25.5,        # float
        "HEALTH.uptime" => 12345,         # integer
        "POWER.mode" => "CHARGING"        # string (for state tables)
      }

  The Coordinator applies reverse conversions to get raw values before
  encoding into binary packets.

  ## Optional Callbacks

  - `handle_command/2` - Respond to commands from the command queue
  - `status/1` - Return current provider state for introspection
  """

  @type telemetry_values :: %{String.t() => number() | String.t()}

  @type command_ack :: %{
          command_name: String.t(),
          status: :accepted | :rejected | :executing | :completed,
          message: String.t() | nil
        }

  @doc """
  Initialize the provider with configuration.

  Config may include provider-specific options such as:
  - Scenario file path (for ScenarioProvider)
  - Value ranges and patterns (for BasicDynamics)
  - Initial spacecraft state
  """
  @callback init(config :: map()) :: {:ok, state :: term()} | {:error, reason :: term()}

  @doc """
  Generate telemetry values for the current simulation step.

  Returns a map of qualified item names (e.g., "HEALTH.cpu_temp") to
  converted values. The step number increases monotonically and can be
  used to create deterministic, reproducible patterns.
  """
  @callback generate_values(state :: term(), step :: non_neg_integer()) ::
              {:ok, telemetry_values(), new_state :: term()}
              | {:error, reason :: term(), state :: term()}

  @doc """
  Handle a command from the command queue.

  Optional callback for providers that support command acknowledgment.
  The command map includes the command name, parameters, and metadata.

  Returns an acknowledgment and updated state.
  """
  @callback handle_command(state :: term(), command :: map()) ::
              {:ok, command_ack(), new_state :: term()}
              | {:error, reason :: term(), state :: term()}

  @doc """
  Return current provider status for introspection.

  Optional callback that returns a map of status information for
  display in the CLI or UI.
  """
  @callback status(state :: term()) :: map()

  @optional_callbacks [handle_command: 2, status: 1]
end
