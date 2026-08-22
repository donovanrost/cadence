defmodule CCSDS.SDLP.TM.Service.ProviderTest do
  use ExUnit.Case, async: true

  alias CCSDS.SDLP.TM.{Configuration, FrameCodec}
  alias CCSDS.SDLP.TM.Service.{Provider, Request}

  test "round-trips a Virtual Channel Packet service request" do
    configuration = packet_configuration()
    {:ok, sender} = Provider.init([configuration])
    {:ok, receiver} = Provider.init([configuration])
    packet = space_packet(9, <<1, 2, 3, 4>>)

    request = %Request{
      service: :virtual_channel_packet,
      data: packet,
      scid: 12,
      vcid: 3,
      packet_version_number: 0,
      timestamp: ~U[2026-07-20 12:00:00Z]
    }

    assert {:ok, [frame], _sender} = Provider.request(request, sender)
    assert {:ok, encoded} = FrameCodec.encode(frame, configuration: configuration)
    assert {:ok, [decoded], <<>>} = FrameCodec.decode(encoded, configuration: configuration)
    assert {:ok, [indication], [], _receiver} = Provider.ingest_detailed(decoded, receiver)

    assert indication.service == :virtual_channel_packet
    assert indication.data == packet
    assert indication.packet_version_number == 0
    assert indication.source_frames == [0]
  end

  test "VCA service preserves status fields and derives loss from a skipped frame" do
    configuration = vca_configuration()
    {:ok, sender} = Provider.init([configuration])
    {:ok, receiver} = Provider.init([configuration])

    assert {:ok, [first], sender} = Provider.request(vca_request(<<0::80>>, 0x0012), sender)
    assert {:ok, [_dropped], sender} = Provider.request(vca_request(<<1::80>>, 0x1234), sender)
    assert {:ok, [third], _sender} = Provider.request(vca_request(<<2::80>>, 0x2ABC), sender)

    assert {:ok, [first_indication], [], receiver} =
             Provider.ingest_detailed(first, receiver)

    refute first_indication.vca_sdu_loss_flag
    assert first_indication.vca_status_fields == 0x0012

    assert {:ok, [third_indication], anomalies, _receiver} =
             Provider.ingest_detailed(third, receiver)

    assert third_indication.service == :virtual_channel_access
    assert third_indication.data == <<2::80>>
    assert third_indication.vca_status_fields == 0x2ABC
    assert third_indication.vca_sdu_loss_flag
    assert Enum.any?(anomalies, &(&1.anomaly_kind == :virtual_channel_frame_count_discontinuity))
  end

  test "generates an OID frame only on Packet Virtual Channels" do
    packet_configuration = packet_configuration()
    {:ok, packet_provider} = Provider.init([packet_configuration])

    assert {:ok, oid, _provider} = Provider.only_idle(12, 3, packet_provider)
    assert oid.meta.fhp == 2046
    assert oid.meta.tm_service == :virtual_channel_packet

    vca_configuration = vca_configuration()
    {:ok, vca_provider} = Provider.init([vca_configuration])

    assert {:error, {:oid_forbidden, :vca_sdu}, _provider} =
             Provider.only_idle(12, 3, vca_provider)
  end

  defp packet_configuration do
    {:ok, configuration} =
      Configuration.new(
        frame_size: 24,
        scid: 12,
        vcid: 3,
        maximum_packet_octets: 128
      )

    configuration
  end

  defp vca_configuration do
    {:ok, configuration} =
      Configuration.new(
        frame_size: 16,
        scid: 12,
        vcid: 3,
        data_field_content: :vca_sdu,
        valid_packet_version_numbers: [],
        maximum_packet_octets: nil
      )

    configuration
  end

  defp vca_request(data, status_fields) do
    %Request{
      service: :virtual_channel_access,
      data: data,
      scid: 12,
      vcid: 3,
      packet_version_number: nil,
      vca_status_fields: status_fields
    }
  end

  defp space_packet(sequence_count, data) do
    <<0::3, 0::1, 0::1, 42::11, 3::2, sequence_count::14, byte_size(data) - 1::16, data::binary>>
  end
end
