defmodule Cadence.Runtime.Uplink.RoutingServiceTest do
  use Cadence.PureCase, async: true

  alias Cadence.Application.Missions.MissionConfig
  alias Cadence.Links.Channel
  alias Cadence.Links.ProtocolConfig, as: LinkProtocolConfig
  alias Cadence.Runtime.Uplink.RoutingService

  test "routes target to transport and builds tc stream id" do
    target_id = "target-1"
    transport_id = "transport-1"
    scid = 12
    vcid = 3

    resolver =
      build_resolver(
        [
          %{
            target_id: target_id,
            transport_id: transport_id,
            scid: scid,
            vcid: vcid,
            map_id: nil
          }
        ],
        cop1: %{"mode" => "fop"}
      )

    assert {:ok, decision} =
             RoutingService.route(resolver, target_id, :space_packet, 10, [])

    assert decision.target_id == target_id
    assert decision.transport_id == transport_id
    assert decision.scid == scid
    assert decision.vcid == vcid
    assert decision.cop1_mode == :fop
    assert decision.tc_stream_id.scid == scid
    assert decision.tc_stream_id.vcid == vcid
  end

  test "disables cop1 when apid is not allowlisted" do
    target_id = "target-1"
    transport_id = "transport-1"

    resolver =
      build_resolver(
        [
          %{
            target_id: target_id,
            transport_id: transport_id,
            scid: 1,
            vcid: 0,
            map_id: nil
          }
        ],
        cop1: %{"mode" => "fop", "apids" => [10, 11]}
      )

    assert {:ok, decision} =
             RoutingService.route(resolver, target_id, :space_packet, 12, [])

    assert decision.cop1_mode == :bypass
  end

  test "honors transport overrides when selecting a route" do
    target_id = "target-1"
    transport_a = "transport-a"
    transport_b = "transport-b"

    resolver =
      build_resolver([
        %{target_id: target_id, transport_id: transport_a, scid: 5, vcid: 0, map_id: nil},
        %{target_id: target_id, transport_id: transport_b, scid: 5, vcid: 1, map_id: nil}
      ])

    assert {:ok, decision} =
             RoutingService.route(resolver, target_id, :space_packet, nil,
               transport_id: transport_b
             )

    assert decision.transport_id == transport_b
  end

  test "returns no_transport when target has no routes" do
    resolver = build_resolver([])

    assert {:error, :no_transport} =
             RoutingService.route(resolver, "target-1", :space_packet, nil, [])
  end

  test "returns routing_ambiguous when multiple routes match" do
    target_id = "target-1"
    transport_a = "transport-a"
    transport_b = "transport-b"

    resolver =
      build_resolver([
        %{target_id: target_id, transport_id: transport_a, scid: 7, vcid: 0, map_id: nil},
        %{target_id: target_id, transport_id: transport_b, scid: 7, vcid: 0, map_id: nil}
      ])

    assert {:error, :routing_ambiguous, candidates} =
             RoutingService.route(resolver, target_id, :space_packet, nil, [])

    transport_ids = Enum.map(candidates, & &1.transport_id)
    assert Enum.sort(transport_ids) == Enum.sort([transport_a, transport_b])
  end

  defp build_resolver(routes, opts \\ []) do
    channel_targets =
      routes
      |> Enum.map(fn route ->
        %{
          target_id: route.target_id,
          scid: route.scid,
          vcid: route.vcid,
          map_id: route.map_id
        }
      end)
      |> Enum.uniq_by(&{&1.target_id, &1.scid, &1.vcid, &1.map_id})

    bindings =
      Enum.map(routes, fn route ->
        %{
          transport_id: route.transport_id,
          direction: :uplink,
          desired_state: :active,
          channel: %Channel{scid: route.scid, vcid: route.vcid, map_id: route.map_id}
        }
      end)

    %MissionConfig{
      mission_id: "mission-1",
      organization_id: "org-1",
      channel_targets: channel_targets,
      bindings: bindings,
      links: build_links(routes, opts)
    }
    |> RoutingService.new()
  end

  defp build_links(routes, opts) do
    cop1 = Keyword.get(opts, :cop1, %{})

    routes
    |> Enum.group_by(& &1.scid)
    |> Enum.map(fn {scid, scid_routes} ->
      %{
        scid: scid,
        protocol_config: %LinkProtocolConfig{config: %{"cop1" => cop1}},
        channels:
          Enum.map(scid_routes, fn route ->
            %Channel{scid: route.scid, vcid: route.vcid, map_id: route.map_id}
          end)
      }
    end)
  end
end
