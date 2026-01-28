defmodule Cadence.Telemetry.PacketEnvelopeTest do
  use ExUnit.Case, async: true

  alias Cadence.Telemetry.{Evidence, PacketEnvelope}

  test "evidence list is monotonic" do
    envelope = PacketEnvelope.new("mission-1", <<1, 2, 3>>, config_version_seen: 1)

    envelope = PacketEnvelope.add_evidence(envelope, Evidence.scid(42, :frame, :high))

    envelope =
      PacketEnvelope.add_evidence(envelope, Evidence.apid(100, :space_packet_header, :high))

    assert length(envelope.evidence) == 2
    assert Enum.at(envelope.evidence, 0).kind == :scid
    assert Enum.at(envelope.evidence, 1).kind == :apid
  end
end
