defmodule Cadence.Ops.PointCatalogTest do
  use Cadence.DataCase, async: false

  @moduletag :runtime

  alias Cadence.ApplicationDispatch.{BindingRule, BindingSet}
  alias Cadence.Telemetry.PacketDefinition

  setup do
    organization_id = "org-point-catalog"
    mission_id = "mission-point-catalog"

    persist_mission_scope(organization_id, mission_id)

    %{organization_id: organization_id, mission_id: mission_id}
  end

  test "returns no points without an active binding set", %{
    organization_id: organization_id,
    mission_id: mission_id
  } do
    assert [] = Cadence.list_ops_telemetry_points(organization_id, mission_id)
  end

  test "lists points from the active Mission Model binding set", %{
    organization_id: organization_id,
    mission_id: mission_id
  } do
    activate_binding_set_fixture(organization_id, mission_id)

    assert [bus_voltage, counter] =
             Cadence.list_ops_telemetry_points(organization_id, mission_id)

    assert %{
             point_id: "HK.bus_voltage",
             packet_name: "HK",
             field_name: "bus_voltage",
             unit: "V",
             stale_timeout_ms: nil,
             description: nil
           } = bus_voltage

    assert %{
             point_id: "HK.counter",
             packet_name: "HK",
             field_name: "counter",
             stale_timeout_ms: nil,
             description: nil
           } = counter
  end

  defp activate_binding_set_fixture(organization_id, mission_id) do
    packet_definition =
      PacketDefinition.new(%{
        mission_id: mission_id,
        packet_definition_id: "hk-packet",
        packet_name: "HK",
        apid: 42,
        fields: [
          %{
            field_id: "field-counter",
            name: "counter",
            offset_bits: 0,
            size_bits: 16,
            data_type: :uint
          },
          %{
            name: "bus_voltage",
            offset_bits: 16,
            size_bits: 16,
            data_type: :uint,
            engineering_unit: "V"
          }
        ]
      })

    binding_set =
      BindingSet.new(%{
        mission_id: mission_id,
        binding_set_id: mission_id <> "-binding-set",
        version: 1,
        rules: [
          BindingRule.new(%{
            handler_key: :definition_bound_telemetry,
            packet_kind: :space_packet,
            apid: 42,
            handler_configuration: packet_definition
          })
        ]
      })

    {:ok, persisted} = Cadence.Governance.persist_binding_set(organization_id, binding_set)

    {:ok, _activation} =
      Cadence.ActivationFixtures.activate_binding_set(
        organization_id,
        mission_id,
        persisted.binding_set_id,
        persisted.version,
        []
      )

    persisted
  end
end
