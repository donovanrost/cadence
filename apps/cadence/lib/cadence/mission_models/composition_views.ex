defmodule Cadence.MissionModels.CompositionViews do
  @moduledoc """
  D2 (#543; design `mission-composition-design.md` §6): what the reads show of the composition
  behind a mission-model revision, loaded in a fixed number of queries for any number of revisions.

  - **Which composition.** Until D3 nothing pins a composition, so a read names the model revision
    it already shows and gets that revision's own composition: its link (unique on the revision,
    one per compiler version, #559). A revision with no link has none.
  - **`number`**, the composition's per-mission short number (`nil` if it has none).
  - **`imported_layers`**, in mount order, each with the earliest catalog revision in the tenant
    that imported it (domain's rule (b) on #543), or `nil` when no catalog revision did.
  - **`created_by`** as stored: kind and ids only (#146). `Reads.CompositionActors` names it.

  Readers-first: every key here is additive beside the catalog revision a read already shows.
  """

  import Ecto.Query

  alias Cadence.Catalog.ModelRevisions

  alias Cadence.MissionModels.{
    CompositionLayerRow,
    CompositionNumberRow,
    CompositionRow,
    EffectiveRevisionRow,
    RevisionLayerRow,
    RevisionRow
  }

  alias Cadence.Repo

  @type layer :: %{
          layer_id: binary(),
          mount: binary(),
          catalog_revision:
            %{id: binary(), number: integer(), database: %{id: binary(), name: binary() | nil}}
            | nil
        }
  @type t :: %{
          composition_id: binary(),
          number: pos_integer() | nil,
          imported_layers: [layer()],
          created_by: map(),
          created_at: DateTime.t()
        }

  @doc "`%{revision_id => composition}` for the revisions among `revision_ids` that have a link."
  @spec for_revisions(binary(), binary(), [binary() | nil]) :: %{binary() => t()}
  def for_revisions(organization_id, mission_id, revision_ids) do
    case revision_ids |> Enum.reject(&is_nil/1) |> Enum.uniq() do
      [] -> %{}
      ids -> load(organization_id, mission_id, ids)
    end
  end

  @doc "`%{revision_id => composition_id}`: the link only, for a read that shows just the id."
  @spec ids_for_revisions(binary(), binary(), [binary() | nil]) :: %{binary() => binary()}
  def ids_for_revisions(organization_id, mission_id, revision_ids) do
    case revision_ids |> Enum.reject(&is_nil/1) |> Enum.uniq() do
      [] -> %{}
      ids -> organization_id |> links(mission_id, ids) |> Map.new()
    end
  end

  @doc "The composition `composition_id` names, or nil (a `breaking_base` that has one)."
  @spec fetch(binary(), binary(), binary()) :: t() | nil
  def fetch(organization_id, mission_id, composition_id),
    do: organization_id |> compositions(mission_id, [composition_id]) |> Map.get(composition_id)

  defp load(organization_id, mission_id, ids) do
    links = links(organization_id, mission_id, ids)
    compositions = compositions(organization_id, mission_id, links |> Enum.map(&elem(&1, 1)))

    for {revision_id, composition_id} <- links,
        %{} = composition <- [Map.get(compositions, composition_id)],
        into: %{},
        do: {revision_id, composition}
  end

  defp links(organization_id, mission_id, ids) do
    from(link in EffectiveRevisionRow,
      where:
        link.organization_id == ^organization_id and link.mission_id == ^mission_id and
          link.revision_id in ^ids,
      select: {link.revision_id, link.composition_id}
    )
    |> Repo.all()
  end

  defp compositions(_organization_id, _mission_id, []), do: %{}

  defp compositions(organization_id, mission_id, composition_ids) do
    composition_ids = Enum.uniq(composition_ids)
    scope = {organization_id, mission_id}
    layers = layers(scope, composition_ids)
    sources = sources(scope, layers |> Map.values() |> List.flatten() |> Enum.map(& &1.layer_id))
    numbers = numbers(scope, composition_ids)

    from(row in CompositionRow,
      where:
        row.organization_id == ^organization_id and row.mission_id == ^mission_id and
          row.composition_id in ^composition_ids
    )
    |> Repo.all()
    |> Map.new(fn row ->
      {row.composition_id,
       %{
         composition_id: row.composition_id,
         number: Map.get(numbers, row.composition_id),
         imported_layers:
           layers
           |> Map.get(row.composition_id, [])
           |> Enum.map(&Map.put(&1, :catalog_revision, Map.get(sources, &1.layer_id))),
         created_by: row.created_by,
         created_at: row.inserted_at
       }}
    end)
  end

  defp layers({organization_id, mission_id}, composition_ids) do
    from(layer in CompositionLayerRow,
      where:
        layer.organization_id == ^organization_id and layer.mission_id == ^mission_id and
          layer.composition_id in ^composition_ids,
      order_by: [asc: layer.composition_id, asc: layer.position],
      select: {layer.composition_id, %{layer_id: layer.layer_id, mount: layer.mount}}
    )
    |> Repo.all()
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
  end

  defp numbers({organization_id, mission_id}, composition_ids) do
    from(number in CompositionNumberRow,
      where:
        number.organization_id == ^organization_id and number.mission_id == ^mission_id and
          number.composition_id in ^composition_ids,
      select: {number.composition_id, number.number}
    )
    |> Repo.all()
    |> Map.new()
  end

  # Domain's rule (b): per layer, the earliest catalog revision in the tenant whose model revision
  # carries it. Derived, never stored.
  defp sources(_scope, []), do: %{}

  defp sources({organization_id, mission_id}, layer_ids) do
    carrying =
      from(layer in RevisionLayerRow,
        join: revision in RevisionRow,
        on: revision.revision_id == layer.revision_id,
        where:
          revision.organization_id == ^organization_id and revision.mission_id == ^mission_id and
            layer.layer_id in ^Enum.uniq(layer_ids),
        distinct: true,
        select: {layer.layer_id, revision.revision_id}
      )
      |> Repo.all()
      |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))

    ModelRevisions.first_for_groups(organization_id, mission_id, carrying)
  end
end
