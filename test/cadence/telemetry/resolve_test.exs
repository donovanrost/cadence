defmodule Cadence.Telemetry.ResolveTest do
  use ExUnit.Case, async: true

  alias Cadence.Runtime.Telemetry.ConfigBundle
  alias Cadence.Telemetry.{Evidence, PacketEnvelope, Resolve, ResolvedUnit, SpacePacket}

  defp bundle_with_target(opts) do
    target = %{
      id: Keyword.get(opts, :target_id, "target-1"),
      scid: Keyword.get(opts, :scid, 42),
      definition_set_id: Keyword.get(opts, :definition_set_id)
    }

    %ConfigBundle{
      mission_id: "mission-1",
      config_version: 3,
      targets: [target],
      targets_by_identifier: %{target.id => target},
      target_ids_by_identifier: %{},
      packet_catalog: Keyword.get(opts, :packet_catalog, %{})
    }
  end

  defp space_packet(apid) do
    %SpacePacket{
      primary: %{
        version: 0,
        type: 0,
        sec_hdr_flag: 1,
        apid: apid,
        seq_flags: 3,
        seq_count: 1,
        length: 0
      },
      sec_header: nil,
      user_data: <<0xAA>>,
      raw_ref: nil
    }
  end

  test "resolve identity via scid mapping" do
    envelope =
      PacketEnvelope.new("mission-1", <<1>>, config_version_seen: 3)
      |> PacketEnvelope.add_evidence(Evidence.scid(42, :frame, :high))

    bundle = bundle_with_target(definition_set_id: "def-set-1")
    parsed_unit = {:space_packet, space_packet(100)}

    %ResolvedUnit{identity: identity} = Resolve.resolve(envelope, parsed_unit, bundle)
    assert {:ok, "target-1"} = identity
  end

  test "resolve identity missing mapping" do
    envelope =
      PacketEnvelope.new("mission-1", <<1>>, config_version_seen: 3)
      |> PacketEnvelope.add_evidence(Evidence.scid(99, :frame, :high))

    bundle = bundle_with_target(definition_set_id: "def-set-1")
    parsed_unit = {:space_packet, space_packet(100)}

    %ResolvedUnit{identity: identity} = Resolve.resolve(envelope, parsed_unit, bundle)
    assert {:unresolved, :no_scid_mapping, _hint} = identity
  end

  test "resolve schema ok and unknown apid" do
    packet_def = %{name: "PKT"}

    packet_catalog = %{by_apid: %{{"def-set-1", 100} => packet_def}}

    envelope =
      PacketEnvelope.new("mission-1", <<1>>, config_version_seen: 3)
      |> PacketEnvelope.add_evidence(Evidence.scid(42, :frame, :high))

    bundle = bundle_with_target(definition_set_id: "def-set-1", packet_catalog: packet_catalog)

    parsed_unit = {:space_packet, space_packet(100)}
    %ResolvedUnit{schema: schema} = Resolve.resolve(envelope, parsed_unit, bundle)
    assert {:ok, ^packet_def} = schema

    parsed_unit = {:space_packet, space_packet(101)}
    %ResolvedUnit{schema: schema} = Resolve.resolve(envelope, parsed_unit, bundle)
    assert {:unknown_apid, "target-1", "def-set-1", 101} = schema
  end

  test "resolve schema uncataloged target" do
    envelope =
      PacketEnvelope.new("mission-1", <<1>>, config_version_seen: 3)
      |> PacketEnvelope.add_evidence(Evidence.scid(42, :frame, :high))

    bundle = bundle_with_target(definition_set_id: nil)
    parsed_unit = {:space_packet, space_packet(100)}

    %ResolvedUnit{schema: schema} = Resolve.resolve(envelope, parsed_unit, bundle)
    assert {:uncataloged_target, "target-1"} = schema
  end
end
