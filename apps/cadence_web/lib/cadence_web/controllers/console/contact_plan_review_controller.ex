defmodule CadenceWeb.Console.ContactPlanReviewController do
  @moduledoc """
  An approver's decisions on a plan waiting for approval. `approve` (#257, director 11-19) is the
  only console path that approves: under 'independent' the submitter and the version's author
  are refused, and the approval starts booking off the request. `reject` sends the plan back: it
  returns to `draft` with the approver's reason, recorded as a rejected approval. Contract:
  docs/apogee/api/scheduling.md.
  """

  use CadenceWeb, :controller

  alias Cadence.ContactPlanning.ContactPlans
  alias Cadence.Control.Scheduling
  alias Cadence.Management.Contacts, as: ManagementContacts
  alias Cadence.Reads.ContactPlanOverview
  alias CadenceWeb.Console.{ConfigJSON, ContactPlanWrites, PlanDetail, Problem}

  @doc """
  #257: approves the version the approver saw; 202 with the original answer's body (a replay of
  the same request answers it again with `replayed: true`). Booking starts off the request.
  """
  def approve(conn, %{"plan_id" => plan_id} = params) do
    scope = conn.assigns.current_scope
    mission_id = conn.assigns.current_mission.mission_id

    with {:ok, approve} <- ContactPlanWrites.approve_params(params),
         {:ok, result} <- Scheduling.approve_plan(scope, mission_id, plan_id, approve) do
      case result do
        {:approved, answer, version, sha} ->
          ContactPlanWrites.start_execution(conn, plan_id, version, sha)
          ContactPlanWrites.answer(conn, :approved, answer)

        {:replayed, answer} ->
          ContactPlanWrites.answer(conn, :replayed, answer)
      end
    else
      {:error, reason} -> ContactPlanWrites.refuse(conn, plan_id, reason)
    end
  end

  def reject(conn, %{"plan_id" => plan_id} = params) do
    scope = conn.assigns.current_scope
    mission_id = conn.assigns.current_mission.mission_id

    with {:ok, version, reason} <- reject_params(params),
         {:ok, plan_version} <-
           ContactPlans.fetch_version(scope.organization_id, mission_id, plan_id, version),
         {:ok, _plan, _version, _rejection} <-
           ManagementContacts.reject_plan(
             scope,
             mission_id,
             plan_id,
             version,
             plan_version.content_sha256,
             reason
           ),
         {:ok, plan} <- ContactPlanOverview.plan(scope.organization_id, mission_id, plan_id) do
      # The same plan detail as the other plan writes (drift sweep; lead's K1 reader).
      json(conn, %{data: ConfigJSON.encode(PlanDetail.build(conn, plan))})
    else
      {:error, reason} -> error(conn, reason)
    end
  end

  defp reject_params(params) do
    reason = if is_binary(params["reason"]), do: String.trim(params["reason"]), else: ""

    cond do
      not (is_integer(params["expected_version"]) and params["expected_version"] > 0) ->
        {:error, %{expected_version: "is required (positive integer)"}}

      reason == "" ->
        {:error, %{reason: "is required: say why it's going back"}}

      true ->
        {:ok, params["expected_version"], reason}
    end
  end

  defp error(conn, details) when is_map(details),
    do: Problem.respond(conn, :invalid_params, details)

  defp error(conn, reason)
       when reason in [:contact_plan_version_not_found, :contact_plan_not_found, :plan_not_found],
       do: Problem.respond(conn, :plan_not_found)

  defp error(conn, reason)
       when reason in [:stale_contact_plan_version, :stale_contact_plan_content],
       do: Problem.respond(conn, :plan_changed)

  defp error(conn, :contact_plan_not_pending_approval),
    do: Problem.respond(conn, :plan_not_pending)

  defp error(conn, :forbidden), do: Problem.respond(conn, :forbidden)
  defp error(conn, _reason), do: Problem.respond(conn, :plan_not_pending)
end
