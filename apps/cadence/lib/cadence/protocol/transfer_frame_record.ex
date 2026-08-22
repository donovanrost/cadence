defmodule Cadence.Protocol.TransferFrameRecord do
  @moduledoc """
  Canonical transfer-frame-level record emitted after protocol extraction.
  """

  alias Cadence.Ids

  @type t :: %__MODULE__{
          frame_record_id: binary(),
          evidence_id: binary(),
          mission_id: binary(),
          source_endpoint_ref: binary() | nil,
          spacecraft_id: binary() | nil,
          protocol_family: atom(),
          direction: :downlink | :uplink,
          scid: non_neg_integer(),
          vcid: non_neg_integer(),
          map_id: non_neg_integer() | nil,
          frame_seq: non_neg_integer(),
          raw_frame_offset_bytes: non_neg_integer(),
          raw_frame_length_bytes: pos_integer(),
          payload_length_bytes: non_neg_integer(),
          first_header_pointer: non_neg_integer() | nil,
          quality: atom() | nil,
          source_time: DateTime.t() | nil,
          receipt_time: DateTime.t(),
          metadata: map()
        }

  defstruct [
    :frame_record_id,
    :evidence_id,
    :mission_id,
    :source_endpoint_ref,
    :spacecraft_id,
    :protocol_family,
    :direction,
    :scid,
    :vcid,
    :map_id,
    :frame_seq,
    :raw_frame_offset_bytes,
    :raw_frame_length_bytes,
    :payload_length_bytes,
    :first_header_pointer,
    :quality,
    :source_time,
    :receipt_time,
    metadata: %{}
  ]

  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    %__MODULE__{
      frame_record_id:
        Map.get(attrs, :frame_record_id, Map.get(attrs, "frame_record_id", Ids.new("frame"))),
      evidence_id: Map.fetch!(attrs, :evidence_id),
      mission_id: Map.fetch!(attrs, :mission_id),
      source_endpoint_ref:
        Map.get(attrs, :source_endpoint_ref, Map.get(attrs, "source_endpoint_ref")),
      spacecraft_id: Map.get(attrs, :spacecraft_id, Map.get(attrs, "spacecraft_id")),
      protocol_family: Map.fetch!(attrs, :protocol_family),
      direction: Map.fetch!(attrs, :direction),
      scid: Map.fetch!(attrs, :scid),
      vcid: Map.fetch!(attrs, :vcid),
      map_id: Map.get(attrs, :map_id, Map.get(attrs, "map_id")),
      frame_seq: Map.fetch!(attrs, :frame_seq),
      raw_frame_offset_bytes: Map.fetch!(attrs, :raw_frame_offset_bytes),
      raw_frame_length_bytes: Map.fetch!(attrs, :raw_frame_length_bytes),
      payload_length_bytes: Map.fetch!(attrs, :payload_length_bytes),
      first_header_pointer:
        Map.get(attrs, :first_header_pointer, Map.get(attrs, "first_header_pointer")),
      quality: Map.get(attrs, :quality, Map.get(attrs, "quality")),
      source_time: Map.get(attrs, :source_time, Map.get(attrs, "source_time")),
      receipt_time: Map.fetch!(attrs, :receipt_time),
      metadata: Map.get(attrs, :metadata, Map.get(attrs, "metadata", %{}))
    }
  end
end
