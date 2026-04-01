defmodule Cadence.Runtime.Uplink.UplinkPDU do
  @moduledoc """
  Canonical uplink PDU payload with routing metadata.
  """

  alias Cadence.CCSDS.Core.PDU
  alias Cadence.CCSDS.SDU.SpacePacket

  @type t :: %__MODULE__{
          target_id: String.t(),
          pdu: PDU.t(),
          pdu_type: PDU.pdu_type(),
          apid: non_neg_integer() | nil
        }

  defstruct [
    :target_id,
    :pdu,
    :pdu_type,
    :apid
  ]

  @spec from_pdu(String.t(), PDU.t()) :: t()
  def from_pdu(target_id, %PDU{} = pdu) when is_binary(target_id) do
    %__MODULE__{
      target_id: target_id,
      pdu: pdu,
      pdu_type: pdu.type,
      apid: apid_from_pdu(pdu)
    }
  end

  defp apid_from_pdu(%PDU{type: :space_packet, value: %SpacePacket{apid: apid}})
       when is_integer(apid) do
    apid
  end

  defp apid_from_pdu(_pdu), do: nil
end
