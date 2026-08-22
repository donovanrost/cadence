defmodule Cadence.Telemetry.Conversions.Conversion do
  @moduledoc """
  Base schema for telemetry conversions.

  Conversions transform raw telemetry values into engineering units or human-readable states.

  ## Conversion Types

  - **polynomial** - Polynomial equation: `y = c0 + c1*x + c2*x^2 + ...`
  - **state_table** - Maps raw values to state strings (e.g., 0 → "DISABLED", 1 → "ENABLED")
  - **generic** - Custom Elixir module for complex conversions

  ## Examples

      # Temperature conversion (ADC counts → Celsius)
      %Conversion{
        name: "TEMP_SENSOR_1",
        conversion_type: "polynomial",
        polynomial_conversion: %{coefficients: [-273.15, 0.01]}  # °C = -273.15 + 0.01*x
      }

      # Mode conversion (integer → string)
      %Conversion{
        name: "POWER_MODE",
        conversion_type: "state_table",
        state_table_conversion: %{
          states: %{"0" => "OFF", "1" => "STANDBY", "2" => "ACTIVE"},
          default_state: "UNKNOWN"
        }
      }
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @conversion_types ["polynomial", "state_table", "generic"]

  schema "conversions" do
    field :name, :string
    field :conversion_type, :string
    field :description, :string

    belongs_to :mission, Cadence.Missions.Mission

    has_one :polynomial_conversion, Cadence.Telemetry.Conversions.PolynomialConversion
    has_one :state_table_conversion, Cadence.Telemetry.Conversions.StateTableConversion
    has_one :generic_conversion, Cadence.Telemetry.Conversions.GenericConversion

    has_many :packet_items, Cadence.Telemetry.Packet.PacketItem

    timestamps()
  end

  @doc """
  Creates a changeset for a conversion.
  """
  def changeset(conversion, attrs) do
    conversion
    |> cast(attrs, [:mission_id, :name, :conversion_type, :description])
    |> validate_required([:mission_id, :name, :conversion_type])
    |> validate_inclusion(:conversion_type, @conversion_types,
      message: "must be one of: #{Enum.join(@conversion_types, ", ")}"
    )
    |> unique_constraint([:mission_id, :name],
      message: "Conversion name must be unique within a mission"
    )
  end

  @doc """
  Returns the list of valid conversion types.
  """
  def valid_conversion_types, do: @conversion_types
end
