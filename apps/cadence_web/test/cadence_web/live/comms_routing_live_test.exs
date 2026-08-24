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

      {:ok, view, _html} = live(conn, ~p"/missions/#{mission.mission_id}/comms/routing/new")

      assert has_element?(view, "#comms-routing-new-component")
      refute has_element?(view, "#comms-routing-new-page")
      refute has_element?(view, "#routing-rule-form")
      assert has_element?(view, "details[open] a", "Routing")
      assert has_element?(view, ".drawer-side", org.display_name)
      assert has_element?(view, ".drawer-side", mission.display_name)

      vue = comms_routing_new_vue(view)

      assert vue.component == "CommsRoutingNew"
      assert vue.class == "space-y-6 max-w-2xl"
      assert vue.ssr == false
      assert vue.props == Jason.decode!(Jason.encode!(vue.props))

      assert vue.handlers == %{
               "save" => Phoenix.LiveView.JS.push("save"),
               "validate" => Phoenix.LiveView.JS.push("validate")
             }

      assert vue.props == %{
               "page" => %{
                 "id" => "comms-routing-new-page",
                 "title" => "New Routing Rule",
                 "subtitle" =>
                   "Declare durable spacecraft use of a transport for a purpose and direction. Contacts and runtime Links are handled later.",
                 "breadcrumbs" => [
                   %{
                     "label" => mission.display_name,
                     "href" => "/missions/#{mission.mission_id}"
                   },
                   %{
                     "label" => "Comms",
                     "href" => "/missions/#{mission.mission_id}/comms"
                   },
                   %{
                     "label" => "Routing",
                     "href" => "/missions/#{mission.mission_id}/comms/routing"
                   },
                   %{"label" => "New Routing Rule", "href" => nil}
                 ]
               },
               "form" => %{
                 "id" => "routing-rule-form",
                 "sections" => %{
                   "intent" => %{"number" => "01", "title" => "Intent"},
                   "transport" => %{
                     "number" => "02",
                     "title" => "Spacecraft And Transport"
                   },
                   "policy" => %{"number" => "03", "title" => "Routing Policy"}
                 },
                 "fields" => %{
                   "display_name" => %{
                     "id" => "routing_rule_display_name",
                     "name" => "routing_rule[display_name]",
                     "type" => "text",
                     "label" => "Display Name",
                     "required" => true,
                     "value" => ""
                   },
                   "purpose_label" => %{
                     "id" => "routing_rule_purpose_label",
                     "name" => "routing_rule[purpose_label]",
                     "type" => "text",
                     "label" => "Purpose",
                     "required" => true,
                     "value" => "Live telemetry"
                   },
                   "spacecraft_id" => %{
                     "id" => "routing_rule_spacecraft_id",
                     "name" => "routing_rule[spacecraft_id]",
                     "type" => "select",
                     "label" => "Spacecraft",
                     "required" => true,
                     "value" => ""
                   },
                   "transport_ref" => %{
                     "id" => "routing_rule_transport_ref",
                     "name" => "routing_rule[transport_ref]",
                     "type" => "select",
                     "label" => "Transport",
                     "required" => true,
                     "value" => ""
                   },
                   "direction" => %{
                     "id" => "routing_rule_direction",
                     "name" => "routing_rule[direction]",
                     "type" => "select",
                     "label" => "Direction",
                     "required" => true,
                     "value" => "inbound"
                   },
                   "role" => %{
                     "id" => "routing_rule_role",
                     "name" => "routing_rule[role]",
                     "type" => "select",
                     "label" => "Role",
                     "required" => true,
                     "value" => "primary"
                   }
                 },
                 "actions" => %{
                   "submit" => %{
                     "id" => "create-routing-rule-button",
                     "label" => "Create Routing Rule"
                   },
                   "cancel" => %{
                     "id" => "cancel-routing-rule-link",
                     "label" => "Cancel",
                     "href" => "/missions/#{mission.mission_id}/comms/routing"
                   }
                 }
               },
               "options" => %{
                 "spacecraft" => [
                   %{"label" => "Select spacecraft", "value" => ""},
                   %{"label" => spacecraft.display_name, "value" => spacecraft.spacecraft_id}
                 ],
                 "transports" => [
                   %{"label" => "Select transport", "value" => ""},
                   %{
                     "label" => "#{transport.display_name} (v#{transport.version})",
                     "value" => "#{transport.transport_id}:#{transport.version}"
                   }
                 ],
                 "directions" => [
                   %{"label" => "Inbound", "value" => "inbound"},
                   %{"label" => "Outbound", "value" => "outbound"},
                   %{"label" => "Bidirectional", "value" => "bidirectional"}
                 ],
                 "roles" => [
                   %{"label" => "Primary", "value" => "primary"},
                   %{"label" => "Candidate", "value" => "candidate"},
                   %{"label" => "Contributing", "value" => "contributing"}
                 ]
               }
             }

      render_hook(view, "save", %{
        "routing_rule" => %{
          "display_name" => "Alpha live telemetry via Lab TCP",
          "purpose_label" => "Live telemetry",
          "spacecraft_id" => spacecraft.spacecraft_id,
          "transport_ref" => "#{transport.transport_id}:#{transport.version}",
          "direction" => "inbound",
          "role" => "primary"
        }
      })

      {target, _flash} = assert_redirect(view)

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

    test "preserves nested validate values in the Vue form DTO" do
      {conn, org, mission} = signed_in_org_and_mission()
      spacecraft = TestFixtures.persist_spacecraft!(mission, display_name: "Alpha", scid: 42)
      transport = persist_transport!(org.organization_id, mission.mission_id, "Lab TCP")

      {:ok, view, _html} = live(conn, ~p"/missions/#{mission.mission_id}/comms/routing/new")

      params = %{
        "display_name" => "Alpha outbound command",
        "purpose_label" => "Command relay",
        "spacecraft_id" => spacecraft.spacecraft_id,
        "transport_ref" => "#{transport.transport_id}:#{transport.version}",
        "direction" => "outbound",
        "role" => "candidate"
      }

      render_hook(view, "validate", %{"routing_rule" => params})

      values =
        view
        |> comms_routing_new_vue()
        |> Map.fetch!(:props)
        |> get_in(["form", "fields"])
        |> Map.new(fn {name, field} -> {name, field["value"]} end)

      assert values == params
    end

    test "preserves exact required and invalid save errors" do
      {conn, org, mission} = signed_in_org_and_mission()
      spacecraft = TestFixtures.persist_spacecraft!(mission, display_name: "Alpha", scid: 42)
      transport = persist_transport!(org.organization_id, mission.mission_id, "Lab TCP")
      valid_params = valid_routing_rule_params(spacecraft, transport)

      cases = [
        {%{"display_name" => "   "}, "Display name is required."},
        {%{"purpose_label" => "   "}, "Purpose is required."},
        {%{"spacecraft_id" => ""}, "Spacecraft is required."},
        {%{"transport_ref" => ""}, "Transport is required."},
        {%{"transport_ref" => "#{transport.transport_id}:0"}, "Transport is invalid."},
        {%{"direction" => "sideways"}, "Direction is invalid."},
        {%{"role" => "backup"}, "Role is invalid."}
      ]

      for {overrides, message} <- cases do
        {:ok, view, _html} = live(conn, ~p"/missions/#{mission.mission_id}/comms/routing/new")

        render_hook(view, "save", %{
          "routing_rule" => Map.merge(valid_params, overrides)
        })

        assert has_element?(view, "#flash-error[role='alert']", message)
      end

      assert RoutingRuleStore.list_routing_rules(org.organization_id, mission.mission_id) == []
    end

    test "trims text and preserves the parsed transport version when saving" do
      {conn, org, mission} = signed_in_org_and_mission()
      spacecraft = TestFixtures.persist_spacecraft!(mission, display_name: "Alpha", scid: 42)
      transport = persist_transport!(org.organization_id, mission.mission_id, "Lab TCP")

      {:ok, view, _html} = live(conn, ~p"/missions/#{mission.mission_id}/comms/routing/new")

      params =
        spacecraft
        |> valid_routing_rule_params(transport)
        |> Map.merge(%{
          "display_name" => "  Alpha trimmed routing rule  ",
          "purpose_label" => "  Live telemetry  "
        })

      render_hook(view, "save", %{"routing_rule" => params})

      {_target, _flash} = assert_redirect(view)
      assert [rule] = RoutingRuleStore.list_routing_rules(org.organization_id, mission.mission_id)
      assert rule.display_name == "Alpha trimmed routing rule"
      assert rule.purpose_label == "Live telemetry"
      assert rule.transport_id == transport.transport_id
      assert rule.transport_version == transport.version
    end

    test "preselects local spacecraft, preserves option order, and excludes foreign scope" do
      {conn, org, mission} = signed_in_org_and_mission()
      bravo = TestFixtures.persist_spacecraft!(mission, display_name: "Bravo", scid: 43)
      alpha = TestFixtures.persist_spacecraft!(mission, display_name: "Alpha", scid: 42)
      zulu_transport = persist_transport!(org.organization_id, mission.mission_id, "Zulu TCP")
      alpha_transport = persist_transport!(org.organization_id, mission.mission_id, "Alpha TCP")

      other_mission =
        TestFixtures.persist_mission!(org, slug: "secondary", display_name: "Secondary Mission")

      sibling_spacecraft =
        TestFixtures.persist_spacecraft!(other_mission, display_name: "Sibling", scid: 44)

      sibling_transport =
        persist_transport!(org.organization_id, other_mission.mission_id, "Sibling TCP")

      other_org = TestFixtures.persist_org!(display_name: "Remote Org", slug: "remote-org")
      remote_mission = TestFixtures.persist_mission!(other_org, slug: "remote")
      remote_spacecraft = TestFixtures.persist_spacecraft!(remote_mission, display_name: "Remote")

      remote_transport =
        persist_transport!(other_org.organization_id, remote_mission.mission_id, "Remote TCP")

      {:ok, view, _html} =
        live(
          conn,
          ~p"/missions/#{mission.mission_id}/comms/routing/new?spacecraft_id=#{bravo.spacecraft_id}"
        )

      props = comms_routing_new_vue(view).props

      assert props["form"]["fields"]["spacecraft_id"]["value"] == bravo.spacecraft_id

      local_spacecraft =
        [bravo, alpha]
        |> Enum.sort_by(& &1.spacecraft_id)
        |> Enum.map(&%{"label" => &1.display_name, "value" => &1.spacecraft_id})

      assert props["options"]["spacecraft"] ==
               [%{"label" => "Select spacecraft", "value" => ""} | local_spacecraft]

      assert props["options"]["transports"] == [
               %{"label" => "Select transport", "value" => ""},
               %{
                 "label" => "Alpha TCP (v#{alpha_transport.version})",
                 "value" => "#{alpha_transport.transport_id}:#{alpha_transport.version}"
               },
               %{
                 "label" => "Zulu TCP (v#{zulu_transport.version})",
                 "value" => "#{zulu_transport.transport_id}:#{zulu_transport.version}"
               }
             ]

      foreign_values = [
        sibling_spacecraft.spacecraft_id,
        remote_spacecraft.spacecraft_id,
        "#{sibling_transport.transport_id}:#{sibling_transport.version}",
        "#{remote_transport.transport_id}:#{remote_transport.version}"
      ]

      option_values =
        Enum.flat_map(
          [props["options"]["spacecraft"], props["options"]["transports"]],
          &Enum.map(&1, fn option -> option["value"] end)
        )

      refute Enum.any?(foreign_values, &(&1 in option_values))

      params =
        valid_routing_rule_params(bravo, alpha_transport)
        |> Map.put("spacecraft_id", sibling_spacecraft.spacecraft_id)

      render_hook(view, "save", %{"routing_rule" => params})

      assert has_element?(
               view,
               "#flash-error[role='alert']",
               "Failed to create routing rule: :spacecraft_not_found"
             )

      assert RoutingRuleStore.list_routing_rules(org.organization_id, mission.mission_id) == []
    end

    test "preserves humanized changeset error formatting" do
      {conn, org, mission} = signed_in_org_and_mission()
      spacecraft = TestFixtures.persist_spacecraft!(mission, display_name: "Alpha", scid: 42)
      transport = persist_transport!(org.organization_id, mission.mission_id, "Lab TCP")

      {:ok, view, _html} = live(conn, ~p"/missions/#{mission.mission_id}/comms/routing/new")

      params =
        spacecraft
        |> valid_routing_rule_params(transport)
        |> Map.put("display_name", String.duplicate("x", 201))

      render_hook(view, "save", %{"routing_rule" => params})

      assert has_element?(
               view,
               "#flash-error[role='alert']",
               "Display name should be at most 200 character(s)"
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

    test "spacecraft routing page exposes the client-only empty state DTO" do
      {conn, _org, mission} = signed_in_org_and_mission()
      spacecraft = TestFixtures.persist_spacecraft!(mission, display_name: "Alpha", scid: 42)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/missions/#{mission.mission_id}/spacecraft/#{spacecraft.spacecraft_id}/routing"
        )

      assert has_element?(view, "#spacecraft-routing-page")
      refute has_element?(view, "#new-spacecraft-routing-rule-link")
      refute has_element?(view, "#spacecraft-routing-rules")

      vue = spacecraft_routing_vue(view)

      assert vue.props == %{
               "page" => %{
                 "title" => "Comms Routing",
                 "subtitle" =>
                   "Durable routing rules that describe how this spacecraft uses mission transports.",
                 "breadcrumbs" => [
                   %{
                     "label" => mission.display_name,
                     "href" => "/missions/#{mission.mission_id}"
                   },
                   %{
                     "label" => "Spacecraft",
                     "href" => "/missions/#{mission.mission_id}/spacecraft"
                   },
                   %{
                     "label" => spacecraft.display_name,
                     "href" =>
                       "/missions/#{mission.mission_id}/spacecraft/#{spacecraft.spacecraft_id}"
                   },
                   %{"label" => "Routing", "href" => nil}
                 ],
                 "new_rule" => %{
                   "id" => "new-spacecraft-routing-rule-link",
                   "label" => "New Routing Rule",
                   "href" =>
                     "/missions/#{mission.mission_id}/comms/routing/new?spacecraft_id=#{spacecraft.spacecraft_id}"
                 },
                 "empty_state" => %{
                   "title" => "No routing rules",
                   "description" =>
                     "Create a routing rule to declare how this spacecraft should use a transport."
                 },
                 "rules_id" => "spacecraft-routing-rules",
                 "rows" => []
               }
             }
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
      refute has_element?(view, "#new-spacecraft-routing-rule-link")
      refute has_element?(view, "#spacecraft-routing-rules")
      assert html =~ "Comms Routing"
      assert html =~ rule.display_name
      assert html =~ "mission transports"

      vue = spacecraft_routing_vue(view)

      assert vue.props == %{
               "page" => %{
                 "title" => "Comms Routing",
                 "subtitle" =>
                   "Durable routing rules that describe how this spacecraft uses mission transports.",
                 "breadcrumbs" => [
                   %{
                     "label" => mission.display_name,
                     "href" => "/missions/#{mission.mission_id}"
                   },
                   %{
                     "label" => "Spacecraft",
                     "href" => "/missions/#{mission.mission_id}/spacecraft"
                   },
                   %{
                     "label" => spacecraft.display_name,
                     "href" =>
                       "/missions/#{mission.mission_id}/spacecraft/#{spacecraft.spacecraft_id}"
                   },
                   %{"label" => "Routing", "href" => nil}
                 ],
                 "new_rule" => %{
                   "id" => "new-spacecraft-routing-rule-link",
                   "label" => "New Routing Rule",
                   "href" =>
                     "/missions/#{mission.mission_id}/comms/routing/new?spacecraft_id=#{spacecraft.spacecraft_id}"
                 },
                 "empty_state" => %{
                   "title" => "No routing rules",
                   "description" =>
                     "Create a routing rule to declare how this spacecraft should use a transport."
                 },
                 "rules_id" => "spacecraft-routing-rules",
                 "rows" => [
                   %{
                     "id" => "spacecraft-routing-rule-#{rule.routing_rule_id}",
                     "purpose_label" => rule.purpose_label,
                     "display_name" => rule.display_name,
                     "direction" => "INBOUND",
                     "transport_name" => transport.display_name,
                     "role" => "PRIMARY",
                     "state" => "ENABLED",
                     "href" =>
                       "/missions/#{mission.mission_id}/comms/routing/#{rule.routing_rule_id}"
                   }
                 ]
               }
             }
    end

    test "spacecraft routing page preserves rule ordering, vocabulary, ids, and state" do
      {conn, org, mission} = signed_in_org_and_mission()
      spacecraft = TestFixtures.persist_spacecraft!(mission, display_name: "Alpha", scid: 42)
      transport = persist_transport!(org.organization_id, mission.mission_id, "Lab TCP")

      live_rule =
        persist_routing_rule!(org.organization_id, mission.mission_id, spacecraft, transport)

      disabled_rule =
        RoutingRule.new(%{
          mission_id: mission.mission_id,
          spacecraft_id: spacecraft.spacecraft_id,
          display_name: "Alpha command relay via Lab TCP",
          purpose_label: "Command relay",
          direction: :inbound,
          transport_id: transport.transport_id,
          transport_version: transport.version,
          role: :candidate,
          enabled?: false
        })

      assert {:ok, disabled_rule} =
               RoutingRuleStore.create_routing_rule(org.organization_id, disabled_rule)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/missions/#{mission.mission_id}/spacecraft/#{spacecraft.spacecraft_id}/routing"
        )

      rows = spacecraft_routing_vue(view).props["page"]["rows"]

      assert rows == [
               %{
                 "id" => "spacecraft-routing-rule-#{disabled_rule.routing_rule_id}",
                 "purpose_label" => "Command relay",
                 "display_name" => "Alpha command relay via Lab TCP",
                 "direction" => "INBOUND",
                 "transport_name" => transport.display_name,
                 "role" => "CANDIDATE",
                 "state" => "DISABLED",
                 "href" =>
                   "/missions/#{mission.mission_id}/comms/routing/#{disabled_rule.routing_rule_id}"
               },
               %{
                 "id" => "spacecraft-routing-rule-#{live_rule.routing_rule_id}",
                 "purpose_label" => live_rule.purpose_label,
                 "display_name" => live_rule.display_name,
                 "direction" => "INBOUND",
                 "transport_name" => transport.display_name,
                 "role" => "PRIMARY",
                 "state" => "ENABLED",
                 "href" =>
                   "/missions/#{mission.mission_id}/comms/routing/#{live_rule.routing_rule_id}"
               }
             ]
    end

    test "spacecraft routing page preserves scope and falls back to the transport id" do
      {conn, org, mission} = signed_in_org_and_mission()
      spacecraft = TestFixtures.persist_spacecraft!(mission, display_name: "Alpha", scid: 42)
      sibling = TestFixtures.persist_spacecraft!(mission, display_name: "Bravo", scid: 43)
      transport = persist_transport!(org.organization_id, mission.mission_id, "Lab TCP")
      mine = persist_routing_rule!(org.organization_id, mission.mission_id, spacecraft, transport)

      sibling_rule =
        persist_routing_rule!(org.organization_id, mission.mission_id, sibling, transport)

      other_mission =
        TestFixtures.persist_mission!(org, slug: "secondary", display_name: "Secondary Mission")

      other_spacecraft =
        TestFixtures.persist_spacecraft!(other_mission, display_name: "Secondary Alpha", scid: 44)

      other_transport =
        persist_transport!(org.organization_id, other_mission.mission_id, "Secondary TCP")

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

      assert {:ok, _archived_transport} =
               TransportStore.archive_transport(
                 org.organization_id,
                 mission.mission_id,
                 transport.transport_id
               )

      {:ok, view, _html} =
        live(
          conn,
          ~p"/missions/#{mission.mission_id}/spacecraft/#{spacecraft.spacecraft_id}/routing"
        )

      rows = spacecraft_routing_vue(view).props["page"]["rows"]

      assert rows == [
               %{
                 "id" => "spacecraft-routing-rule-#{mine.routing_rule_id}",
                 "purpose_label" => mine.purpose_label,
                 "display_name" => mine.display_name,
                 "direction" => "INBOUND",
                 "transport_name" => transport.transport_id,
                 "role" => "PRIMARY",
                 "state" => "ENABLED",
                 "href" => "/missions/#{mission.mission_id}/comms/routing/#{mine.routing_rule_id}"
               }
             ]

      foreign_ids =
        Enum.map([sibling_rule, other_mission_rule, other_org_rule], fn rule ->
          "spacecraft-routing-rule-#{rule.routing_rule_id}"
        end)

      refute Enum.any?(rows, &(&1["id"] in foreign_ids))
    end
  end

  defp spacecraft_routing_vue(view) do
    vue = LiveVue.Test.get_vue(view, id: "spacecraft-routing-page")

    assert vue.component == "SpacecraftRouting"
    assert vue.ssr == false
    assert is_binary(Jason.encode!(vue.props))

    vue
  end

  defp comms_routing_new_vue(view) do
    LiveVue.Test.get_vue(view, id: "comms-routing-new-component")
  end

  defp valid_routing_rule_params(spacecraft, transport) do
    %{
      "display_name" => "Alpha live telemetry via Lab TCP",
      "purpose_label" => "Live telemetry",
      "spacecraft_id" => spacecraft.spacecraft_id,
      "transport_ref" => "#{transport.transport_id}:#{transport.version}",
      "direction" => "inbound",
      "role" => "primary"
    }
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
