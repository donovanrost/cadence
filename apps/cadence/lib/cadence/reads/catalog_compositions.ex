defmodule Cadence.Reads.CatalogCompositions do
  @moduledoc """
  D2 (#543): the composition behind each catalog revision a read shows, sent beside it
  (readers-first, additive). Until D3 pins one, it's the composition of the exact mission-model
  revision the catalog revision names (`mission_model_revision_id`), as `Reads.CompositionActors`
  shows it; `nil` when that revision has none, or when the id names none of the mission's catalog
  revisions.

  One `CompositionActors.for_revisions/3` call per read: a read gathers every catalog revision id
  it shows first, then looks each up in the map these functions return.
  """

  alias Cadence.Catalog
  alias Cadence.Catalog.Revision
  alias Cadence.Reads.CompositionActors

  @catalog_path "catalog_revision_id"

  @doc """
  `%{catalog_revision_id => composition}` for `catalog_revision_ids`, over `revisions` (the
  mission's catalog revisions the read already loaded). Ids without a composition are absent.
  """
  @spec by_catalog_revision(binary(), binary(), [Revision.t()], [binary() | nil]) :: %{
          binary() => map()
        }
  def by_catalog_revision(organization_id, mission_id, revisions, catalog_revision_ids) do
    wanted = MapSet.new(catalog_revision_ids)

    models =
      for %Revision{catalog_revision_id: id, mission_model_revision_id: model} <- revisions,
          is_binary(model) and MapSet.member?(wanted, id),
          into: %{},
          do: {id, model}

    compositions = compositions(organization_id, mission_id, models)

    for {id, model} <- models,
        %{} = composition <- [Map.get(compositions, model)],
        into: %{},
        do: {id, composition}
  end

  @doc "As `by_catalog_revision/4`, loading the mission's catalog revisions when any id is given."
  @spec load(binary(), binary(), [binary() | nil]) :: %{binary() => map()}
  def load(organization_id, mission_id, catalog_revision_ids) do
    case Enum.filter(catalog_revision_ids, &is_binary/1) do
      [] ->
        %{}

      ids ->
        revisions = Catalog.list_revisions(organization_id, mission_id)
        by_catalog_revision(organization_id, mission_id, revisions, ids)
    end
  end

  @doc "The catalog revision ids that per-spacecraft overrides of `catalog_revision_id` set."
  @spec override_ids([map()]) :: [binary()]
  def override_ids(overrides),
    do: for(%{path: @catalog_path, spacecraft_value: id} <- overrides, is_binary(id), do: id)

  @doc "The composition behind the catalog revision an override sets, or nil (any other override)."
  @spec for_override(map(), %{binary() => map()}) :: map() | nil
  def for_override(%{path: @catalog_path, spacecraft_value: id}, compositions) when is_binary(id),
    do: Map.get(compositions, id)

  def for_override(_override, _compositions), do: nil

  @doc "An override row with `composition` (`for_override/2`)."
  @spec put_override(map(), %{binary() => map()}) :: map()
  def put_override(override, compositions),
    do: Map.put(override, :composition, for_override(override, compositions))

  @doc """
  L10's `configuration_changes` (#235) with `composition` on each catalog revision a
  `catalog_revision` row names (its `before` and `after`, each `{id, number}`); nil stays nil.
  """
  @spec configuration_changes(binary(), binary(), map() | nil) :: map() | nil
  def configuration_changes(_organization_id, _mission_id, nil), do: nil

  def configuration_changes(organization_id, mission_id, %{groups: groups} = changes) do
    ids =
      for %{rows: rows} <- groups,
          %{field: "catalog_revision", before: before, after: later} <- rows,
          %{id: id} <- [before, later],
          do: id

    compositions = load(organization_id, mission_id, ids)
    %{changes | groups: Enum.map(groups, &group(&1, compositions))}
  end

  defp compositions(_organization_id, _mission_id, models) when map_size(models) == 0, do: %{}

  defp compositions(organization_id, mission_id, models),
    do: CompositionActors.for_revisions(organization_id, mission_id, Map.values(models))

  defp group(%{rows: rows} = group, compositions),
    do: %{group | rows: Enum.map(rows, &row(&1, compositions))}

  defp row(%{field: "catalog_revision", before: before, after: later} = row, compositions),
    do: %{row | before: ref(before, compositions), after: ref(later, compositions)}

  defp row(row, _compositions), do: row

  defp ref(%{id: id} = ref, compositions),
    do: Map.put(ref, :composition, Map.get(compositions, id))

  defp ref(other, _compositions), do: other
end
