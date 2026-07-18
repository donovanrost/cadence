defmodule Cadence.ContactPlanning.FleetOptimizer.Constraints do
  @moduledoc false

  alias Cadence.ContactPlanning.{
    ContactOpportunitySnapshot,
    ContactRequirementVersion,
    FleetPlanningPolicyVersion
  }

  @spec inherent_failures(
          ContactRequirementVersion.t(),
          ContactOpportunitySnapshot.t(),
          FleetPlanningPolicyVersion.t(),
          DateTime.t()
        ) :: [map()]
  def inherent_failures(requirement, snapshot, policy, now) do
    duration = DateTime.diff(snapshot.ends_at, snapshot.starts_at, :second)
    route = snapshot.route_binding_document
    cost = cost(snapshot)

    [
      failure(
        snapshot.contact_requirement_id != requirement.contact_requirement_id or
          snapshot.contact_requirement_version != requirement.version,
        "requirement_binding_mismatch",
        "Opportunity snapshot does not reference this exact Requirement version."
      ),
      failure(
        not snapshot.eligible,
        "stage_4_ineligible",
        "Stage 4 marked this opportunity ineligible.",
        %{"stage_4_evaluation" => snapshot.evaluation_document}
      ),
      failure(
        snapshot.availability == :unavailable,
        "provider_unavailable",
        "Provider marks this opportunity unavailable."
      ),
      failure(
        not DateTime.after?(snapshot.expires_at, now),
        "opportunity_expired",
        "Provider opportunity evidence has expired."
      ),
      failure(
        DateTime.before?(snapshot.starts_at, requirement.earliest_start) or
          DateTime.after?(snapshot.ends_at, requirement.latest_end),
        "outside_requirement_window",
        "Opportunity is outside the Requirement window."
      ),
      failure(
        is_integer(requirement.minimum_duration_seconds) and
          duration < requirement.minimum_duration_seconds,
        "minimum_duration_not_met",
        "Opportunity is shorter than the Requirement minimum."
      ),
      failure(
        route["spacecraft_id"] != requirement.spacecraft_id,
        "spacecraft_binding_mismatch",
        "Provider route does not reference the Requirement spacecraft."
      ),
      failure(
        blank?(route["provider_id"]),
        "provider_binding_missing",
        "Provider identity is missing from the route snapshot."
      ),
      failure(
        blank?(route["provider_account_grant_id"]),
        "provider_grant_binding_missing",
        "Exact provider account grant evidence is missing from the route snapshot."
      ),
      failure(
        hard_cost_policy?(policy, route["provider_id"]) and cost == :unknown,
        "estimated_cost_unknown",
        "A hard cost ceiling requires normalized cost evidence."
      ),
      failure(
        cost_currency_mismatch?(cost, policy),
        "estimated_cost_currency_mismatch",
        "Opportunity cost currency does not match fleet policy.",
        cost_evidence(cost, policy)
      )
    ]
    |> Enum.reject(&is_nil/1)
  end

  @spec dynamic_failures(
          ContactRequirementVersion.t(),
          ContactOpportunitySnapshot.t(),
          [ContactOpportunitySnapshot.t()],
          map(),
          FleetPlanningPolicyVersion.t()
        ) :: [map()]
  def dynamic_failures(requirement, snapshot, selected, requirements, policy) do
    provider_id = provider_id(snapshot)

    [
      same_spacecraft_failure(requirement, snapshot, selected, requirements),
      separation_failure(requirement, snapshot, selected),
      resource_failure(snapshot, selected, policy),
      contact_quota_failure(requirement, selected, policy),
      provider_contact_quota_failure(provider_id, selected, policy),
      cost_budget_failure(requirement, snapshot, selected, policy),
      provider_cost_budget_failure(provider_id, snapshot, selected, policy),
      redundancy_failure(requirement, snapshot, selected, policy)
    ]
    |> Enum.reject(&is_nil/1)
  end

  @spec cost(ContactOpportunitySnapshot.t()) ::
          {:known, non_neg_integer(), binary()} | :unknown
  def cost(snapshot) do
    document = snapshot.normalized_opportunity_document

    cost_document =
      document["estimated_cost"] ||
        get_in(document, ["extensions", "estimated_cost"]) ||
        get_in(document, ["extensions", "cost"])

    normalize_cost(cost_document)
  end

  @spec provider_id(ContactOpportunitySnapshot.t()) :: binary() | nil
  def provider_id(snapshot), do: snapshot.route_binding_document["provider_id"]

  @spec station_id(ContactOpportunitySnapshot.t()) :: binary() | nil
  def station_id(snapshot), do: snapshot.normalized_opportunity_document["ground_station_ref"]

  @spec service_pool_id(ContactOpportunitySnapshot.t()) :: binary() | nil
  def service_pool_id(snapshot),
    do: snapshot.normalized_opportunity_document["antenna_or_service_pool_ref"]

  @spec resource_key(ContactOpportunitySnapshot.t()) :: binary()
  def resource_key(snapshot) do
    [
      provider_id(snapshot) || "provider-unknown",
      station_id(snapshot) || "station-unknown",
      service_pool_id(snapshot) || snapshot.route_binding_document["route_key"] ||
        "resource-unknown"
    ]
    |> Enum.join(":")
  end

  @spec overlap?(ContactOpportunitySnapshot.t(), ContactOpportunitySnapshot.t()) :: boolean()
  def overlap?(left, right) do
    DateTime.before?(left.starts_at, right.ends_at) and
      DateTime.before?(right.starts_at, left.ends_at)
  end

  @spec resource_summary([ContactOpportunitySnapshot.t()], FleetPlanningPolicyVersion.t()) ::
          map()
  def resource_summary(selected, policy) do
    resources =
      selected
      |> Enum.group_by(&resource_key/1)
      |> Enum.map(fn {key, snapshots} ->
        peak = peak_parallel(snapshots)
        capacity = resource_capacity(key, policy)

        {key,
         %{
           "selected_count" => length(snapshots),
           "peak_parallel" => peak,
           "capacity" => capacity,
           "over_capacity" => peak > capacity
         }}
      end)
      |> Map.new()

    %{
      "resource_count" => map_size(resources),
      "resources" => resources,
      "over_capacity_count" =>
        Enum.count(resources, fn {_key, summary} -> summary["over_capacity"] end)
    }
  end

  @spec budget_summary([ContactOpportunitySnapshot.t()], FleetPlanningPolicyVersion.t()) :: map()
  def budget_summary(selected, policy) do
    budget = policy.budget_quota_document
    costs = Enum.map(selected, &cost/1)
    known_cost = costs |> Enum.map(&known_cost/1) |> Enum.reject(&is_nil/1) |> Enum.sum()

    providers =
      selected
      |> Enum.group_by(&provider_id/1)
      |> Enum.map(fn {provider, snapshots} ->
        provider_costs = Enum.map(snapshots, &cost/1)

        {provider || "provider-unknown",
         %{
           "selected_contacts" => length(snapshots),
           "known_cost_micros" =>
             provider_costs
             |> Enum.map(&known_cost/1)
             |> Enum.reject(&is_nil/1)
             |> Enum.sum(),
           "unknown_cost_count" => Enum.count(provider_costs, &(&1 == :unknown)),
           "policy" => get_in(budget, ["per_provider", provider]) || %{}
         }}
      end)
      |> Map.new()

    %{
      "selected_contacts" => length(selected),
      "known_cost_micros" => known_cost,
      "unknown_cost_count" => Enum.count(costs, &(&1 == :unknown)),
      "currency" => budget["currency"],
      "max_contacts" => budget["max_contacts"],
      "max_estimated_cost_micros" => budget["max_estimated_cost_micros"],
      "providers" => providers
    }
  end

  defp same_spacecraft_failure(requirement, snapshot, selected, requirements) do
    conflict =
      Enum.find(selected, fn current ->
        current_requirement = requirements[requirement_key(current)]

        current_requirement &&
          current_requirement.spacecraft_id == requirement.spacecraft_id &&
          overlap?(snapshot, current)
      end)

    if conflict do
      failure(
        true,
        "same_spacecraft_overlap",
        "The spacecraft already has an overlapping selected or locked contact.",
        %{"conflicting_snapshot_id" => conflict.contact_opportunity_snapshot_id}
      )
    end
  end

  defp separation_failure(requirement, snapshot, selected) do
    conflict =
      selected
      |> Enum.filter(&same_requirement?(&1, requirement))
      |> Enum.find(fn current ->
        gap(snapshot, current) < requirement.minimum_separation_seconds
      end)

    if conflict do
      failure(
        true,
        "minimum_separation_not_met",
        "This contact is too close to another contact selected for the same Requirement.",
        %{
          "conflicting_snapshot_id" => conflict.contact_opportunity_snapshot_id,
          "required_seconds" => requirement.minimum_separation_seconds,
          "gap_seconds" => gap(snapshot, conflict)
        }
      )
    end
  end

  defp resource_failure(snapshot, selected, policy) do
    key = resource_key(snapshot)
    capacity = resource_capacity(key, policy)

    overlapping =
      Enum.filter(selected, fn current ->
        resource_key(current) == key and overlap?(snapshot, current)
      end)

    if length(overlapping) >= capacity do
      failure(
        true,
        "exclusive_resource_capacity_exhausted",
        "The declared provider resource has no remaining concurrent capacity.",
        %{
          "resource_key" => key,
          "capacity" => capacity,
          "conflicting_snapshot_ids" =>
            Enum.map(overlapping, & &1.contact_opportunity_snapshot_id)
        }
      )
    end
  end

  defp contact_quota_failure(requirement, selected, policy) do
    budget = policy.budget_quota_document
    maximum = budget["max_contacts"]
    reserve = budget["critical_contact_reserve"]

    effective_maximum =
      if requirement.priority == :critical,
        do: maximum,
        else: subtract_reserve(maximum, reserve)

    if is_integer(effective_maximum) and length(selected) + 1 > effective_maximum do
      code =
        if requirement.priority == :critical,
          do: "global_contact_quota_exhausted",
          else: "critical_contact_reserve_protected"

      failure(
        true,
        code,
        "Fleet contact quota does not permit this selection.",
        %{"selected_contacts" => length(selected), "effective_maximum" => effective_maximum}
      )
    end
  end

  defp provider_contact_quota_failure(nil, _selected, _policy), do: nil

  defp provider_contact_quota_failure(provider, selected, policy) do
    maximum = get_in(policy.budget_quota_document, ["per_provider", provider, "max_contacts"])
    current = Enum.count(selected, &(provider_id(&1) == provider))

    if is_integer(maximum) and current + 1 > maximum do
      failure(
        true,
        "provider_contact_quota_exhausted",
        "Provider planning quota does not permit this selection.",
        %{"provider_id" => provider, "selected_contacts" => current, "maximum" => maximum}
      )
    end
  end

  defp cost_budget_failure(requirement, snapshot, selected, policy) do
    budget = policy.budget_quota_document
    maximum = budget["max_estimated_cost_micros"]
    reserve = budget["critical_cost_reserve_micros"]

    effective_maximum =
      if requirement.priority == :critical,
        do: maximum,
        else: subtract_reserve(maximum, reserve)

    projected_cost_failure(
      snapshot,
      selected,
      effective_maximum,
      "global_cost_budget_exhausted",
      "Fleet cost ceiling does not permit this selection."
    )
  end

  defp provider_cost_budget_failure(nil, _snapshot, _selected, _policy), do: nil

  defp provider_cost_budget_failure(provider, snapshot, selected, policy) do
    maximum =
      get_in(
        policy.budget_quota_document,
        ["per_provider", provider, "max_estimated_cost_micros"]
      )

    selected = Enum.filter(selected, &(provider_id(&1) == provider))

    projected_cost_failure(
      snapshot,
      selected,
      maximum,
      "provider_cost_budget_exhausted",
      "Provider cost ceiling does not permit this selection.",
      %{"provider_id" => provider}
    )
  end

  defp projected_cost_failure(snapshot, selected, maximum, code, message, extra \\ %{})

  defp projected_cost_failure(
         _snapshot,
         _selected,
         nil,
         _code,
         _message,
         _extra
       ),
       do: nil

  defp projected_cost_failure(snapshot, selected, maximum, code, message, extra) do
    selected_cost =
      selected
      |> Enum.map(&cost/1)
      |> Enum.map(&known_cost/1)
      |> Enum.reject(&is_nil/1)
      |> Enum.sum()

    case cost(snapshot) do
      {:known, micros, _currency} when selected_cost + micros > maximum ->
        failure(
          true,
          code,
          message,
          Map.merge(extra, %{
            "selected_cost_micros" => selected_cost,
            "candidate_cost_micros" => micros,
            "maximum_micros" => maximum
          })
        )

      _cost ->
        nil
    end
  end

  defp redundancy_failure(requirement, snapshot, selected, policy) do
    current = Enum.filter(selected, &same_requirement?(&1, requirement))

    if current == [] or requirement.contact_count <= 1 do
      nil
    else
      redundancy = policy.redundancy_document

      violations =
        [
          duplicate_dimension(
            redundancy["distinct_provider_required"],
            provider_id(snapshot),
            Enum.map(current, &provider_id/1),
            "provider"
          ),
          duplicate_dimension(
            redundancy["distinct_station_required"],
            station_id(snapshot),
            Enum.map(current, &station_id/1),
            "station"
          ),
          duplicate_dimension(
            redundancy["distinct_service_pool_required"],
            service_pool_id(snapshot),
            Enum.map(current, &service_pool_id/1),
            "service_pool"
          )
        ]
        |> Enum.reject(&is_nil/1)

      if violations != [] do
        failure(
          true,
          "redundancy_not_distinct",
          "Selection would not satisfy declared contact diversity.",
          %{"duplicate_dimensions" => violations}
        )
      end
    end
  end

  defp duplicate_dimension(false, _candidate, _selected, _name), do: nil

  defp duplicate_dimension(true, candidate, selected, name) do
    if is_nil(candidate) or candidate in selected, do: name
  end

  defp normalize_cost(%{"amount_micros" => micros, "currency" => currency})
       when is_integer(micros) and micros >= 0 and is_binary(currency) and currency != "" do
    {:known, micros, String.upcase(currency)}
  end

  defp normalize_cost(_value), do: :unknown

  defp hard_cost_policy?(policy, provider_id) do
    is_integer(policy.budget_quota_document["max_estimated_cost_micros"]) or
      is_integer(
        get_in(
          policy.budget_quota_document,
          ["per_provider", provider_id, "max_estimated_cost_micros"]
        )
      )
  end

  defp cost_currency_mismatch?({:known, _micros, actual}, policy) do
    case policy.budget_quota_document["currency"] do
      nil -> false
      expected -> actual != expected
    end
  end

  defp cost_currency_mismatch?(_cost, _policy), do: false

  defp cost_evidence({:known, _micros, actual}, policy),
    do: %{
      "actual_currency" => actual,
      "expected_currency" => policy.budget_quota_document["currency"]
    }

  defp cost_evidence(_cost, _policy), do: %{}

  defp known_cost({:known, micros, _currency}), do: micros
  defp known_cost(_cost), do: nil

  defp resource_capacity(key, policy) do
    Map.get(
      policy.resource_policy_document["capacities"],
      key,
      policy.resource_policy_document["default_exclusive_capacity"]
    )
  end

  defp peak_parallel(snapshots) do
    snapshots
    |> Enum.flat_map(fn snapshot ->
      [
        {snapshot.starts_at, 1, snapshot.contact_opportunity_snapshot_id},
        {snapshot.ends_at, -1, snapshot.contact_opportunity_snapshot_id}
      ]
    end)
    |> Enum.sort_by(fn {at, delta, id} -> {at, delta, id} end)
    |> Enum.reduce({0, 0}, fn {_at, delta, _id}, {current, peak} ->
      current = current + delta
      {current, max(current, peak)}
    end)
    |> elem(1)
  end

  defp subtract_reserve(nil, _reserve), do: nil
  defp subtract_reserve(maximum, reserve), do: max(maximum - reserve, 0)

  defp requirement_key(snapshot),
    do: {snapshot.contact_requirement_id, snapshot.contact_requirement_version}

  defp same_requirement?(snapshot, requirement),
    do:
      snapshot.contact_requirement_id == requirement.contact_requirement_id and
        snapshot.contact_requirement_version == requirement.version

  defp gap(left, right) do
    cond do
      overlap?(left, right) ->
        -1

      DateTime.compare(left.ends_at, right.starts_at) in [:lt, :eq] ->
        DateTime.diff(right.starts_at, left.ends_at, :second)

      true ->
        DateTime.diff(left.starts_at, right.ends_at, :second)
    end
  end

  defp failure(condition, code, message, evidence \\ %{})

  defp failure(false, _code, _message, _evidence), do: nil

  defp failure(true, code, message, evidence) do
    %{"code" => code, "message" => message, "evidence" => evidence}
  end

  defp blank?(value), do: not (is_binary(value) and value != "")
end
