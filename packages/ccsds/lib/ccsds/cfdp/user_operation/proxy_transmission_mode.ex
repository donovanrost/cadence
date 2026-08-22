defmodule CCSDS.CFDP.UserOperation.ProxyTransmissionMode do
  @moduledoc "Typed Proxy Transmission Mode reserved message."

  @type t :: %__MODULE__{transmission_mode: :acknowledged | :unacknowledged}
  @enforce_keys [:transmission_mode]
  defstruct [:transmission_mode]
end
