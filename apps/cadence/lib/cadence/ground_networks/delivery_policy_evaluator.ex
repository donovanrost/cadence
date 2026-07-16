defmodule Cadence.GroundNetworks.DeliveryPolicyEvaluator do
  @moduledoc "Pure classification of authoritative provider Contact changes."

  alias Cadence.GroundNetworks.DeliveryPolicy

  @configuration_fields ~w(
    provider_contact_ref client_reference opportunity_ref spacecraft_ref
    service_profile_ref delivery_profile_ref
  )
  @observation_fields ~w(status pass_phase delivery_state status_reason)
  @schedule_fields ~w(starts_at ends_at)
  @resource_fields ~w(ground_station_ref antenna_or_service_pool_ref)
  @immutable_delivery_paths [
    ["delivery_descriptor", "direction"],
    ["delivery_descriptor", "delivery_kind"],
    ["delivery_descriptor", "mode"],
    ["delivery_descriptor", "protocol"],
    ["delivery_descriptor", "endpoint_ref"],
    ["delivery_descriptor", "framing"],
    ["delivery_descriptor", "credential_ref"],
    ["delivery_descriptor", "allowed_source_refs"]
  ]

  @type decision ::
          :observation
          | :policy_accept
          | :approval_required
          | :acknowledgment_required
          | :configuration_failure

  @spec evaluate(DeliveryPolicy.t(), map(), map(), keyword()) :: map()
  def evaluate(%DeliveryPolicy{} = policy, before, current, opts \\ [])
      when is_map(before) and is_map(current) do
    changed_fields = changed_fields(before, current)
    categories = categories(changed_fields, before, current)
    impact = impact(before, current)

    cond do
      configuration_changed?(changed_fields, before, current) ->
        result(:configuration_failure, policy, changed_fields, categories, impact, [
          "provider_contact_configuration_mismatch"
        ])

      changed_fields == [] ->
        result(:observation, policy, changed_fields, categories, impact, ["no_material_change"])

      already_effective_fact?(current, categories, opts) ->
        result(:acknowledgment_required, policy, changed_fields, categories, impact, [
          "provider_change_already_effective"
        ])

      Enum.all?(changed_fields, &(&1 in @observation_fields)) ->
        result(:observation, policy, changed_fields, categories, impact, [
          "provider_operational_observation"
        ])

      counteroffer?(current) ->
        result(:approval_required, policy, changed_fields, categories, impact, [
          "provider_counteroffer_requires_approval"
        ])

      policy.mode == :approval_required ->
        result(:approval_required, policy, changed_fields, categories, impact, [
          "delivery_policy_requires_approval"
        ])

      not policy.allow_automatic_execution_revision ->
        result(:approval_required, policy, changed_fields, categories, impact, [
          "automatic_execution_revision_disabled"
        ])

      category_requires_approval?(policy, categories) ->
        result(:approval_required, policy, changed_fields, categories, impact, [
          "change_category_always_requires_approval"
        ])

      true ->
        case tolerance_violations(policy, before, current, changed_fields) do
          [] ->
            result(:policy_accept, policy, changed_fields, categories, impact, [
              "change_within_delivery_policy"
            ])

          violations ->
            result(:approval_required, policy, changed_fields, categories, impact, violations)
        end
    end
  end

  defp result(decision, policy, changed_fields, categories, impact, reasons) do
    %{
      decision: decision,
      policy_version: policy.version,
      changed_fields: changed_fields,
      categories: categories,
      impact: impact,
      reasons: reasons
    }
  end

  defp changed_fields(before, current) do
    (Map.keys(before) ++ Map.keys(current))
    |> Enum.uniq()
    |> Enum.reject(&(&1 in ["provider_revision"]))
    |> Enum.filter(&(Map.get(before, &1) != Map.get(current, &1)))
    |> Enum.sort()
  end

  defp categories(changed_fields, before, current) do
    []
    |> maybe_category(:schedule, Enum.any?(@schedule_fields, &(&1 in changed_fields)))
    |> maybe_category(:resource, Enum.any?(@resource_fields, &(&1 in changed_fields)))
    |> maybe_category(:capacity, capacity_changed?(before, current))
    |> maybe_category(:cost, cost_changed?(before, current))
    |> maybe_category(:cancellation, current["status"] == "canceled")
    |> maybe_category(:counteroffer, counteroffer?(current))
    |> Enum.reverse()
  end

  defp maybe_category(categories, _category, false), do: categories
  defp maybe_category(categories, category, true), do: [category | categories]

  defp configuration_changed?(changed_fields, before, current) do
    Enum.any?(@configuration_fields, &(&1 in changed_fields)) or
      Enum.any?(@immutable_delivery_paths, &(get_in(before, &1) != get_in(current, &1)))
  end

  defp already_effective_fact?(current, categories, opts) do
    Keyword.get(opts, :already_effective?, false) or
      :cancellation in categories or
      provider_change_effective?(current)
  end

  defp provider_change_effective?(current),
    do: get_in(current, ["extensions", "provider_change", "effective"]) == true

  defp counteroffer?(current), do: is_map(get_in(current, ["extensions", "counteroffer"]))

  defp category_requires_approval?(policy, categories) do
    required = MapSet.new(policy.changes_always_requiring_approval)
    Enum.any?(categories, &MapSet.member?(required, Atom.to_string(&1)))
  end

  defp tolerance_violations(policy, before, current, changed_fields) do
    []
    |> timing_violations(policy, before, current, changed_fields)
    |> duration_violations(policy, current)
    |> capacity_violations(policy, current)
    |> resource_violations(policy, before, current, changed_fields)
    |> cost_violations(policy, before, current)
    |> Enum.reverse()
  end

  defp timing_violations(violations, policy, before, current, changed_fields) do
    violations
    |> time_shift_violation(
      "starts_at",
      before,
      current,
      changed_fields,
      policy.maximum_earlier_start_shift_seconds,
      policy.maximum_later_start_shift_seconds
    )
    |> time_shift_violation(
      "ends_at",
      before,
      current,
      changed_fields,
      policy.maximum_earlier_end_shift_seconds,
      policy.maximum_later_end_shift_seconds
    )
  end

  defp time_shift_violation(
         violations,
         field,
         before,
         current,
         changed_fields,
         max_earlier,
         max_later
       ) do
    if field in changed_fields do
      case shift_seconds(before[field], current[field]) do
        {:ok, shift} when shift < 0 and abs(shift) > max_earlier ->
          ["#{field}_earlier_shift_exceeds_policy" | violations]

        {:ok, shift} when shift > max_later ->
          ["#{field}_later_shift_exceeds_policy" | violations]

        {:ok, _shift} ->
          violations

        :error ->
          ["#{field}_shift_missing_or_invalid" | violations]
      end
    else
      violations
    end
  end

  defp duration_violations(violations, %{minimum_retained_duration_seconds: nil}, _after),
    do: violations

  defp duration_violations(violations, policy, current) do
    case duration_seconds(current) do
      {:ok, duration} when duration >= policy.minimum_retained_duration_seconds -> violations
      {:ok, _duration} -> ["retained_duration_below_policy" | violations]
      :error -> ["retained_duration_missing_or_invalid" | violations]
    end
  end

  defp capacity_violations(
         violations,
         %{minimum_retained_estimated_capacity_bytes: nil},
         _after
       ),
       do: violations

  defp capacity_violations(violations, policy, current) do
    case estimated_capacity(current) do
      value
      when is_integer(value) and value >= policy.minimum_retained_estimated_capacity_bytes ->
        violations

      value when is_integer(value) ->
        ["retained_capacity_below_policy" | violations]

      _value ->
        ["retained_capacity_missing_or_invalid" | violations]
    end
  end

  defp resource_violations(violations, policy, before, current, changed_fields) do
    violations
    |> station_violation(policy, current, changed_fields)
    |> equivalent_resource_violation(policy, before, current, changed_fields)
  end

  defp station_violation(violations, policy, current, changed_fields) do
    if "ground_station_ref" in changed_fields and
         current["ground_station_ref"] not in policy.approved_station_substitutions,
       do: ["station_substitution_not_approved" | violations],
       else: violations
  end

  defp equivalent_resource_violation(violations, policy, before, current, changed_fields) do
    if "antenna_or_service_pool_ref" in changed_fields do
      allowed = policy.approved_equivalent_resource_substitutions
      pair = "#{before["antenna_or_service_pool_ref"]}->#{current["antenna_or_service_pool_ref"]}"

      if current["antenna_or_service_pool_ref"] in allowed or pair in allowed,
        do: violations,
        else: ["resource_substitution_not_equivalent" | violations]
    else
      violations
    end
  end

  defp cost_violations(violations, %{maximum_cost_delta: nil}, _before, _after),
    do: violations

  defp cost_violations(violations, policy, before, current) do
    before_cost = get_in(before, ["extensions", "cost"])
    after_cost = get_in(current, ["extensions", "cost"])

    cond do
      is_number(before_cost) and is_number(after_cost) and
          after_cost - before_cost <= policy.maximum_cost_delta ->
        violations

      is_number(before_cost) and is_number(after_cost) ->
        ["cost_delta_exceeds_policy" | violations]

      before_cost == after_cost ->
        violations

      true ->
        ["cost_delta_missing_or_invalid" | violations]
    end
  end

  defp capacity_changed?(before, current),
    do: estimated_capacity(before) != estimated_capacity(current)

  defp cost_changed?(before, current),
    do: get_in(before, ["extensions", "cost"]) != get_in(current, ["extensions", "cost"])

  defp impact(before, current) do
    %{
      "start_shift_seconds" => shift_value(before["starts_at"], current["starts_at"]),
      "end_shift_seconds" => shift_value(before["ends_at"], current["ends_at"]),
      "retained_duration_seconds" => duration_value(current),
      "estimated_capacity_bytes" => estimated_capacity(current),
      "before_ground_station_ref" => before["ground_station_ref"],
      "after_ground_station_ref" => current["ground_station_ref"],
      "before_resource_ref" => before["antenna_or_service_pool_ref"],
      "after_resource_ref" => current["antenna_or_service_pool_ref"]
    }
  end

  defp shift_value(before, current) do
    case shift_seconds(before, current) do
      {:ok, value} -> value
      :error -> nil
    end
  end

  defp duration_value(snapshot) do
    case duration_seconds(snapshot) do
      {:ok, value} -> value
      :error -> nil
    end
  end

  defp estimated_capacity(snapshot),
    do: get_in(snapshot, ["extensions", "estimated_capacity", "value"])

  defp duration_seconds(snapshot) do
    with {:ok, starts_at, _offset} <- DateTime.from_iso8601(snapshot["starts_at"] || ""),
         {:ok, ends_at, _offset} <- DateTime.from_iso8601(snapshot["ends_at"] || "") do
      {:ok, DateTime.diff(ends_at, starts_at)}
    else
      _error -> :error
    end
  end

  defp shift_seconds(before, current) do
    with {:ok, before_at, _offset} <- DateTime.from_iso8601(before || ""),
         {:ok, after_at, _offset} <- DateTime.from_iso8601(current || "") do
      {:ok, DateTime.diff(after_at, before_at)}
    else
      _error -> :error
    end
  end
end
