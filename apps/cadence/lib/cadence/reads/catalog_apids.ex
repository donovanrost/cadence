defmodule Cadence.Reads.CatalogApids do
  @moduledoc """
  The APIDs a catalog revision defines, with their packets (L17/L22, fe-setup): the choices for a
  profile's or override's `handled_apids`. `available: false` when the revision has no decodable
  telemetry plan yet (not compiled into a mission model), so the list is empty, not wrong.
  """

  alias Cadence.MissionModels.CatalogApids

  @spec load(binary(), binary(), binary()) ::
          {:ok, %{revision_id: binary(), available: boolean(), apids: [map()]}}
          | {:error, :catalog_revision_not_found}
  def load(organization_id, mission_id, revision_id) do
    case CatalogApids.list(organization_id, mission_id, revision_id) do
      {:ok, apids} -> {:ok, %{revision_id: revision_id, available: true, apids: apids}}
      {:error, :catalog_revision_not_found} -> {:error, :catalog_revision_not_found}
      {:error, _no_plan} -> {:ok, %{revision_id: revision_id, available: false, apids: []}}
    end
  end
end
