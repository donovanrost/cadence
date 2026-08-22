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
      assert has_element?(view, "#comms-transports")
      assert render(view) =~ "Transport"
      assert has_element?(view, "#comms-validation-page")
      assert has_element?(view, "#comms-validation-transport-setup")
      assert has_element?(view, "#comms-validation-advanced-runtime-identity")
      refute has_element?(view, "details[open] a", "Providers")
    end

    test "inlined validation surface includes spacecraft setup findings" do
      {conn, _org, mission} = signed_in_org_and_mission()
      _spacecraft = TestFixtures.persist_spacecraft!(mission, display_name: "Needs SCID")

      {:ok, view, _html} = live(conn, ~p"/missions/#{mission.mission_id}/comms")

      assert has_element?(view, "#comms-validation-spacecraft-setup")
      assert render(view) =~ "Findings"
      assert render(view) =~ "Spacecraft Setup"
      assert render(view) =~ "Spacecraft Profile"
      refute render(view) =~ "Link Assignments"
      refute render(view) =~ "Link Template"
    end

    test "inlined validation surface includes routing setup findings" do
      {conn, org, mission} = signed_in_org_and_mission()
      _spacecraft = TestFixtures.persist_spacecraft!(mission, display_name: "Needs Routing")
      _transport = persist_transport!(org.organization_id, mission.mission_id)

      {:ok, view, _html} = live(conn, ~p"/missions/#{mission.mission_id}/comms")

      assert has_element?(view, "#comms-validation-routing-setup")
      assert render(view) =~ "No Routing Rules configured"
      assert render(view) =~ ~p"/missions/#{mission.mission_id}/comms/routing/new"
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
