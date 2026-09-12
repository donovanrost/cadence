defmodule Cadence.Applications.OpsConsole.Actions.PlanReviewWorkflow do
  @moduledoc "Captured plan review commands and actual governed decision results."
  alias Cadence.Applications.OpsConsole.Actions.PlanDecisions
  alias Cadence.Auth.Policy
  alias Cadence.Management.Contacts

  @actions ~w(submit-plan approve-plan reject-plan execute-plan)
  @no_effect ~w(stale_contact_plan_evidence stale_contact_plan_version
    contact_plan_not_draft contact_plan_not_pending_approval contact_plan_version_already_decided
    contact_plan_not_executable contact_plan_not_approved contact_plan_not_found
    invalid_plan_evidence invalid_plan_decision scope_mismatch forbidden unauthorized
    stale_contact_plan_content contact_plan_not_satisfied contact_plan_approval_policy_not_satisfied
    contact_plan_opportunity_expired contact_plan_policy_snapshot_changed
    contact_plan_requirement_not_found contact_plan_requirement_not_active
    contact_plan_requirement_changed contact_plan_requirement_version_not_found
    contact_plan_version_not_found contact_plan_decision_reason_required)a

  def actions, do: @actions

  def execute(scope, mission, action, input, detail) when action in @actions do
    with :ok <- authorize(scope, mission, action),
         :ok <- captured(input, detail),
         {:ok, result} <- dispatch(scope, mission, action, input) do
      {:ok,
       Map.merge(result, %{
         contract_version: 1,
         actor_id: scope.user.user_id,
         organization_id: scope.organization_id,
         mission_id: mission,
         action: action
       })}
    else
      {:error, :forbidden} -> {:rejected, ["forbidden"]}
      {:error, reason} when reason in @no_effect -> {:rejected, ["review_changed"]}
      # Approval and execution can fail after committing work. An unclassified
      # error is not a promise that no governed effect occurred.
      _ -> {:error, :unconfirmed}
    end
  end

  def execute(_, _, _, _, _), do: {:rejected, ["invalid_input"]}

  defp authorize(scope, mission, action) do
    permission =
      if action in ~w(approve-plan reject-plan),
        do: :approve_contact_plans,
        else: :operate_mission

    if scope.mission_id in [nil, mission] and
         Policy.authorize(scope, permission, %{
           organization_id: scope.organization_id,
           mission_id: mission
         }) == :ok,
       do: :ok,
       else: {:error, :forbidden}
  end

  defp captured(input, detail) do
    expected = %{
      "contract_version" => 1,
      "organization_id" => detail["context"]["organization_id"],
      "mission_id" => detail["context"]["mission_id"],
      "plan_id" => detail["plan"]["id"],
      "plan_version" => detail["plan"]["version"],
      "content_sha256" => detail["plan"]["content_sha256"]
    }

    if input["plan_evidence"] == expected and input["contact_plan_id"] == expected["plan_id"],
      do: :ok,
      else: {:error, :stale_contact_plan_evidence}
  end

  defp dispatch(scope, mission, "submit-plan", input) do
    with {:ok, id, version} <- PlanDecisions.submit(scope, mission, input),
         do: {:ok, result(id, version)}
  end

  defp dispatch(scope, mission, action, input) when action in ~w(approve-plan reject-plan) do
    with {:ok, id, version} <- PlanDecisions.decide(scope, mission, action, input),
         do: {:ok, result(id, version)}
  end

  defp dispatch(scope, mission, "execute-plan", input) do
    with {:ok, %{plan: plan, items: items}} <- PlanDecisions.execute(scope, mission, input),
         {:ok, version} <-
           Contacts.fetch_plan_version(
             scope.organization_id,
             mission,
             plan.contact_plan_id,
             plan.approved_version
           ) do
      {:ok,
       Map.merge(result(plan.contact_plan_id, version), %{
         lifecycleState: Atom.to_string(plan.lifecycle_state),
         executionItemCount: length(items)
       })}
    end
  end

  defp result(id, version),
    do: %{contactPlanId: id, version: version.version, contentSha256: version.content_sha256}
end
