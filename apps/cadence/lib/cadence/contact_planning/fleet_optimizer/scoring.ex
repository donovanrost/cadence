defmodule Cadence.ContactPlanning.FleetOptimizer.Scoring do
  @moduledoc false

  alias Cadence.ContactPlanning.{
    ContactOpportunitySnapshot,
    ContactRequirementVersion,
    FleetOptimizer.Constraints,
    FleetPlanningPolicyVersion
  }

  @scale 1_000
  @expiry_risk_window_seconds 24 * 60 * 60
  @fragmentation_window_seconds 60 * 60

  @spec score(
          ContactRequirementVersion.t(),
          ContactOpportunitySnapshot.t(),
          non_neg_integer(),
          [ContactOpportunitySnapshot.t()],
          FleetPlanningPolicyVersion.t(),
          DateTime.t()
        ) :: {integer(), map()}
  def score(requirement, snapshot, scarcity, selected, policy, now) do
    components = %{
      "priority" => priority(requirement.priority),
      "deadline" => deadline(requirement, snapshot),
      "scarcity" => scarcity(scarcity),
      "preferred_duration" => preferred_duration(requirement, snapshot),
      "volume" => volume(requirement, snapshot),
      "confidence" => confidence(snapshot),
      "cost_efficiency" => cost_efficiency(snapshot, policy),
      "diversity" => diversity(requirement, snapshot, selected, policy),
      "fragmentation_penalty" => fragmentation(snapshot, selected),
      "expiry_risk_penalty" => expiry_risk(snapshot, now)
    }

    weights = policy.scoring_document

    contributions = %{
      "priority" => components["priority"] * weights["priority_weight"],
      "deadline" => components["deadline"] * weights["deadline_weight"],
      "scarcity" => components["scarcity"] * weights["scarcity_weight"],
      "preferred_duration" =>
        components["preferred_duration"] * weights["preferred_duration_weight"],
      "volume" => components["volume"] * weights["volume_weight"],
      "confidence" => components["confidence"] * weights["confidence_weight"],
      "cost_efficiency" => components["cost_efficiency"] * weights["cost_efficiency_weight"],
      "diversity" => components["diversity"] * weights["diversity_weight"],
      "fragmentation_penalty" =>
        -components["fragmentation_penalty"] * weights["fragmentation_penalty"],
      "expiry_risk_penalty" => -components["expiry_risk_penalty"] * weights["expiry_risk_penalty"]
    }

    total = contributions |> Map.values() |> Enum.sum()

    {total,
     %{
       "scale" => @scale,
       "components" => components,
       "weights" => Map.take(weights, weight_fields()),
       "contributions" => contributions,
       "total" => total
     }}
  end

  defp priority(:critical), do: 1_000
  defp priority(:high), do: 700
  defp priority(:routine), do: 300

  defp deadline(requirement, snapshot) do
    window = max(DateTime.diff(requirement.latest_end, requirement.earliest_start, :second), 1)
    elapsed = max(DateTime.diff(snapshot.ends_at, requirement.earliest_start, :second), 0)
    max(0, @scale - div(min(elapsed, window) * @scale, window))
  end

  defp scarcity(0), do: 0
  defp scarcity(count), do: div(@scale, count)

  defp preferred_duration(requirement, snapshot) do
    duration = DateTime.diff(snapshot.ends_at, snapshot.starts_at, :second)

    case requirement.preferred_duration_seconds || requirement.minimum_duration_seconds do
      target when is_integer(target) and target > 0 ->
        min(@scale, div(duration * @scale, target))

      _target ->
        @scale
    end
  end

  defp volume(requirement, snapshot) do
    value = estimated_volume(snapshot.estimated_capacity_document)

    case {requirement.minimum_data_volume_bytes, value} do
      {target, bytes} when is_integer(target) and is_integer(bytes) ->
        min(@scale, div(bytes * @scale, target))

      {nil, bytes} when is_integer(bytes) ->
        @scale

      _other ->
        0
    end
  end

  defp confidence(%{availability: :available, synthetic: false}), do: 1_000
  defp confidence(%{availability: :available, synthetic: true}), do: 800
  defp confidence(%{availability: :limited}), do: 500
  defp confidence(_snapshot), do: 0

  defp cost_efficiency(snapshot, policy) do
    case Constraints.cost(snapshot) do
      {:known, micros, _currency} ->
        case policy.budget_quota_document["max_estimated_cost_micros"] do
          maximum when is_integer(maximum) and maximum > 0 ->
            max(0, @scale - div(min(micros, maximum) * @scale, maximum))

          _maximum ->
            div(@scale, 2)
        end

      :unknown ->
        0
    end
  end

  defp diversity(requirement, snapshot, selected, policy) do
    existing =
      Enum.filter(selected, fn current ->
        current.contact_requirement_id == requirement.contact_requirement_id and
          current.contact_requirement_version == requirement.version
      end)

    dimensions =
      [
        diversity_dimension(
          policy.redundancy_document["distinct_provider_required"],
          Constraints.provider_id(snapshot),
          Enum.map(existing, &Constraints.provider_id/1)
        ),
        diversity_dimension(
          policy.redundancy_document["distinct_station_required"],
          Constraints.station_id(snapshot),
          Enum.map(existing, &Constraints.station_id/1)
        ),
        diversity_dimension(
          policy.redundancy_document["distinct_service_pool_required"],
          Constraints.service_pool_id(snapshot),
          Enum.map(existing, &Constraints.service_pool_id/1)
        )
      ]
      |> Enum.reject(&is_nil/1)

    case dimensions do
      [] -> div(@scale, 2)
      values -> div(Enum.sum(values), length(values))
    end
  end

  defp diversity_dimension(false, _candidate, _selected), do: nil
  defp diversity_dimension(true, nil, _selected), do: 0

  defp diversity_dimension(true, candidate, selected),
    do: if(candidate in selected, do: 0, else: 1_000)

  defp fragmentation(snapshot, selected) do
    gaps =
      selected
      |> Enum.filter(fn current ->
        current.route_binding_document["spacecraft_id"] ==
          snapshot.route_binding_document["spacecraft_id"]
      end)
      |> Enum.map(&gap(snapshot, &1))
      |> Enum.filter(&is_integer/1)

    case gaps do
      [] ->
        0

      values ->
        nearest = Enum.min(values)

        max(
          0,
          @scale -
            div(
              min(nearest, @fragmentation_window_seconds) * @scale,
              @fragmentation_window_seconds
            )
        )
    end
  end

  defp expiry_risk(snapshot, now) do
    remaining = DateTime.diff(snapshot.expires_at, now, :second)

    cond do
      remaining <= 0 -> @scale
      remaining >= @expiry_risk_window_seconds -> 0
      true -> @scale - div(remaining * @scale, @expiry_risk_window_seconds)
    end
  end

  defp gap(left, right) do
    cond do
      Constraints.overlap?(left, right) ->
        0

      DateTime.compare(left.ends_at, right.starts_at) in [:lt, :eq] ->
        DateTime.diff(right.starts_at, left.ends_at, :second)

      true ->
        DateTime.diff(left.starts_at, right.ends_at, :second)
    end
  end

  defp estimated_volume(%{"bytes" => bytes}) when is_integer(bytes) and bytes >= 0, do: bytes

  defp estimated_volume(%{"data_volume_bytes" => bytes})
       when is_integer(bytes) and bytes >= 0,
       do: bytes

  defp estimated_volume(_capacity), do: nil

  defp weight_fields do
    ~w(
      priority_weight deadline_weight scarcity_weight preferred_duration_weight
      volume_weight confidence_weight cost_efficiency_weight diversity_weight
      fragmentation_penalty expiry_risk_penalty
    )
  end
end
