defmodule Cadence.MissionModels.RevisionDecisions do
  @moduledoc """
  Approving or rejecting a mission-model revision (`MissionModels.approve_revision/5`,
  `reject_revision/5`): the human gate a revision passes before a generation may introduce it
  (DECISIONS #92 (a), director 11-15; `Control.ModelApprovalGate`).

  - Only an organization administrator decides (`:approve_mission_model`), never a service.
  - Approval names the comparison report the approver saw. It must be this revision's and must
    have passed; a report whose replay didn't run (no qualification corpus) passes, and says so.
  - Under 'independent' approval (the mission's governance setting) whoever imported the revision
    can't approve it (`:mission_model_self_approval_forbidden`). A revision whose importer wasn't
    recorded can be approved by any administrator; the approval records that.
  - Approval needs a candidate (or already approved) revision whose four runtime plans are ready.
  """

  import Ecto.Query

  alias Cadence.Auth.{Policy, Scope}
  alias Cadence.Catalog
  alias Cadence.Catalog.MissionModel.Revision
  alias Cadence.Governance.ActivationPolicy
  alias Cadence.MissionModels.{Comparison, RevisionRow, RuntimePlanRow}
  alias Cadence.Persistence.JsonDocument
  alias Cadence.Repo

  @spec approve(Scope.t(), binary(), binary(), binary(), keyword()) ::
          {:ok, Revision.t()} | {:error, term()}
  def approve(%Scope{} = scope, mission_id, revision_id, comparison_report_id, opts \\ [])
      when is_binary(mission_id) and is_binary(revision_id) and is_binary(comparison_report_id) do
    organization_id = scope.organization_id

    with :ok <- authorize(scope, mission_id),
         {:ok, actor} <- actor(scope) do
      # Read, check and update under the revision's row lock: two administrators deciding at once
      # serialize, and an approval can't land on a revision another one just rejected (api-ops).
      locked(organization_id, mission_id, revision_id, fn row ->
        approve_locked(row, actor, comparison_report_id, opts)
      end)
    end
  end

  # Approving an approved revision again changes nothing: the first approver stays on record.
  defp approve_locked(%RevisionRow{status: "approved"} = row, _actor, _report, _opts),
    do: {:ok, row}

  defp approve_locked(row, actor, comparison_report_id, opts) do
    %{organization_id: organization_id, mission_id: mission_id, revision_id: revision_id} = row

    with :ok <- require_approvable(RevisionRow.to_domain(row)),
         :ok <- require_ready_plans(organization_id, mission_id, revision_id),
         {:ok, comparison} <- Comparison.fetch(organization_id, mission_id, comparison_report_id),
         :ok <- passed_for(comparison, revision_id),
         {:ok, importers} <- independent(organization_id, mission_id, revision_id, actor) do
      evidence =
        Map.merge(actor, %{
          "comparison_report_id" => comparison_report_id,
          "replay" => get_in(comparison, ["replay", "status"]),
          "importer_recorded" => importers != [],
          # Approved after it already ran (the pre-gate revisions, lead 11-15): the caller says so
          # (ModelApprovalGate.running?/3), and the audit tells it.
          "retroactive" => Keyword.get(opts, :retroactive, false) == true
        })

      row |> RevisionRow.status_changeset(:approved, evidence, at(opts)) |> Repo.update()
    end
  end

  @doc "Rejects a candidate revision, with the reason (an approved one stays approved)."
  @spec reject(Scope.t(), binary(), binary(), binary(), keyword()) ::
          {:ok, Revision.t()} | {:error, term()}
  def reject(%Scope{} = scope, mission_id, revision_id, reason, opts \\ [])
      when is_binary(mission_id) and is_binary(revision_id) do
    with :ok <- authorize(scope, mission_id),
         {:ok, actor} <- actor(scope),
         {:ok, reason} <- reason(reason) do
      locked(
        scope.organization_id,
        mission_id,
        revision_id,
        &reject_locked(&1, actor, reason, opts)
      )
    end
  end

  @doc """
  The mission's model decisions people made, newest first, for the organization audit:
  `[%{revision_id, decision: :approved | :rejected, at, by: %{"id", "display_name"}, evidence}]`.
  """
  # todo(authz): no scope here; callers authorize (the organization audit source).
  @spec list_decisions(binary(), binary()) :: [map()]
  def list_decisions(organization_id, mission_id) do
    from(row in RevisionRow,
      where:
        row.organization_id == ^organization_id and row.mission_id == ^mission_id and
          (not is_nil(row.approved_at) or not is_nil(row.rejected_at)),
      select:
        {row.revision_id, row.status, row.approved_at, row.approved_by, row.rejected_at,
         row.rejected_by}
    )
    |> Repo.all()
    |> Enum.flat_map(&decision/1)
    |> Enum.sort_by(& &1.at, {:desc, DateTime})
  end

  defp decision({id, "rejected", _approved_at, _approved_by, at, by}),
    do: person(id, :rejected, at, by)

  defp decision({id, _status, at, by, _rejected_at, _rejected_by}) when not is_nil(at),
    do: person(id, :approved, at, by)

  defp decision(_row), do: []

  defp person(id, decision, at, by) do
    case JsonDocument.unwrap_value(by) do
      %{"kind" => "user", "id" => user} = evidence ->
        [
          %{
            revision_id: id,
            decision: decision,
            at: at,
            by: %{"id" => user, "display_name" => evidence["display_name"]},
            evidence: evidence
          }
        ]

      _not_a_person ->
        []
    end
  end

  defp locked(organization_id, mission_id, revision_id, fun) do
    Repo.transaction(fn ->
      RevisionRow
      |> where(
        [row],
        row.organization_id == ^organization_id and row.mission_id == ^mission_id and
          row.revision_id == ^revision_id
      )
      |> lock("FOR UPDATE")
      |> Repo.one()
      |> decide_locked(fun)
    end)
    |> case do
      {:ok, row} -> {:ok, RevisionRow.to_domain(row)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp reject_locked(%RevisionRow{status: "candidate"} = row, actor, reason, opts) do
    row
    |> RevisionRow.status_changeset(:rejected, Map.put(actor, "reason", reason), at(opts))
    |> Repo.update()
  end

  defp reject_locked(%RevisionRow{}, _actor, _reason, _opts),
    do: {:error, :mission_model_revision_not_approvable}

  @reason_max 2_000

  defp reason(reason) when is_binary(reason) do
    case String.trim(reason) do
      "" ->
        {:error, :mission_model_decision_reason_required}

      trimmed when byte_size(trimmed) > @reason_max ->
        {:error, :mission_model_decision_reason_too_long}

      trimmed ->
        {:ok, trimmed}
    end
  end

  defp reason(_reason), do: {:error, :mission_model_decision_reason_required}

  defp decide_locked(nil, _fun), do: Repo.rollback(:mission_model_revision_not_found)

  defp decide_locked(row, fun) do
    case fun.(row) do
      {:ok, updated} -> updated
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp authorize(%Scope{} = scope, mission_id) do
    Policy.authorize(scope, :approve_mission_model, %{
      organization_id: scope.organization_id,
      mission_id: mission_id
    })
  end

  defp actor(%Scope{actor_kind: :user, user: %{user_id: id} = user}) when is_binary(id),
    do: {:ok, %{"kind" => "user", "id" => id, "display_name" => user.display_name}}

  defp actor(%Scope{}), do: {:error, :human_mission_model_approver_required}

  defp passed_for(%{"candidate_revision_id" => id, "status" => "passed"}, id), do: :ok

  defp passed_for(%{"candidate_revision_id" => id}, id),
    do: {:error, :mission_model_comparison_not_passed}

  defp passed_for(_comparison, _id), do: {:error, :mission_model_comparison_mismatch}

  defp independent(organization_id, mission_id, revision_id, %{"id" => actor_id}) do
    importers = Catalog.model_importers(organization_id, mission_id, revision_id)
    separation = ActivationPolicy.evidence(organization_id, mission_id)["separation_of_duties"]

    if separation == true and actor_id in importers,
      do: {:error, :mission_model_self_approval_forbidden},
      else: {:ok, importers}
  end

  defp at(opts), do: opts |> Keyword.get(:at, DateTime.utc_now()) |> normalized_datetime()

  defp require_approvable(%Revision{status: :candidate}), do: :ok
  defp require_approvable(%Revision{status: :approved}), do: :ok
  defp require_approvable(%Revision{}), do: {:error, :mission_model_revision_not_approvable}

  defp require_ready_plans(organization_id, mission_id, revision_id) do
    statuses =
      RuntimePlanRow
      |> where(
        [row],
        row.organization_id == ^organization_id and row.mission_id == ^mission_id and
          row.revision_id == ^revision_id
      )
      |> select([row], row.status)
      |> Repo.all()

    if length(statuses) == 4 and Enum.all?(statuses, &(&1 == "ready")) do
      :ok
    else
      {:error, :mission_model_runtime_plans_not_ready}
    end
  end

  defp normalized_datetime(%DateTime{} = datetime) do
    {microsecond, _precision} = datetime.microsecond
    %{datetime | microsecond: {microsecond, 6}}
  end
end
