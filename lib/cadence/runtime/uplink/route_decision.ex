defmodule Cadence.Runtime.Uplink.RouteDecision do
  @moduledoc """
  Resolved uplink route decision for a single PDU.
  """

  alias Cadence.CCSDS.Core.PDU
  alias Cadence.Transport.TCStreamId

  @type cop1_mode :: :fop | :bypass

  @type t :: %__MODULE__{
          target_id: String.t(),
          pdu_type: PDU.pdu_type() | nil,
          apid: non_neg_integer() | nil,
          interface_id: String.t(),
          scid: non_neg_integer() | nil,
          vcid: non_neg_integer() | nil,
          cop1_mode: cop1_mode(),
          tc_stream_id: TCStreamId.t() | nil,
          tc_stream_id_raw: term() | nil
        }

  defstruct [
    :target_id,
    :pdu_type,
    :apid,
    :interface_id,
    :scid,
    :vcid,
    :cop1_mode,
    :tc_stream_id,
    :tc_stream_id_raw
  ]
end
