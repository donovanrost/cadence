defmodule Cadence.Catalog.Telemetry.MatchCriteria do
  @moduledoc """
  Reusable typed condition AST for canonical telemetry catalog matching.
  """

  alias Cadence.Catalog.Telemetry.Normalize

  @type criteria_type :: :comparison | :range | :expression | :compound

  @type comparison ::
          :equal
          | :not_equal
          | :greater
          | :less
          | :greater_equal
          | :less_equal
          | :in_range
          | :not_in_range

  @type operator :: :and | :or

  @type t :: %__MODULE__{
          criteria_type: criteria_type(),
          subject_ref: binary() | nil,
          comparison: comparison() | nil,
          value: term() | nil,
          range_min: number() | nil,
          range_max: number() | nil,
          use_calibrated: boolean(),
          boolean_expression: binary() | nil,
          operator: operator() | nil,
          conditions: [t()],
          metadata: map(),
          extensions: map()
        }

  defstruct [
    :criteria_type,
    :subject_ref,
    :comparison,
    :value,
    :range_min,
    :range_max,
    :boolean_expression,
    :operator,
    conditions: [],
    use_calibrated: true,
    metadata: %{},
    extensions: %{}
  ]

  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    %__MODULE__{
      criteria_type:
        Normalize.get(attrs, :criteria_type, :comparison) |> normalize_criteria_type(),
      subject_ref: Normalize.get(attrs, :subject_ref),
      comparison: Normalize.get(attrs, :comparison) |> normalize_comparison(),
      value: Normalize.get(attrs, :value),
      range_min: Normalize.get(attrs, :range_min),
      range_max: Normalize.get(attrs, :range_max),
      use_calibrated: Normalize.get(attrs, :use_calibrated, true),
      boolean_expression: Normalize.get(attrs, :boolean_expression),
      operator: Normalize.get(attrs, :operator) |> normalize_operator(),
      conditions: Normalize.nested_list(attrs, :conditions, __MODULE__),
      metadata: Normalize.get(attrs, :metadata, %{}),
      extensions: Normalize.get(attrs, :extensions, %{})
    }
  end

  defp normalize_criteria_type(:comparison), do: :comparison
  defp normalize_criteria_type("comparison"), do: :comparison
  defp normalize_criteria_type(:range), do: :range
  defp normalize_criteria_type("range"), do: :range
  defp normalize_criteria_type(:expression), do: :expression
  defp normalize_criteria_type("expression"), do: :expression
  defp normalize_criteria_type(:compound), do: :compound
  defp normalize_criteria_type("compound"), do: :compound
  defp normalize_criteria_type(_other), do: :comparison

  defp normalize_comparison(nil), do: nil
  defp normalize_comparison(:equal), do: :equal
  defp normalize_comparison("equal"), do: :equal
  defp normalize_comparison(:not_equal), do: :not_equal
  defp normalize_comparison("not_equal"), do: :not_equal
  defp normalize_comparison(:greater), do: :greater
  defp normalize_comparison("greater"), do: :greater
  defp normalize_comparison(:less), do: :less
  defp normalize_comparison("less"), do: :less
  defp normalize_comparison(:greater_equal), do: :greater_equal
  defp normalize_comparison("greater_equal"), do: :greater_equal
  defp normalize_comparison(:less_equal), do: :less_equal
  defp normalize_comparison("less_equal"), do: :less_equal
  defp normalize_comparison(:in_range), do: :in_range
  defp normalize_comparison("in_range"), do: :in_range
  defp normalize_comparison(:not_in_range), do: :not_in_range
  defp normalize_comparison("not_in_range"), do: :not_in_range
  defp normalize_comparison(_other), do: nil

  defp normalize_operator(nil), do: nil
  defp normalize_operator(:and), do: :and
  defp normalize_operator("and"), do: :and
  defp normalize_operator(:or), do: :or
  defp normalize_operator("or"), do: :or
  defp normalize_operator(_other), do: nil
end
