defmodule Cadence.Runtime.Uplink.DispatcherRoutingAmbiguousTest do
  use Cadence.PureCase, async: true

  alias Cadence.Application.Missions.MissionConfig
  alias Cadence.CCSDS.Core.PDU
  alias Cadence.CCSDS.SDU.SpacePacket
  alias Cadence.Runtime.Uplink.{Dispatcher, UplinkPDU}

  setup_mission_registry()

  test "returns :no_transport when no channels are available" do
    mission_id = "mission-routing-ambiguous"
    target_id = "target-1"

    config = %MissionConfig{
      mission_id: mission_id,
      organization_id: "org-1"
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

    assert {:error, :no_transport} =
             Dispatcher.dispatch_pdu(mission_id, UplinkPDU.from_pdu(target_id, pdu))
  end
end
