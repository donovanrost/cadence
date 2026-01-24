defmodule Cadence.Runtime.Uplink.DispatcherRoutingAmbiguousTest do
  use Cadence.PureCase, async: true

  alias Cadence.Application.Missions.MissionConfig
  alias Cadence.CCSDS.Core.PDU
  alias Cadence.CCSDS.SDU.SpacePacket
  alias Cadence.Domain.Interfaces.Entities.Interface
  alias Cadence.Domain.Interfaces.Entities.TargetInterface
  alias Cadence.Runtime.Uplink.{Dispatcher, UplinkPDU}

  setup_mission_registry()

  test "returns :no_interface when no active bindings are available" do
    mission_id = "mission-routing-ambiguous"
    target_id = "target-1"

    interface_a = build_interface("interface-a", mission_id)
    interface_b = build_interface("interface-b", mission_id)

    {:ok, route_a} =
      TargetInterface.new(%{
        target_id: target_id,
        interface_id: interface_a.id,
        direction: :write
      })

    {:ok, route_b} =
      TargetInterface.new(%{
        target_id: target_id,
        interface_id: interface_b.id,
        direction: :write
      })

    config = %MissionConfig{
      mission_id: mission_id,
      organization_id: "org-1",
      interfaces: [interface_a, interface_b],
      target_interface_routings: [route_a, route_b],
      interface_vcids: []
    }

    {:ok, _pid} = start_supervised({Dispatcher, config: config})

    pdu = %PDU{
      type: :space_packet,
      value: %SpacePacket{
        apid: 1,
        sequence_flags: 3,
        sequence_count: 0,
        secondary_header_flag: 1,
        user_data: <<1, 2, 3>>
      },
      quality: :good,
      timestamp: nil,
      meta: %{}
    }

    assert {:error, :no_interface} =
             Dispatcher.dispatch_pdu(mission_id, UplinkPDU.from_pdu(target_id, pdu))
  end

  defp build_interface(id, mission_id) do
    Interface.from_persistence(%{
      id: id,
      mission_id: mission_id,
      name: "IFACE-#{id}",
      connection_type: "tcp_client",
      config: %{}
    })
  end
end
