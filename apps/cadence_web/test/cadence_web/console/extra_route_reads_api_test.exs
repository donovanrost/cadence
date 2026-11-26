defmodule CadenceWeb.Console.ExtraRouteReadsAPITest do
  @moduledoc """
  ux U79 over HTTP: the reads behind a spacecraft's own extra routes.
  (A) the spacecraft detail's routing rules carry origin, route_id and station;
  (B) GET …/spacecraft/:id/routes/:route_id hands the editor the route as staged;
  (C) the profile page lists extra routes beside its overrides.
  """
  use CadenceWeb.ConnCase, async: false

  alias Cadence.Comms.{GroundStation, GroundStationStore}
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
    profile = TestFixtures.persist_spacecraft_profile!(mission, display_name: "Earendil standard")

    craft =
      TestFixtures.persist_spacecraft!(mission,
        display_name: "EARENDIL-389",
        scid: 389,
        spacecraft_type_id: profile.spacecraft_type_id,
        spacecraft_type_version: profile.version
      )

    other = TestFixtures.persist_spacecraft!(mission, display_name: "EARENDIL-390", scid: 390)

    {:ok, station} =
      GroundStationStore.persist_ground_station(
        org.organization_id,
        GroundStation.new(%{mission_id: mission.mission_id, display_name: "Inuvik", code: "INU"})
      )

    {:ok, _transport} =
      TransportStore.persist_transport(
        org.organization_id,
        Transport.new(%{
          mission_id: mission.mission_id,
          display_name: "INU S-band",
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

    %{
      conn: TestFixtures.member_conn(user),
      base: "/api/v1/missions/#{mission.mission_id}",
      craft: craft,
      other: other,
      profile: profile,
      station: station
    }
  end

  defp data(c, path),
    do: c.conn |> get(c.base <> path) |> json_response(200) |> Map.fetch!("data")

  # An extra route staged and applied through the console's change sets, as the editor does it.
  defp add_extra_route!(c) do
    op = %{
      "kind" => "spacecraft_route",
      "action" => "create",
      "document" => %{
        "spacecraft_id" => c.craft.spacecraft_id,
        "ground_station_id" => c.station.ground_station_id,
        "downlink" => "candidate",
        "uplink" => "none",
        "purpose_label" => "Recovery"
      }
    }

    %{"change_set_id" => set_id, "version" => version, "entity_ids" => [route_id]} =
      c.conn
      |> post(c.base <> "/config/stage", %{"summary" => "Add", "ops" => [op]})
      |> json_response(201)
      |> Map.fetch!("data")

    c.conn
    |> post("#{c.base}/config/change-sets/#{set_id}/submit", %{
      "reason" => "Recovery route for EARENDIL-389",
      "expected_version" => version
    })
    |> json_response(200)

    route_id
  end

  test "(A) every rule says its origin and station; an extra route's legs carry its id", c do
    route_id = add_extra_route!(c)
    rules = data(c, "/spacecraft/#{c.craft.spacecraft_id}")["routing_rules"]
    station_id = c.station.ground_station_id

    assert [
             %{
               "origin" => "spacecraft",
               "route_id" => ^route_id,
               "role" => "candidate",
               "station" => %{"id" => ^station_id, "code" => "INU", "name" => "Inuvik"}
             }
           ] = rules
  end

  test "(B) the extra route's document, as staged, and only on its own spacecraft", c do
    route_id = add_extra_route!(c)
    craft_id = c.craft.spacecraft_id
    station_id = c.station.ground_station_id

    assert %{
             "id" => ^route_id,
             "document" =>
               %{
                 "spacecraft_id" => ^craft_id,
                 "ground_station_id" => ^station_id,
                 "downlink" => "candidate",
                 "uplink" => "none"
               } = document
           } = data(c, "/spacecraft/#{craft_id}/routes/#{route_id}")

    # Staged without a transport: it stays unpinned (domain 01ad846e7).
    assert document["transport_id"] in [nil, ""]

    for path <- [
          "/spacecraft/#{c.other.spacecraft_id}/routes/#{route_id}",
          "/spacecraft/#{craft_id}/routes/spacecraft_route-nope"
        ] do
      assert %{"error" => %{"code" => "spacecraft_route_not_found"}} =
               c.conn |> get(c.base <> path) |> json_response(404)
    end
  end

  test "(C) the profile page lists extra routes beside its overrides, one entry per route", c do
    route_id = add_extra_route!(c)
    craft_id = c.craft.spacecraft_id

    assert %{"extra_routes" => [entry], "overrides" => _overrides} =
             data(c, "/profiles/#{c.profile.spacecraft_type_id}")

    assert %{
             "spacecraft" => %{"id" => ^craft_id, "name" => "EARENDIL-389"},
             "route_id" => ^route_id,
             "station" => %{"code" => "INU", "name" => "Inuvik"},
             "legs" => [%{"direction" => "downlink", "role" => "candidate"}]
           } = entry
  end
end
