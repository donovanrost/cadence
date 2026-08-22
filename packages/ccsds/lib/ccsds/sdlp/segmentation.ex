defmodule CCSDS.SDLP.Segmentation do
  @moduledoc """
  Behaviour for SDLP profile segmentation services.
  """

  alias CCSDS.Core.{LinkFrame, SDUOctets}

  @callback init(keyword()) :: {:ok, term()}
  @callback segment(SDUOctets.t(), map(), term()) ::
              {:ok, [LinkFrame.t()], term()} | {:error, term(), term()}
end
