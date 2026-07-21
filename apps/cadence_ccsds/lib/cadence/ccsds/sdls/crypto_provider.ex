defmodule Cadence.CCSDS.SDLS.CryptoProvider do
  @moduledoc """
  Cryptographic callback boundary for SDLS.

  Implementations resolve the opaque algorithm and key references carried by
  the Security Association. This library owns framing and protocol state; the
  callback owns cryptographic operations and key custody.
  """

  alias Cadence.CCSDS.SDLS.Operation

  @callback padding_length(binary(), Operation.t(), term()) ::
              {:ok, non_neg_integer(), term()} | {:error, term()}

  @callback encrypt(binary(), Operation.t(), term()) ::
              {:ok, binary(), binary(), term()} | {:error, term()}

  @callback decrypt(binary(), Operation.t(), term()) ::
              {:ok, binary(), binary(), term()} | {:error, term()}

  @callback authenticate(binary(), Operation.t(), term()) ::
              {:ok, binary(), term()} | {:error, term()}
end
