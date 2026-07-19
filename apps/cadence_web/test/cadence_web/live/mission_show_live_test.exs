defmodule CadenceWeb.MissionShowLiveTest do
  use CadenceWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias Cadence.Contacts.{LinkAssignment, PathTemplate, ProviderProfile}
  alias Cadence.Missions.Mission
  alias CadenceWeb.TestFixtures

  defp signed_in_conn do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!(display_name: "Cadence Ops", slug: "cadence-ops")
    _ = TestFixtures.grant_membership!(user, org)
    {TestFixtures.member_conn(user), org}
  end

  defp persist_mission!(org, slug, display_name) do
    mission =
      Mission.new(%{
        organization_id: org.organization_id,
        slug: slug,
        display_name: display_name
      })

    assert {:ok, persisted} = Cadence.Missions.persist_mission(mission)
    persisted
  end

  defp persist_ready_spacecraft_comms_setup!(org, mission) do
    spacecraft =
      TestFixtures.persist_spacecraft!(mission, display_name: "Alpha", scid: 42)

    assert {:ok, endpoint} =
             Cadence.ensure_managed_spacecraft_source_endpoint(org.organization_id, spacecraft)

    provider =
      ProviderProfile.new(%{
        mission_id: mission.mission_id,
        adapter_key: :tcp_socket,
        metadata: %{"display_name" => "TCP Provider"}
      })

    assert {:ok, provider} = Cadence.persist_provider_profile(org.organization_id, provider)

    path_template =
      PathTemplate.new(%{
        mission_id: mission.mission_id,
        direction: :downlink,
        selection_role: :selected,
        source_endpoint_ref: endpoint.source_endpoint_id,
        provider_profile_refs: [
          %{"provider_profile_id" => provider.provider_profile_id, "version" => provider.version}
        ],
        metadata: %{"display_name" => "Alpha downlink"}
      })

    assert {:ok, path_template} =
             Cadence.persist_path_template(org.organization_id, path_template)

    link_assignment =
      LinkAssignment.new(%{
        mission_id: mission.mission_id,
        spacecraft_id: spacecraft.spacecraft_id,
        source_endpoint_ref: endpoint.source_endpoint_id,
        path_template_id: path_template.path_template_id,
        path_template_version: path_template.version,
        direction: path_template.direction,
        selection_role: path_template.selection_role,
        provider_profile_refs: path_template.provider_profile_refs,
        metadata: %{"display_name" => "Alpha downlink"}
      })

    assert {:ok, _link_assignment} =
             Cadence.persist_link_assignment(org.organization_id, link_assignment)

    %{
      spacecraft: spacecraft,
      endpoint: endpoint,
      provider: provider,
      path_template: path_template
    }
  end

  describe "mount" do
    test "renders mission heading with the mission sidebar layout" do
      {conn, org} = signed_in_conn()
      mission = persist_mission!(org, "alpha", "Alpha Mission")

      {:ok, view, html} = live(conn, ~p"/missions/#{mission.mission_id}")

      assert has_element?(view, "#mission-overview-page")
      assert html =~ "Alpha Mission"
      assert html =~ "alpha"
      # Sidebar Overview nav item is highlighted.
      assert html =~ ~r/border-primary[^"]*".*Overview/s
      # Sidebar back link shows the org display_name.
      assert html =~ "Cadence Ops"
    end

    test "renders the spacecraft readiness table" do
      {conn, org} = signed_in_conn()
      mission = persist_mission!(org, "primary", "Primary Mission")

      {:ok, view, _html} = live(conn, ~p"/missions/#{mission.mission_id}")

      assert has_element?(view, "#spacecraft-readiness-section")
      assert has_element?(view, "#spacecraft-readiness-empty")
    end

    test "shows spacecraft readiness from SCID and runtime state" do
      {conn, org} = signed_in_conn()
      mission = persist_mission!(org, "primary", "Primary Mission")
      missing_scid = TestFixtures.persist_spacecraft!(mission, display_name: "Needs SCID")
      ready = persist_ready_spacecraft_comms_setup!(org, mission)

      {:ok, view, _html} = live(conn, ~p"/missions/#{mission.mission_id}")
      html = render(view)

      assert html =~ missing_scid.display_name
      assert html =~ "Set SCID"
      assert html =~ "Needs identity"

      assert html =~ ready.spacecraft.display_name

      assert html =~
               ~p"/missions/#{mission.mission_id}/spacecraft/#{ready.spacecraft.spacecraft_id}/readiness"
    end
  end

  describe "authorization" do
    test "redirects to /missions when mission id is unknown" do
      {conn, _org} = signed_in_conn()

      assert {:error, {:redirect, %{to: "/missions"}}} =
               live(conn, ~p"/missions/mission_unknown")
    end

    test "redirects to /missions when mission belongs to another org" do
      {conn, _mine} = signed_in_conn()
      other = TestFixtures.persist_org!(slug: "other-org")
      their_mission = persist_mission!(other, "theirs", "Their Mission")

      assert {:error, {:redirect, %{to: "/missions"}}} =
               live(conn, ~p"/missions/#{their_mission.mission_id}")
    end

    test "unauthenticated request redirects to /sign-in", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/sign-in"}}} =
               live(conn, ~p"/missions/mission_anything")
    end
  end
end
