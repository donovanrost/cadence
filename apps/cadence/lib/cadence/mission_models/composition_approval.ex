defmodule Cadence.MissionModels.CompositionApproval do
  @moduledoc """
  The model gate approves compositions (#542, design E1, `mission-composition-design.md` §4). The
  gated unit stays the mission-model revision; what changes is how its approval is anchored:

  - **A composition must name the revision** (its link, unique on the revision, #541), **and every
    imported layer must come from an import a catalog revision names.** That is the interim guard
    (director 11-17) applied per layer: a reimport makes no catalog revision, and after #541 it
    still gets its own one-layer composition, so without the per-layer rule its revision would
    become approvable by the file's original importer, whom a reimport doesn't count. For an
    import's own one-layer composition this is exactly the old rule. Either failure keeps the
    code `:mission_model_revision_not_in_catalog`, whose words ("import its file as a new catalog
    revision") stay true and remain the remedy. A rename waits for D2's reads.
  - **Importers are the union across the composition's imported layers**: for each layer, the
    importers of the import revisions that carry it (`Catalog.model_import_actors/3`, so a system
    import counts its `run_by` per #513, and one from before #513 counts no one). A one-layer
    composition's revision IS its import's revision, so its importers are exactly today's.
  - **The composer joins separation** (mms-security M1): the composition's `created_by` counts as
    a catalog revision's creator does (`Catalog.model_import_actor_of/1`). A migrated composition's
    system actor has no `run_by` and counts no one.
  - **The approval evidence names the combination** (M2): the composition id and each imported
    layer's id, mount and content digest.
  """

  import Ecto.Query

  alias Cadence.Catalog
  alias Cadence.MissionModels.{Compositions, RevisionLayerRow, RevisionRow}
  alias Cadence.Repo

  @doc """
  The composition that names `revision_id`, when every one of its imported layers comes from a
  catalog-named import; otherwise the not-named refusal.
  """
  @spec require(binary(), binary(), binary()) ::
          {:ok, Compositions.t()} | {:error, :mission_model_revision_not_in_catalog}
  def require(organization_id, mission_id, revision_id) do
    with {:ok, composition} <- Compositions.for_revision(organization_id, mission_id, revision_id),
         true <- layers_named?(organization_id, mission_id, composition) do
      {:ok, composition}
    else
      _not_named -> {:error, :mission_model_revision_not_in_catalog}
    end
  end

  # Every imported layer is carried by at least one import revision a catalog revision names.
  defp layers_named?(organization_id, mission_id, composition) do
    layer_ids = Enum.map(composition.imported_layers, & &1.layer_id)
    by_layer = carrying_revisions(organization_id, mission_id, layer_ids)

    named =
      Catalog.catalog_named_model_revisions(
        organization_id,
        mission_id,
        by_layer |> Map.values() |> List.flatten() |> Enum.uniq()
      )

    layer_ids != [] and
      Enum.all?(layer_ids, fn layer_id ->
        by_layer |> Map.get(layer_id, []) |> Enum.any?(&MapSet.member?(named, &1))
      end)
  end

  @doc """
  Every actor separation counts for approving `revision_id`: the union of its composition's
  layers' importers and its composer. A revision no composition names falls back to its own
  importers (`Catalog.model_import_actors/3`), as before; approving it is refused anyway.
  """
  @spec importer_actors(binary(), binary(), binary()) :: [
          {:user, binary()} | {:service, binary()}
        ]
  def importer_actors(organization_id, mission_id, revision_id) do
    case Compositions.for_revision(organization_id, mission_id, revision_id) do
      {:ok, composition} ->
        composition_actors(organization_id, mission_id, composition)

      {:error, :not_found} ->
        Catalog.model_import_actors(organization_id, mission_id, revision_id)
    end
  end

  @doc "The union of a composition's layers' importers and its composer."
  @spec composition_actors(binary(), binary(), Compositions.t()) :: [
          {:user, binary()} | {:service, binary()}
        ]
  def composition_actors(organization_id, mission_id, composition) do
    layer_ids = Enum.map(composition.imported_layers, & &1.layer_id)

    layer_importers =
      organization_id
      |> carrying_revisions(mission_id, layer_ids)
      |> Map.values()
      |> List.flatten()
      |> Enum.uniq()
      |> Enum.flat_map(&Catalog.model_import_actors(organization_id, mission_id, &1))

    composer = Catalog.model_import_actor_of(composition.created_by)

    (layer_importers ++ List.wrap(composer)) |> Enum.uniq()
  end

  @doc "What an approval records about the combination it approved (M2)."
  @spec evidence(Compositions.t()) :: map()
  def evidence(composition) do
    %{
      "composition_id" => composition.composition_id,
      "imported_layers" =>
        Enum.map(composition.imported_layers, fn layer ->
          %{
            "layer_id" => layer.layer_id,
            "mount" => layer.mount,
            "content_sha256" => layer.content_sha256
          }
        end)
    }
  end

  # Per layer, the revisions in this mission that carry it: its import revision (and any composed
  # revision over it, which no catalog revision names and whose own importers are empty, so it
  # adds neither a name nor an importer).
  defp carrying_revisions(_organization_id, _mission_id, []), do: %{}

  defp carrying_revisions(organization_id, mission_id, layer_ids) do
    from(layer in RevisionLayerRow,
      join: revision in RevisionRow,
      on: revision.revision_id == layer.revision_id,
      where:
        revision.organization_id == ^organization_id and revision.mission_id == ^mission_id and
          layer.layer_id in ^layer_ids,
      distinct: true,
      select: {layer.layer_id, revision.revision_id}
    )
    |> Repo.all()
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
  end
end
