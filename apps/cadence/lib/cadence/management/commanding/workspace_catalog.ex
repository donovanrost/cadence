defmodule Cadence.Management.Commanding.WorkspaceCatalog do
  @moduledoc "Curated spacecraft labels for the bounded command target page."
  alias Cadence.Management.Commanding.RequestAuthoring
  alias Cadence.SpacecraftStore

  def load(scope, mission_id, query) do
    with {:ok, catalog} <- RequestAuthoring.load(scope, mission_id, query) do
      ids =
        catalog["targets"]["entries"]
        |> Enum.map(& &1["spacecraft_id"])
        |> Enum.reject(&is_nil/1)
        |> Enum.uniq()

      with {:ok, spacecraft} <-
             SpacecraftStore.display_names(scope.organization_id, mission_id, ids) do
        {:ok, catalog, spacecraft}
      end
    end
  end
end
