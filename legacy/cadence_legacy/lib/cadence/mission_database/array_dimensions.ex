defmodule Cadence.MissionDatabase.ArrayDimensions do
  @moduledoc """
  Defines the dimensions of an array data type.

  Supports both static (fixed-size) and dynamic (size from parameter) arrays.

  ## Static Array Example

      # A 10x20 matrix
      %ArrayDimensions{
        dimensions: [10, 20]
      }

  ## Dynamic Array Example

      # Array size comes from HEADER.COUNT parameter
      %ArrayDimensions{
        dynamic_dimension_refs: ["HEADER.COUNT"],
        linear_adjustments: [%{slope: 1, intercept: 0}]
      }

  ## Mixed Example

      # First dimension fixed, second dynamic
      %ArrayDimensions{
        dimensions: [10, nil],
        dynamic_dimension_refs: [nil, "HEADER.COL_COUNT"]
      }
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false
  embedded_schema do
    # Static dimensions (nil for dynamic dimensions)
    field :dimensions, {:array, :integer}

    # Dynamic dimensions (reference to parameter for size)
    field :dynamic_dimension_refs, {:array, :string}

    # Linear adjustment for dynamic sizes
    # Each element: %{slope: float, intercept: float}
    # actual_size = slope * ref_value + intercept
    field :linear_adjustments, {:array, :map}
  end

  @doc """
  Changeset for creating or updating array dimensions.
  """
  def changeset(array_dims, attrs) do
    array_dims
    |> cast(attrs, [:dimensions, :dynamic_dimension_refs, :linear_adjustments])
    |> validate_has_dimensions()
  end

  defp validate_has_dimensions(changeset) do
    dims = get_field(changeset, :dimensions)
    dynamic = get_field(changeset, :dynamic_dimension_refs)

    has_static = is_list(dims) and length(dims) > 0
    has_dynamic = is_list(dynamic) and length(dynamic) > 0

    if has_static or has_dynamic do
      changeset
    else
      add_error(changeset, :base, "must specify dimensions or dynamic_dimension_refs")
    end
  end

  @doc """
  Returns the number of dimensions.
  """
  def rank(%__MODULE__{dimensions: dims}) when is_list(dims), do: length(dims)
  def rank(%__MODULE__{dynamic_dimension_refs: refs}) when is_list(refs), do: length(refs)
  def rank(_), do: 0

  @doc """
  Returns true if all dimensions are statically known.
  """
  def static?(%__MODULE__{dimensions: dims, dynamic_dimension_refs: nil}) when is_list(dims) do
    Enum.all?(dims, &(not is_nil(&1)))
  end

  def static?(%__MODULE__{dimensions: dims, dynamic_dimension_refs: refs})
      when is_list(dims) and is_list(refs) do
    Enum.all?(dims, &(not is_nil(&1))) and Enum.all?(refs, &is_nil/1)
  end

  def static?(_), do: false
end
