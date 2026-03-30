defmodule Cadence.Catalog.Telemetry.ArrayShape do
  @moduledoc """
  Canonical array shape for telemetry type definitions.
  """

  alias Cadence.Catalog.Telemetry.Normalize

  @type t :: %__MODULE__{
          element_type_id: binary(),
          dimensions: [pos_integer()],
          dynamic_dimension_refs: [binary()],
          dynamic_adjustments: [map()]
        }

  defstruct [
    :element_type_id,
    dimensions: [],
    dynamic_dimension_refs: [],
    dynamic_adjustments: []
  ]

  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    %__MODULE__{
      element_type_id: Normalize.fetch!(attrs, :element_type_id),
      dimensions: positive_integer_list(Normalize.get(attrs, :dimensions, [])),
      dynamic_dimension_refs: binary_list(Normalize.get(attrs, :dynamic_dimension_refs, [])),
      dynamic_adjustments: map_list(Normalize.get(attrs, :dynamic_adjustments, []))
    }
  end

  defp positive_integer_list(values) when is_list(values) do
    Enum.filter(values, &(is_integer(&1) and &1 > 0))
  end

  defp positive_integer_list(_other), do: []

  defp binary_list(values) when is_list(values) do
    Enum.filter(values, &is_binary/1)
  end

  defp binary_list(_other), do: []

  defp map_list(values) when is_list(values) do
    Enum.filter(values, &is_map/1)
  end

  defp map_list(_other), do: []
end
