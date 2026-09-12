defmodule CadenceWeb.CommunicationsSetupPageTest do
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

  test "four setup forms validate and save through the host, consuming each page instance", c do
    {:ok, view, _} = live(c.conn, c.path)

    for {suffix, form} <- [
          {"/transports/new", "transport_new"},
          {"/routing/new", "routing_new"},
          {"/ground-stations/new", "ground_station_new"},
          {"/ground-stations/#{c.station.ground_station_id}/edit", "ground_station_edit"}
        ] do
      path = c.path <> suffix
      refresh(view, path)
      original = page(view)
      assert original["id"] == "comms." <> String.replace(form, "_", "-")
      assert original["status"] == "ready"
      assert original["data"]["phase"] == "editing"
      input = input(c, form)
      assert action(view, path, original, "save", input)["snapshot"]["status"] == "rejected"
      assert action(view, path, original, "validate", input)["snapshot"]["status"] == "ok"
      refresh(view, path)
      assert page(view)["token"] == original["token"]
      assert page(view)["data"]["model"] == original["data"]["model"]
      saved = action(view, path, original, "save", input)
      assert saved["snapshot"]["status"] == "ok"
      assert saved["snapshot"]["data"]["result"]["navigation"]["href"] =~ c.path
      refute action(view, path, original, "save", input)["ok"]
      refresh(view, path)
      assert page(view)["data"]["phase"] == "completed"
      assert page(view)["token"] == original["token"]
      refute action(view, path, original, "save", input)["ok"]
    end

    assert length(TransportStore.list_transports(c.org.organization_id, c.mission.mission_id)) ==
             2

    assert length(
             RoutingRuleStore.list_routing_rules(c.org.organization_id, c.mission.mission_id)
           ) == 2

    assert {:ok, station} =
             GroundStationStore.fetch_ground_station(
               c.org.organization_id,
               c.mission.mission_id,
               c.station.ground_station_id
             )

    assert station.display_name == "Host station edit"
  end

  test "save requires the exact current validation; invalid validation clears previous admission",
       c do
    path = c.path <> "/transports/new"
    {:ok, view, _} = live(c.conn, path)
    original = page(view)
    input = input(c, "transport_new")
    assert action(view, path, original, "validate", input)["snapshot"]["status"] == "ok"
    changed = put_in(input, ["transport", "display_name"], "Unvalidated change")
    assert action(view, path, original, "save", changed)["snapshot"]["status"] == "rejected"

    assert action(view, path, original, "validate", %{"transport" => %{}})["snapshot"]["status"] ==
             "rejected"

    assert action(view, path, original, "save", input)["snapshot"]["status"] == "rejected"

    assert length(TransportStore.list_transports(c.org.organization_id, c.mission.mission_id)) ==
             1
  end

  test "uncertain effect results remain consumed after refresh and cannot be replayed", c do
    path = c.path <> "/routing/new"
    {:ok, view, _} = live(c.conn, path)
    original = page(view)

    input =
      put_in(input(c, "routing_new"), ["routing_rule", "spacecraft_id"], "missing-spacecraft")

    assert action(view, path, original, "validate", input)["snapshot"]["status"] == "ok"
    assert action(view, path, original, "save", input)["snapshot"] == %{"status" => "unknown"}
    refresh(view, path)
    assert page(view)["data"]["phase"] == "submitted"
    assert page(view)["token"] == original["token"]
    refute action(view, path, original, "save", input)["ok"]

    assert length(
             RoutingRuleStore.list_routing_rules(c.org.organization_id, c.mission.mission_id)
           ) == 1
  end

  test "station edit is bound to its URL, not query or submitted identities", c do
    path =
      c.path <> "/ground-stations/#{c.station.ground_station_id}/edit?ground_station_id=foreign"

    {:ok, view, _} = live(c.conn, path)
    original = page(view)
    assert original["context"]["resourceId"] == c.station.ground_station_id

    forged =
      put_in(input(c, "ground_station_edit"), ["ground_station", "ground_station_id"], "foreign")

    for event <- ["validate", "save"] do
      assert action(view, path, original, event, forged)["snapshot"]["status"] == "rejected"
    end

    refute action(view, path, %{original | "token" => Ecto.UUID.generate()}, "validate", forged)[
             "ok"
           ]

    refute action(view, c.path <> "/ground-stations/new", original, "validate", forged)["ok"]
  end

  test "navigation invalidates prior form instances and routing preselection survives loading",
       c do
    path = c.path <> "/routing/new?spacecraft_id=#{c.rule.spacecraft_id}"
    {:ok, view, _} = live(c.conn, path)
    original = page(view)

    assert original["data"]["model"]["data"]["form"]["fields"]["spacecraft_id"]["value"] ==
             c.rule.spacecraft_id

    refresh(view, c.path)
    refute action(view, path, original, "validate", input(c, "routing_new"))["ok"]
    refresh(view, path)
    refute page(view)["token"] == original["token"]
    refute action(view, path, original, "validate", input(c, "routing_new"))["ok"]
  end

  test "revoked sessions cannot validate or save a mounted form", c do
    path = c.path <> "/transports/new"
    {:ok, view, _} = live(c.conn, path)
    original = page(view)
    :ok = Cadence.Auth.revoke_user_session(get_session(c.conn, :user_session_token))

    render_hook(
      view,
      "host:mission-page",
      request(path, original, "validate", input(c, "transport_new"))
    )

    assert_redirect(view, "/sign-in")
  end

  defp page(view),
    do:
      LiveVue.Test.get_vue(view, id: "application-shell").props["snapshot"]["mission_module_page"]

  defp refresh(view, path) do
    render_hook(view, "host:context", %{"path" => path})
    assert_reply(view, %{ok: true})
  end

  defp request(path, page, event, input),
    do: %{
      "path" => path,
      "id" => page["id"],
      "token" => page["token"],
      "event" => event,
      "input" => input
    }

  defp action(view, path, page, event, input) do
    render_hook(view, "host:mission-page", request(path, page, event, input))
    assert_reply(view, reply)
    Jason.decode!(Jason.encode!(reply))
  end

  defp input(_c, "transport_new"),
    do: %{
      "transport" => %{
        "display_name" => "Host transport",
        "origin" => "direct",
        "transport_kind" => "tcp_socket",
        "tcp_mode" => "listen",
        "direction_capability" => "inbound",
        "host" => "0.0.0.0",
        "port" => "5000",
        "framing_mode" => "raw",
        "tls_enabled" => "false"
      }
    }

  defp input(c, "routing_new"),
    do: %{
      "routing_rule" => %{
        "display_name" => "Host routing",
        "purpose_label" => "Telemetry",
        "spacecraft_id" => c.rule.spacecraft_id,
        "transport_ref" => "#{c.transport.transport_id}:1",
        "direction" => "inbound",
        "role" => "primary"
      }
    }

  defp input(c, form),
    do: %{
      "ground_station" => %{
        "ground_station_id" =>
          if(form == "ground_station_edit",
            do: c.station.ground_station_id,
            else: "host-new-station"
          ),
        "display_name" =>
          if(form == "ground_station_edit", do: "Host station edit", else: "Host station"),
        "provider" => "DSN",
        "region" => "California",
        "metadata_json" => "{}"
      }
    }
end
