defmodule Cadence.Applications.OpsConsole.Actions.FleetPolicyEditing do
  @moduledoc "Exact-base, lossless policy form preparation for the Fleet Planning host actions."

  alias Cadence.Applications.OpsConsole.Actions.FleetPlanningFormDuration
  alias Cadence.Auth.Scope
  alias Cadence.ContactPlanning.{FleetPlanningPolicies, FleetPlanningPolicyDocument}

  @fields %{
    "max_horizon_duration" => {:horizon_document, "max_horizon_seconds", :duration},
    "requirement_concurrency" => {:horizon_document, "requirement_concurrency", :integer},
    "provider_search_concurrency" => {:horizon_document, "provider_search_concurrency", :integer},
    "reuse_freshness_seconds" => {:horizon_document, "reuse_freshness_seconds", :integer},
    "max_contacts" => {:budget_quota_document, "max_contacts", :optional_integer},
    "max_estimated_cost_micros" =>
      {:budget_quota_document, "max_estimated_cost_micros", :optional_integer},
    "currency" => {:budget_quota_document, "currency", :currency},
    "critical_contact_reserve" => {:budget_quota_document, "critical_contact_reserve", :integer},
    "automation_mode" => {:automation_repair_document, "mode", :mode},
    "execution_concurrency" => {:automation_repair_document, "execution_concurrency", :integer},
    "max_repair_attempts" => {:automation_repair_document, "max_repair_attempts", :integer},
    "repair_horizon_duration" =>
      {:automation_repair_document, "repair_horizon_seconds", :duration},
    "automatic_submission" => {:automation_repair_document, "automatic_submission", :boolean},
    "distinct_provider_required" =>
      {:redundancy_document, "distinct_provider_required", :boolean},
    "distinct_station_required" => {:redundancy_document, "distinct_station_required", :boolean},
    "distinct_service_pool_required" =>
      {:redundancy_document, "distinct_service_pool_required", :boolean}
  }
  @normalizers %{
    horizon_document: :normalize_horizon,
    budget_quota_document: :normalize_budgets,
    automation_repair_document: :normalize_automation,
    redundancy_document: :normalize_redundancy
  }

  def validate_input(params) do
    with true <- exact_keys?(Map.delete(params, "mission_id"), ~w(policy edit_reference)),
         :ok <- validate_reference(params["edit_reference"]),
         {:ok, _patch} <- parse_fields(params["policy"]) do
      :ok
    else
      {:error, _} = error -> error
      _ -> {:error, :invalid_fleet_policy_form}
    end
  end

  def prepare(%Scope{} = scope, mission_id, params) do
    reference = params["edit_reference"]

    with :ok <- validate_input(params),
         :ok <- same_scope(scope, mission_id, reference),
         {:ok, base} <- reviewed_base(scope, mission_id, reference["base"]),
         {:ok, patch} <- parse_fields(params["policy"]),
         {:ok, attrs} <- merge_documents(base, patch) do
      {:ok, reference["base"], attrs}
    end
  end

  def save(scope, mission_id, params) do
    with {:ok, base, attrs} <- prepare(scope, mission_id, params) do
      persist(scope, mission_id, base, attrs)
    end
  end

  defp persist(scope, mission_id, nil, attrs),
    do: FleetPlanningPolicies.create(scope, mission_id, attrs)

  defp persist(scope, mission_id, base, attrs),
    do:
      FleetPlanningPolicies.version(
        scope,
        mission_id,
        base["policy_id"],
        base["policy_version"],
        attrs
      )

  defp validate_reference(reference) do
    with true <- exact_keys?(reference, ~w(contract_version organization_id mission_id base)),
         true <- reference["contract_version"] === 1,
         true <-
           identifier?(reference["organization_id"]) and identifier?(reference["mission_id"]),
         true <- valid_base?(reference["base"], reference) do
      :ok
    else
      _ -> {:error, :invalid_fleet_policy_edit_reference}
    end
  end

  defp valid_base?(nil, _reference), do: true

  defp valid_base?(base, reference) do
    exact_keys?(
      base,
      ~w(contract_version organization_id mission_id policy_id policy_version content_sha256)
    ) and
      base["contract_version"] === 1 and
      base["organization_id"] == reference["organization_id"] and
      base["mission_id"] == reference["mission_id"] and
      identifier?(base["policy_id"]) and
      is_integer(base["policy_version"]) and base["policy_version"] in 1..9_007_199_254_740_991 and
      is_binary(base["content_sha256"]) and
      Regex.match?(~r/\A[0-9a-f]{64}\z/, base["content_sha256"])
  end

  defp identifier?(value) when is_binary(value),
    do: byte_size(value) in 1..256 and not Regex.match?(~r/[\x00-\x20\x7f]/, value)

  defp identifier?(_), do: false

  defp exact_keys?(value, keys) when is_map(value),
    do: Enum.sort(Map.keys(value)) == Enum.sort(keys)

  defp exact_keys?(_, _), do: false

  defp same_scope(scope, mission_id, reference) do
    if reference["organization_id"] == scope.organization_id and
         reference["mission_id"] == mission_id,
       do: :ok,
       else: {:error, :scope_mismatch}
  end

  defp reviewed_base(scope, mission_id, expected) do
    scope.organization_id
    |> FleetPlanningPolicies.fetch(mission_id)
    |> match_base(expected)
  end

  defp match_base({:error, :fleet_planning_policy_not_found}, nil), do: {:ok, nil}
  defp match_base({:error, _} = error, _expected), do: error

  defp match_base({:ok, policy, version}, expected) when is_map(expected) do
    if policy.lifecycle_state != :retired and
         expected["policy_id"] == policy.fleet_planning_policy_id and
         expected["policy_version"] == version.version and
         expected["content_sha256"] == version.content_sha256,
       do: {:ok, version},
       else: {:error, :stale_fleet_planning_policy_evidence}
  end

  defp match_base(_, _), do: {:error, :stale_fleet_planning_policy_evidence}

  defp parse_fields(params) do
    if exact_keys?(params, Map.keys(@fields)) do
      Enum.reduce_while(@fields, {:ok, %{}}, &parse_field(&1, &2, params))
    else
      {:error, :invalid_fleet_policy_form}
    end
  end

  defp parse_field({field, {document, key, type}}, {:ok, patch}, params) do
    case parse(type, params[field]) do
      {:ok, value} ->
        {:cont, {:ok, Map.update(patch, document, %{key => value}, &Map.put(&1, key, value))}}

      :error ->
        {:halt, {:error, :invalid_fleet_policy_form}}
    end
  end

  defp merge_documents(base, patch) do
    Enum.reduce_while(patch, {:ok, %{}}, fn {document, values}, {:ok, attrs} ->
      original = if base, do: Map.fetch!(base, document), else: %{}

      case apply(FleetPlanningPolicyDocument, Map.fetch!(@normalizers, document), [
             Map.merge(original, values)
           ]) do
        {:ok, normalized} -> {:cont, {:ok, Map.put(attrs, document, normalized)}}
        {:error, _} = error -> {:halt, error}
      end
    end)
  end

  defp parse(:optional_integer, ""), do: {:ok, nil}
  defp parse(:optional_integer, value), do: parse(:integer, value)

  defp parse(:integer, value) when is_binary(value) and byte_size(value) <= 16 do
    case Integer.parse(value) do
      {integer, ""} when integer >= 0 and integer <= 9_007_199_254_740_991 -> {:ok, integer}
      _ -> :error
    end
  end

  defp parse(:boolean, "true"), do: {:ok, true}
  defp parse(:boolean, "false"), do: {:ok, false}
  defp parse(:currency, ""), do: {:ok, nil}

  defp parse(:currency, value) when is_binary(value) and byte_size(value) <= 3,
    do: {:ok, String.upcase(value)}

  defp parse(:mode, value) when value in ~w(advisory approval_required bounded_automatic),
    do: {:ok, value}

  defp parse(:duration, value), do: FleetPlanningFormDuration.parse(value)

  defp parse(_, _), do: :error
end
