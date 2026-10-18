defmodule Cadence.ContactPlanning.FleetRunReviews do
  @moduledoc "Exact scoped run evidence shared by semantic reads and reviewed operator decisions."
  alias Cadence.Auth.{Policy, Scope}
  alias Cadence.ContactPlanning.{ContentHash, FleetPlanningPolicies, FleetPlanningRuns}

  def load(%Scope{} = scope, mission_id, run_id) do
    with :ok <- authorize(scope, mission_id),
         {:ok, run} <- FleetPlanningRuns.fetch(scope.organization_id, mission_id, run_id),
         {:ok, policy} <-
           FleetPlanningPolicies.fetch_version(
             scope.organization_id,
             mission_id,
             run.fleet_planning_policy_id,
             run.fleet_planning_policy_version
           ),
         refs <-
           FleetPlanningRuns.list_requirement_refs(scope.organization_id, mission_id, run_id),
         :ok <- exact_inputs(run, policy, refs) do
      {:ok, %{run: run, policy: policy, refs: refs, evidence: evidence(run, refs)}}
    end
  end

  def authorize(scope, mission),
    do:
      Policy.authorize(scope, :operate_mission, %{
        organization_id: scope.organization_id,
        mission_id: mission
      })

  def evidence(run, refs) do
    %{
      "contract_version" => 1,
      "organization_id" => run.organization_id,
      "mission_id" => run.mission_id,
      "run_id" => run.fleet_planning_run_id,
      "lifecycle_state" => Atom.to_string(run.lifecycle_state),
      "phase" => Atom.to_string(run.phase),
      "sha256" =>
        ContentHash.sha256(%{
          run: Map.from_struct(run),
          inputs: Enum.map(refs, &Map.from_struct/1)
        })
    }
  end

  def validate_evidence(e) when is_map(e) do
    keys = ~w(contract_version organization_id mission_id run_id lifecycle_state phase sha256)

    if Enum.sort(Map.keys(e)) == Enum.sort(keys) and e["contract_version"] === 1 and
         Enum.all?(
           ~w(organization_id mission_id run_id lifecycle_state phase),
           &(is_binary(e[&1]) and byte_size(e[&1]) in 1..240)
         ) and
         is_binary(e["sha256"]) and Regex.match?(~r/\A[a-f0-9]{64}\z/, e["sha256"]),
       do: :ok,
       else: {:error, :fleet_run_review_invalid}
  end

  def validate_evidence(_), do: {:error, :fleet_run_review_invalid}

  def continuable?(%{lifecycle_state: state, phase: phase}),
    do: state in [:queued, :running] and phase != :finished

  defp exact_inputs(run, policy, refs) do
    expected = run.input_document["requirements"]

    actual =
      Enum.map(refs, &{&1.contact_requirement_id, &1.contact_requirement_version}) |> Enum.sort()

    with true <- is_list(expected) and length(expected) in 1..10_000,
         true <- run.input_document["requirement_count"] == length(refs),
         true <- run.input_document["policy_content_sha256"] == policy.content_sha256,
         true <- Enum.all?(expected, &is_map/1),
         expected_refs <-
           Enum.map(expected, &{&1["contact_requirement_id"], &1["contact_requirement_version"]})
           |> Enum.sort(),
         true <- expected_refs == actual,
         true <- length(Enum.uniq(actual)) == length(actual) do
      :ok
    else
      _ -> {:error, :fleet_run_inputs_unavailable}
    end
  end
end
