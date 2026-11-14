defmodule Cadence.MissionModels.RevisionDecisions do
  @moduledoc """
  Approving or rejecting a mission-model revision (`MissionModels.approve_revision/5`,
  `reject_revision/5`). Approval needs a candidate (or already approved) revision whose four
  runtime plans are ready. Either decision records who made it: the actor's kind and id are
  required (lead 11-15).
  """

  import Ecto.Query

  alias Cadence.Catalog.MissionModel.Revision
  alias Cadence.MissionModels
  alias Cadence.MissionModels.{RevisionRow, RuntimePlanRow}
  alias Cadence.Repo

  @spec approve(binary(), binary(), binary(), map(), keyword()) ::
          {:ok, Revision.t()} | {:error, term()}
  def approve(organization_id, mission_id, revision_id, actor, opts \\ [])
      when is_binary(organization_id) and is_binary(mission_id) and is_binary(revision_id) and
             is_map(actor) do
    with :ok <- require_actor(actor),
         {:ok, %Revision{} = revision} <-
           MissionModels.fetch_revision(organization_id, mission_id, revision_id),
         :ok <- require_approvable(revision),
         :ok <- require_ready_plans(organization_id, mission_id, revision_id),
         {:ok, row} <- fetch_revision_row(organization_id, mission_id, revision_id),
         {:ok, approved_row} <-
           row
           |> RevisionRow.status_changeset(
             :approved,
             actor,
             normalized_datetime(Keyword.get(opts, :at, DateTime.utc_now()))
           )
           |> Repo.update() do
      {:ok, RevisionRow.to_domain(approved_row)}
    end
  end

  @spec reject(binary(), binary(), binary(), map(), keyword()) ::
          {:ok, Revision.t()} | {:error, term()}
  def reject(organization_id, mission_id, revision_id, actor, opts \\ [])
      when is_binary(organization_id) and is_binary(mission_id) and is_binary(revision_id) and
             is_map(actor) do
    with :ok <- require_actor(actor),
         {:ok, row} <- fetch_revision_row(organization_id, mission_id, revision_id),
         {:ok, rejected_row} <-
           row
           |> RevisionRow.status_changeset(
             :rejected,
             actor,
             normalized_datetime(Keyword.get(opts, :at, DateTime.utc_now()))
           )
           |> Repo.update() do
      {:ok, RevisionRow.to_domain(rejected_row)}
    end
  end

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

  # lead 11-15: a decision names who made it. approved_by/rejected_by were stored empty when a
  # caller passed %{}; now a decision needs the actor's kind and id.
  defp require_actor(%{"kind" => kind, "id" => id})
       when is_binary(kind) and kind != "" and is_binary(id) and id != "",
       do: :ok

  defp require_actor(_actor), do: {:error, :mission_model_decision_actor_required}

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
