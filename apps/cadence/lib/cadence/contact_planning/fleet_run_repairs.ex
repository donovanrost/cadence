defmodule Cadence.ContactPlanning.FleetRunRepairs do
  @moduledoc "Reviewed repair source and atomic creation of a successor fleet run."
  alias Cadence.ContactPlanning.{
    ContactPlanExecutions,
    ContactPlans,
    ContentHash,
    FleetPlanningPolicies,
    FleetPlanningRuns,
    FleetRepairs,
    FleetRunReviews,
    FleetStartProjection
  }

  alias Cadence.Repo

  def review(scope, snapshot) do
    run = snapshot.run

    with true <- is_binary(run.candidate_contact_plan_id),
         {:ok, source} <-
           FleetRepairs.source(
             run.organization_id,
             run.mission_id,
             run.fleet_planning_run_id,
             run.candidate_contact_plan_id,
             run.candidate_contact_plan_version
           ),
         {:ok, _, policy} <-
           FleetPlanningPolicies.fetch_active(run.organization_id, run.mission_id),
         items <-
           ContactPlanExecutions.list(
             run.organization_id,
             run.mission_id,
             source.plan.contact_plan_id,
             source.plan_version.version
           ),
         true <- length(items) <= 10_000 and length(source.locked_commitments) <= 10_000 do
      {:ok,
       %{
         source: source,
         policy: policy,
         evidence: evidence(snapshot, source, policy, items),
         allowed:
           source.repair_attempt <= policy.automation_repair_document["max_repair_attempts"],
         context: %{organization_id: scope.organization_id, mission_id: run.mission_id}
       }}
    else
      false -> {:error, :fleet_repair_source_unavailable}
      {:error, _} = error -> error
    end
  end

  def policy_projection(review) do
    review.policy
    |> FleetStartProjection.policy()
    |> Map.merge(%{
      max_repair_horizon_seconds:
        min(
          review.policy.horizon_document["max_horizon_seconds"],
          review.policy.automation_repair_document["repair_horizon_seconds"]
        ),
      max_attempts: review.policy.automation_repair_document["max_repair_attempts"]
    })
  end

  def create(scope, mission, run_id, expected, window) do
    with :ok <- FleetRunReviews.authorize(scope, mission), :ok <- validate_evidence(expected) do
      Repo.transaction(fn -> claim(scope, mission, run_id, expected, window) end)
      |> case do
        {:ok, run} -> {:ok, run}
        {:error, _} = error -> error
      end
    end
  end

  def validate_evidence(e) when is_map(e) do
    keys =
      ~w(contract_version organization_id mission_id run_id run_sha256 plan_id plan_version plan_sha256 policy_id policy_version policy_sha256 sha256)

    if Enum.sort(Map.keys(e)) == Enum.sort(keys) and e["contract_version"] === 1 and
         Enum.all?(
           ~w(organization_id mission_id run_id plan_id policy_id),
           &(is_binary(e[&1]) and byte_size(e[&1]) in 1..240)
         ) and
         Enum.all?(~w(plan_version policy_version), &(is_integer(e[&1]) and e[&1] > 0)) and
         Enum.all?(
           ~w(run_sha256 plan_sha256 policy_sha256 sha256),
           &(is_binary(e[&1]) and Regex.match?(~r/\A[a-f0-9]{64}\z/, e[&1]))
         ), do: :ok, else: {:error, :fleet_repair_review_invalid}
  end

  def validate_evidence(_), do: {:error, :fleet_repair_review_invalid}

  defp claim(scope, mission, run_id, expected, window) do
    with {:ok, run} <- FleetPlanningRuns.fetch_locked(scope.organization_id, mission, run_id),
         true <- run.candidate_contact_plan_id == expected["plan_id"],
         {:ok, _, _} <-
           ContactPlans.fetch_locked(scope.organization_id, mission, expected["plan_id"]),
         {:ok, _} <-
           ContactPlanExecutions.list_locked(
             scope.organization_id,
             mission,
             expected["plan_id"],
             expected["plan_version"]
           ),
         {:ok, _, _} <- FleetPlanningPolicies.fetch_active_locked(scope.organization_id, mission),
         {:ok, snapshot} <- FleetRunReviews.load(scope, mission, run_id),
         {:ok, reviewed} <- review(scope, snapshot),
         true <- reviewed.allowed and reviewed.evidence === expected,
         :ok <- horizon(window, reviewed),
         {:ok, successor, _} <-
           FleetRepairs.start(
             scope,
             mission,
             run_id,
             expected["plan_id"],
             expected["plan_version"],
             Map.put(window, :creation_review_document, expected)
           ) do
      successor
    else
      false -> Repo.rollback(:fleet_repair_review_changed)
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp horizon(window, review) do
    micros = DateTime.diff(window.horizon_end, window.horizon_start, :microsecond)

    if micros > 0 and micros <= policy_projection(review).max_repair_horizon_seconds * 1_000_000,
      do: :ok,
      else: {:error, :fleet_repair_horizon_exceeded}
  end

  defp evidence(snapshot, source, policy, items) do
    base = %{
      "contract_version" => 1,
      "organization_id" => snapshot.run.organization_id,
      "mission_id" => snapshot.run.mission_id,
      "run_id" => snapshot.run.fleet_planning_run_id,
      "run_sha256" => snapshot.evidence["sha256"],
      "plan_id" => source.plan.contact_plan_id,
      "plan_version" => source.plan_version.version,
      "plan_sha256" => source.plan_version.content_sha256,
      "policy_id" => policy.fleet_planning_policy_id,
      "policy_version" => policy.version,
      "policy_sha256" => policy.content_sha256
    }

    Map.put(
      base,
      "sha256",
      ContentHash.sha256(%{
        identity: base,
        plan_state: source.plan.lifecycle_state,
        attempt: source.repair_attempt,
        executions: Enum.map(items, &Map.from_struct/1),
        locked: Enum.map(source.locked_commitments, &Map.from_struct/1)
      })
    )
  end
end
