defmodule Cadence.CCSDS.CFDP.UserOperation.ProxyFlowLabel do
  @moduledoc "Typed Proxy Flow Label reserved message."

  @type t :: %__MODULE__{value: binary()}
  defstruct value: <<>>
end
