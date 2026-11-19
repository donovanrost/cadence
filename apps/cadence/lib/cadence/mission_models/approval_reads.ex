defmodule Cadence.MissionModels.ApprovalReads do
  @moduledoc """
  What the console's model approval screen reads (U65, DECISIONS #92 a): revisions by status
  with their decisions, the latest comparison report per revision, and whether a revision's
  four runtime plans are ready. Rows only; `Cadence.Reads.MissionModelApprovals` shapes them.
  """

  import Ecto.Query

  alias Cadence.MissionModels.{ComparisonReportRow, RevisionRow, RuntimePlanRow}
  alias Cadence.Persistence.JsonDocument
  alias Cadence.Repo

  @statuses ~w(candidate approved rejected retired)

  @spec list(binary(), binary(), binary()) :: [map()]
  def list(organization_id, mission_id, status) when status in @statuses do
    scoped(organization_id, mission_id)
    |> where([row], row.status == ^status)
    |> order_by([row], desc: row.inserted_at, desc: row.revision_id)
    |> limit(200)
    |> select_row()
    |> Repo.all()
    |> Enum.map(&decode/1)
  end

  @spec fetch(binary(), binary(), binary()) ::
          {:ok, map()} | {:error, :mission_model_revision_not_found}
  def fetch(organization_id, mission_id, revision_id) do
    scoped(organization_id, mission_id)
    |> where([row], row.revision_id == ^revision_id)
    |> select_row()
    |> Repo.one()
    |> case do
      nil -> {:error, :mission_model_revision_not_found}
      row -> {:ok, decode(row)}
    end
  end

  @doc "The newest comparison report document for each of `revision_ids`."
  @spec latest_reports(binary(), binary(), [binary()]) :: %{binary() => map()}
  def latest_reports(_organization_id, _mission_id, []), do: %{}

  def latest_reports(organization_id, mission_id, revision_ids) do
    ComparisonReportRow
    |> where(
      [row],
      row.organization_id == ^organization_id and row.mission_id == ^mission_id and
        row.candidate_revision_id in ^revision_ids
    )
    |> order_by([row], desc: row.inserted_at)
    |> select([row], {row.candidate_revision_id, row.report, row.inserted_at})
    |> Repo.all()
    |> Enum.reduce(%{}, fn {id, report, at}, acc ->
      Map.put_new(acc, id, Map.put(JsonDocument.unwrap_value(report), "generated_at", at))
    end)
  end

  @doc "Report documents by id (the audit's approvals name the report they saw)."
  @spec reports(binary(), binary(), [binary()]) :: %{binary() => map()}
  def reports(_organization_id, _mission_id, []), do: %{}

  def reports(organization_id, mission_id, report_ids) do
    ComparisonReportRow
    |> where(
      [row],
      row.organization_id == ^organization_id and row.mission_id == ^mission_id and
        row.comparison_report_id in ^report_ids
    )
    |> select([row], {row.comparison_report_id, row.report})
    |> Repo.all()
    |> Map.new(fn {id, report} -> {id, JsonDocument.unwrap_value(report)} end)
  end

  @doc "The latest report's status per revision (`passed | failed`), for the list."
  @spec latest_statuses(binary(), binary(), [binary()]) :: %{binary() => binary()}
  def latest_statuses(organization_id, mission_id, revision_ids) do
    organization_id
    |> latest_reports(mission_id, revision_ids)
    |> Map.new(fn {id, report} -> {id, report["status"]} end)
  end

  @doc "Whether the revision's four runtime plans are ready (approval needs it)."
  @spec plans_ready?(binary(), binary(), binary()) :: boolean()
  def plans_ready?(organization_id, mission_id, revision_id) do
    statuses =
      RuntimePlanRow
      |> where(
        [row],
        row.organization_id == ^organization_id and row.mission_id == ^mission_id and
          row.revision_id == ^revision_id
      )
      |> select([row], row.status)
      |> Repo.all()

    length(statuses) == 4 and Enum.all?(statuses, &(&1 == "ready"))
  end

  defp scoped(organization_id, mission_id),
    do:
      where(
        RevisionRow,
        [row],
        row.organization_id == ^organization_id and row.mission_id == ^mission_id
      )

  defp select_row(query) do
    select(query, [row], %{
      id: row.revision_id,
      status: row.status,
      imported_at: row.inserted_at,
      approved_by: row.approved_by,
      approved_at: row.approved_at,
      rejected_by: row.rejected_by,
      rejected_at: row.rejected_at
    })
  end

  defp decode(row) do
    %{
      row
      | approved_by: row.approved_by && JsonDocument.unwrap_value(row.approved_by),
        rejected_by: row.rejected_by && JsonDocument.unwrap_value(row.rejected_by)
    }
  end
end
