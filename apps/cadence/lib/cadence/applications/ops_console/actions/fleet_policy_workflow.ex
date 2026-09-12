defmodule Cadence.Applications.OpsConsole.Actions.FleetPolicyWorkflow do
  @moduledoc "Reviewed policy contribution actions using the existing governed domain owners."
  alias Cadence.Applications.{ActionRequest, HostContext}
  alias Cadence.Applications.OpsConsole.Actions.{FleetPlanning, FleetPolicyEditing}
  alias Cadence.Auth.Policy
  alias Cadence.ContactPlanning.AutomationGrants

  @actions ~w(validate-policy save-policy approve-policy validate-grant issue-grant revoke-grant)
  @rejected ~w(forbidden authenticated_user_required scope_mismatch
    stale_fleet_planning_policy_version stale_fleet_planning_policy_hash
    stale_fleet_planning_policy_evidence fleet_planning_policy_retired
    fleet_planning_policy_already_decided fleet_planning_policy_decision_reason_required
    automation_grant_action_exceeds_policy automation_grant_horizon_exceeds_policy
    automation_grant_contacts_exceed_policy automation_grant_cost_exceeds_policy
    automation_grant_currency_differs_from_policy automation_grant_concurrency_exceeds_policy
    automation_grant_validity_expired automation_service_identity_disabled
    automation_service_identity_scope_mismatch active_fleet_planning_policy_not_found)a
  def actions, do: @actions
  def validation?(event), do: event in ~w(validate-policy validate-grant)

  def admitted?(model, event, input) when is_map(model) and is_map(input) do
    case event do
      event when event in ~w(validate-policy save-policy) -> edit_admitted?(model, input)
      "approve-policy" -> approval_admitted?(model, input)
      event when event in ~w(validate-grant issue-grant) -> grant_admitted?(model, event, input)
      "revoke-grant" -> revocation_admitted?(model, input)
      _ -> false
    end
  end

  def admitted?(_, _, _), do: false

  defp edit_admitted?(model, input) do
    expected =
      Map.merge(model["context"], %{
        "contract_version" => 1,
        "base" => get_in(model, ["current", "reference"])
      })

    model["permissions"]["edit"] and model["state"] != "retired" and
      input["edit_reference"] === expected
  end

  defp approval_admitted?(model, input) do
    reference = get_in(model, ["current", "reference"])

    model["permissions"]["approve"] and is_map(reference) and model["state"] != "retired" and
      reference !== get_in(model, ["active", "reference"]) and
      get_in(input, ["decision", "policy_evidence"]) === reference
  end

  defp grant_admitted?(model, event, input) do
    active = get_in(model, ["active", "reference"])

    model["permissions"]["grants"] and is_map(active) and
      Enum.any?(
        model["identities"]["entries"],
        &(&1["id"] == get_in(input, ["grant", "service_identity_id"]))
      ) and
      (event == "validate-grant" or input["policy_evidence"] === active)
  end

  defp revocation_admitted?(model, input) do
    model["permissions"]["grants"] and
      Enum.any?(model["grants"]["entries"], fn grant ->
        grant["state"] == "active" and grant["reference"] === input["grant_evidence"] and
          grant["reference"]["grant_id"] == get_in(input, ["revocation", "automation_grant_id"])
      end)
  end

  def execute(scope, mission, "save-policy", input) do
    case FleetPolicyEditing.prepare(scope, mission, input) do
      {:ok, _, _} -> legacy(scope, mission, "save-policy", input)
      _ -> {:rejected, :invalid_policy}
    end
  end

  def execute(scope, mission, "revoke-grant", input) do
    with true <- Enum.sort(Map.keys(input)) == ~w(grant_evidence revocation),
         %{"automation_grant_id" => id, "reason" => reason} = revocation <- input["revocation"],
         true <- map_size(revocation) == 2 and is_binary(reason) and byte_size(reason) in 1..2000,
         %{
           "contract_version" => 1,
           "organization_id" => org,
           "mission_id" => mid,
           "grant_id" => ^id,
           "content_sha256" => hash
         } = reference <- input["grant_evidence"],
         true <- map_size(reference) == 5 and org == scope.organization_id and mid == mission,
         true <- is_binary(hash) and Regex.match?(~r/\A[a-f0-9]{64}\z/, hash),
         :ok <- Policy.authorize(scope, :manage_automation_grants, %{organization_id: org}),
         {:ok, grant} <- AutomationGrants.revoke(scope, mission, id, hash, reason) do
      {:ok,
       %{
         "automationGrantId" => grant.automation_grant_id,
         "lifecycleState" => Atom.to_string(grant.lifecycle_state)
       }}
    else
      _ -> {:rejected, :invalid_or_changed_grant}
    end
  end

  def execute(scope, mission, event, input) when event in @actions,
    do: legacy(scope, mission, event, input)

  def execute(_, _, _, _), do: {:rejected, :undeclared_action}

  defp legacy(scope, mission, event, input) do
    request = %ActionRequest{
      application_key: "ops_console",
      application_version: 1,
      surface_id: "fleet_planning_policy",
      surface_version: 1,
      action_id: event,
      params: input
    }

    result =
      FleetPlanning.execute(scope, HostContext.mission(mission), "fleet_planning_policy", request)

    case result do
      {:error, _} when event in ~w(validate-policy validate-grant) -> {:rejected, :invalid_fields}
      {:error, reason} when reason in @rejected -> {:rejected, reason}
      {:error, %Ecto.Changeset{}} -> {:rejected, :invalid_fields}
      {:error, {:invalid_automation_grant, _}} -> {:rejected, :invalid_fields}
      other -> other
    end
  end
end
