defmodule Cadence.Protocol.PacketRecord do
  @moduledoc """
  Canonical packet-level record emitted after protocol extraction.
  """

  @type t :: %__MODULE__{
          packet_id: binary(),
          evidence_id: binary(),
          mission_id: binary(),
          source_endpoint_ref: binary() | nil,
          spacecraft_id: binary() | nil,
          protocol_family: atom(),
          packet_kind: atom(),
          apid: non_neg_integer(),
          sequence_flags: non_neg_integer(),
          sequence_count: non_neg_integer(),
          secondary_header?: boolean(),
          packet_data: binary(),
          source_time: DateTime.t() | nil,
          receipt_time: DateTime.t(),
          provenance: map()
        }

  defstruct [
    :packet_id,
    :evidence_id,
    :mission_id,
    :source_endpoint_ref,
    :spacecraft_id,
    :protocol_family,
    :packet_kind,
    :apid,
    :sequence_flags,
    :sequence_count,
    :secondary_header?,
    :packet_data,
    :source_time,
    :receipt_time,
    provenance: %{}
  ]
end
