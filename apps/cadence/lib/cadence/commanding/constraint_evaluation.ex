defmodule Cadence.Commanding.ConstraintEvaluation do
  @moduledoc """
  Evaluates compiled command transmission constraints against the latest
  mission telemetry values immediately before release.
  """

  alias Cadence.Catalog.Command.Compiler.ConstraintPlan
  alias Cadence.Catalog.Command.MatchCriteria
  alias Cadence.Telemetry.{Sample, SampleRecords}

  @spec validate(binary(), binary(), [ConstraintPlan.t()]) :: :ok | {:error, term()}
  def validate(organization_id, mission_id, plans)
      when is_binary(organization_id) and is_binary(mission_id) and is_list(plans) do
    samples =
      SampleRecords.list_samples(mission_id,
        organization_id: organization_id,
        order: :receipt_desc
      )

    validate(plans, latest_values(samples))
  end

  @spec validate([ConstraintPlan.t()], map()) :: :ok | {:error, term()}
  def validate(plans, latest_values) when is_list(plans) and is_map(latest_values) do
    Enum.reduce_while(plans, :ok, fn %ConstraintPlan{} = plan, :ok ->
      cond do
        matches?(plan.criteria, latest_values) ->
          {:cont, :ok}

        not plan.blocking ->
          {:cont, :ok}

        true ->
          {:halt, {:error, {:command_constraint_not_satisfied, plan.constraint_id}}}
      end
    end)
  end

  @spec latest_values([Sample.t()]) :: map()
  def latest_values(samples) when is_list(samples) do
    Enum.reduce(samples, %{}, fn %Sample{} = sample, values ->
      sample
      |> sample_subjects()
      |> Enum.reduce(values, &Map.put_new(&2, &1, sample_value(sample)))
    end)
  end

  defp matches?(nil, _values), do: false

  defp matches?(%MatchCriteria{criteria_type: :comparison} = criteria, values) do
    case Map.fetch(values, normalize_subject(criteria.subject_ref)) do
      {:ok, subject_value} -> compare(subject_value, criteria.comparison, criteria.value)
      :error -> false
    end
  end

  defp matches?(%MatchCriteria{criteria_type: :range} = criteria, values) do
    case Map.fetch(values, normalize_subject(criteria.subject_ref)) do
      {:ok, subject_value} -> in_range?(subject_value, criteria.range_min, criteria.range_max)
      :error -> false
    end
  end

  defp matches?(%MatchCriteria{criteria_type: :compound, operator: :and} = criteria, values),
    do: Enum.all?(criteria.conditions, &matches?(&1, values))

  defp matches?(%MatchCriteria{criteria_type: :compound, operator: :or} = criteria, values),
    do: Enum.any?(criteria.conditions, &matches?(&1, values))

  defp matches?(%MatchCriteria{}, _values), do: false

  defp sample_subjects(%Sample{} = sample) do
    [sample.semantic_id, sample.qualified_name, sample.point_id, sample.point_name]
    |> Enum.filter(&is_binary/1)
    |> Enum.map(&normalize_subject/1)
    |> Enum.uniq()
  end

  defp sample_value(%Sample{} = sample),
    do: if(is_nil(sample.engineering_value), do: sample.raw_value, else: sample.engineering_value)

  defp normalize_subject(nil), do: nil

  defp normalize_subject(subject) do
    subject
    |> String.trim()
    |> String.trim_leading("telemetry:")
  end

  defp compare(_actual, nil, _expected), do: false
  defp compare(actual, :equal, expected), do: actual == expected
  defp compare(actual, :not_equal, expected), do: actual != expected

  defp compare(actual, operation, expected)
       when operation in [:greater, :less, :greater_equal, :less_equal] do
    with {:ok, actual} <- number(actual),
         {:ok, expected} <- number(expected) do
      case operation do
        :greater -> actual > expected
        :less -> actual < expected
        :greater_equal -> actual >= expected
        :less_equal -> actual <= expected
      end
    else
      :error -> false
    end
  end

  defp compare(actual, :in_range, expected) when is_map(expected),
    do: in_range?(actual, map_value(expected, :min), map_value(expected, :max))

  defp compare(actual, :not_in_range, expected) when is_map(expected),
    do: not in_range?(actual, map_value(expected, :min), map_value(expected, :max))

  defp compare(_actual, _operation, _expected), do: false

  defp in_range?(actual, minimum, maximum) do
    with {:ok, actual} <- number(actual),
         {:ok, minimum} <- number(minimum),
         {:ok, maximum} <- number(maximum) do
      actual >= minimum and actual <= maximum
    else
      :error -> false
    end
  end

  defp number(value) when is_integer(value) or is_float(value), do: {:ok, value}
  defp number(_value), do: :error

  defp map_value(map, key), do: Map.get(map, key, Map.get(map, Atom.to_string(key)))
end
