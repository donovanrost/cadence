defmodule Cadence.Runtime.Transport.COP1.FOPLoopbackIntegrationTest do
  use Cadence.IntegrationCase

  @moduletag :skip

  alias Cadence.Application.Missions.MissionConfig
  alias Cadence.CCSDS.Core.PDU
  alias Cadence.CCSDS.SDU.SpacePacket
  alias Cadence.Links
  alias Cadence.Runtime.ChannelId
  alias Cadence.Runtime.Interfaces.TcpServerInterface
  alias Cadence.Runtime.Missions.MissionSupervisor
  alias Cadence.Runtime.Transport.COP1.Application, as: COP1Application
  alias Cadence.Runtime.Transport.COP1.Stream
  alias Cadence.Runtime.Uplink.{Dispatcher, FramingContext, UplinkPDU}
  alias Cadence.Simulator.Coordinator
  alias Cadence.TestHelpers
  alias Cadence.Transport.TCStreamId
  alias Cadence.Transports
  alias Ecto.Adapters.SQL.Sandbox

  @tm_frame_size 256
  @tc_frame_size 32
  @scid 42
  @vcid 0

  setup do
    Sandbox.mode(Cadence.Repo, {:shared, self()})

    setup_result = TestHelpers.full_test_setup()
    mission = setup_result.mission
    org = setup_result.org
    target = hd(setup_result.targets)
    port = find_open_port()

    {:ok, transport} =
      Transports.create_interface(org.id, mission.id, %{
        name: "COP1_LOOPBACK",
        type: :tcp,
        endpoint: %{
          mode: "server",
          host: "127.0.0.1",
          port: port
        }
      })

    {:ok, link} =
      Links.create_link(org.id, mission.id, %{
        scid: @scid,
        name: "COP1 Link"
      })

    {:ok, channel} =
      Links.create_channel(org.id, mission.id, %{
        link_id: link.id,
        scid: @scid,
        vcid: @vcid,
        direction: :both,
        enabled: true
      })

    {:ok, binding} =
      Links.create_binding(org.id, mission.id, %{
        channel_id: channel.id,
        transport_id: transport.id,
        direction: :both,
        role: :primary,
        priority: 100,
        desired_state: :active
      })

    {:ok, _selection} =
      Links.create_active_selection(org.id, mission.id, %{
        channel_id: channel.id,
        binding_id: binding.id,
        direction: :uplink
      })

    {:ok, _channel_target} =
      Links.create_channel_target(org.id, mission.id, %{
        target_id: target.id,
        scid: @scid,
        vcid: @vcid,
        map_id: nil
      })

    {:ok, _protocol_config} =
      Links.create_protocol_config(org.id, mission.id, %{
        link_id: link.id,
        config: %{
          framing: "sdlp",
          sdlp: %{
            profile: "tm",
            frame_size: @tm_frame_size,
            ocf_length: 4,
            default_sdu_type: "space_packet",
            sdu_mapping: [
              %{
                scid: @scid,
                vcid: @vcid,
                direction: "downlink",
                type: "space_packet"
              }
            ],
            uplink_profile: "tc",
            uplink_frame_size: @tc_frame_size,
            uplink_scid: @scid,
            uplink_vcid: @vcid
          },
          cop1: %{
            mode: "fop",
            window_size: 4,
            timeout_ms: 1000,
            max_retransmit: 3
          }
        }
      })

    {:ok, config} = MissionConfig.load(mission.id)

    {:ok, _pid} = MissionSupervisor.start_mission(config)

    on_exit(fn ->
      MissionSupervisor.stop_mission(mission.id)
    end)

    {:ok, mission: mission, target: target, transport: transport, port: port}
  end

  test "acknowledges uplink via CLCW loopback", %{
    mission: mission,
    target: target,
    transport: transport,
    port: port
  } do
    transport_id = transport.id
    server_pid = wait_for_transport_pid(mission.id, transport_id)
    :ok = wait_for(fn -> TcpServerInterface.stats(server_pid).listening end)

    {:ok, sim_pid} =
      Coordinator.start_link(
        mission_id: mission.id,
        target_id: target.identifier,
        rate_hz: 1.0,
        output: {:tcp, "127.0.0.1", port},
        mode: :connect,
        definitions_path: "priv/databases/example_telemetry.yaml",
        frame: %{format: :tm, scid: @scid, vcid: @vcid, frame_size: @tm_frame_size},
        uplink_frame: %{format: :tc, frame_size: @tc_frame_size},
        clcw_enabled: true
      )

    on_exit(fn ->
      if Process.alive?(sim_pid), do: Coordinator.stop(sim_pid)
    end)

    :ok =
      wait_for(fn ->
        stats = TcpServerInterface.stats(server_pid)
        stats.connected_clients == 1
      end)

    channel_id = ChannelId.new(@scid, @vcid)
    _fop_pid = wait_for_fop_pid(mission.id, channel_id)
    {:ok, initial_stats} = COP1Application.stats(mission.id, channel_id)
    assert initial_stats.in_flight_count == 0

    pdu = build_space_packet_pdu()

    uplink_pdu = UplinkPDU.from_pdu(target.id, pdu)

    framing_context = FramingContext.new(%{scid: @scid})

    decision =
      case Dispatcher.dispatch_pdu(mission.id, uplink_pdu, framing_context: framing_context) do
        {:ok, decision} ->
          decision

        {:defer, :hold_pending_resync} ->
          tc_stream_id = TCStreamId.new!(mission.id, transport_id, @scid, @vcid)
          :ok = Stream.resync(tc_stream_id)

          {:ok, decision} =
            Dispatcher.dispatch_pdu(mission.id, uplink_pdu, framing_context: framing_context)

          decision
      end

    assert decision.transport_id == transport_id

    {:ok, stats} = COP1Application.stats(mission.id, channel_id)
    assert stats.in_flight_count > 0

    :ok =
      wait_for(fn ->
        {:ok, stats} = COP1Application.stats(mission.id, channel_id)
        stats.in_flight_count == 0 and not is_nil(stats.last_report_value)
      end)
  end

  defp build_space_packet_pdu do
    %PDU{
      type: :space_packet,
      value: %SpacePacket{
        apid: 1,
        secondary_header_flag: 1,
        user_data: <<1, 2, 3, 4>>
      }
    }
  end

  defp wait_for_transport_pid(mission_id, transport_id) do
    :ok =
      wait_for(fn ->
        Registry.lookup(Cadence.MissionRegistry, {:transport, mission_id, transport_id}) != []
      end)

    [{pid, _}] =
      Registry.lookup(Cadence.MissionRegistry, {:transport, mission_id, transport_id})

    pid
  end

  defp wait_for_fop_pid(mission_id, %ChannelId{} = channel_id) do
    :ok =
      wait_for(fn ->
        Registry.lookup(
          Cadence.MissionRegistry,
          {:cop1_fop, mission_id, ChannelId.key(channel_id)}
        ) != []
      end)

    [{pid, _}] =
      Registry.lookup(Cadence.MissionRegistry, {:cop1_fop, mission_id, ChannelId.key(channel_id)})

    pid
  end

  defp wait_for(fun, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, 5_000)
    interval = Keyword.get(opts, :interval, 25)
    deadline = System.monotonic_time(:millisecond) + timeout

    case do_wait_for(fun, deadline, interval) do
      :ok -> :ok
      :timeout -> flunk("Condition was not met within timeout")
    end
  end

  defp do_wait_for(fun, deadline, interval) do
    if fun.() do
      :ok
    else
      if System.monotonic_time(:millisecond) < deadline do
        Process.sleep(interval)
        do_wait_for(fun, deadline, interval)
      else
        :timeout
      end
    end
  end

  defp find_open_port do
    {:ok, socket} = :gen_tcp.listen(0, [:binary, active: false])
    {:ok, port} = :inet.port(socket)
    :gen_tcp.close(socket)
    port
  end
end
