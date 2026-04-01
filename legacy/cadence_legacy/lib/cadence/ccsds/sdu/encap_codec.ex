defmodule Cadence.CCSDS.SDU.EncapCodec do
  @moduledoc """
  Encapsulation packet SDU codec (stub).
  """

  @behaviour Cadence.CCSDS.SDU.CodecBehaviour

  alias Cadence.CCSDS.Core.{PDU, SDUOctets}

  @impl true
  def id, do: :encap

  @impl true
  def decode(%SDUOctets{}, _opts), do: {:error, :not_implemented}

  @impl true
  def encode(%PDU{type: :encap}, _opts), do: {:error, :not_implemented}
  def encode(_pdu, _opts), do: {:error, :invalid_pdu}
end
