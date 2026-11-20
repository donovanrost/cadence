defmodule CadenceWeb.Console.ActivationRequestController do
  @moduledoc """
  `…/missions/:mission_id/activations` (§11 L10): list, show, approve, reject and resume.
  Contract: docs/apogee/api/activations.md.
  """

  use CadenceWeb, :controller

  alias Cadence.Control.ActivationRequests
  alias Cadence.Reads.CatalogCompositions
  alias CadenceWeb.Console.{ApproveRefusals, ConfigJSON, Problem}

  def index(conn, params),
    do: respond(conn, ActivationRequests.list(scope(conn), mission_id(conn), params))

  def show(conn, %{"request_id" => id}) do
    result = ActivationRequests.get(scope(conn), mission_id(conn), id)
    respond(conn, with_compositions(conn, result))
  end

  # #235: one page of a configuration change group's spacecraft names.
  def configuration_change_names(conn, %{"request_id" => id} = params),
    do:
      respond(
        conn,
        ActivationRequests.configuration_change_names(scope(conn), mission_id(conn), id, params)
      )

  def approve(conn, %{"request_id" => id} = params),
    do: respond(conn, ActivationRequests.approve(scope(conn), mission_id(conn), id, params))

  def reject(conn, %{"request_id" => id} = params),
    do: respond(conn, ActivationRequests.reject(scope(conn), mission_id(conn), id, params))

  def withdraw(conn, %{"request_id" => id} = params),
    do: respond(conn, ActivationRequests.withdraw(scope(conn), mission_id(conn), id, params))

  def resume(conn, %{"request_id" => id}),
    do: respond(conn, ActivationRequests.resume(scope(conn), mission_id(conn), id))

  # D2 (#543): each catalog revision a configuration change names carries its composition. Added
  # here, in the read layer, so Control doesn't depend on Reads.
  defp with_compositions(conn, {:ok, %{configuration_changes: %{} = changes} = detail}) do
    changes =
      CatalogCompositions.configuration_changes(
        scope(conn).organization_id,
        mission_id(conn),
        changes
      )

    {:ok, %{detail | configuration_changes: changes}}
  end

  defp with_compositions(_conn, result), do: result

  defp respond(conn, {:ok, data}), do: json(conn, %{data: ConfigJSON.encode(data)})
  defp respond(conn, {:error, reason}), do: error(conn, reason)

  defp error(conn, {:invalid_params, details}),
    do: Problem.respond(conn, :invalid_params, details)

  defp error(conn, {:not_pending, state}),
    do: Problem.respond(conn, :not_pending, %{state: state})

  defp error(conn, {:nothing_to_resume, state}),
    do: Problem.respond(conn, :nothing_to_resume, %{state: state})

  # ux U95: the approve preflight refused before anything was recorded (a 409 per code).
  defp error(conn, {:approve_refused, code, details}),
    do: ApproveRefusals.respond(conn, code, details)

  # #236: an author of the configuration being activated can't approve it (nothing recorded).
  # Both #236 clauses take only the details map Refusals.explain builds (or #280's service map),
  # never a raw id list, which falls through to the generic refusal (mms-security).
  defp error(conn, {:activation_approver_authored_content, %{} = details}),
    do: ApproveRefusals.authored(conn, details)

  # #236 fail-closed and #280 (one wire code, ux U100): who made it can't be established, so nobody
  # may approve it as it stands. details.service picks the line: null for #236's unreadable
  # configuration authors (Refusals.explain builds that map), {id, name} for #280's service.
  defp error(conn, {:activation_approver_authors_unknown, %{} = details}),
    do: ApproveRefusals.authors_unknown(conn, details)

  defp error(conn, {:not_resumable, code}),
    do: Problem.respond(conn, :not_resumable, %{error_code: code})

  # #275 (U94): the requester's refusal, kind-prefixed. #280 (U100): it always says whether it
  # came through a service.
  defp error(conn, {:activation_self_approval_forbidden, %{} = details}),
    do:
      Problem.respond(
        conn,
        :activation_self_approval_forbidden,
        Map.put_new(details, :via_service, nil)
      )

  defp error(conn, reason)
       when reason in [
              :activation_request_not_found,
              :configuration_changes_group_not_found,
              :not_requester,
              :activation_policy_changed,
              :activation_execution_in_progress
            ],
       do: Problem.respond(conn, reason)

  defp error(conn, reason)
       when reason in [:forbidden, :scope_mismatch, :invalid_activation_scope],
       do: Problem.respond(conn, :forbidden)

  defp error(conn, _reason), do: Problem.respond(conn, :invalid_params, %{request: "refused"})

  defp scope(conn), do: conn.assigns.current_scope
  defp mission_id(conn), do: conn.assigns.current_mission.mission_id
end
