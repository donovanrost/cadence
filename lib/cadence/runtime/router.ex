defmodule Cadence.Runtime.Router do
  @moduledoc """
  Interface event router for downlink bytes and interface state changes.
  """

  alias Cadence.Runtime.ChannelId
  alias Cadence.Runtime.Links.LinkController

  @spec ingest(String.t(), String.t(), binary(), map()) :: :ok
  def ingest(mission_id, interface_id, bytes, meta \\ %{}) when is_binary(bytes) do
    scid = meta[:scid]

    if is_integer(scid) do
      LinkController.route_downlink(mission_id, scid, interface_id, bytes, meta)
    else
      # Fallback: try each link controller that has a binding to this interface.
      # This is an intentionally simple routing heuristic until schedulers/classifiers
      # are fully implemented.
      for scid <- candidate_scids(mission_id, interface_id) do
        LinkController.route_downlink(mission_id, scid, interface_id, bytes, meta)
      end
    end

    :ok
  end

  @spec interface_connected(String.t(), String.t(), keyword()) :: :ok
  def interface_connected(mission_id, interface_id, _meta \\ []) do
    Enum.each(candidate_scids(mission_id, interface_id), fn scid ->
      LinkController.interface_state(mission_id, scid, interface_id, :up)
    end)

    :ok
  end

  @spec interface_disconnected(String.t(), String.t(), keyword()) :: :ok
  def interface_disconnected(mission_id, interface_id, _meta \\ []) do
    Enum.each(candidate_scids(mission_id, interface_id), fn scid ->
      LinkController.interface_state(mission_id, scid, interface_id, :down)
    end)

    :ok
  end

  defp candidate_scids(mission_id, interface_id) do
    Registry.select(Cadence.MissionRegistry, [
      {{{:link_binding, mission_id, :"$1", interface_id}, :_, :_}, [], [:"$1"]}
    ])
  end

  @spec tag_channel_meta(map(), ChannelId.t()) :: map()
  def tag_channel_meta(meta, %ChannelId{} = channel_id) do
    Map.put(meta, :channel_id, channel_id)
  end
end
