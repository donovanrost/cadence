defmodule Cadence.Control.ScidRoutes do
  @moduledoc """
  Builds an endpoint's `Cadence.Protocol.ScidRoutes` (#1078 P5 slice E1b): what its partition may
  accept by frame SCID. Two reads in all, whatever the size of the relay set: the endpoint, and the
  spacecraft it and its relay set name (bounded batches). The runtime calls it through
  `config :cadence, :scid_routes` (`module:`, `refresh_ms:`), so the data plane reads no
  management table itself.

  An endpoint that can't be read yields routes that check nothing: a doubt refuses no frame.
  """

  alias Cadence.Protocol.ScidRoutes
  alias Cadence.SourceEndpoints
  alias Cadence.Spacecraft
  alias Cadence.SpacecraftStore

  @spec build(binary(), binary(), binary()) :: ScidRoutes.t()
  def build(organization_id, mission_id, source_endpoint_id)
      when is_binary(organization_id) and is_binary(mission_id) and is_binary(source_endpoint_id) do
    with {:ok, endpoint} <-
           SourceEndpoints.fetch_source_endpoint(organization_id, mission_id, source_endpoint_id),
         origin_ids = origin_ids(endpoint),
         {:ok, crafts} <-
           SpacecraftStore.fetch_spacecrafts_in_batches(
             organization_id,
             mission_id,
             Enum.uniq(Enum.filter([endpoint.spacecraft_id | origin_ids], &is_binary/1))
           ) do
      own = Map.get(crafts, endpoint.spacecraft_id)

      ScidRoutes.new(
        source_endpoint_id,
        endpoint.spacecraft_id,
        own && own.scid,
        origins(origin_ids, crafts)
      )
    else
      _unreadable -> ScidRoutes.none()
    end
  end

  defp origins(ids, crafts) do
    for id <- ids, %Spacecraft{} = craft <- [Map.get(crafts, id)] do
      {id, craft.scid, if(Spacecraft.archived?(craft), do: :archived, else: :active)}
    end
  end

  defp origin_ids(%{relay: %{"origin_spacecraft_ids" => ids}}) when is_list(ids), do: ids
  defp origin_ids(_endpoint), do: []
end
