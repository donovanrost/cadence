defmodule Cadence.Reads.Spacecraft.ConfigurationCatalogs do
  @moduledoc "Bounded catalog choices for spacecraft setup; list reads do not hydrate model documents."
  alias Cadence.Applications.SpacecraftConfiguration.Drafts, as: ConfigurationDrafts
  alias Cadence.Applications.TelemetryDecom

  defdelegate list(mission, selected_ids \\ []), to: Cadence.Catalog.ConfigurationChoices

  def packets(scope, mission_id, spacecraft_id, catalog_id) do
    with {:ok, _mission, _craft} <-
           ConfigurationDrafts.authorize(scope, mission_id, spacecraft_id),
         true <- is_binary(catalog_id) and byte_size(catalog_id) in 1..255,
         {:ok, %{rows: rows}} <-
           TelemetryDecom.list_revision_apid_rows(
             scope.organization_id,
             mission_id,
             catalog_id
           ) do
      {:ok,
       %{
         catalog_id: catalog_id,
         packets:
           Enum.take(rows, 2048)
           |> Enum.map(fn row ->
             %{
               apid: row.apid,
               name: Enum.map_join(row.packets, ", ", & &1.packet_name),
               definitions: row.def_count
             }
           end)
       }}
    else
      false -> {:error, :spacecraft_catalog_unavailable}
      {:error, reason} -> {:error, reason}
    end
  end
end
