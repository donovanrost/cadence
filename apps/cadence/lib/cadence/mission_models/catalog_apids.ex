defmodule Cadence.MissionModels.CatalogApids do
  @moduledoc """
  The APIDs a catalog revision defines, with their packets (L22): what a profile's or override's
  `handled_apids` may name, and what `nil` ("all of the catalog's APIDs") expands to at apply.
  Read from the catalog's executable telemetry plan (`TelemetryProjection`), so it's exactly what
  decode can handle.
  """

  alias Cadence.Catalog
  alias Cadence.MissionModels.TelemetryProjection

  @doc "`[%{apid, packets: [packet_name]}]`, sorted by APID."
  @spec list(binary(), binary(), binary()) :: {:ok, [map()]} | {:error, term()}
  def list(organization_id, mission_id, catalog_revision_id)
      when is_binary(catalog_revision_id) do
    with {:ok, revision} <-
           Catalog.fetch_revision(organization_id, mission_id, catalog_revision_id),
         {:ok, telemetry} <- TelemetryProjection.load(organization_id, mission_id, revision) do
      {:ok,
       telemetry.packet_definitions
       |> Enum.filter(&is_integer(&1.apid))
       |> Enum.group_by(& &1.apid, & &1.packet_name)
       |> Enum.map(fn {apid, packets} -> %{apid: apid, packets: Enum.sort(packets)} end)
       |> Enum.sort_by(& &1.apid)}
    end
  end

  def list(_organization_id, _mission_id, nil), do: {:ok, []}

  @doc "Just the APIDs, sorted."
  @spec apids(binary(), binary(), binary() | nil) :: {:ok, [non_neg_integer()]} | {:error, term()}
  def apids(organization_id, mission_id, catalog_revision_id) do
    with {:ok, rows} <- list(organization_id, mission_id, catalog_revision_id),
         do: {:ok, Enum.map(rows, & &1.apid)}
  end

  @doc """
  What a spacecraft decodes for `handled` (nil = all) in `catalog_apids`: `nil` expands to them
  all; a list is taken as given (`stray/2` says which the catalog doesn't define).
  """
  @spec effective([non_neg_integer()] | nil, [non_neg_integer()]) :: [non_neg_integer()]
  def effective(nil, catalog_apids), do: catalog_apids
  def effective(handled, _catalog_apids) when is_list(handled), do: Enum.sort(handled)

  @doc "The APIDs in `handled` that `catalog_apids` doesn't define."
  @spec stray([non_neg_integer()] | nil, [non_neg_integer()]) :: [non_neg_integer()]
  def stray(nil, _catalog_apids), do: []
  def stray(handled, catalog_apids), do: Enum.sort(handled -- catalog_apids)
end
