defmodule CadenceWeb.Console.MissionModelRevisionController do
  @moduledoc """
  The model approval gate (ux U65, DECISIONS #92 a), `…/missions/:mission_id/mission-model-revisions`:
  list by status, read one (with its latest comparison and what the viewer may do), run a
  comparison, approve against a passed comparison, reject with a reason. Reads are open to the
  mission's console members; deciding is an organization administrator's
  (`MissionModels.approve_revision/5`, `reject_revision/5`). Contract: docs/apogee/api/setup.md.
  """

  use CadenceWeb, :controller

  alias Cadence.MissionModels
  alias Cadence.Reads.MissionModelApprovals
  alias CadenceWeb.Console.Problem

  @statuses ~w(candidate approved rejected retired)

  # todo(authz): reads are open to the mission's console members; Cedar may narrow them.
  def index(conn, params) do
    case Map.get(params, "status", "candidate") do
      status when status in @statuses ->
        revisions = MissionModelApprovals.list(scope(conn), mission_id(conn), status)
        json(conn, %{data: %{revisions: revisions}})

      _other ->
        Problem.respond(conn, :invalid_params, %{
          status: "must be one of #{Enum.join(@statuses, ", ")}"
        })
    end
  end

  def show(conn, %{"id" => id}),
    do: reply(conn, MissionModelApprovals.read(scope(conn), mission_id(conn), id))

  def compare(conn, %{"id" => id}) do
    case MissionModelApprovals.compare(scope(conn), mission_id(conn), id) do
      {:ok, comparison} -> conn |> put_status(201) |> json(%{data: comparison})
      {:error, reason} -> error(conn, reason)
    end
  end

  def approve(conn, %{"id" => id} = params) do
    case params["comparison_report_id"] do
      report_id when is_binary(report_id) and report_id != "" ->
        decide(conn, id, fn ->
          MissionModelApprovals.approve(scope(conn), mission_id(conn), id, report_id)
        end)

      _missing ->
        Problem.respond(conn, :invalid_params, %{
          comparison_report_id: "Run the comparison first."
        })
    end
  end

  def reject(conn, %{"id" => id} = params) do
    case params["reason"] do
      reason when is_binary(reason) ->
        reason = String.trim(reason)

        decide(conn, id, fn ->
          MissionModels.reject_revision(scope(conn), mission_id(conn), id, reason)
        end)

      _missing ->
        error(conn, :mission_model_decision_reason_required)
    end
  end

  defp decide(conn, id, decision) do
    case decision.() do
      {:ok, _revision} -> show(conn, %{"id" => id})
      {:error, reason} -> error(conn, reason)
    end
  end

  defp reply(conn, {:ok, data}), do: json(conn, %{data: data})
  defp reply(conn, {:error, reason}), do: error(conn, reason)

  @codes ~w(forbidden human_mission_model_approver_required mission_model_self_approval_forbidden
            mission_model_comparison_not_passed mission_model_comparison_mismatch
            mission_model_runtime_plans_not_ready mission_model_revision_not_approvable
            mission_model_revision_not_found mission_model_comparison_report_not_found
            mission_model_decision_reason_required mission_model_decision_reason_too_long
            mission_model_no_active_binding_set mission_model_revision_not_in_catalog)a

  defp error(conn, reason) when reason in @codes, do: Problem.respond(conn, reason)

  defp error(conn, {:invalid_params, details}),
    do: Problem.respond(conn, :invalid_params, details)

  defp error(conn, _other), do: Problem.respond(conn, :mission_model_unavailable)

  defp scope(conn), do: conn.assigns.current_scope
  defp mission_id(conn), do: conn.assigns.current_mission.mission_id
end
