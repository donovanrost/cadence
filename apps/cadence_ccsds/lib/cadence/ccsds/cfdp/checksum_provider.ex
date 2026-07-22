defmodule Cadence.CCSDS.CFDP.ChecksumProvider do
  @moduledoc """
  Extension boundary for optional CFDP file checksum algorithms.

  CCSDS 727.0-B-5 assigns checksum type zero to the modular checksum and type
  fifteen to the null checksum. A caller can provide the remaining mission
  algorithms without coupling the protocol library to cryptographic packages.
  """

  @callback compute(checksum_type :: 1..14, file :: binary()) ::
              {:ok, 0..0xFFFFFFFF} | {:error, term()}
end
