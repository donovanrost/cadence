defmodule Cadence.Applications.OpsConsole.Actions.PlanDecisions do
  @moduledoc "Exact reviewed plan evidence for host submission, decisions and execution."

  alias Cadence.Auth.Scope
  alias Cadence.Control.Contacts, as: ControlContacts
  alias Cadence.Management.Contacts, as: ManagementContacts

  @keys ~w(contract_version organization_id mission_id plan_id plan_version content_sha256)

  def submit(%Scope{} = scope, mission_id, params) do
    with {:ok, plan, version, reason} <- reason_review(scope, mission_id, params, "submission"),
         {:ok, updated} <-
           ManagementContacts.submit_plan(
             scope,
             mission_id,
             plan.contact_plan_id,
             version.version,
             reason
           ) do
      {:ok, updated.contact_plan_id, version}
    end
  end

  def decide(%Scope{} = scope, mission_id, action, params)
      when action in ["approve-plan", "reject-plan"] do
    with {:ok, plan, version, reason} <- reason_review(scope, mission_id, params, "decision") do
      apply_decision(action, scope, mission_id, plan, version, reason)
    end
  end

  def execute(%Scope{} = scope, mission_id, params) do
    with :ok <- exact_map(params, ~w(contact_plan_id plan_evidence)),
         {:ok, plan, version} <- reviewed(scope, mission_id, params) do
      ControlContacts.execute_approved_plan(scope, mission_id, plan.contact_plan_id,
        expected_plan_version: version.version,
        expected_plan_hash: version.content_sha256
      )
    end
  end

  defp reason_review(scope, mission_id, params, wrapper) do
    with :ok <- exact_map(params, ["contact_plan_id", "plan_evidence", wrapper]),
         :ok <- exact_map(params[wrapper], ["reason"]),
         reason when is_binary(reason) <- params[wrapper]["reason"],
         true <-
           String.valid?(reason) and byte_size(reason) in 1..4096 and String.trim(reason) != "",
         {:ok, plan, version} <- reviewed(scope, mission_id, params) do
      {:ok, plan, version, reason}
    else
      {:error, _} = error -> error
      _ -> {:error, :invalid_plan_decision}
    end
  end

  defp reviewed(scope, mission_id, params) do
    evidence = params["plan_evidence"]

    with :ok <- evidence(evidence),
         true <- identifier?(params["contact_plan_id"]),
         :ok <- scope_matches(scope, mission_id, params["contact_plan_id"], evidence),
         {:ok, plan, version} <-
           ManagementContacts.fetch_plan(
             scope.organization_id,
             mission_id,
             params["contact_plan_id"]
           ),
         true <-
           version.version == evidence["plan_version"] and
             version.content_sha256 == evidence["content_sha256"] do
      {:ok, plan, version}
    else
      {:error, _} = error -> error
      _ -> {:error, :stale_contact_plan_evidence}
    end
  end

  defp evidence(value) do
    with :ok <- exact_map(value, @keys),
         true <- value["contract_version"] === 1,
         true <- Enum.all?(~w(organization_id mission_id plan_id), &identifier?(value[&1])),
         version when is_integer(version) and version in 1..9_007_199_254_740_991 <-
           value["plan_version"],
         hash when is_binary(hash) <- value["content_sha256"],
         true <- byte_size(hash) == 64 and Regex.match?(~r/\A[0-9a-f]{64}\z/, hash) do
      :ok
    else
      _ -> {:error, :invalid_plan_evidence}
    end
  end

  defp scope_matches(scope, mission_id, plan_id, evidence) do
    if scope.mission_id in [nil, mission_id] and
         evidence["organization_id"] == scope.organization_id and
         evidence["mission_id"] == mission_id and evidence["plan_id"] == plan_id,
       do: :ok,
       else: {:error, :scope_mismatch}
  end

  defp apply_decision("approve-plan", scope, mission_id, plan, version, reason) do
    with {:ok, approved} <-
           ControlContacts.approve_and_accept_plan(
             scope,
             mission_id,
             plan.contact_plan_id,
             version.version,
             version.content_sha256,
             reason
           ) do
      {:ok, approved.contact_plan_id, version}
    end
  end

  defp apply_decision("reject-plan", scope, mission_id, plan, version, reason) do
    with {:ok, updated, ^version, _approval} <-
           ManagementContacts.reject_plan(
             scope,
             mission_id,
             plan.contact_plan_id,
             version.version,
             version.content_sha256,
             reason
           ) do
      {:ok, updated.contact_plan_id, version}
    end
  end

  defp identifier?(value) when is_binary(value) and byte_size(value) in 1..240,
    do: String.valid?(value) and not Regex.match?(~r/[\x00-\x20\x7f]/, value)

  defp identifier?(_), do: false

  defp exact_map(value, keys) when is_map(value) do
    if Enum.sort(Map.keys(value)) == Enum.sort(keys),
      do: :ok,
      else: {:error, :invalid_plan_decision}
  end

  defp exact_map(_, _), do: {:error, :invalid_plan_decision}
end
