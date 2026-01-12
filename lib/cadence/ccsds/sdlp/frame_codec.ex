defmodule Cadence.CCSDS.SDLP.FrameCodec do
  @moduledoc """
  Behaviour for SDLP profile frame codecs (TM/AOS/USLP).
  """

  alias Cadence.CCSDS.Core.LinkFrame
  alias Cadence.CCSDS.Core.Types

  @callback profile() :: Types.profile()
  @callback decode(binary(), keyword()) ::
              {:ok, [LinkFrame.t()], rest :: binary()} | {:error, term()}
  @callback encode(LinkFrame.t(), keyword()) :: {:ok, binary()} | {:error, term()}
end
