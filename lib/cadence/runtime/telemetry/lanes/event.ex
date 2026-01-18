defmodule Cadence.Runtime.Telemetry.Lanes.Event do
  @moduledoc """
  Event flowing through the lanes/shards pipeline.

  This struct is a minimal superset of the previous PipelineEvent, adding
  lane/shard metadata and router/config versions.
  """

  alias Cadence.Runtime.Telemetry.Lanes.LaneSelector
  alias Cadence.Telemetry.Packet
  alias Cadence.Time, as: CadenceTime

  @type t :: %__MODULE__{
          id: String.t(),
          mission_id: String.t(),
          target_id: String.t(),
          apid: non_neg_integer() | nil,
          lane: atom(),
          shard_id: non_neg_integer(),
          router_version: non_neg_integer(),
          config_version: non_neg_integer(),
          packet: Packet.t(),
          metadata: map(),
          received_at: integer(),
          ingest_monotonic_ns: non_neg_integer(),
          packet_def: map() | nil,
          packet_format: atom() | nil,
          raw_items: map() | nil,
          converted_items: map() | nil,
          qualified_items: map() | nil,
          all_items: map() | nil,
          items_with_limits: list() | nil
        }

  defstruct [
    :id,
    :mission_id,
    :target_id,
    :apid,
    :lane,
    :shard_id,
    :router_version,
    :config_version,
    :packet,
    :metadata,
    :received_at,
    :ingest_monotonic_ns,
    :packet_def,
    :packet_format,
    :raw_items,
    :converted_items,
    :qualified_items,
    :all_items,
    :items_with_limits
  ]

  @doc """
  Construct a new event for the configured lane/shard mapping.
  """
  @spec new(Packet.t(), map(), map()) :: t()
  def new(%Packet{} = packet, metadata, %{
        mission_id: mission_id,
        lanes: lanes,
        router_version: router_version,
        config_version: config_version
      }) do
    target_id = metadata[:target_id] || packet.target_id || "default"
    apid = get_apid(packet)
    lane = LaneSelector.select_lane(packet, metadata, lanes)
    lane_config = Enum.find(lanes, &(&1.name == lane)) || List.first(lanes)

    shard_id =
      compute_shard(
        target_id,
        apid,
        lane_config.shard_count,
        lane_config.virtual_shards
      )

    %__MODULE__{
      id: generate_id(),
      mission_id: mission_id,
      target_id: target_id,
      apid: apid,
      lane: lane,
      shard_id: shard_id,
      router_version: router_version,
      config_version: config_version,
      packet: packet,
      metadata: metadata,
      received_at: CadenceTime.monotonic(:microsecond),
      ingest_monotonic_ns: CadenceTime.monotonic(:nanosecond)
    }
  end

  defp compute_shard(target_id, apid, shard_count, virtual_shards) do
    vnode = :erlang.phash2({target_id, apid}, virtual_shards)
    rem(vnode, shard_count)
  end

  defp get_apid(%Packet{ccsds_header: %{apid: apid}}) when not is_nil(apid), do: apid

  defp get_apid(%Packet{raw: raw}) when is_binary(raw) and byte_size(raw) > 0 do
    <<type_byte::8, _rest::binary>> = raw
    type_byte
  end

  defp get_apid(_), do: nil

  defp generate_id do
    :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
  end
end
