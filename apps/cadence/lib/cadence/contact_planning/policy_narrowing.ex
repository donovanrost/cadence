defmodule Cadence.ContactPlanning.PolicyNarrowing do
  @moduledoc "Validates Requirement policy as a restriction over mission delivery policy."

  alias Cadence.GroundNetworks.DeliveryPolicy

  @maximum_fields ~w(
    maximum_earlier_start_shift_seconds maximum_later_start_shift_seconds
    maximum_earlier_end_shift_seconds maximum_later_end_shift_seconds maximum_cost_delta
  )
  @minimum_fields ~w(
    minimum_retained_duration_seconds minimum_retained_estimated_capacity_bytes
  )
  @subset_fields ~w(
    approved_station_substitutions approved_equivalent_resource_substitutions
  )
  @known_fields @maximum_fields ++
                  @minimum_fields ++
                  @subset_fields ++
                  ~w(mode changes_always_requiring_approval allow_automatic_execution_revision)

  @spec narrow(map(), map()) :: {:ok, map()} | {:error, term()}
  def narrow(mission_document, requirement_constraints)
      when is_map(mission_document) and is_map(requirement_constraints) do
    with {:ok, mission} <- DeliveryPolicy.normalize(mission_document),
         :ok <- known_constraints(requirement_constraints),
         mission_document <- DeliveryPolicy.to_document(mission),
         :ok <- maximums_narrowed(mission_document, requirement_constraints),
         :ok <- minimums_narrowed(mission_document, requirement_constraints),
         :ok <- lists_narrowed(mission_document, requirement_constraints),
         :ok <- mode_narrowed(mission_document, requirement_constraints),
         :ok <- approval_categories_narrowed(mission_document, requirement_constraints),
         :ok <- automatic_revision_narrowed(mission_document, requirement_constraints) do
      {:ok, Map.merge(mission_document, requirement_constraints)}
    end
  end

  def narrow(_mission_document, _requirement_constraints),
    do: {:error, :contact_plan_policy_must_be_an_object}

  defp known_constraints(constraints) do
    case Map.keys(constraints) -- @known_fields do
      [] -> :ok
      [field | _rest] -> {:error, {:unknown_contact_requirement_policy_constraint, field}}
    end
  end

  defp maximums_narrowed(mission, constraints) do
    Enum.reduce_while(@maximum_fields, :ok, fn field, :ok ->
      constraints
      |> Map.fetch(field)
      |> maximum_result(mission[field], field)
    end)
  end

  defp maximum_result(:error, _maximum, _field), do: {:cont, :ok}

  defp maximum_result({:ok, value}, maximum, _field)
       when is_number(value) and value >= 0 and (is_nil(maximum) or value <= maximum),
       do: {:cont, :ok}

  defp maximum_result({:ok, value}, _maximum, field) when is_number(value) and value >= 0,
    do: {:halt, widened(field)}

  defp maximum_result({:ok, _value}, _maximum, field), do: {:halt, invalid(field)}

  defp minimums_narrowed(mission, constraints) do
    Enum.reduce_while(@minimum_fields, :ok, fn field, :ok ->
      constraints
      |> Map.fetch(field)
      |> minimum_result(mission[field], field)
    end)
  end

  defp minimum_result(:error, _minimum, _field), do: {:cont, :ok}

  defp minimum_result({:ok, value}, minimum, _field)
       when is_integer(value) and value >= 0 and (is_nil(minimum) or value >= minimum),
       do: {:cont, :ok}

  defp minimum_result({:ok, value}, _minimum, field) when is_integer(value) and value >= 0,
    do: {:halt, widened(field)}

  defp minimum_result({:ok, _value}, _minimum, field), do: {:halt, invalid(field)}

  defp lists_narrowed(mission, constraints) do
    Enum.reduce_while(@subset_fields, :ok, fn field, :ok ->
      constraints
      |> Map.fetch(field)
      |> list_result(mission[field], field)
    end)
  end

  defp list_result(:error, _allowed, _field), do: {:cont, :ok}

  defp list_result({:ok, values}, allowed, field) when is_list(values) do
    if subset?(values, allowed), do: {:cont, :ok}, else: {:halt, widened(field)}
  end

  defp list_result({:ok, _value}, _allowed, field), do: {:halt, invalid(field)}

  defp subset?(values, allowed) do
    allowed = MapSet.new(allowed)
    Enum.all?(values, &(is_binary(&1) and MapSet.member?(allowed, &1)))
  end

  defp mode_narrowed(mission, constraints) do
    case {Map.fetch(constraints, "mode"), mission["mode"]} do
      {:error, _mission_mode} ->
        :ok

      {{:ok, "approval_required"}, _mission_mode} ->
        :ok

      {{:ok, "bounded_automatic"}, "bounded_automatic"} ->
        :ok

      {{:ok, "bounded_automatic"}, _mission_mode} ->
        widened("mode")

      {{:ok, _value}, _mission_mode} ->
        invalid("mode")
    end
  end

  defp approval_categories_narrowed(mission, constraints) do
    case Map.fetch(constraints, "changes_always_requiring_approval") do
      :error ->
        :ok

      {:ok, values} when is_list(values) ->
        required = MapSet.new(mission["changes_always_requiring_approval"])
        proposed = MapSet.new(values)

        if Enum.all?(values, &is_binary/1) and MapSet.subset?(required, proposed),
          do: :ok,
          else: widened("changes_always_requiring_approval")

      {:ok, _value} ->
        invalid("changes_always_requiring_approval")
    end
  end

  defp automatic_revision_narrowed(mission, constraints) do
    case {
      Map.fetch(constraints, "allow_automatic_execution_revision"),
      mission["allow_automatic_execution_revision"]
    } do
      {:error, _mission_value} -> :ok
      {{:ok, false}, _mission_value} -> :ok
      {{:ok, true}, true} -> :ok
      {{:ok, true}, false} -> widened("allow_automatic_execution_revision")
      {{:ok, _value}, _mission_value} -> invalid("allow_automatic_execution_revision")
    end
  end

  defp widened(field), do: {:error, {:contact_requirement_policy_widens_mission_policy, field}}
  defp invalid(field), do: {:error, {:invalid_contact_requirement_policy_constraint, field}}
end
