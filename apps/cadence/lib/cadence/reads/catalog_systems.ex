defmodule Cadence.Reads.CatalogSystems do
  @moduledoc """
  The SpaceSystems a catalog revision's mission model has and what each holds (ADR-020 P5, #1078
  slice B1): the choices a spacecraft's binding offers, beside `CatalogApids`. `available: false`
  when the revision has no compiled model yet, so the list is empty, not wrong.

  Each system: `system_id`, `path`, `name`, `parent_id`, its `packets` (`packet_definition_id`,
  `name`, `runtime_name`, `apid`), its `commands` (`command_id`, `name`, `runtime_name`) and the
  counts of its `algorithms` and `policies`.
  """

  alias Cadence.Catalog
  alias Cadence.MissionModels
  alias Cadence.MissionModels.SystemSelection

  @spec load(binary(), binary(), binary()) ::
          {:ok, %{revision_id: binary(), available: boolean(), systems: [map()]}}
          | {:error, :catalog_revision_not_found}
  def load(organization_id, mission_id, catalog_revision_id) do
    with {:ok, catalog} <-
           Catalog.fetch_revision(organization_id, mission_id, catalog_revision_id) do
      case systems(catalog) do
        {:ok, systems} ->
          {:ok, %{revision_id: catalog_revision_id, available: true, systems: systems}}

        :unavailable ->
          {:ok, %{revision_id: catalog_revision_id, available: false, systems: []}}
      end
    end
  end

  @doc """
  The systems `handled_apids` of a document amount to in `catalog_revision_id`'s model (the craft's
  effective systems, from its APIDs): `[%{system_id, path, name, bound, apids}]`, or nil when the
  document names no catalog revision or the revision has no compiled model.
  """
  @spec effective(binary(), binary(), binary() | nil, [non_neg_integer()] | nil) :: [map()] | nil
  def effective(_organization_id, _mission_id, nil, _apids), do: nil

  def effective(organization_id, mission_id, catalog_revision_id, apids) do
    with {:ok, catalog} <-
           Catalog.fetch_revision(organization_id, mission_id, catalog_revision_id),
         {:ok, revision, plans} <- model(catalog) do
      SystemSelection.effective(revision, plans, {:apids, List.wrap(apids)})
    else
      _unavailable -> nil
    end
  end

  defp systems(catalog) do
    case model(catalog) do
      {:ok, revision, plans} -> {:ok, SystemSelection.contributions(revision, plans)}
      :error -> :unavailable
    end
  end

  defp model(%{mission_model_revision_id: model_id} = catalog)
       when is_binary(model_id) and model_id != "" do
    with {:ok, revision} <-
           MissionModels.fetch_revision(catalog.organization_id, catalog.mission_id, model_id),
         {:ok, plans} <-
           MissionModels.fetch_runtime_plans(
             catalog.organization_id,
             catalog.mission_id,
             model_id
           ) do
      {:ok, revision, plans}
    else
      _no_model -> :error
    end
  end

  defp model(_catalog), do: :error
end
