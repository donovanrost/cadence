defmodule Cadence.MissionDatabase.Unit do
  @moduledoc """
  Unit of measure definition with optional SI conversion.

  Units provide human-readable labels and enable automatic unit conversion.

  ## Example

      %Unit{
        name: "Celsius",
        symbol: "°C",
        description: "Temperature in degrees Celsius",
        si_unit: "K",
        si_conversion_factor: 1.0,
        si_conversion_offset: 273.15
      }

  The SI conversion formula is: `value_in_si = value * factor + offset`
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "mdb_units" do
    belongs_to :organization, Cadence.Organizations.Organization
    belongs_to :mission, Cadence.Missions.Mission
    belongs_to :definition_set, Cadence.MissionDatabase.DefinitionSet

    field :name, :string
    field :symbol, :string
    field :description, :string

    # SI conversion (value_in_si = value * factor + offset)
    field :si_conversion_factor, :float
    field :si_conversion_offset, :float
    field :si_unit, :string

    field :extensions, :map, default: %{}

    timestamps(type: :utc_datetime)
  end

  @doc """
  Creates a changeset for a Unit.
  """
  def changeset(unit, attrs) do
    unit
    |> cast(attrs, [
      :organization_id,
      :mission_id,
      :definition_set_id,
      :name,
      :symbol,
      :description,
      :si_conversion_factor,
      :si_conversion_offset,
      :si_unit,
      :extensions
    ])
    |> validate_required([:organization_id, :mission_id, :definition_set_id, :name])
    |> unique_constraint([:definition_set_id, :name],
      name: :mdb_units_definition_set_name_index
    )
  end

  @doc """
  Converts a value from this unit to SI base units.
  Returns nil if no SI conversion is defined.
  """
  def to_si(%__MODULE__{si_conversion_factor: nil}, _value), do: nil
  def to_si(%__MODULE__{si_conversion_factor: factor, si_conversion_offset: offset}, value) do
    value * factor + (offset || 0)
  end

  @doc """
  Converts a value from SI base units to this unit.
  Returns nil if no SI conversion is defined.
  """
  def from_si(%__MODULE__{si_conversion_factor: nil}, _value), do: nil
  def from_si(%__MODULE__{si_conversion_factor: 0}, _value), do: nil
  def from_si(%__MODULE__{si_conversion_factor: factor, si_conversion_offset: offset}, value) do
    (value - (offset || 0)) / factor
  end
end
