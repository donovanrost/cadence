defmodule Cadence.Runtime.Uplink.RoutingServiceTest do
  use Cadence.PureCase, async: true

  alias Cadence.Application.Missions.MissionConfig
  alias Cadence.Domain.Interfaces.Entities.Interface
  alias Cadence.Domain.Interfaces.Entities.TargetInterface
  alias Cadence.Interfaces.InterfaceVcid
  alias Cadence.Links.Channel
  alias Cadence.Links.ProtocolConfig, as: LinkProtocolConfig
  alias Cadence.Runtime.Uplink.RoutingService

  test "resolves target-specific vcid and cop1 mode" do
    target_id = "target-1"
    interface = build_interface("interface-1")

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

    links =
      build_links(
        scid: 12,
        cop1: %{"mode" => "fop"},
        channels: [%{scid: 12, vcid: 3, map_id: nil}]
      )

    resolver = build_resolver([interface], [routing], [vcid_mapping], links)

    assert {:ok, decision} =
             RoutingService.route(resolver, target_id, :space_packet, 10, [])

    assert decision.target_id == target_id
    assert decision.pdu_type == :space_packet
    assert decision.apid == 10
    assert decision.interface_id == interface.id
    assert decision.scid == 12
    assert decision.vcid == 3
    assert decision.cop1_mode == :fop
    assert decision.tc_stream_id.scid == 12
    assert decision.tc_stream_id.vcid == 3
  end

  test "captures raw tc stream id from routing" do
    target_id = "target-1"
    interface = build_interface("interface-1")

    {:ok, routing} =
      TargetInterface.new(%{
        target_id: target_id,
        interface_id: interface.id,
        direction: :write,
        tc_stream_id: "stream-1",
        scid: 3
      })

    default_mapping = %InterfaceVcid{
      interface_id: interface.id,
      target_id: nil,
      vcid: 2
    }

    resolver = build_resolver([interface], [routing], [default_mapping])

    assert {:ok, decision} =
             RoutingService.route(resolver, target_id, :space_packet, 10, [])

    assert decision.tc_stream_id_raw == "stream-1"
    assert decision.tc_stream_id.scid == 3
    assert decision.tc_stream_id.vcid == 2
  end

  test "disables cop1 when apid is not allowlisted" do
    target_id = "target-1"

    interface = build_interface("interface-1")

    {:ok, routing} =
      TargetInterface.new(%{
        target_id: target_id,
        interface_id: interface.id,
        direction: :write,
        scid: 1
      })

    links =
      build_links(
        scid: 1,
        cop1: %{"mode" => "fop", "apids" => [10, 11]},
        channels: [%{scid: 1, vcid: 0, map_id: nil}]
      )

    resolver = build_resolver([interface], [routing], [], links)

    assert {:ok, decision} =
             RoutingService.route(resolver, target_id, :space_packet, 12, [])

    assert decision.cop1_mode == :bypass
  end

  test "enables cop1 when apid is allowlisted" do
    target_id = "target-1"

    interface = build_interface("interface-1")

    {:ok, routing} =
      TargetInterface.new(%{
        target_id: target_id,
        interface_id: interface.id,
        direction: :write,
        scid: 1
      })

    links =
      build_links(
        scid: 1,
        cop1: %{"mode" => "fop", "apids" => [10, 11]},
        channels: [%{scid: 1, vcid: 0, map_id: nil}]
      )

    resolver = build_resolver([interface], [routing], [], links)

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
        direction: :write,
        scid: 4
      })

    default_mapping = %InterfaceVcid{
      interface_id: interface.id,
      target_id: nil,
      vcid: 5
    }

    links =
      build_links(
        scid: 4,
        cop1: %{"mode" => "fop"},
        channels: [%{scid: 4, vcid: 5, map_id: nil}]
      )

    resolver = build_resolver([interface], [routing], [default_mapping], links)

    assert {:ok, decision} =
             RoutingService.route(resolver, target_id, :space_packet, nil, [])

    assert decision.vcid == 5
  end

  test "returns nil scid when routing scid is missing" do
    target_id = "target-1"
    interface = build_interface("interface-1")

    {:ok, routing} =
      TargetInterface.new(%{
        target_id: target_id,
        interface_id: interface.id,
        direction: :write
      })

    resolver = build_resolver([interface], [routing], [], [])

    assert {:ok, decision} =
             RoutingService.route(resolver, target_id, :space_packet, nil, [])

    assert is_nil(decision.scid)
    assert is_nil(decision.vcid)
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

    resolver = build_resolver([interface_a, interface_b], [route_a, route_b], [], [])

    assert {:ok, decision} =
             RoutingService.route(resolver, target_id, :space_packet, nil,
               interface_id: interface_b.id
             )

    assert decision.interface_id == interface_b.id
  end

  test "returns no_interface when target has no routes" do
    resolver = build_resolver([], [], [], [])

    assert {:error, :no_interface} =
             RoutingService.route(resolver, "target-1", :space_packet, nil, [])
  end

  test "returns routing_ambiguous when multiple routes match" do
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

    resolver = build_resolver([interface_a, interface_b], [route_a, route_b], [], [])

    assert {:error, :routing_ambiguous, candidates} =
             RoutingService.route(resolver, target_id, :space_packet, nil, [])

    interface_ids = Enum.map(candidates, & &1.interface_id)
    assert Enum.sort(interface_ids) == Enum.sort([interface_a.id, interface_b.id])
  end

  defp build_resolver(interfaces, routes, vcids, links \\ []) do
    config = %MissionConfig{
      mission_id: "mission-1",
      organization_id: "org-1",
      interfaces: interfaces,
      target_interface_routings: routes,
      interface_vcids: vcids,
      links: links
    }

    RoutingService.new(config)
  end

  defp build_interface(id, _opts \\ []) do
    Interface.from_persistence(%{
      id: id,
      mission_id: "mission-1",
      name: "IFACE-#{id}",
      connection_type: "tcp_client",
      config: %{}
    })
  end

  defp build_links(opts) do
    scid = Keyword.fetch!(opts, :scid)
    cop1 = Keyword.get(opts, :cop1, %{})
    channels = Keyword.get(opts, :channels, [])

    [
      %{
        scid: scid,
        protocol_config: %LinkProtocolConfig{config: %{"cop1" => cop1}},
        channels: Enum.map(channels, &to_channel/1)
      }
    ]
  end

  defp to_channel(%{scid: scid, vcid: vcid} = attrs) do
    %Channel{
      scid: scid,
      vcid: vcid,
      map_id: Map.get(attrs, :map_id),
      protocol_config: Map.get(attrs, :protocol_config)
    }
  end
end
