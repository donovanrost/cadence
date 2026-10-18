defmodule CadenceWeb.MissionModulePageTest do
  use CadenceWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  alias Cadence.Comms.{
    GroundStation,
    GroundStationStore,
    RoutingRule,
    RoutingRuleStore,
    Transport,
    TransportStore
  }

  alias CadenceWeb.TestFixtures

  setup do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    TestFixtures.grant_membership!(user, org)
    mission = TestFixtures.persist_mission!(org)
    spacecraft = TestFixtures.persist_spacecraft!(mission)

    {:ok, transport} =
      TransportStore.persist_transport(
        org.organization_id,
        Transport.new(%{
          mission_id: mission.mission_id,
          display_name: "Lab TCP",
          transport_kind: :tcp_socket,
          direction_capability: :inbound,
          adapter_key: :tcp_socket,
          configuration: %{
            "mode" => "listen",
            "direction_capability" => "inbound",
            "host" => "0.0.0.0",
            "port" => "5000",
            "framing_mode" => "raw",
            "tls_enabled" => "false"
          }
        })
      )

    {:ok, station} =
      GroundStationStore.persist_ground_station(
        org.organization_id,
        GroundStation.new(%{
          mission_id: mission.mission_id,
          display_name: "Goldstone",
          provider: "DSN",
          region: "California"
        })
      )

    {:ok, rule} =
      RoutingRuleStore.create_routing_rule(
        org.organization_id,
        RoutingRule.new(%{
          mission_id: mission.mission_id,
          spacecraft_id: spacecraft.spacecraft_id,
          display_name: "Downlink",
          purpose_label: "Telemetry",
          direction: :inbound,
          transport_id: transport.transport_id,
          transport_version: transport.version,
          role: :primary
        })
      )

    %{
      conn: TestFixtures.member_conn(user),
      org: org,
      mission: mission,
      transport: transport,
      station: station,
      rule: rule,
      path: "/missions/#{mission.mission_id}/comms"
    }
  end

  test "all eight read pages compose without a frontend installation or release", c do
    {:ok, view, _} = live(c.conn, c.path)

    for {suffix, id, resource} <- [
          {"", "overview", nil},
          {"/validation", "validation", nil},
          {"/transports", "transports", nil},
          {"/routing", "routing", nil},
          {"/ground-stations", "ground-stations", nil},
          {"/transports/#{c.transport.transport_id}", "transport", c.transport.transport_id},
          {"/routing/#{c.rule.routing_rule_id}", "routing-detail", c.rule.routing_rule_id},
          {"/ground-stations/#{c.station.ground_station_id}", "ground-station",
           c.station.ground_station_id}
        ] do
      render_hook(view, "host:context", %{"path" => c.path <> suffix})
      page = contribution(view)
      assert page["status"] == "ready"
      assert page["slot"] == "mission.page"
      assert page["version"] == 1
      assert page["id"] == "comms." <> id
      assert page["context"]["organizationId"] == c.org.organization_id
      assert page["context"]["missionId"] == c.mission.mission_id
      assert page["context"]["resourceId"] == resource
      assert has_element?(view, "#application-shell")
    end

    render_hook(view, "host:context", %{"path" => "/missions/#{c.mission.mission_id}/spacecraft"})
    assert contribution(view) == nil
  end

  test "query filters survive refresh and path resource identity wins over query input", c do
    path = c.path <> "/transports?q=Lab&page=999&pageSize=1&sort=display_name&dir=desc"
    {:ok, view, _} = live(c.conn, path)
    page = contribution(view)
    assert page["data"]["data"]["query"] == "Lab"
    assert page["data"]["data"]["page"] == 1
    assert page["data"]["data"]["dir"] == "desc"
    assert [%{"id" => id}] = page["data"]["data"]["items"]
    assert id == c.transport.transport_id

    render_hook(view, "host:context", %{"path" => path})
    assert contribution(view) == page

    render_hook(view, "host:context", %{
      "path" => c.path <> "/transports/#{id}?transport_id=foreign&mission_id=foreign"
    })

    assert contribution(view)["context"]["resourceId"] == id
    assert contribution(view)["data"]["data"]["id"] == id
  end

  test "bad input and missing resources produce a bounded unavailable contribution", c do
    {:ok, view, _} = live(c.conn, c.path)

    for suffix <- [
          "/transports?pageSize=101",
          "/transports/missing",
          "/ground-stations/missing",
          "/routing/missing"
        ] do
      render_hook(view, "host:context", %{"path" => c.path <> suffix})
      page = contribution(view)
      assert page["status"] == "unavailable"
      refute Map.has_key?(page, "data")
      assert has_element?(view, "#application-shell")
    end

    render_hook(view, "host:context", %{"path" => c.path <> "/transports"})
    assert contribution(view)["status"] == "ready"
  end

  test "authentication, organization admission and revoked sessions still guard reads", c do
    assert {:error, {:redirect, %{to: "/sign-in"}}} = live(build_conn(), c.path)
    other = TestFixtures.persist_org!() |> TestFixtures.persist_mission!()

    assert {:error, {:redirect, _}} =
             live(c.conn, "/missions/#{other.mission_id}/comms/transports")

    {:ok, view, _} = live(c.conn, c.path)
    :ok = Cadence.Auth.revoke_user_session(get_session(c.conn, :user_session_token))
    render_hook(view, "host:context", %{"path" => c.path})
    assert_redirect(view, "/sign-in")
  end

  defp contribution(view),
    do:
      LiveVue.Test.get_vue(view, id: "application-shell").props["snapshot"]["mission_module_page"]
end
