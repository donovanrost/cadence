defmodule Cadence.MissionModels.RevisionDecisions do
  @moduledoc """
  Approving or rejecting a mission-model revision (`MissionModels.approve_revision/5`,
  `reject_revision/4`): the human gate a revision passes before a generation may introduce it
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
  alias Cadence.MissionModels
  alias Cadence.MissionModels.{Comparison, RevisionRow, RuntimePlanRow}
  alias Cadence.Repo

  @spec approve(Scope.t(), binary(), binary(), binary(), keyword()) ::
          {:ok, Revision.t()} | {:error, term()}
  def approve(%Scope{} = scope, mission_id, revision_id, comparison_report_id, opts \\ [])
      when is_binary(mission_id) and is_binary(revision_id) and is_binary(comparison_report_id) do
    organization_id = scope.organization_id

    with :ok <- authorize(scope, mission_id),
         {:ok, actor} <- actor(scope),
         {:ok, %Revision{} = revision} <-
           MissionModels.fetch_revision(organization_id, mission_id, revision_id),
         :ok <- require_approvable(revision),
         :ok <- require_ready_plans(organization_id, mission_id, revision_id),
         {:ok, comparison} <- Comparison.fetch(organization_id, mission_id, comparison_report_id),
         :ok <- passed_for(comparison, revision_id),
         {:ok, importers} <- independent(organization_id, mission_id, revision_id, actor),
         {:ok, row} <- fetch_revision_row(organization_id, mission_id, revision_id) do
      evidence =
        Map.merge(actor, %{
          "comparison_report_id" => comparison_report_id,
          "replay" => get_in(comparison, ["replay", "status"]),
          "importer_recorded" => importers != []
        })

      row
      |> RevisionRow.status_changeset(:approved, evidence, at(opts))
      |> Repo.update()
      |> to_domain()
    end
  end

  @spec reject(Scope.t(), binary(), binary(), keyword()) ::
          {:ok, Revision.t()} | {:error, term()}
  def reject(%Scope{} = scope, mission_id, revision_id, opts \\ [])
      when is_binary(mission_id) and is_binary(revision_id) do
    with :ok <- authorize(scope, mission_id),
         {:ok, actor} <- actor(scope),
         {:ok, row} <- fetch_revision_row(scope.organization_id, mission_id, revision_id) do
      row
      |> RevisionRow.status_changeset(:rejected, actor, at(opts))
      |> Repo.update()
      |> to_domain()
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

  defp to_domain({:ok, row}), do: {:ok, RevisionRow.to_domain(row)}
  defp to_domain({:error, reason}), do: {:error, reason}

  defp at(opts), do: opts |> Keyword.get(:at, DateTime.utc_now()) |> normalized_datetime()

  defp fetch_revision_row(organization_id, mission_id, revision_id) do
    case Repo.get_by(RevisionRow,
           organization_id: organization_id,
           mission_id: mission_id,
           revision_id: revision_id
         ) do
      nil -> {:error, :mission_model_revision_not_found}
      row -> {:ok, row}
    end
  end

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
