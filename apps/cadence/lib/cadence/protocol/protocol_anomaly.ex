defmodule Cadence.Protocol.ProtocolAnomaly do
  @moduledoc """
  Canonical protocol-level anomaly emitted during frame and packet extraction.
  """

  alias Cadence.Ids

  @type anomaly_kind ::
          :frame_decode_dropped
          | :frame_reassembly_error
          | :frame_sequence_discontinuity
          | :master_channel_frame_count_discontinuity
          | :partial_packet_on_frame_count_discontinuity
          | :orphan_packet_continuation
          | :first_header_pointer_resynchronization
          | :continuation_decode_failed
          | :invalid_space_packet
          | :oid_validation_failed

  @type t :: %__MODULE__{
          anomaly_id: binary(),
          evidence_id: binary(),
          mission_id: binary(),
          source_endpoint_ref: binary() | nil,
          spacecraft_id: binary() | nil,
          protocol_family: atom(),
          direction: :downlink | :uplink,
          anomaly_kind: anomaly_kind(),
          scid: non_neg_integer() | nil,
          vcid: non_neg_integer() | nil,
          map_id: non_neg_integer() | nil,
          frame_seq: non_neg_integer() | nil,
          raw_frame_offset_bytes: non_neg_integer() | nil,
          raw_frame_length_bytes: pos_integer() | nil,
          recorded_at: DateTime.t(),
          metadata: map()
        }

  defstruct [
    :anomaly_id,
    :evidence_id,
    :mission_id,
    :source_endpoint_ref,
    :spacecraft_id,
    :protocol_family,
    :direction,
    :anomaly_kind,
    :scid,
    :vcid,
    :map_id,
    :frame_seq,
    :raw_frame_offset_bytes,
    :raw_frame_length_bytes,
    :recorded_at,
    metadata: %{}
  ]

  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    %__MODULE__{
      anomaly_id:
        Map.get(
          attrs,
          :anomaly_id,
          Map.get(attrs, "anomaly_id", Ids.new("protocol_anomaly"))
        ),
      evidence_id: Map.fetch!(attrs, :evidence_id),
      mission_id: Map.fetch!(attrs, :mission_id),
      source_endpoint_ref:
        Map.get(attrs, :source_endpoint_ref, Map.get(attrs, "source_endpoint_ref")),
      spacecraft_id: Map.get(attrs, :spacecraft_id, Map.get(attrs, "spacecraft_id")),
      protocol_family: Map.fetch!(attrs, :protocol_family),
      direction: Map.fetch!(attrs, :direction),
      anomaly_kind: Map.fetch!(attrs, :anomaly_kind),
      scid: Map.get(attrs, :scid, Map.get(attrs, "scid")),
      vcid: Map.get(attrs, :vcid, Map.get(attrs, "vcid")),
      map_id: Map.get(attrs, :map_id, Map.get(attrs, "map_id")),
      frame_seq: Map.get(attrs, :frame_seq, Map.get(attrs, "frame_seq")),
      raw_frame_offset_bytes:
        Map.get(attrs, :raw_frame_offset_bytes, Map.get(attrs, "raw_frame_offset_bytes")),
      raw_frame_length_bytes:
        Map.get(attrs, :raw_frame_length_bytes, Map.get(attrs, "raw_frame_length_bytes")),
      recorded_at: Map.fetch!(attrs, :recorded_at),
      metadata: Map.get(attrs, :metadata, Map.get(attrs, "metadata", %{}))
    }
  end
end
