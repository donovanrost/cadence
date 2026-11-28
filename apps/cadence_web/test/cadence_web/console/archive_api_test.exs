defmodule CadenceWeb.Console.ArchiveAPITest do
  @moduledoc """
  ux U82 over HTTP: archiving transports and ground stations through change sets.
  - An archive of something still used is refused with 409 in_use, naming it and its uses.
  - The lists stay active-only; ?include_archived=true adds archived rows after the active ones.
  - A station reads 'Inuvik · INU' in the preview (its name alone without a code).
  """
  use CadenceWeb.ConnCase, async: false

  alias Cadence.Comms.{GroundStation, GroundStationStore, RoutingRule, RoutingRuleStore}
  alias Cadence.Comms.{Transport, TransportStore}
  alias CadenceWeb.TestFixtures

  setup do
    previous = Application.get_env(:cadence, :activation_governance, [])
    Application.put_env(:cadence, :activation_governance, approval_required: false)
    on_exit(fn -> Application.put_env(:cadence, :activation_governance, previous) end)

    org = TestFixtures.persist_org!()
    user = TestFixtures.persist_user!(display_name: "Mira K.")
    TestFixtures.grant_membership!(user, org, role: :organization_admin)
    mission = TestFixtures.persist_mission!(org)
    craft = TestFixtures.persist_spacecraft!(mission, display_name: "EARENDIL-312", scid: 312)

    station = station!(org, mission, "Inuvik", "INU")
    spare_station = station!(org, mission, "Yellowknife", "YKN")
    used = transport!(org, mission, "INU S-band", station)
    spare = transport!(org, mission, "INU spare", station)

    {:ok, _rule} =
      RoutingRuleStore.create_routing_rule(
        org.organization_id,
        RoutingRule.new(%{
          mission_id: mission.mission_id,
          spacecraft_id: craft.spacecraft_id,
          display_name: "INU downlink",
          purpose_label: "TT&C downlink",
          direction: :inbound,
          transport_id: used.transport_id,
          transport_version: used.version,
          ground_station_id: station.ground_station_id,
          role: :primary
        })
      )

    %{
      conn: TestFixtures.member_conn(user),
      base: "/api/v1/missions/#{mission.mission_id}",
      craft: craft,
      used: used,
      spare: spare,
      spare_station: spare_station
    }
  end

  defp station!(org, mission, name, code) do
    {:ok, station} =
      GroundStationStore.persist_ground_station(
        org.organization_id,
        GroundStation.new(%{mission_id: mission.mission_id, display_name: name, code: code})
      )

    station
  end

  defp transport!(org, mission, name, station) do
    {:ok, transport} =
      TransportStore.persist_transport(
        org.organization_id,
        Transport.new(%{
          mission_id: mission.mission_id,
          display_name: name,
          transport_kind: :tcp_socket,
          direction_capability: :inbound,
          adapter_key: :tcp_socket,
          ground_station_id: station.ground_station_id,
          configuration: %{
            "mode" => "listen",
            "expected_peer_addresses" => ["127.0.0.1/32", "::1/128"],
            "direction_capability" => "inbound",
            "host" => "127.0.0.1",
            "port" => Integer.to_string(40_000 + rem(System.unique_integer([:positive]), 20_000)),
            "framing_mode" => "raw",
            "tls_enabled" => "false"
          }
        })
      )

    transport
  end

  defp archive_op(kind, id), do: %{"kind" => kind, "action" => "delete", "entity_id" => id}

  defp stage(c, ops),
    do: c.conn |> post(c.base <> "/config/stage", %{"summary" => "Archive", "ops" => ops})

  defp archive!(c, kind, id) do
    %{"change_set_id" => set_id, "version" => version} =
      c |> stage([archive_op(kind, id)]) |> json_response(201) |> Map.fetch!("data")

    c.conn
    |> post("#{c.base}/config/change-sets/#{set_id}/submit", %{
      "reason" => "No longer used here",
      "expected_version" => version
    })
    |> json_response(200)
  end

  test "an archive of a transport still in use is refused, naming it and its uses", c do
    used_id = c.used.transport_id
    craft_id = c.craft.spacecraft_id

    assert %{"error" => %{"code" => "in_use", "details" => details}} =
             c |> stage([archive_op("transport", used_id)]) |> json_response(409)

    assert %{
             "entity" => %{"kind" => "transport", "id" => ^used_id, "name" => "INU S-band"},
             "uses" => %{
               "routes" => %{
                 "count" => 1,
                 "items" => [%{"spacecraft" => %{"id" => ^craft_id, "name" => "EARENDIL-312"}}]
               },
               "booked_passes" => %{"count" => 0},
               "listening_now" => %{"count" => 0}
             }
           } = details

    # Nothing was staged.
    assert %{"change_set" => nil} =
             c.conn |> get(c.base <> "/config") |> json_response(200) |> Map.fetch!("data")
  end

  test "lists stay active-only; ?include_archived=true adds archived rows after active ones", c do
    archive!(c, "transport", c.spare.transport_id)
    spare_id = c.spare.transport_id

    default =
      c.conn
      |> get(c.base <> "/transports")
      |> json_response(200)
      |> get_in(["data", "transports"])

    refute Enum.any?(default, &(&1["id"] == spare_id))

    all =
      c.conn
      |> get(c.base <> "/transports?include_archived=true")
      |> json_response(200)
      |> get_in(["data", "transports"])

    assert [%{"lifecycle_state" => "active"} | _] = all
    assert %{"id" => ^spare_id, "lifecycle_state" => "archived"} = List.last(all)
  end

  test "a station's archive reads 'Name · CODE' in the preview", c do
    station_id = c.spare_station.ground_station_id

    %{"change_set_id" => set_id} =
      c
      |> stage([archive_op("ground_station", station_id)])
      |> json_response(201)
      |> Map.fetch!("data")

    preview =
      c.conn
      |> post(c.base <> "/config/change-sets/#{set_id}/preview", %{})
      |> json_response(200)
      |> Map.fetch!("data")

    assert [%{"entity_name" => "Yellowknife · YKN"} | _] =
             Enum.filter(preview["diffs"], &(&1["kind"] == "ground_station"))
  end
end
