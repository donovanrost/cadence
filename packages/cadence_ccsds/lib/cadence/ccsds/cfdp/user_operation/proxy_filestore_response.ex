defmodule Cadence.CCSDS.CFDP.UserOperation.ProxyFilestoreResponse do
  @moduledoc "Typed Proxy Filestore Response reserved message."

  alias Cadence.CCSDS.CFDP.TLV.FilestoreResponse

  @type t :: %__MODULE__{response: FilestoreResponse.t()}
  @enforce_keys [:response]
  defstruct [:response]
end
