defmodule Cadence.CCSDS.SDLP.TM.OnlyIdleData do
  @moduledoc """
  TM namespace for the shared CCSDS Only Idle Data sequence.
  """

  alias Cadence.CCSDS.SDLP.OnlyIdleData

  defdelegate initial_state(), to: OnlyIdleData
  defdelegate take(length), to: OnlyIdleData
  defdelegate take(length, state), to: OnlyIdleData
  defdelegate validate(data), to: OnlyIdleData
  defdelegate validate(data, state), to: OnlyIdleData
  defdelegate validate_prefix(data, prefix_octets), to: OnlyIdleData
  defdelegate validate_prefix(data, prefix_octets, state), to: OnlyIdleData
end
