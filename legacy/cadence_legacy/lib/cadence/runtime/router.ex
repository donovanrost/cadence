defmodule Cadence.Runtime.Router do
  @moduledoc """
  Transport event router for downlink bytes and transport state changes.
  """

  alias Cadence.Runtime.ChannelId
  alias Cadence.Runtime.Links.LinkController

  @spec ingest(String.t(), String.t(), binary(), map()) :: :ok
  def ingest(mission_id, transport_id, bytes, meta \\ %{}) when is_binary(bytes) do
    scid = meta[:scid]

    if is_integer(scid) do
      LinkController.route_downlink(mission_id, scid, transport_id, bytes, meta)
    else
      # Fallback: try each link controller that has a binding to this transport.
      # This is an intentionally simple routing heuristic until schedulers/classifiers
      # are fully implemented.
      for scid <- candidate_scids(mission_id, transport_id) do
        LinkController.route_downlink(mission_id, scid, transport_id, bytes, meta)
      end
    end

    :ok
  end

  @spec transport_connected(String.t(), String.t(), keyword()) :: :ok
  def transport_connected(mission_id, transport_id, _meta \\ []) do
    Enum.each(candidate_scids(mission_id, transport_id), fn scid ->
      LinkController.transport_state(mission_id, scid, transport_id, :up)
    end)

    :ok
  end

  @spec transport_disconnected(String.t(), String.t(), keyword()) :: :ok
  def transport_disconnected(mission_id, transport_id, _meta \\ []) do
    Enum.each(candidate_scids(mission_id, transport_id), fn scid ->
      LinkController.transport_state(mission_id, scid, transport_id, :down)
    end)

    :ok
  end

  defp candidate_scids(mission_id, transport_id) do
    Registry.select(Cadence.MissionRegistry, [
      {{{:link_binding, mission_id, :"$1", transport_id}, :_, :_}, [], [:"$1"]}
    ])
  end

  @spec tag_channel_meta(map(), ChannelId.t()) :: map()
  def tag_channel_meta(meta, %ChannelId{} = channel_id) do
    Map.put(meta, :channel_id, channel_id)
  end
end
