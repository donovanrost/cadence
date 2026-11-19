defmodule CadenceWeb.Console.ActivationRequestController do
  @moduledoc """
  `…/missions/:mission_id/activations` (§11 L10): list, show, approve, reject and resume.
  Contract: docs/apogee/api/activations.md.
  """

  use CadenceWeb, :controller

  alias Cadence.Control.ActivationRequests
  alias CadenceWeb.Console.{ApproveRefusals, ConfigJSON, Problem}

  def index(conn, params),
    do: respond(conn, ActivationRequests.list(scope(conn), mission_id(conn), params))

  def show(conn, %{"request_id" => id}),
    do: respond(conn, ActivationRequests.get(scope(conn), mission_id(conn), id))

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

  defp error(conn, {:not_resumable, code}),
    do: Problem.respond(conn, :not_resumable, %{error_code: code})

  # #280 (U100): the self-approval refusal always says whether it came through a service.
  defp error(conn, :self_approval_forbidden),
    do: Problem.respond(conn, :self_approval_forbidden, %{via_service: nil})

  defp error(conn, {reason, details})
       when reason in [:self_approval_forbidden, :activation_approver_authors_unknown],
       do: Problem.respond(conn, reason, details)

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
