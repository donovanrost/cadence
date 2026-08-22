defmodule Cadence.Transport.TCStreamId do
  @moduledoc """
  Canonical identity for a TC stream in shared-link contexts.

  Stream identity is keyed by mission + channel (scid/vcid/map), independent of transport.
  """

  alias Cadence.Runtime.ChannelId

  @enforce_keys [:mission_id, :scid, :vcid]
  defstruct [
    :mission_id,
    :transport_id,
    :channel_id,
    :scid,
    :vcid,
    dir: :uplink,
    map_id: nil
  ]

  @type t :: %__MODULE__{
          mission_id: String.t(),
          transport_id: String.t() | nil,
          channel_id: ChannelId.t() | nil,
          scid: non_neg_integer(),
          vcid: non_neg_integer(),
          dir: :uplink | :downlink,
          map_id: non_neg_integer() | nil
        }

  @spec new!(String.t(), String.t() | nil, non_neg_integer(), non_neg_integer(), keyword()) :: t()
  def new!(mission_id, transport_id, scid, vcid, opts \\ [])
      when is_binary(mission_id) and is_integer(scid) and is_integer(vcid) do
    channel_id = Keyword.get(opts, :channel_id)
    map_id = Keyword.get(opts, :map_id) || map_id_from_channel(channel_id)

    %__MODULE__{
      mission_id: mission_id,
      transport_id: transport_id,
      channel_id: channel_id,
      scid: scid,
      vcid: vcid,
      dir: Keyword.get(opts, :dir, :uplink),
      map_id: map_id
    }
  end

  @spec new_from_channel!(String.t(), ChannelId.t(), keyword()) :: t()
  def new_from_channel!(mission_id, %ChannelId{} = channel_id, opts \\ []) do
    new!(
      mission_id,
      Keyword.get(opts, :transport_id),
      channel_id.scid,
      channel_id.vcid,
      Keyword.put(opts, :channel_id, channel_id)
    )
  end

  @spec to_key(t()) :: tuple()
  def to_key(%__MODULE__{} = tc_stream_id) do
    {tc_stream_id.mission_id, tc_stream_id.scid, tc_stream_id.vcid, tc_stream_id.dir,
     tc_stream_id.map_id}
  end

  @spec to_string(t()) :: String.t()
  def to_string(%__MODULE__{} = tc_stream_id) do
    "mission_id=#{tc_stream_id.mission_id} scid=#{tc_stream_id.scid} vcid=#{tc_stream_id.vcid} dir=#{tc_stream_id.dir} map_id=#{inspect(tc_stream_id.map_id)} transport_id=#{inspect(tc_stream_id.transport_id)}"
  end

  defp map_id_from_channel(%ChannelId{map_id: map_id}), do: map_id
  defp map_id_from_channel(_), do: nil
end
