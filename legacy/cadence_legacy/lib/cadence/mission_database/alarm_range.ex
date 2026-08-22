defmodule Cadence.MissionDatabase.AlarmRange do
  @moduledoc """
  Defines a single alarm range with inclusive or exclusive bounds.

  ## Example

      %AlarmRange{
        min_inclusive: 0.0,
        max_inclusive: 100.0
      }

  Or with exclusive bounds:

      %AlarmRange{
        min_exclusive: -273.15,  # Must be > absolute zero
        max_inclusive: 1000.0
      }
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false
  embedded_schema do
    field :min_inclusive, :float
    field :max_inclusive, :float
    field :min_exclusive, :float
    field :max_exclusive, :float
  end

  @doc """
  Changeset for creating or updating an alarm range.
  """
  def changeset(alarm_range, attrs) do
    alarm_range
    |> cast(attrs, [:min_inclusive, :max_inclusive, :min_exclusive, :max_exclusive])
    |> validate_range_bounds()
  end

  defp validate_range_bounds(changeset) do
    min_inc = get_field(changeset, :min_inclusive)
    max_inc = get_field(changeset, :max_inclusive)
    min_exc = get_field(changeset, :min_exclusive)
    max_exc = get_field(changeset, :max_exclusive)

    # Get effective min and max
    min_val = min_inc || min_exc
    max_val = max_inc || max_exc

    cond do
      is_nil(min_val) and is_nil(max_val) ->
        add_error(changeset, :base, "must specify at least one bound")

      not is_nil(min_val) and not is_nil(max_val) and min_val > max_val ->
        add_error(changeset, :base, "min bound cannot be greater than max bound")

      true ->
        changeset
    end
  end

  @doc """
  Checks if a value is within this range.
  """
  def in_range?(%__MODULE__{} = range, value) when is_number(value) do
    check_min(range, value) and check_max(range, value)
  end

  defp check_min(%{min_inclusive: nil, min_exclusive: nil}, _value), do: true
  defp check_min(%{min_inclusive: min}, value) when not is_nil(min), do: value >= min
  defp check_min(%{min_exclusive: min}, value) when not is_nil(min), do: value > min

  defp check_max(%{max_inclusive: nil, max_exclusive: nil}, _value), do: true
  defp check_max(%{max_inclusive: max}, value) when not is_nil(max), do: value <= max
  defp check_max(%{max_exclusive: max}, value) when not is_nil(max), do: value < max
end
