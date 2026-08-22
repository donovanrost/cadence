defmodule Cadence.Telemetry.Conversions.ConverterBehaviour do
  @moduledoc """
  Behaviour for telemetry value converters.

  All converters (polynomial, state_table, generic) implement this behaviour
  to provide a consistent interface for converting RAW → CONVERTED values.

  ## Callback

  The `convert/2` callback receives:
  - `raw_value` - The raw telemetry value (integer, float, string, etc.)
  - `config` - Converter-specific configuration

  And returns:
  - `{:ok, converted_value}` - Successfully converted
  - `{:error, reason}` - Conversion failed

  ## Example

      defmodule MyApp.CustomConverter do
        @behaviour Cadence.Telemetry.Conversions.ConverterBehaviour

        @impl true
        def convert(raw_value, config) when is_number(raw_value) do
          multiplier = Map.get(config, "multiplier", 1.0)
          {:ok, raw_value * multiplier}
        end

        def convert(_raw_value, _config) do
          {:error, :invalid_input}
        end
      end
  """

  @doc """
  Converts a raw telemetry value to engineering units or a human-readable state.

  ## Parameters

  - `raw_value` - Raw value from decommutation (integer, float, string, etc.)
  - `config` - Converter configuration (map with converter-specific settings)

  ## Returns

  - `{:ok, converted_value}` - Conversion successful
  - `{:error, reason}` - Conversion failed (invalid input, out of range, etc.)
  """
  @callback convert(raw_value :: any(), config :: map()) ::
              {:ok, any()} | {:error, term()}
end
