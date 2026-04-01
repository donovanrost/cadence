defmodule Cadence.Telemetry.ParsedUnit do
  @moduledoc false

  @type t ::
          {:space_packet, Cadence.Telemetry.SpacePacket.t()}
          | {:encap_packet, Cadence.Telemetry.EncapPacket.t()}
          | {:unknown, Cadence.Telemetry.UnknownUnit.t()}

  @type parse_error :: {:malformed, reason :: term(), context :: map()}
end
