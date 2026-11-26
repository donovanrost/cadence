defmodule CadenceWeb.Console.MissionModelRevisionController do
  @moduledoc """
  The model approval gate (ux U65, DECISIONS #92 a), `…/missions/:mission_id/mission-model-revisions`:
  list by status, read one (with its latest comparison and what the viewer may do), run a
  comparison, approve against a passed comparison, reject with a reason. Reads are open to the
  mission's console members; deciding is an organization administrator's
  (`MissionModels.approve_revision/5`, `reject_revision/5`). Contract: docs/apogee/api/setup.md.
  """

  use CadenceWeb, :controller

  alias Cadence.Control.ModelWithdrawal
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

  # #260: `operation_id` is optional (the #257 form: 1-120 characters); with it, a retry of this
  # approval answers its original 200 with `replayed: true`.
  def approve(conn, %{"id" => id} = params) do
    with {:ok, report_id} <- report_id(params["comparison_report_id"]),
         {:ok, operation_id} <- operation_id(params["operation_id"]) do
      case MissionModelApprovals.approve(
             scope(conn),
             mission_id(conn),
             id,
             report_id,
             operation_id
           ) do
        {:ok, {:replayed, _revision}} -> read(conn, id, true)
        {:ok, _revision} -> read(conn, id, false)
        {:error, reason} -> error(conn, reason)
      end
    else
      {:error, details} -> Problem.respond(conn, :invalid_params, details)
    end
  end

  defp report_id(id) when is_binary(id) and id != "", do: {:ok, id}
  defp report_id(_id), do: {:error, %{comparison_report_id: "Run the comparison first."}}

  defp operation_id(nil), do: {:ok, nil}
  defp operation_id(id) when is_binary(id) and byte_size(id) in 1..120, do: {:ok, id}
  defp operation_id(_id), do: {:error, %{operation_id: "must be 1-120 characters"}}

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

  # E2 (#546; U109 "Withdrawing an approval"): an approved revision's approval taken back, with a
  # required reason. Answers the revision read; a retry with the same `operation_id` replays.
  def withdraw(conn, %{"id" => id} = params) do
    case operation_id(params["operation_id"]) do
      {:ok, operation_id} ->
        conn
        |> scope()
        |> ModelWithdrawal.withdraw(mission_id(conn), id, params["reason"],
          operation_id: operation_id
        )
        |> withdrawn(conn, id)

      {:error, details} ->
        Problem.respond(conn, :invalid_params, details)
    end
  end

  defp withdrawn({:ok, {:replayed, _revision}}, conn, id), do: read(conn, id, true)
  defp withdrawn({:ok, _revision}, conn, id), do: read(conn, id, false)
  defp withdrawn({:error, reason}, conn, _id), do: error(conn, reason)

  defp decide(conn, id, decision) do
    case decision.() do
      {:ok, _revision} -> show(conn, %{"id" => id})
      {:error, reason} -> error(conn, reason)
    end
  end

  # A decision answers the read; an approve also says whether it was a replay (#260).
  defp read(conn, id, replayed) do
    case MissionModelApprovals.read(scope(conn), mission_id(conn), id) do
      {:ok, data} -> json(conn, %{data: Map.put(data, :replayed, replayed)})
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
            mission_model_no_active_binding_set mission_model_revision_not_in_catalog
            mission_model_revision_not_withdrawable)a

  # #280 (U100): the self-approval refusal always says whether it came through a service.
  defp error(conn, :mission_model_self_approval_forbidden),
    do: Problem.respond(conn, :mission_model_self_approval_forbidden, %{via_service: nil})

  defp error(conn, reason) when reason in @codes, do: Problem.respond(conn, reason)

  defp error(conn, {reason, details})
       when reason in [
              :mission_model_self_approval_forbidden,
              :mission_model_approver_authors_unknown,
              :mission_model_revision_already_approved
            ],
       do: Problem.respond(conn, reason, details)

  defp error(conn, {:invalid_params, details}),
    do: Problem.respond(conn, :invalid_params, details)

  defp error(conn, _other), do: Problem.respond(conn, :mission_model_unavailable)

  defp scope(conn), do: conn.assigns.current_scope
  defp mission_id(conn), do: conn.assigns.current_mission.mission_id
end
