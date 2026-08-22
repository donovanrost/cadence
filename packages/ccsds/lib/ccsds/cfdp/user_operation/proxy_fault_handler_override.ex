defmodule CCSDS.CFDP.UserOperation.ProxyFaultHandlerOverride do
  @moduledoc "Typed Proxy Fault Handler Override reserved message."

  alias CCSDS.CFDP.TLV.FaultHandlerOverride

  @type t :: %__MODULE__{override: FaultHandlerOverride.t()}
  @enforce_keys [:override]
  defstruct [:override]
end
