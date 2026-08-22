defmodule CCSDS.CFDP.UserOperation.ProxyFilestoreRequest do
  @moduledoc "Typed Proxy Filestore Request reserved message."

  alias CCSDS.CFDP.TLV.FilestoreRequest

  @type t :: %__MODULE__{request: FilestoreRequest.t()}
  @enforce_keys [:request]
  defstruct [:request]
end
