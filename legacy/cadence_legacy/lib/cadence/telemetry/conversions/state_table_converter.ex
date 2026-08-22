defmodule Cadence.Telemetry.Conversions.StateTableConverter do
  @moduledoc """
  State table converter: maps raw values to descriptive strings.

  Looks up the raw value in a state table and returns the corresponding
  state string. If the value isn't found, returns the default state (if configured)
  or an error.

  ## Examples

      # Power mode states
      config = %{
        states: %{"0" => "OFF", "1" => "STANDBY", "2" => "NOMINAL"},
        default_state: "UNKNOWN"
      }

      convert(0, config)   # => {:ok, "OFF"}
      convert(1, config)   # => {:ok, "STANDBY"}
      convert(99, config)  # => {:ok, "UNKNOWN"}  (not in table, uses default)

      # Without default state
      config = %{states: %{"0" => "DISABLED", "1" => "ENABLED"}}
      convert(5, config)   # => {:error, :state_not_found}

  ## State Key Conversion

  Raw values are automatically converted to strings before lookup:
  - Integer 0 → "0"
  - Float 1.0 → "1.0"
  - String "foo" → "foo"

  This ensures consistent matching regardless of raw value type.
  """

  @behaviour Cadence.Telemetry.Conversions.ConverterBehaviour

  @impl true
  def convert(raw_value, %{states: states} = config) when is_map(states) do
    # Convert raw value to string for lookup
    key = to_lookup_key(raw_value)

    case Map.get(states, key) do
      nil ->
        # Not found - check for default state
        case Map.get(config, :default_state) do
          nil -> {:error, :state_not_found}
          default -> {:ok, default}
        end

      state_value ->
        {:ok, state_value}
    end
  end

  def convert(_raw_value, _config) do
    {:error, :missing_states}
  end

  ## Private Functions

  # Convert raw value to string key for state table lookup
  defp to_lookup_key(value) when is_integer(value), do: Integer.to_string(value)
  defp to_lookup_key(value) when is_float(value), do: Float.to_string(value)
  defp to_lookup_key(value) when is_binary(value), do: value
  defp to_lookup_key(value) when is_atom(value), do: Atom.to_string(value)
  defp to_lookup_key(value), do: inspect(value)
end
