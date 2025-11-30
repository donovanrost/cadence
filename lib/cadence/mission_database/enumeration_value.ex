defmodule Cadence.MissionDatabase.EnumerationValue do
  @moduledoc """
  Defines a single enumeration value mapping.

  Used in enumerated data types to map raw integer values to human-readable labels.

  ## Single Value Example

      %EnumerationValue{
        value: 0,
        label: "OFF",
        description: "System is powered off"
      }

  ## Range Example

  For contiguous ranges, use `max_value`:

      %EnumerationValue{
        value: 100,
        max_value: 199,
        label: "NOMINAL",
        description: "Values 100-199 indicate nominal operation"
      }
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false
  embedded_schema do
    field :value, :integer
    field :label, :string
    field :description, :string
    field :max_value, :integer  # For ranges: value..max_value
  end

  @doc """
  Changeset for creating or updating an enumeration value.
  """
  def changeset(enum_value, attrs) do
    enum_value
    |> cast(attrs, [:value, :label, :description, :max_value])
    |> validate_required([:value, :label])
    |> validate_range()
  end

  defp validate_range(changeset) do
    value = get_field(changeset, :value)
    max_value = get_field(changeset, :max_value)

    if not is_nil(max_value) and not is_nil(value) and max_value < value do
      add_error(changeset, :max_value, "must be greater than or equal to value")
    else
      changeset
    end
  end

  @doc """
  Checks if a raw value matches this enumeration entry.
  """
  def matches?(%__MODULE__{value: v, max_value: nil}, raw_value), do: raw_value == v
  def matches?(%__MODULE__{value: v, max_value: max}, raw_value), do: raw_value >= v and raw_value <= max
end
