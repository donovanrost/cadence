defmodule Cadence.Catalog.ModelRevisionNaming do
  @moduledoc """
  Whether a catalog revision names a mission-model revision (director 11-17, interim). Every
  import run compiles its own model revision, and a run that makes no catalog revision leaves
  one that no catalog revision names. The model approval's importer separation is recorded
  against catalog revisions, so such a revision can be neither approved
  (`MissionModels.RevisionDecisions`) nor requested or applied for activation
  (`MissionModels.request_promotion/6`, `Control.MissionModelPromotion`). Rejecting it stays
  allowed, so it can be cleared from the approval queue.
  """

  import Ecto.Query

  alias Cadence.Catalog.RevisionRow
  alias Cadence.Repo

  @doc "`:ok`, or `{:error, :mission_model_revision_not_in_catalog}`."
  @spec require_named(binary(), binary(), binary()) ::
          :ok | {:error, :mission_model_revision_not_in_catalog}
  def require_named(organization_id, mission_id, mission_model_revision_id)
      when is_binary(organization_id) and is_binary(mission_id) and
             is_binary(mission_model_revision_id) do
    named? =
      Repo.exists?(
        from(row in RevisionRow,
          where:
            row.organization_id == ^organization_id and row.mission_id == ^mission_id and
              row.mission_model_revision_id == ^mission_model_revision_id
        )
      )

    if named?, do: :ok, else: {:error, :mission_model_revision_not_in_catalog}
  end
end
