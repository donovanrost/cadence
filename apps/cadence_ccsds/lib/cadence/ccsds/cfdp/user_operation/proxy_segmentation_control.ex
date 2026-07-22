defmodule Cadence.CCSDS.CFDP.UserOperation.ProxySegmentationControl do
  @moduledoc "Typed Proxy Segmentation Control reserved message."

  @type t :: %__MODULE__{record_boundaries_preserved?: boolean()}
  defstruct record_boundaries_preserved?: true
end
