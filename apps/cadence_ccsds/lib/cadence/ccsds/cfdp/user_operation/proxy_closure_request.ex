defmodule Cadence.CCSDS.CFDP.UserOperation.ProxyClosureRequest do
  @moduledoc "Typed Proxy Closure Request reserved message."

  @type t :: %__MODULE__{closure_requested?: boolean()}
  defstruct closure_requested?: false
end
