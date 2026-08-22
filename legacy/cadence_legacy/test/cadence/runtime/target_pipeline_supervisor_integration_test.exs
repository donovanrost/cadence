defmodule Cadence.Runtime.TargetPipelineSupervisorIntegrationTest do
  use Cadence.IntegrationCase

  import Cadence.TargetsFixtures
  import Supertester.Assertions

  alias Cadence.Application.Missions.MissionConfig
  alias Cadence.Application.Targeting.TargetOperations
  alias Cadence.Links
  alias Cadence.Runtime.ChannelId
  alias Cadence.Runtime.Commands.{TargetDispatcher, TargetPipeline, TargetQueue}
  alias Cadence.Runtime.Links.LinkController
  alias Cadence.Runtime.Missions.ConfigManager
  alias Cadence.Runtime.Missions.MissionSupervisor
  alias Cadence.Runtime.Protocol.Supervisor, as: ProtocolSupervisor
  alias Cadence.Runtime.Router
  alias Cadence.Runtime.Transport.COP1.Context, as: COP1Context
  alias Cadence.Runtime.Transport.COP1.FOP, as: COP1FOP
  alias Cadence.Runtime.Transport.COP1.StreamSupervisor, as: COP1StreamSupervisor
  alias Cadence.TestHelpers
  alias Cadence.Transport.TCStreamId
  alias Cadence.Transports
  alias Ecto.Adapters.SQL.Sandbox

  @moduletag :integration

  setup do
    Sandbox.mode(Cadence.Repo, {:shared, self()})

    setup_result = TestHelpers.full_test_setup()
    mission = setup_result.mission
    org = setup_result.org
    targets = setup_result.targets

    {:ok, config} = MissionConfig.load(mission.id)
    {:ok, _pid} = MissionSupervisor.start_mission(config)

    on_exit(fn -> MissionSupervisor.stop_mission(mission.id) end)

    {:ok, mission: mission, org: org, targets: targets}
  end

  test "creates target pipeline processes when config adds a target", %{
    mission: mission,
    org: org
  } do
    target = target_fixture(organization: org, mission: mission)

    {:ok, updated_config} = MissionConfig.load(mission.id)
    :ok = ConfigManager.apply_config(mission.id, updated_config)

    pipeline_pid = wait_for_pid(fn -> TargetPipeline.whereis(mission.id, target.id) end)
    assert_process_alive(pipeline_pid)

    queue_pid = wait_for_pid(fn -> TargetQueue.whereis(mission.id, target.id) end)
    dispatcher_pid = wait_for_pid(fn -> TargetDispatcher.whereis(mission.id, target.id) end)

    assert_process_alive(queue_pid)
    assert_process_alive(dispatcher_pid)
  end

  test "creates link/protocol and COP-1 processes when link config is applied", %{
    mission: mission,
    org: org
  } do
    scid = 42
    vcid = 1
    map_id = 0

    {:ok, interface} =
      Transports.create_interface(org.id, mission.id, %{
        name: "test-interface",
        type: :tcp,
        enabled: false
      })

    {:ok, link} =
      Links.create_link(org.id, mission.id, %{
        scid: scid,
        name: "Test Link"
      })

    {:ok, channel} =
      Links.create_channel(org.id, mission.id, %{
        link_id: link.id,
        scid: scid,
        vcid: vcid,
        map_id: map_id,
        direction: :both,
        enabled: true
      })

    {:ok, binding} =
      Links.create_binding(org.id, mission.id, %{
        channel_id: channel.id,
        transport_id: interface.id,
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

    {:ok, _protocol_config} =
      Links.create_protocol_config(org.id, mission.id, %{
        link_id: link.id,
        config: sdlp_config(scid, vcid)
      })

    {:ok, updated_config} = MissionConfig.load(mission.id)
    :ok = ConfigManager.apply_config(mission.id, updated_config)

    link_pid = wait_for_registry({:link_controller, mission.id, scid})
    assert_process_alive(link_pid)

    _ = wait_for_registry({:link_binding, mission.id, scid, interface.id})

    channel_id = ChannelId.new(scid, vcid, map_id)
    Router.transport_connected(mission.id, interface.id)
    :ok = wait_for(fn -> binding_active?(mission.id, channel_id, interface.id) end)

    Router.ingest(mission.id, interface.id, <<>>, %{
      channel_id: channel_id,
      transport_id: interface.id
    })

    {:ok, channel_pid} =
      wait_for_lookup(fn -> ProtocolSupervisor.lookup_channel(mission.id, channel_id) end)

    assert_process_alive(channel_pid)

    fop_pid = wait_for_registry({:cop1_fop, mission.id, ChannelId.key(channel_id)})
    assert_process_alive(fop_pid)

    :ok = wait_for(fn -> active_uplink_transport?(mission.id, channel_id) end)

    stream_id = TCStreamId.new!(mission.id, interface.id, scid, vcid, map_id: map_id)
    frames = [%{bytes: <<0, 1, 2, 3>>}]
    context = COP1Context.new(stream_id: stream_id, vcid: vcid)
    _ = COP1FOP.send_frames(mission.id, channel_id, frames, context)

    {:ok, stream_pid} =
      wait_for_lookup(fn -> COP1StreamSupervisor.lookup_stream(mission.id, stream_id) end)

    assert_process_alive(stream_pid)
  end

  test "creates target pipeline processes when target change event is broadcast", %{
    mission: mission,
    targets: targets
  } do
    definition_set_id = hd(targets).definition_set_id

    {:ok, target} =
      TargetOperations.create(%{
        mission_id: mission.id,
        definition_set_id: definition_set_id,
        name: "Event Target",
        identifier: unique_target_identifier(),
        type: :spacecraft,
        scid: 42,
        status: :offline
      })

    pipeline_pid = wait_for_pid(fn -> TargetPipeline.whereis(mission.id, target.id) end)
    assert_process_alive(pipeline_pid)

    queue_pid = wait_for_pid(fn -> TargetQueue.whereis(mission.id, target.id) end)
    dispatcher_pid = wait_for_pid(fn -> TargetDispatcher.whereis(mission.id, target.id) end)

    assert_process_alive(queue_pid)
    assert_process_alive(dispatcher_pid)
  end

  defp wait_for_pid(fun, attempts \\ 40)

  defp wait_for_pid(fun, attempts) when attempts > 0 do
    case fun.() do
      pid when is_pid(pid) ->
        pid

      _ ->
        receive do
        after
          50 -> :ok
        end

        wait_for_pid(fun, attempts - 1)
    end
  end

  defp wait_for_pid(_fun, 0) do
    flunk("Timed out waiting for process to start")
  end

  defp wait_for_registry(key, attempts \\ 40)

  defp wait_for_registry(key, attempts) when attempts > 0 do
    case Registry.lookup(Cadence.MissionRegistry, key) do
      [{pid, _}] ->
        pid

      _ ->
        receive do
        after
          50 -> :ok
        end

        wait_for_registry(key, attempts - 1)
    end
  end

  defp wait_for_registry(_key, 0), do: flunk("Timed out waiting for registry entry")

  defp wait_for_lookup(fun, attempts \\ 40)

  defp wait_for_lookup(fun, attempts) when attempts > 0 do
    case fun.() do
      {:ok, pid} when is_pid(pid) ->
        {:ok, pid}

      _ ->
        receive do
        after
          50 -> :ok
        end

        wait_for_lookup(fun, attempts - 1)
    end
  end

  defp wait_for_lookup(_fun, 0), do: flunk("Timed out waiting for lookup")

  defp wait_for(fun, attempts \\ 40)

  defp wait_for(fun, attempts) when attempts > 0 do
    if fun.() do
      :ok
    else
      receive do
      after
        50 -> :ok
      end

      wait_for(fun, attempts - 1)
    end
  end

  defp wait_for(_fun, 0), do: flunk("Timed out waiting for condition")

  defp binding_active?(mission_id, channel_id, transport_id) do
    LinkController.binding_active?(
      mission_id,
      channel_id,
      transport_id,
      :downlink
    )
  end

  defp active_uplink_transport?(mission_id, channel_id) do
    LinkController.active_uplink_transport(mission_id, channel_id)
    |> is_binary()
  end

  defp sdlp_config(scid, vcid) do
    %{
      "framing" => "sdlp",
      "cop1" => %{"mode" => "fop"},
      "sdlp" => %{
        "profile" => "tm",
        "frame_size" => 32,
        "uplink_frame_size" => 32,
        "uplink_scid" => scid,
        "uplink_vcid" => vcid,
        "sdu_mapping" => [
          %{
            "scid" => scid,
            "vcid" => vcid,
            "map_id" => 0,
            "direction" => "downlink",
            "type" => "space_packet"
          }
        ]
      }
    }
  end
end
