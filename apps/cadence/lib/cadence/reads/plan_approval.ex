defmodule Cadence.Reads.PlanApproval do
  @moduledoc """
  The latest approval decision on a plan version, for plan detail (`approval`, backlog): who
  approved or sent it back, when, why, and the unmet requirements the approver acknowledged
  (`exceptions`, DECISIONS #28).
  """

  alias Cadence.ContactPlanning.ContactPlanApprovals

  @spec latest(binary(), binary(), binary(), pos_integer()) :: map() | nil
  def latest(organization_id, mission_id, plan_id, version) do
    organization_id
    |> ContactPlanApprovals.list(mission_id, plan_id)
    |> Enum.filter(&(&1.contact_plan_version == version))
    |> Enum.max_by(&DateTime.to_unix(&1.decided_at, :microsecond), fn -> nil end)
    |> view()
  end

  @doc false
  # The approval shape for one decision (also the plan history's decisions, U69 A10).
  def view(nil), do: nil

  def view(approval) do
    %{
      decision: approval.decision,
      actor: actor(approval),
      at: approval.decided_at,
      reason: approval.reason,
      exceptions: Enum.map(approval.exceptions || [], &exception/1)
    }
  end

  defp actor(%{actor_document: %{} = doc} = approval) do
    %{
      kind: doc["kind"] || to_string(approval.actor_kind),
      id: doc["id"] || approval.actor_id,
      # Never the email a row written before #466 may hold.
      name: doc["display_name"] || doc["name"]
    }
  end

  defp actor(approval),
    do: %{kind: to_string(approval.actor_kind), id: approval.actor_id, name: nil}

  # Join `requirement_id` with plan detail's `unmet[]` for the requirement's description.
  defp exception(exception) do
    %{
      requirement_id: exception["contact_requirement_id"],
      requirement_version: exception["contact_requirement_version"],
      reason: exception["reason"]
    }
  end
end
