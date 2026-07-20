defmodule Cadence.Catalog.Telemetry.CalibrationAlgorithm do
  @moduledoc """
  Canonical imported telemetry calibration or conversion algorithm.
  """

  alias Cadence.Catalog.Ids
  alias Cadence.Catalog.Telemetry.{InterpolationPoint, Normalize, Provenance}

  @type algorithm_type :: :polynomial | :table | :math_expression | :state_map
  @type interpolation_order :: :step | :linear | :quadratic

  @type t :: %__MODULE__{
          algorithm_id: binary(),
          snapshot_id: binary(),
          name: binary(),
          description: binary() | nil,
          algorithm_type: algorithm_type(),
          polynomial_coefficients: [number()],
          interpolation_points: [InterpolationPoint.t()],
          interpolation_order: interpolation_order(),
          extrapolate: boolean(),
          math_expression: binary() | nil,
          state_mappings: map(),
          input_point_refs: [binary()],
          provenance: Provenance.t() | nil,
          extensions: map()
        }

  defstruct [
    :algorithm_id,
    :snapshot_id,
    :name,
    :description,
    :algorithm_type,
    :math_expression,
    :provenance,
    polynomial_coefficients: [],
    interpolation_points: [],
    interpolation_order: :linear,
    extrapolate: false,
    state_mappings: %{},
    input_point_refs: [],
    extensions: %{}
  ]

  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    %__MODULE__{
      algorithm_id: Normalize.get(attrs, :algorithm_id, Ids.new("telemetry_algorithm")),
      snapshot_id: Normalize.fetch!(attrs, :snapshot_id),
      name: Normalize.fetch!(attrs, :name),
      description: Normalize.get(attrs, :description),
      algorithm_type:
        Normalize.get(attrs, :algorithm_type, :polynomial) |> normalize_algorithm_type(),
      polynomial_coefficients: numeric_list(Normalize.get(attrs, :polynomial_coefficients, [])),
      interpolation_points:
        Normalize.nested_list(attrs, :interpolation_points, InterpolationPoint),
      interpolation_order:
        Normalize.get(attrs, :interpolation_order, :linear) |> normalize_interpolation_order(),
      extrapolate: Normalize.get(attrs, :extrapolate, false),
      math_expression: Normalize.get(attrs, :math_expression),
      state_mappings: Normalize.get(attrs, :state_mappings, %{}),
      input_point_refs: binary_list(Normalize.get(attrs, :input_point_refs, [])),
      provenance: Normalize.nested(attrs, :provenance, Provenance),
      extensions: Normalize.get(attrs, :extensions, %{})
    }
  end

  defp normalize_algorithm_type(:polynomial), do: :polynomial
  defp normalize_algorithm_type("polynomial"), do: :polynomial
  defp normalize_algorithm_type(:table), do: :table
  defp normalize_algorithm_type("table"), do: :table
  defp normalize_algorithm_type(:math_expression), do: :math_expression
  defp normalize_algorithm_type("math_expression"), do: :math_expression
  defp normalize_algorithm_type(:state_map), do: :state_map
  defp normalize_algorithm_type("state_map"), do: :state_map
  defp normalize_algorithm_type(_other), do: :polynomial

  defp normalize_interpolation_order(:step), do: :step
  defp normalize_interpolation_order("step"), do: :step
  defp normalize_interpolation_order(:linear), do: :linear
  defp normalize_interpolation_order("linear"), do: :linear
  defp normalize_interpolation_order(:quadratic), do: :quadratic
  defp normalize_interpolation_order("quadratic"), do: :quadratic
  defp normalize_interpolation_order(_other), do: :linear

  defp numeric_list(values) when is_list(values) do
    Enum.filter(values, &(is_integer(&1) or is_float(&1)))
  end

  defp numeric_list(_other), do: []

  defp binary_list(values) when is_list(values) do
    Enum.filter(values, &is_binary/1)
  end

  defp binary_list(_other), do: []
end
