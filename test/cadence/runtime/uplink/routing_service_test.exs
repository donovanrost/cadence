defmodule Cadence.Runtime.Uplink.RoutingServiceTest do
  use Cadence.PureCase, async: true

  alias Cadence.Application.Missions.MissionConfig
  alias Cadence.Domain.Interfaces.Entities.Interface
  alias Cadence.Domain.Interfaces.Entities.TargetInterface
  alias Cadence.Interfaces.InterfaceVcid
  alias Cadence.Runtime.Uplink.RoutingService

  test "resolves target-specific vcid and cop1 mode" do
    target_id = "target-1"
    interface = build_interface("interface-1", cop1_mode: "fop")

    {:ok, routing} =
      TargetInterface.new(%{
        target_id: target_id,
        interface_id: interface.id,
        direction: :write,
        scid: 12
      })

    vcid_mapping = %InterfaceVcid{
      interface_id: interface.id,
      target_id: target_id,
      vcid: 3
    }

    resolver = build_resolver([interface], [routing], [vcid_mapping])

    assert {:ok, decision} =
             RoutingService.route(resolver, target_id, :space_packet, 10, [])

    assert decision.target_id == target_id
    assert decision.pdu_type == :space_packet
    assert decision.apid == 10
    assert decision.interface_id == interface.id
    assert decision.scid == 12
    assert decision.vcid == 3
    assert decision.cop1_mode == :fop
  end

  test "uses tc stream id from routing" do
    target_id = "target-1"
    interface = build_interface("interface-1")

    {:ok, routing} =
      TargetInterface.new(%{
        target_id: target_id,
        interface_id: interface.id,
        direction: :write,
        tc_stream_id: "stream-1"
      })

    resolver = build_resolver([interface], [routing], [])

    assert {:ok, decision} =
             RoutingService.route(resolver, target_id, :space_packet, 10, [])

    assert decision.tc_stream_id == "stream-1"
  end

  test "disables cop1 when apid is not allowlisted" do
    target_id = "target-1"

    interface =
      build_interface("interface-1",
        cop1_mode: "fop",
        cop1_apids: [10, 11]
      )

    {:ok, routing} =
      TargetInterface.new(%{
        target_id: target_id,
        interface_id: interface.id,
        direction: :write
      })

    resolver = build_resolver([interface], [routing], [])

    assert {:ok, decision} =
             RoutingService.route(resolver, target_id, :space_packet, 12, [])

    assert decision.cop1_mode == :disabled
  end

  test "enables cop1 when apid is allowlisted" do
    target_id = "target-1"

    interface =
      build_interface("interface-1",
        cop1_mode: "fop",
        cop1_apids: [10, 11]
      )

    {:ok, routing} =
      TargetInterface.new(%{
        target_id: target_id,
        interface_id: interface.id,
        direction: :write
      })

    resolver = build_resolver([interface], [routing], [])

    assert {:ok, decision} =
             RoutingService.route(resolver, target_id, :space_packet, 10, [])

    assert decision.cop1_mode == :fop
  end

  test "uses default vcid mapping when no target-specific mapping exists" do
    target_id = "target-1"
    interface = build_interface("interface-1")

    {:ok, routing} =
      TargetInterface.new(%{
        target_id: target_id,
        interface_id: interface.id,
        direction: :write
      })

    default_mapping = %InterfaceVcid{
      interface_id: interface.id,
      target_id: nil,
      vcid: 5
    }

    resolver = build_resolver([interface], [routing], [default_mapping])

    assert {:ok, decision} =
             RoutingService.route(resolver, target_id, :space_packet, nil, [])

    assert decision.vcid == 5
  end

  test "uses uplink defaults when routing scid is missing" do
    target_id = "target-1"

    interface =
      build_interface("interface-1",
        framing: %{
          "profile" => "tm",
          "uplink_scid" => 42,
          "uplink_vcid" => 1
        }
      )

    {:ok, routing} =
      TargetInterface.new(%{
        target_id: target_id,
        interface_id: interface.id,
        direction: :write
      })

    resolver = build_resolver([interface], [routing], [])

    assert {:ok, decision} =
             RoutingService.route(resolver, target_id, :space_packet, nil, [])

    assert decision.scid == 42
    assert decision.vcid == 1
  end

  test "honors interface overrides when selecting a route" do
    target_id = "target-1"
    interface_a = build_interface("interface-a")
    interface_b = build_interface("interface-b")

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

    resolver = build_resolver([interface_a, interface_b], [route_a, route_b], [])

    assert {:ok, decision} =
             RoutingService.route(resolver, target_id, :space_packet, nil,
               interface_id: interface_b.id
             )

    assert decision.interface_id == interface_b.id
  end

  test "returns no_interface when target has no routes" do
    resolver = build_resolver([], [], [])

    assert {:error, :no_interface} =
             RoutingService.route(resolver, "target-1", :space_packet, nil, [])
  end

  defp build_resolver(interfaces, routes, vcids) do
    config = %MissionConfig{
      mission_id: "mission-1",
      organization_id: "org-1",
      interfaces: interfaces,
      target_interface_routings: routes,
      interface_vcids: vcids
    }

    RoutingService.new(config)
  end

  defp build_interface(id, opts \\ []) do
    config = build_interface_config(opts)

    Interface.from_persistence(%{
      id: id,
      mission_id: "mission-1",
      name: "IFACE-#{id}",
      connection_type: "tcp_client",
      config: config
    })
  end

  defp build_interface_config(opts) do
    config = %{}

    config =
      case Keyword.get(opts, :framing) do
        nil ->
          config

        framing_opts ->
          framing_opts =
            Map.merge(
              %{
                "profile" => "tm",
                "sdu_mapping" => [
                  %{
                    "scid" => 0,
                    "vcid" => 0,
                    "direction" => "downlink",
                    "type" => "space_packet"
                  }
                ],
                "default_sdu_type" => "space_packet"
              },
              framing_opts
            )

          Map.merge(config, %{
            "framing" => "sdlp",
            "sdlp" => framing_opts
          })
      end

    config =
      case Keyword.get(opts, :cop1_mode) do
        nil ->
          config

        mode ->
          Map.put(config, "cop1", %{"mode" => mode})
      end

    case Keyword.get(opts, :cop1_apids) do
      nil ->
        config

      apids ->
        cop1 = Map.get(config, "cop1", %{})
        Map.put(config, "cop1", Map.put(cop1, "apids", apids))
    end
  end
end
