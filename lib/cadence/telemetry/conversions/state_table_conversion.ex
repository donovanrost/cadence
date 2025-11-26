defmodule Cadence.Telemetry.Conversions.StateTableConversion do
  @moduledoc """
  State table conversion: maps raw integer/string values to descriptive states.

  Common for mode indicators, status flags, and enumerated values.

  ## Examples

      # Power mode mapping
      %StateTableConversion{
        states: %{
          "0" => "OFF",
          "1" => "STANDBY",
          "2" => "NOMINAL",
          "3" => "HIGH_POWER"
        },
        default_state: "UNKNOWN"
      }

      # Boolean flag
      %StateTableConversion{
        states: %{
          "0" => "DISABLED",
          "1" => "ENABLED"
        },
        default_state: "ERROR"
      }

  ## State Keys

  State keys are always stored as strings in the JSON map, even if
  the raw telemetry value is an integer. This ensures consistent
  JSON encoding/decoding.

  The conversion logic will automatically convert integer raw values
  to strings before lookup.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "state_table_conversions" do
    # Stored as JSON: {"0": "STATE_NAME", "1": "OTHER_STATE"}
    field :states, :map

    # Default state for unmapped values
    field :default_state, :string

    belongs_to :conversion, Cadence.Telemetry.Conversions.Conversion

    timestamps()
  end

  @doc """
  Creates a changeset for a state table conversion.
  """
  def changeset(state_table_conversion, attrs) do
    state_table_conversion
    |> cast(attrs, [:conversion_id, :states, :default_state])
    |> validate_required([:conversion_id, :states])
    |> validate_states()
    |> unique_constraint(:conversion_id)
  end

  defp validate_states(changeset) do
    case get_field(changeset, :states) do
      nil ->
        changeset

      states when is_map(states) ->
        if map_size(states) == 0 do
          add_error(changeset, :states, "must have at least one state mapping")
        else
          # Validate that all values are strings
          invalid_values =
            states
            |> Map.values()
            |> Enum.reject(&is_binary/1)

          if Enum.empty?(invalid_values) do
            changeset
          else
            add_error(changeset, :states, "all state values must be strings")
          end
        end

      _ ->
        add_error(changeset, :states, "must be a map")
    end
  end
end
