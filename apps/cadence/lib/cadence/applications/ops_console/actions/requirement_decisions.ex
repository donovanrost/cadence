defmodule Cadence.Applications.OpsConsole.Actions.RequirementDecisions do
  @moduledoc "Exact reviewed requirement and run references for host planning decisions."
  alias Cadence.Auth.Scope
  alias Cadence.ContactPlanning.{ContactPlans, ContactRequirements, Planner}

  @evidence_keys ~w(contract_version organization_id mission_id requirement_id requirement_version content_sha256)

  def plan(%Scope{} = scope, mission_id, params) do
    with :ok <- exact_map(params, ~w(contact_requirement_id requirement_evidence)),
         {:ok, requirement, version} <- reviewed(scope, mission_id, params) do
      Planner.run(scope, mission_id, requirement.contact_requirement_id, version.version)
    end
  end

  def create_plan(%Scope{} = scope, mission_id, params) do
    with :ok <-
           exact_map(
             params,
             ~w(contact_requirement_id requirement_evidence planning_run_id selected_snapshot_ids)
           ),
         {:ok, requirement, version} <- reviewed(scope, mission_id, params),
         {:ok, run_id} <- identifier(params["planning_run_id"]),
         {:ok, ids} <- selected_ids(params["selected_snapshot_ids"]),
         {:ok, run} <- Planner.fetch_run(scope.organization_id, mission_id, run_id),
         :ok <- run_matches(run, requirement, version),
         :ok <- snapshots_match(scope.organization_id, mission_id, run_id, version, ids) do
      ContactPlans.create(scope, mission_id, %{
        planning_run_ids: [run_id],
        selected_snapshot_ids: ids,
        rationale: "Operator-selected provider windows for #{version.contact_intent}"
      })
    end
  end

  defp reviewed(scope, mission_id, params) do
    with {:ok, requirement_id} <- identifier(params["contact_requirement_id"]),
         {:ok, evidence} <- evidence(params["requirement_evidence"]),
         :ok <- scope_matches(scope, mission_id, requirement_id, evidence),
         {:ok, requirement, version} <-
           ContactRequirements.fetch(scope.organization_id, mission_id, requirement_id),
         :ok <- current_matches(requirement, version, evidence) do
      {:ok, requirement, version}
    end
  end

  defp evidence(value) do
    with :ok <- exact_map(value, @evidence_keys),
         true <- value["contract_version"] === 1,
         :ok <- evidence_ids(value),
         version when is_integer(version) and version in 1..9_007_199_254_740_991 <-
           value["requirement_version"],
         hash when is_binary(hash) <- value["content_sha256"],
         true <- Regex.match?(~r/\A[0-9a-f]{64}\z/, hash) do
      {:ok, value}
    else
      _ -> {:error, :invalid_requirement_evidence}
    end
  end

  defp evidence_ids(value) do
    if Enum.all?(~w(organization_id mission_id requirement_id), fn key ->
         match?({:ok, _}, identifier(value[key]))
       end), do: :ok, else: {:error, :invalid_requirement_evidence}
  end

  defp scope_matches(scope, mission_id, requirement_id, evidence) do
    if scope.mission_id in [nil, mission_id] and
         evidence["organization_id"] == scope.organization_id and
         evidence["mission_id"] == mission_id and
         evidence["requirement_id"] == requirement_id, do: :ok, else: {:error, :scope_mismatch}
  end

  defp current_matches(requirement, version, evidence) do
    cond do
      requirement.lifecycle_state != :active ->
        {:error, :contact_requirement_inactive}

      version.version != evidence["requirement_version"] ->
        {:error, :stale_contact_requirement_evidence}

      version.content_sha256 != evidence["content_sha256"] ->
        {:error, :stale_contact_requirement_evidence}

      true ->
        :ok
    end
  end

  defp run_matches(run, requirement, version) do
    cond do
      run.contact_requirement_id != requirement.contact_requirement_id ->
        {:error, :planning_run_scope_mismatch}

      run.contact_requirement_version != version.version ->
        {:error, :planning_run_requirement_version_mismatch}

      run.lifecycle_state == :running ->
        {:error, :contact_plan_planning_run_incomplete}

      true ->
        :ok
    end
  end

  defp snapshots_match(organization_id, mission_id, run_id, version, ids) do
    if Enum.all?(ids, fn id ->
         snapshot_matches?(organization_id, mission_id, run_id, version, id)
       end), do: :ok, else: {:error, :opportunity_scope_mismatch}
  end

  defp snapshot_matches?(organization_id, mission_id, run_id, version, id) do
    case ContactPlans.fetch_opportunity_snapshot(organization_id, mission_id, id) do
      {:ok, snapshot} ->
        snapshot.contact_planning_run_id == run_id and
          snapshot.contact_requirement_id == version.contact_requirement_id and
          snapshot.contact_requirement_version == version.version

      _ ->
        false
    end
  end

  defp selected_ids(ids) when is_list(ids) and length(ids) in 1..200 do
    if length(Enum.uniq(ids)) == length(ids) and Enum.all?(ids, &match?({:ok, _}, identifier(&1))),
      do: {:ok, ids},
      else: {:error, :invalid_opportunity_selection}
  end

  defp selected_ids(_), do: {:error, :invalid_opportunity_selection}

  defp identifier(value) when is_binary(value) and byte_size(value) in 1..256 do
    if Regex.match?(~r/[\x00-\x20\x7f]/, value),
      do: {:error, :invalid_identifier},
      else: {:ok, value}
  end

  defp identifier(_), do: {:error, :invalid_identifier}

  defp exact_map(value, keys) when is_map(value) do
    if Enum.sort(Map.keys(value)) == Enum.sort(keys),
      do: :ok,
      else: {:error, :invalid_requirement_decision}
  end

  defp exact_map(_, _), do: {:error, :invalid_requirement_decision}
end
