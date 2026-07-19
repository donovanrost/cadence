defmodule CadenceWeb.CommsRoutingLiveTest do
  use CadenceWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias Cadence.Comms.{RoutingRuleStore, TransportStore}

  alias Cadence.Comms.{RoutingRule, Transport}
  alias CadenceWeb.TestFixtures

  defp signed_in_org_and_mission do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org)
    mission = TestFixtures.persist_mission!(org, slug: "primary", display_name: "Primary Mission")
    {TestFixtures.member_conn(user), org, mission}
  end

  describe "routing routes" do
    test "lists routing rules with routing vocabulary" do
      {conn, org, mission} = signed_in_org_and_mission()
      spacecraft = TestFixtures.persist_spacecraft!(mission, display_name: "Alpha", scid: 42)
      transport = persist_transport!(org.organization_id, mission.mission_id, "Lab TCP")
      rule = persist_routing_rule!(org.organization_id, mission.mission_id, spacecraft, transport)

      {:ok, view, _html} = live(conn, ~p"/missions/#{mission.mission_id}/comms/routing")

      assert has_element?(view, "#comms-routing-page")
      assert has_element?(view, "#new-routing-rule-link")
      assert has_element?(view, "td", rule.display_name)
      assert has_element?(view, "details[open] a", "Routing")
      assert has_element?(view, "#routing-rules[phx-update='stream']")

      page = render(view)
      assert page =~ "Routing"
      assert page =~ "Durable rules"
      refute page =~ "Link Assignment"
      refute page =~ "Link Template"
    end

    test "creates and shows a routing rule" do
      {conn, org, mission} = signed_in_org_and_mission()
      spacecraft = TestFixtures.persist_spacecraft!(mission, display_name: "Alpha", scid: 42)
      transport = persist_transport!(org.organization_id, mission.mission_id, "Lab TCP")

      {:ok, view, html} = live(conn, ~p"/missions/#{mission.mission_id}/comms/routing/new")

      assert has_element?(view, "#comms-routing-new-page")
      assert has_element?(view, "#routing-rule-form")
      assert html =~ "New Routing Rule"
      assert html =~ "Contacts and runtime Links are handled later."

      assert {:error, {:live_redirect, %{to: target}}} =
               view
               |> form("#routing-rule-form",
                 routing_rule: %{
                   display_name: "Alpha live telemetry via Lab TCP",
                   purpose_label: "Live telemetry",
                   spacecraft_id: spacecraft.spacecraft_id,
                   transport_ref: "#{transport.transport_id}:#{transport.version}",
                   direction: "inbound",
                   role: "primary"
                 }
               )
               |> render_submit()

      assert target =~ "/missions/#{mission.mission_id}/comms/routing/"

      [rule] =
        RoutingRuleStore.list_routing_rules(org.organization_id, mission.mission_id)

      assert rule.display_name == "Alpha live telemetry via Lab TCP"
      assert rule.transport_id == transport.transport_id
      assert is_binary(rule.materialized_link_assignment_id)

      {:ok, show_view, show_html} = live(conn, target)
      assert has_element?(show_view, "#comms-routing-show-page")
      assert show_html =~ "Routing Rule"
      assert show_html =~ "Durable spacecraft use of a transport"
      assert show_html =~ "Assignment artifact"
      refute show_html =~ "Link Template"
    end

    test "spacecraft routing page lists rules for current spacecraft" do
      {conn, org, mission} = signed_in_org_and_mission()
      spacecraft = TestFixtures.persist_spacecraft!(mission, display_name: "Alpha", scid: 42)
      transport = persist_transport!(org.organization_id, mission.mission_id, "Lab TCP")
      rule = persist_routing_rule!(org.organization_id, mission.mission_id, spacecraft, transport)

      {:ok, view, html} =
        live(
          conn,
          ~p"/missions/#{mission.mission_id}/spacecraft/#{spacecraft.spacecraft_id}/routing"
        )

      assert has_element?(view, "#spacecraft-routing-page")
      assert has_element?(view, "#new-spacecraft-routing-rule-link")
      assert html =~ "Comms Routing"
      assert html =~ rule.display_name
      assert html =~ "mission transports"
    end

    test "unauthenticated requests redirect to sign in", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/sign-in"}}} =
               live(conn, ~p"/missions/m/comms/routing")
    end
  end

  defp persist_transport!(organization_id, mission_id, display_name) do
    transport =
      Transport.new(%{
        mission_id: mission_id,
        display_name: display_name,
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

    assert {:ok, persisted} =
             TransportStore.persist_transport(organization_id, transport)

    persisted
  end

  defp persist_routing_rule!(organization_id, mission_id, spacecraft, transport) do
    routing_rule =
      RoutingRule.new(%{
        mission_id: mission_id,
        spacecraft_id: spacecraft.spacecraft_id,
        display_name: "Alpha live telemetry via Lab TCP",
        purpose_label: "Live telemetry",
        direction: :inbound,
        transport_id: transport.transport_id,
        transport_version: transport.version,
        role: :primary
      })

    assert {:ok, persisted} =
             RoutingRuleStore.create_routing_rule(organization_id, routing_rule)

    persisted
  end
end
