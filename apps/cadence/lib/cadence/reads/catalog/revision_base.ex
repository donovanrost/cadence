defmodule Cadence.Reads.Catalog.RevisionBase do
  @moduledoc """
  The revision a catalog revision is compared against, and its breaking count (Catalog C3; #195,
  ux U102). The base is the revision before it in the same catalog database: the highest
  `revision_number` below its own. Catalog revisions are numbered (never null) and immutable, and
  none is deleted, so a revision's base and count never move when later revisions are imported.
  Only a release that changes `CatalogDiff`'s breaking rules can change the count.

  The import page's C3 diff and the revision read's `breaking` both use `previous/3`, so for a
  revision the two counts are always the same.
  """

  alias Cadence.Catalog
  alias Cadence.Catalog.Revision
  alias Cadence.Reads.CatalogDiff

  @doc "The revision before `revision` in its database, or nil for the database's first."
  @spec previous(binary(), binary(), Revision.t()) :: Revision.t() | nil
  def previous(organization_id, mission_id, %Revision{} = revision) do
    organization_id
    |> Catalog.list_revisions(mission_id, revision.catalog_database_id)
    |> Enum.filter(&(&1.revision_number < revision.revision_number))
    |> Enum.max_by(& &1.revision_number, fn -> nil end)
  end

  @doc """
  `%{breaking, breaking_base}` for the revision read. `breaking_base` is null for a database's
  first revision (and `breaking` null with it). With a base, `breaking` is the count, or null when
  either revision's declarations can't be read. It's never 0 for unknown.
  """
  @spec breaking(binary(), binary(), Revision.t()) :: %{
          breaking: non_neg_integer() | nil,
          breaking_base: %{catalog_revision_id: binary(), revision: integer()} | nil
        }
  def breaking(organization_id, mission_id, %Revision{} = revision) do
    case previous(organization_id, mission_id, revision) do
      nil ->
        %{breaking: nil, breaking_base: nil}

      %Revision{} = base ->
        diff =
          CatalogDiff.diff(
            organization_id,
            mission_id,
            base.mission_model_revision_id,
            revision.mission_model_revision_id
          )

        %{
          breaking: diff && diff.summary.breaking,
          breaking_base: %{
            catalog_revision_id: base.catalog_revision_id,
            revision: base.revision_number
          }
        }
    end
  end
end
