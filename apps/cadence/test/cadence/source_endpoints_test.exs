defmodule Cadence.SourceEndpointsTest do
  use Cadence.DataCase, async: true

  alias Cadence.ApplicationDispatch.{BindingRule, BindingSet}
  alias Cadence.Ingress.RawEvidence
  alias Cadence.SourceEndpoints.SourceEndpoint
  alias Cadence.Spacecraft
  alias Cadence.Telemetry.PacketDefinition

  @organization_id "org-alpha"
  @mission_id "mission-alpha"

  test "resolves ingress evidence to a mission-owned source endpoint by source_ref" do
    persist_mission_scope(@organization_id, @mission_id)

    spacecraft =
      Spacecraft.new(%{
        spacecraft_id: "sc-001",
        organization_id: @organization_id,
        mission_id: @mission_id,
        display_name: "SC-001"
      })

    assert {:ok, _persisted_spacecraft} = Cadence.persist_spacecraft(@organization_id, spacecraft)

    source_endpoint =
      SourceEndpoint.new(%{
        source_endpoint_id: "endpoint-sc-001",
        organization_id: @organization_id,
        mission_id: @mission_id,
        spacecraft_id: "sc-001",
        source_ref: "provider/path-a",
        display_name: "SC-001 Downlink"
      })

    assert {:ok, persisted_source_endpoint} =
             Cadence.persist_source_endpoint(@organization_id, source_endpoint)

    raw_evidence =
      RawEvidence.new(%{
        mission_id: @mission_id,
        source_ref: "provider/path-a",
        raw: build_space_packet(42, 7, <<0, 10>>)
      })

    assert {:ok, result} =
             Cadence.process_telemetry_ingress(
               raw_evidence,
               telemetry_binding_set(@organization_id, @mission_id)
             )

    assert result.raw_evidence.source_endpoint_ref == persisted_source_endpoint.source_endpoint_id
    assert result.raw_evidence.spacecraft_id == "sc-001"

    [packet_record] = result.packet_records

    assert packet_record.source_endpoint_ref ==
             persisted_source_endpoint.source_endpoint_id

    assert packet_record.spacecraft_id == "sc-001"
  end

  test "lists source endpoints filtered by spacecraft scope" do
    persist_mission_scope(@organization_id, @mission_id)

    spacecraft_alpha =
      Spacecraft.new(%{
        spacecraft_id: "sc-001",
        organization_id: @organization_id,
        mission_id: @mission_id,
        display_name: "SC-001"
      })

    spacecraft_beta =
      Spacecraft.new(%{
        spacecraft_id: "sc-002",
        organization_id: @organization_id,
        mission_id: @mission_id,
        display_name: "SC-002"
      })

    assert {:ok, _persisted_spacecraft} =
             Cadence.persist_spacecraft(@organization_id, spacecraft_alpha)

    assert {:ok, _persisted_spacecraft} =
             Cadence.persist_spacecraft(@organization_id, spacecraft_beta)

    assert {:ok, _endpoint_alpha} =
             Cadence.persist_source_endpoint(
               @organization_id,
               SourceEndpoint.new(%{
                 source_endpoint_id: "endpoint-sc-001-primary",
                 organization_id: @organization_id,
                 mission_id: @mission_id,
                 spacecraft_id: "sc-001",
                 source_ref: "provider/path-a"
               })
             )

    assert {:ok, _endpoint_beta} =
             Cadence.persist_source_endpoint(
               @organization_id,
               SourceEndpoint.new(%{
                 source_endpoint_id: "endpoint-sc-002-primary",
                 organization_id: @organization_id,
                 mission_id: @mission_id,
                 spacecraft_id: "sc-002",
                 source_ref: "provider/path-b"
               })
             )

    filtered_source_endpoints =
      Cadence.list_source_endpoints(@organization_id, @mission_id, spacecraft_id: "sc-001")

    assert Enum.map(filtered_source_endpoints, & &1.source_endpoint_id) == [
             "endpoint-sc-001-primary"
           ]

    assert Enum.map(filtered_source_endpoints, & &1.spacecraft_id) == ["sc-001"]
  end

  defp telemetry_binding_set(organization_id, mission_id) do
    packet_definition =
      PacketDefinition.new(%{
        organization_id: organization_id,
        mission_id: mission_id,
        packet_definition_id: "hk",
        packet_name: "HK",
        apid: 42,
        version: 1,
        fields: [
          %{field_id: "counter", name: "counter", offset_bits: 0, size_bits: 16, data_type: :uint}
        ]
      })

    BindingSet.new(%{
      organization_id: organization_id,
      mission_id: mission_id,
      binding_set_id: "source-endpoint-test",
      version: 1,
      rules: [
        BindingRule.new(%{
          binding_rule_id: "hk-rule",
          handler_key: :definition_bound_telemetry,
          packet_kind: :space_packet,
          apid: 42,
          handler_configuration: packet_definition
        })
      ]
    })
  end

  defp build_space_packet(apid, sequence_count, packet_data) do
    packet_length = byte_size(packet_data) - 1

    <<
      0::3,
      0::1,
      0::1,
      apid::11,
      3::2,
      sequence_count::14,
      packet_length::16,
      packet_data::binary
    >>
  end
end
