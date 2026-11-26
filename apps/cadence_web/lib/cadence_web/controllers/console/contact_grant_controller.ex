defmodule CadenceWeb.Console.ContactGrantController do
  @moduledoc """
  §11 L3 automation grants (contract scheduling.md §Automation grants): the Policy tab's Grants
  panel. Read for mission operators; issue and revoke for organization admins.
  """

  use CadenceWeb, :controller

  alias Cadence.Control.{PlanningGrantDecisions, PlanningGrants}
  alias CadenceWeb.Console.{ConfigJSON, Problem}

  def index(conn, _params),
    do: reply(conn, :ok, PlanningGrants.load(scope(conn), mission_id(conn)))

  def create(conn, params),
    do: reply(conn, :created, PlanningGrants.issue(scope(conn), mission_id(conn), params), :grant)

  def revoke(conn, %{"grant_id" => id} = params),
    do: reply(conn, :ok, PlanningGrants.revoke(scope(conn), mission_id(conn), id, params), :grant)

  # #283 (U105): approve, reject and narrow take an operation_id; a replay answers the original
  # body with `replayed: true`.
  def approve(conn, %{"grant_id" => id} = params),
    do: decided(conn, PlanningGrantDecisions.approve(scope(conn), mission_id(conn), id, params))

  def reject(conn, %{"grant_id" => id} = params),
    do: decided(conn, PlanningGrantDecisions.reject(scope(conn), mission_id(conn), id, params))

  # #499: resume a grant a tightening suspended (an approval-like act, with replays).
  def resume(conn, %{"grant_id" => id} = params),
    do: decided(conn, PlanningGrantDecisions.resume(scope(conn), mission_id(conn), id, params))

  def narrow(conn, %{"grant_id" => id} = params),
    do: decided(conn, PlanningGrantDecisions.narrow(scope(conn), mission_id(conn), id, params))

  defp decided(conn, {:ok, {:decided, row}}),
    do: json(conn, %{data: %{grant: row, replayed: false}})

  defp decided(conn, {:ok, {:replayed, row}}),
    do: json(conn, %{data: %{grant: row, replayed: true}})

  defp decided(conn, {:error, reason}), do: error(conn, reason)

  defp reply(conn, status, result, wrap \\ nil)

  defp reply(conn, status, {:ok, data}, wrap) do
    data = if wrap, do: %{wrap => data}, else: data
    conn |> put_status(status) |> json(%{data: ConfigJSON.encode(data)})
  end

  defp reply(conn, _status, {:error, reason}, _wrap), do: error(conn, reason)

  defp error(conn, {:invalid_params, details}),
    do: Problem.respond(conn, :invalid_params, details)

  defp error(conn, {:policy_changed, active}),
    do: Problem.respond(conn, :policy_changed, %{active_version: active})

  defp error(conn, :policy_changed),
    do: Problem.respond(conn, :policy_changed, %{active_version: nil})

  defp error(conn, reason) when reason in [:grant_changed, :grant_not_found],
    do: Problem.respond(conn, reason)

  defp error(conn, :automation_grant_not_found), do: Problem.respond(conn, :grant_not_found)
  defp error(conn, :stale_automation_grant_hash), do: Problem.respond(conn, :grant_changed)
  defp error(conn, :operation_already_claimed), do: Problem.respond(conn, :operation_conflict)

  defp error(conn, :automation_grant_rejection_reason_required),
    do: Problem.respond(conn, :invalid_params, %{reason: "Say why."})

  # Every grant act is person-only (#283): a service, even an organization admin, is told so.
  defp error(conn, :authenticated_user_required),
    do: Problem.respond(conn, :authenticated_user_required)

  defp error(conn, {reason, %{} = details})
       when reason in [
              :automation_grant_self_approval_forbidden,
              :automation_grant_approver_authors_unknown,
              :automation_grant_not_proposed,
              :approval_policy_changed,
              :automation_grant_not_active,
              :automation_grant_not_narrower,
              :automation_grant_legacy,
              :automation_grant_not_suspended,
              :automation_grant_service_has_grant
            ],
       do: Problem.respond(conn, reason, details)

  defp error(conn, reason)
       when reason in [
              :duplicate_operation,
              :automation_grant_narrow_unchanged,
              :automation_grant_capability_required
            ],
       do: Problem.respond(conn, reason)

  defp error(conn, reason) when reason in [:forbidden, :scope_mismatch],
    do: Problem.respond(conn, :forbidden)

  defp error(conn, reason), do: Problem.respond(conn, :invalid_params, %{grant: inspect(reason)})

  defp scope(conn), do: conn.assigns.current_scope
  defp mission_id(conn), do: conn.assigns.current_mission.mission_id
end
