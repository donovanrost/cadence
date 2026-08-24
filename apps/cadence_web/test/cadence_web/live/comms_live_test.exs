defmodule CadenceWeb.CommsLiveTest do
  use CadenceWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias Cadence.Applications.{ApplicationInstallations, HostContext}
  alias Cadence.Auth.Scope
  alias Cadence.Comms.TransportStore

  alias Cadence.Comms.Transport
  alias CadenceWeb.TestFixtures

  defp signed_in_org_and_mission do
    {conn, org, mission, _scope} = signed_in_scope_and_mission()
    {conn, org, mission}
  end

  defp signed_in_scope_and_mission do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    membership = TestFixtures.grant_membership!(user, org)
    mission = TestFixtures.persist_mission!(org, slug: "primary", display_name: "Primary Mission")

    scope =
      Scope.new(%{
        user: user,
        organization_id: org.organization_id,
        organization: org,
        organization_membership: membership
      })

    {TestFixtures.member_conn(user), org, mission, scope}
  end

  describe "overview" do
    test "renders the comms setup overview and section navigation" do
      {conn, _org, mission} = signed_in_org_and_mission()

      {:ok, view, _html} = live(conn, ~p"/missions/#{mission.mission_id}/comms")

      assert has_element?(view, "#comms-overview-page")
      assert has_element?(view, "#comms-overview-component")

      assert comms_overview_props(view) == %{
               "transport" => expected_transport_summary(mission.mission_id, []),
               "validation" =>
                 expected_validation_summary([
                   expected_transport_setup_group(mission.mission_id),
                   expected_advanced_runtime_identity_group()
                 ])
             }

      refute has_element?(view, "details[open] a", "Providers")
    end

    test "inlined validation surface includes spacecraft setup findings" do
      {conn, _org, mission} = signed_in_org_and_mission()
      spacecraft = TestFixtures.persist_spacecraft!(mission, display_name: "Needs SCID")

      {:ok, view, _html} = live(conn, ~p"/missions/#{mission.mission_id}/comms")

      validation = comms_overview_props(view)["validation"]

      assert validation ==
               expected_validation_summary([
                 expected_spacecraft_setup_group(spacecraft, mission.mission_id),
                 expected_transport_setup_group(mission.mission_id),
                 expected_advanced_runtime_identity_group()
               ])
    end

    test "inlined validation surface includes routing setup findings" do
      {conn, org, mission} = signed_in_org_and_mission()
      spacecraft = TestFixtures.persist_spacecraft!(mission, display_name: "Needs Routing")
      transport = persist_transport!(org.organization_id, mission.mission_id)

      {:ok, view, _html} = live(conn, ~p"/missions/#{mission.mission_id}/comms")

      overview = comms_overview_props(view)

      assert overview["transport"] ==
               expected_transport_summary(mission.mission_id, [
                 %{
                   "id" => "comms-transport-#{transport.transport_id}",
                   "display_name" => "Lab TCP",
                   "metadata" => "tcp_socket · inbound · v#{transport.version}",
                   "href" =>
                     "/missions/#{mission.mission_id}/comms/transports/#{transport.transport_id}"
                 }
               ])

      assert Enum.find(
               overview["validation"]["finding_groups"],
               &(&1["id"] == "comms-validation-routing-setup")
             ) == %{
               "id" => "comms-validation-routing-setup",
               "title" => "Routing Setup",
               "description" => "Durable rules for how spacecraft use mission Transports.",
               "findings" => [
                 expected_finding(
                   "No Routing Rules configured",
                   "Create Routing Rules to declare how spacecraft use mission Transports.",
                   "blocked",
                   "Blocking",
                   "Create Routing Rule",
                   "/missions/#{mission.mission_id}/comms/routing/new"
                 ),
                 expected_finding(
                   "Needs Routing has no Routing Rule",
                   "Add a Routing Rule when this spacecraft should use a mission Transport.",
                   "attention",
                   "Warning",
                   "Review Routing",
                   "/missions/#{mission.mission_id}/spacecraft/#{spacecraft.spacecraft_id}/routing"
                 )
               ]
             }
    end

    test "expands the Comms section and marks Overview active on /comms" do
      {conn, _org, mission} = signed_in_org_and_mission()

      {:ok, view, _html} = live(conn, ~p"/missions/#{mission.mission_id}/comms")

      assert has_element?(view, "details[open] summary", "Comms")

      assert has_element?(
               view,
               ~s|details[open] a[href="/missions/#{mission.mission_id}/comms"].text-primary|,
               "Overview"
             )

      assert has_element?(
               view,
               ~s|details[open] a[href="/missions/#{mission.mission_id}/comms"] span.bg-primary|
             )

      assert has_element?(
               view,
               ~s|details[open] a[href="/missions/#{mission.mission_id}/comms/validation"]|,
               "Validation"
             )
    end

    test "renders dedicated validation page grouped by setup owner" do
      {conn, _org, mission} = signed_in_org_and_mission()
      _spacecraft = TestFixtures.persist_spacecraft!(mission, display_name: "Needs SCID")

      {:ok, view, _html} = live(conn, ~p"/missions/#{mission.mission_id}/comms/validation")

      assert has_element?(view, "#comms-validation-page")
      assert has_element?(view, "#comms-validation-spacecraft-setup")
      assert has_element?(view, "#comms-validation-transport-setup")
      assert render(view) =~ "Spacecraft Setup"
      assert render(view) =~ "Transport Setup"

      assert has_element?(
               view,
               ~s|details[open] a[href="/missions/#{mission.mission_id}/comms/validation"].text-primary|,
               "Validation"
             )

      refute render(view) =~ "Link Template"
      refute render(view) =~ "Link Assignments"
    end

    test "projects required application installation status into Comms Validation" do
      {conn, _org, mission, _scope} = signed_in_scope_and_mission()
      profile = TestFixtures.persist_spacecraft_profile!(mission, display_name: "Aurora Bus")

      spacecraft =
        TestFixtures.persist_spacecraft!(mission,
          display_name: "Nova-1",
          spacecraft_type_id: profile.spacecraft_type_id,
          spacecraft_type_version: profile.version
        )

      {:ok, view, _html} =
        live(conn, ~p"/missions/#{mission.mission_id}/comms/validation")

      finding_id =
        "#comms-validation-application-#{spacecraft.spacecraft_id}-telemetry_decom"

      assert has_element?(view, finding_id)
      assert has_element?(view, "#{finding_id} h3", "Nova-1 — Telemetry Decom: Not installed")

      assert has_element?(
               view,
               "#{finding_id} a[href='/missions/#{mission.mission_id}/spacecraft/#{spacecraft.spacecraft_id}/applications']",
               "Review applications"
             )
    end

    test "projects installed application status without application-specific Comms code" do
      {conn, _org, mission, scope} = signed_in_scope_and_mission()
      profile = TestFixtures.persist_spacecraft_profile!(mission, display_name: "Aurora Bus")

      spacecraft =
        TestFixtures.persist_spacecraft!(mission,
          display_name: "Nova-1",
          spacecraft_type_id: profile.spacecraft_type_id,
          spacecraft_type_version: profile.version
        )

      assert {:ok, _installation} =
               ApplicationInstallations.install(
                 scope,
                 HostContext.spacecraft(mission.mission_id, spacecraft.spacecraft_id),
                 "telemetry_decom"
               )

      {:ok, view, _html} =
        live(conn, ~p"/missions/#{mission.mission_id}/comms/validation")

      finding_id =
        "#comms-validation-application-#{spacecraft.spacecraft_id}-telemetry_decom"

      assert has_element?(view, finding_id)
      assert has_element?(view, "#{finding_id} h3", "Nova-1 — Telemetry Decom: Not configured")

      assert has_element?(
               view,
               "#{finding_id} a[href='/missions/#{mission.mission_id}/spacecraft/#{spacecraft.spacecraft_id}/applications/telemetry_decom']",
               "Review application"
             )

      refute has_element?(view, finding_id, "Configure telemetry")
    end

    test "leaves the Comms section collapsed when not on a /comms route" do
      {conn, _org, mission} = signed_in_org_and_mission()

      {:ok, view, _html} = live(conn, ~p"/missions/#{mission.mission_id}")

      assert has_element?(view, "details:not([open]) summary", "Comms")
      refute has_element?(view, "details[open] summary", "Comms")
    end
  end

  defp comms_overview_props(view) do
    vue = LiveVue.Test.get_vue(view, id: "comms-overview-component")
    assert vue.component == "CommsOverview"
    vue.props["overview"]
  end

  defp expected_transport_summary(mission_id, rows) do
    count = length(rows)

    %{
      "id" => "comms-transports",
      "eyebrow" => "Transport",
      "count" => count,
      "count_label" => if(count == 1, do: "transport configured", else: "transports configured"),
      "description" =>
        "Transports describe durable capabilities for moving bytes. Routing rules will decide how spacecraft use those capabilities.",
      "status" =>
        if(count == 0,
          do: %{"tone" => "attention", "label" => "Needs Work"},
          else: %{"tone" => "ready", "label" => "Ready"}
        ),
      "empty" => rows == [],
      "empty_state" => %{
        "title" => "No transports configured",
        "description" => "Add a transport to describe a byte-moving capability for this mission.",
        "action_label" => "Add a transport",
        "action_href" => "/missions/#{mission_id}/comms/transports/new"
      },
      "rows" => rows,
      "manage_label" => "Manage transports →",
      "manage_href" => "/missions/#{mission_id}/comms/transports",
      "add_label" => "+ Add a transport",
      "add_href" => "/missions/#{mission_id}/comms/transports/new"
    }
  end

  defp expected_validation_summary(finding_groups) do
    finding_count = Enum.sum(Enum.map(finding_groups, &length(&1["findings"])))

    %{
      "id" => "comms-validation-page",
      "eyebrow" => "Setup Checks",
      "title" => "What's missing or broken",
      "description" => "Checks on saved configuration for spacecraft on this mission.",
      "status" => %{"tone" => "attention", "label" => "#{finding_count} Findings"},
      "empty" => false,
      "empty_state" => %{
        "title" => "All clear",
        "description" => "The saved configuration looks consistent."
      },
      "findings_id" => "comms-validation-findings",
      "finding_groups" => finding_groups
    }
  end

  defp expected_spacecraft_setup_group(spacecraft, mission_id) do
    identity_href =
      "/missions/#{mission_id}/spacecraft/#{spacecraft.spacecraft_id}/identity"

    %{
      "id" => "comms-validation-spacecraft-setup",
      "title" => "Spacecraft Setup",
      "description" =>
        "Identity, Spacecraft Profile, and application setup owned by each spacecraft.",
      "findings" => [
        expected_finding(
          "#{spacecraft.display_name} is missing SCID",
          "Set spacecraft identity so Cadence can associate interpreted bytes with this spacecraft.",
          "blocked",
          "Blocking",
          "Edit identity",
          identity_href
        ),
        expected_finding(
          "#{spacecraft.display_name} has no Spacecraft Profile",
          "Select a Spacecraft Profile to pin the byte-interpretation contract.",
          "attention",
          "Warning",
          "Select profile",
          identity_href
        )
      ]
    }
  end

  defp expected_transport_setup_group(mission_id) do
    %{
      "id" => "comms-validation-transport-setup",
      "title" => "Transport Setup",
      "description" => "Durable byte-moving capabilities available to this mission.",
      "findings" => [
        expected_finding(
          "No Transports configured",
          "Add a Transport to describe a durable byte-moving capability for this mission.",
          "blocked",
          "Blocking",
          "Add Transport",
          "/missions/#{mission_id}/comms/transports/new"
        )
      ]
    }
  end

  defp expected_advanced_runtime_identity_group do
    %{
      "id" => "comms-validation-advanced-runtime-identity",
      "title" => "Internal Runtime Artifacts",
      "description" =>
        "Diagnostics for internal execution artifacts derived from spacecraft routing setup.",
      "findings" => [
        expected_finding(
          "No internal telemetry identities configured",
          "Internal runtime diagnostics need telemetry identities so ingress can resolve ownership.",
          "blocked",
          "Blocking"
        ),
        expected_finding(
          "No internal routing artifacts configured",
          "Create Routing Rules to materialize internal runtime artifacts used during execution.",
          "blocked",
          "Blocking"
        ),
        expected_finding(
          "No transport compatibility providers configured",
          "Transports materialize provider records for existing runtime integrations.",
          "attention",
          "Warning"
        ),
        expected_finding(
          "No advanced protocol behaviors configured",
          "Advanced protocol behaviors are optional runtime-local extensions such as uplink gateways and heartbeat monitors.",
          "attention",
          "Warning"
        )
      ]
    }
  end

  defp expected_finding(title, body, tone, label, action_label \\ nil, action_href \\ nil) do
    %{
      "id" => nil,
      "title" => title,
      "body" => body,
      "action_label" => action_label,
      "action_href" => action_href,
      "status" => %{"tone" => tone, "label" => label}
    }
  end

  defp persist_transport!(organization_id, mission_id) do
    transport =
      Transport.new(%{
        mission_id: mission_id,
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

    assert {:ok, persisted} =
             TransportStore.persist_transport(organization_id, transport)

    persisted
  end
end
