defmodule Cadence.CCSDS.SDLP.TM.Frame do
  @moduledoc """
  TM profile frame struct.
  """

  alias Cadence.CCSDS.Core.LinkFrame

  @type t :: %LinkFrame{profile: :tm}
end
