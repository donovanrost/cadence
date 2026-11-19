defmodule Cadence.MissionModels.DeclarationProjection do
  @moduledoc """
  Bounded projection of named declarations from one immutable revision.

  Like `Cadence.MissionModels.CommandArgumentChoices`, it reads only the
  requested declarations out of the revision document instead of
  materializing the whole revision. Each declaration comes back as its stored
  JSON (string keys).
  """

  alias Cadence.Repo

  @max_ids 4096

  @query """
  SELECT requested.id, revision.revision_document->'value'->'declarations'->requested.id
  FROM mission_model_revisions AS revision
  CROSS JOIN unnest($4::text[]) AS requested(id)
  WHERE revision.organization_id = $1 AND revision.mission_id = $2 AND revision.revision_id = $3
    AND revision.revision_document->'value'->'declarations' ? requested.id
  """

  @spec load(binary(), binary(), binary(), [binary()]) ::
          {:ok, %{binary() => map()}} | {:error, term()}
  def load(_organization_id, _mission_id, _revision_id, []), do: {:ok, %{}}

  def load(organization_id, mission_id, revision_id, ids)
      when is_binary(organization_id) and is_binary(mission_id) and is_binary(revision_id) and
             is_list(ids) and length(ids) <= @max_ids do
    ids = ids |> Enum.filter(&is_binary/1) |> Enum.uniq()

    case Repo.query(@query, [organization_id, mission_id, revision_id, ids]) do
      {:ok, %{rows: rows}} -> {:ok, Map.new(rows, fn [id, declaration] -> {id, declaration} end)}
      {:error, _reason} -> {:error, :declarations_unavailable}
    end
  end

  def load(_organization_id, _mission_id, _revision_id, _ids),
    do: {:error, :declarations_unavailable}
end
