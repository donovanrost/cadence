defmodule CCSDS do
  @moduledoc """
  Dependency-free protocol building blocks for Consultative Committee for
  Space Data Systems (CCSDS) standards.

  The library provides immutable protocol values, strict wire codecs,
  segmentation and reassembly helpers, and pure protocol state machines. It
  deliberately does not own persistence, networking, authorization, mission
  configuration, scheduling, or process supervision.

  Start with `CCSDS.SpacePacket`, `CCSDS.EncapsulationPacket`, `CCSDS.CFDP`,
  or the transfer-frame modules under `CCSDS.SDLP` and `CCSDS.TC`.

  The implemented surface is a tested subset of the cited standards. It is not
  a complete CCSDS protocol stack and is not flight-qualified software.
  """
end
