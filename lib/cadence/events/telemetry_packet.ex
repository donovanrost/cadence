defmodule Cadence.Events.TelemetryPacket do
  @moduledoc """
  Event for a fully decoded telemetry packet.
  """

  alias Cadence.Telemetry.Packet

  @type t :: %__MODULE__{
          packet: Packet.t(),
          metadata: map()
        }

  defstruct [:packet, :metadata]
end
