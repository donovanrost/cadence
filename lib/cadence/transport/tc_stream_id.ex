defmodule Cadence.Transport.TCStreamId do
  @moduledoc """
  Canonical identity for a TC stream in shared-link contexts.
  """

  @enforce_keys [:mission_id, :interface_id, :scid, :vcid]
  defstruct [
    :mission_id,
    :interface_id,
    :scid,
    :vcid,
    dir: :uplink,
    map_id: nil
  ]

  @type t :: %__MODULE__{
          mission_id: String.t(),
          interface_id: String.t(),
          scid: non_neg_integer(),
          vcid: non_neg_integer(),
          dir: :uplink | :downlink,
          map_id: non_neg_integer() | nil
        }

  @spec new!(String.t(), String.t(), non_neg_integer(), non_neg_integer(), keyword()) :: t()
  def new!(mission_id, interface_id, scid, vcid, opts \\ [])
      when is_binary(mission_id) and is_binary(interface_id) and is_integer(scid) and
             is_integer(vcid) do
    %__MODULE__{
      mission_id: mission_id,
      interface_id: interface_id,
      scid: scid,
      vcid: vcid,
      dir: Keyword.get(opts, :dir, :uplink),
      map_id: Keyword.get(opts, :map_id)
    }
  end

  @spec to_key(t()) :: tuple()
  def to_key(%__MODULE__{} = tc_stream_id) do
    {tc_stream_id.mission_id, tc_stream_id.interface_id, tc_stream_id.scid, tc_stream_id.vcid,
     tc_stream_id.dir, tc_stream_id.map_id}
  end

  @spec to_string(t()) :: String.t()
  def to_string(%__MODULE__{} = tc_stream_id) do
    "mission_id=#{tc_stream_id.mission_id} interface_id=#{tc_stream_id.interface_id} scid=#{tc_stream_id.scid} vcid=#{tc_stream_id.vcid} dir=#{tc_stream_id.dir} map_id=#{inspect(tc_stream_id.map_id)}"
  end
end
