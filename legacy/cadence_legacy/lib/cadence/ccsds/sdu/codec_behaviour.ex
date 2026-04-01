defmodule Cadence.CCSDS.SDU.CodecBehaviour do
  @moduledoc """
  Behaviour for SDU codecs (Space Packet, Encap, Custom).
  """

  alias Cadence.CCSDS.Core.{PDU, SDUOctets}

  @callback id() :: term()
  @callback decode(SDUOctets.t(), keyword()) :: {:ok, PDU.t()} | {:error, term()}
  @callback encode(PDU.t(), keyword()) :: {:ok, SDUOctets.t()} | {:error, term()}
end
