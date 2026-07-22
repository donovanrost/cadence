defmodule Cadence.CCSDS.CFDP.UserOperation.ProxyMessageToUser do
  @moduledoc "Typed Proxy Message-to-User reserved message."

  @type t :: %__MODULE__{message: binary()}
  defstruct message: <<>>
end
