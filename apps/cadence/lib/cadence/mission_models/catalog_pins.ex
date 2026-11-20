defmodule Cadence.MissionModels.CatalogPins do
  @moduledoc """
  Between a catalog revision and the one-layer composition it imported (D3, #544): the
  translation of an old client's catalog pin, and the provenance catalog revision of a
  composition pin. A composition of more than one layer (D4) has no catalog revision.
  """

  import Ecto.Query

  alias Cadence.Catalog.RevisionRow, as: CatalogRevisionRow
  alias Cadence.MissionModels.{CompositionLayerRow, CompositionRow, Compositions, LayerRow}
  alias Cadence.MissionModels.RevisionLayerRow
  alias Cadence.Repo

  @doc "The catalog revision's one-layer composition at '/', when it exists in the tenant."
  @spec for_catalog_revision(binary(), binary(), binary()) :: {:ok, binary()} | {:error, :none}
  def for_catalog_revision(organization_id, mission_id, catalog_revision_id) do
    with [layer_id] <- layers(organization_id, mission_id, catalog_revision_id),
         id = Compositions.id(organization_id, mission_id, [{layer_id, "/"}]),
         true <- stored?(organization_id, mission_id, id) do
      {:ok, id}
    else
      _none -> {:error, :none}
    end
  end

  @doc """
  The provenance catalog revision of a one-layer composition: the earliest catalog revision in the
  tenant that imported its layer (by `inserted_at`, then id; domain's rule on #543). Nil for a
  composition of several layers, or one no catalog revision imported.
  """
  @spec catalog_revision_for(binary(), binary(), binary()) :: binary() | nil
  def catalog_revision_for(organization_id, mission_id, composition_id) do
    case composition_layers(organization_id, mission_id, composition_id) do
      [layer_id] ->
        from(catalog in CatalogRevisionRow,
          join: carried in RevisionLayerRow,
          on: carried.revision_id == catalog.mission_model_revision_id,
          where:
            catalog.organization_id == ^organization_id and catalog.mission_id == ^mission_id and
              carried.layer_id == ^layer_id,
          order_by: [asc: catalog.inserted_at, asc: catalog.catalog_revision_id],
          limit: 1,
          select: catalog.catalog_revision_id
        )
        |> Repo.one()

      _not_one ->
        nil
    end
  end

  @doc "A catalog revision's number in its database, or nil when it isn't the tenant's."
  @spec catalog_number(binary(), binary(), binary() | nil) :: integer() | nil
  def catalog_number(_organization_id, _mission_id, nil), do: nil

  def catalog_number(organization_id, mission_id, catalog_revision_id) do
    from(catalog in CatalogRevisionRow,
      where:
        catalog.catalog_revision_id == ^catalog_revision_id and
          catalog.organization_id == ^organization_id and catalog.mission_id == ^mission_id,
      select: catalog.revision_number
    )
    |> Repo.one()
  end

  defp layers(organization_id, mission_id, catalog_revision_id) do
    from(catalog in CatalogRevisionRow,
      join: carried in RevisionLayerRow,
      on: carried.revision_id == catalog.mission_model_revision_id,
      join: layer in LayerRow,
      on: layer.layer_id == carried.layer_id,
      where:
        catalog.catalog_revision_id == ^catalog_revision_id and
          catalog.organization_id == ^organization_id and catalog.mission_id == ^mission_id and
          layer.organization_id == ^organization_id and layer.mission_id == ^mission_id and
          layer.layer_kind == "imported",
      select: layer.layer_id
    )
    |> Repo.all()
  end

  defp composition_layers(organization_id, mission_id, composition_id) do
    from(layer in CompositionLayerRow,
      where:
        layer.organization_id == ^organization_id and layer.mission_id == ^mission_id and
          layer.composition_id == ^composition_id,
      select: layer.layer_id
    )
    |> Repo.all()
  end

  defp stored?(organization_id, mission_id, composition_id) do
    CompositionRow
    |> where(
      [row],
      row.organization_id == ^organization_id and row.mission_id == ^mission_id and
        row.composition_id == ^composition_id
    )
    |> Repo.exists?()
  end
end
