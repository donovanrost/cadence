defmodule Cadence.MissionModelApproval do
  @moduledoc """
  Test setup: marks a mission-model revision approved without the human gate. The gate's own
  tests go through `MissionModels.approve_revision/5` (Scope, comparison, importer separation).
  """

  alias Cadence.MissionModels.RevisionRow
  alias Cadence.Repo

  @doc "The revision, approved."
  def approve!(organization_id, mission_id, revision_id) do
    {:ok, row} =
      RevisionRow
      |> Repo.get_by!(mission_id: mission_id, revision_id: revision_id)
      |> RevisionRow.status_changeset(
        :approved,
        %{"kind" => "test_fixture", "id" => "mission-model-approval", "org" => organization_id},
        DateTime.utc_now()
      )
      |> Repo.update()

    {:ok, RevisionRow.to_domain(row)}
  end
end
