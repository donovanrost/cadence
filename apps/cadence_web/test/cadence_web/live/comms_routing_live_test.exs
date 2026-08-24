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
    test "renders the empty state when the mission has no routing rules" do
      {conn, _org, mission} = signed_in_org_and_mission()

      {:ok, view, _html} = live(conn, ~p"/missions/#{mission.mission_id}/comms/routing")

      assert has_element?(view, "#comms-routing-page", "No routing rules")
      assert has_element?(view, "#new-routing-rule-link")
      refute has_element?(view, "#routing-rules-list-component")
    end

    test "lists routing rules with routing vocabulary and JSON-safe row props" do
      {conn, org, mission} = signed_in_org_and_mission()
      spacecraft = TestFixtures.persist_spacecraft!(mission, display_name: "Alpha", scid: 42)
      transport = persist_transport!(org.organization_id, mission.mission_id, "Lab TCP")
      rule = persist_routing_rule!(org.organization_id, mission.mission_id, spacecraft, transport)

      {:ok, view, _html} = live(conn, ~p"/missions/#{mission.mission_id}/comms/routing")

      assert has_element?(view, "#comms-routing-page")
      assert has_element?(view, "#new-routing-rule-link")
      assert has_element?(view, "#routing-rules-list-component")
      assert has_element?(view, "details[open] a", "Routing")
      assert has_element?(view, "#comms-routing-page", "Durable rules")

      vue = LiveVue.Test.get_vue(view, id: "routing-rules-list-component")

      assert vue.component == "CommsRoutingList"
      assert vue.ssr == false
      assert is_binary(Jason.encode!(vue.props))

      assert vue.props == %{
               "rows" => [
                 %{
                   "id" => "routing-rule-#{rule.routing_rule_id}",
                   "display_name" => rule.display_name,
                   "spacecraft_name" => spacecraft.display_name,
                   "purpose_label" => rule.purpose_label,
                   "direction" => "INBOUND",
                   "transport_name" => transport.display_name,
                   "role" => "PRIMARY",
                   "href" =>
                     "/missions/#{mission.mission_id}/comms/routing/#{rule.routing_rule_id}"
                 }
               ]
             }

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

      {:ok, show_view, _show_html} = live(conn, target)
      assert has_element?(show_view, "#comms-routing-show-page")
      assert has_element?(show_view, "#comms-routing-show-component")

      vue = routing_rule_vue(show_view)

      assert vue.component == "CommsRoutingShow"
      assert vue.ssr == false
      assert is_binary(Jason.encode!(vue.props))

      events =
        RoutingRuleStore.list_routing_rule_events(
          org.organization_id,
          mission.mission_id,
          rule.routing_rule_id
        )

      assert vue.props == %{
               "events" =>
                 Enum.map(events, fn event ->
                   %{
                     "event_type" => human_atom(event.event_type),
                     "occurred_at" => format_timestamp(event.occurred_at)
                   }
                 end),
               "navigation" => %{
                 "breadcrumbs" => [
                   %{
                     "href" => "/missions/#{mission.mission_id}",
                     "label" => mission.display_name
                   },
                   %{
                     "href" => "/missions/#{mission.mission_id}/comms",
                     "label" => "Comms"
                   },
                   %{
                     "href" => "/missions/#{mission.mission_id}/comms/routing",
                     "label" => "Routing"
                   },
                   %{"href" => nil, "label" => rule.display_name}
                 ]
               },
               "rule" => %{
                 "description" =>
                   "Durable spacecraft use of a transport for a purpose and direction.",
                 "details" => [
                   %{"label" => "Spacecraft", "value" => spacecraft.display_name},
                   %{"label" => "Purpose", "value" => rule.purpose_label},
                   %{"label" => "Direction", "value" => "INBOUND"},
                   %{"label" => "Transport", "value" => transport.display_name},
                   %{"label" => "Transport Version", "value" => "v#{transport.version}"},
                   %{"label" => "Role", "value" => "PRIMARY"}
                 ],
                 "display_name" => rule.display_name,
                 "routing_rule_id" => rule.routing_rule_id,
                 "runtime_artifacts" => [
                   %{
                     "label" => "Assignment artifact",
                     "value" => rule.materialized_link_assignment_id
                   },
                   %{
                     "label" => "Path artifacts",
                     "value" =>
                       rule.metadata
                       |> Map.get("materialized_path_template_ids", [])
                       |> Enum.join(", ")
                   }
                 ],
                 "runtime_artifacts_title" => "Internal Runtime Artifacts",
                 "section_title" => "Routing Rule",
                 "state" => %{"label" => "Enabled", "tone" => "ready"}
               }
             }

      refute Enum.any?(
               vue.props["rule"]["details"] ++ vue.props["rule"]["runtime_artifacts"],
               &(&1["label"] == "Link Template")
             )
    end

    test "shows disabled routing rule state without changing its details" do
      {conn, org, mission} = signed_in_org_and_mission()
      spacecraft = TestFixtures.persist_spacecraft!(mission, display_name: "Alpha", scid: 42)
      transport = persist_transport!(org.organization_id, mission.mission_id, "Lab TCP")
      rule = persist_routing_rule!(org.organization_id, mission.mission_id, spacecraft, transport)

      assert {:ok, disabled_rule} =
               RoutingRuleStore.set_routing_rule_enabled(
                 org.organization_id,
                 mission.mission_id,
                 rule.routing_rule_id,
                 false
               )

      {:ok, view, _html} =
        live(
          conn,
          ~p"/missions/#{mission.mission_id}/comms/routing/#{disabled_rule.routing_rule_id}"
        )

      props = routing_rule_vue(view).props

      assert props["rule"]["state"] == %{"label" => "Disabled", "tone" => "info"}

      assert Enum.at(props["rule"]["details"], 0) == %{
               "label" => "Spacecraft",
               "value" => spacecraft.display_name
             }
    end

    test "missing routing rule redirects to the current mission routing list" do
      {conn, _org, mission} = signed_in_org_and_mission()

      assert {:error,
              {:live_redirect,
               %{
                 to: to,
                 flash: %{"error" => "Routing rule not found."}
               }}} =
               live(conn, ~p"/missions/#{mission.mission_id}/comms/routing/missing")

      assert to == ~p"/missions/#{mission.mission_id}/comms/routing"
    end

    test "does not expose routing rules outside the current organization or mission scope" do
      {conn, org, mission} = signed_in_org_and_mission()

      other_mission =
        TestFixtures.persist_mission!(org, slug: "secondary", display_name: "Secondary Mission")

      other_spacecraft =
        TestFixtures.persist_spacecraft!(other_mission, display_name: "Sibling", scid: 43)

      other_transport =
        persist_transport!(org.organization_id, other_mission.mission_id, "Sibling TCP")

      other_mission_rule =
        persist_routing_rule!(
          org.organization_id,
          other_mission.mission_id,
          other_spacecraft,
          other_transport
        )

      other_org = TestFixtures.persist_org!(display_name: "Remote Org", slug: "remote-org")
      remote_mission = TestFixtures.persist_mission!(other_org, slug: "remote")
      remote_spacecraft = TestFixtures.persist_spacecraft!(remote_mission, display_name: "Remote")

      remote_transport =
        persist_transport!(other_org.organization_id, remote_mission.mission_id, "Remote TCP")

      other_org_rule =
        persist_routing_rule!(
          other_org.organization_id,
          remote_mission.mission_id,
          remote_spacecraft,
          remote_transport
        )

      for foreign_rule <- [other_mission_rule, other_org_rule] do
        assert {:error,
                {:live_redirect,
                 %{
                   to: to,
                   flash: %{"error" => "Routing rule not found."}
                 }}} =
                 live(
                   conn,
                   ~p"/missions/#{mission.mission_id}/comms/routing/#{foreign_rule.routing_rule_id}"
                 )

        assert to == ~p"/missions/#{mission.mission_id}/comms/routing"
      end
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

  defp routing_rule_vue(view) do
    LiveVue.Test.get_vue(view, id: "comms-routing-show-component")
  end

  defp format_timestamp(timestamp) do
    Calendar.strftime(timestamp, "%Y-%m-%d %H:%M:%S UTC")
  end

  defp human_atom(value) when is_atom(value) do
    value |> Atom.to_string() |> String.replace("_", " ") |> String.upcase()
  end
end
