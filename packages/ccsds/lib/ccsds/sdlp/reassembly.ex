defmodule CCSDS.SDLP.Reassembly do
  @moduledoc """
  Behaviour for SDLP profile reassembly services.
  """

  alias CCSDS.Core.{LinkFrame, SDUOctets}

  @callback init(keyword()) :: {:ok, term()}
  @callback ingest(LinkFrame.t(), map(), term()) ::
              {:ok, [SDUOctets.t()], term()} | {:error, term(), term()}
end
