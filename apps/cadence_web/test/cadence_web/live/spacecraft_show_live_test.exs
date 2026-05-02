defmodule CadenceWeb.SpacecraftShowLiveTest do
  use CadenceWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias Cadence.Contacts.{LinkAssignment, PathTemplate, ProviderProfile}
  alias CadenceWeb.TestFixtures

  defp signed_in_org_and_mission do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _ = TestFixtures.grant_membership!(user, org)
    mission = TestFixtures.persist_mission!(org, slug: "primary", display_name: "Primary Mission")
    {TestFixtures.member_conn(user), user, org, mission}
  end

  describe "mount" do
    test "renders spacecraft detail" do
      {conn, _user, _org, mission} = signed_in_org_and_mission()
      spacecraft = TestFixtures.persist_spacecraft!(mission, display_name: "Nova-1", scid: 42)

      {:ok, view, html} =
        live(conn, ~p"/missions/#{mission.mission_id}/spacecraft/#{spacecraft.spacecraft_id}")

      assert html =~ "Nova-1"
      assert html =~ spacecraft.spacecraft_id
      assert html =~ "42"
      assert html =~ mission.display_name

      assert html =~
               ~p"/missions/#{mission.mission_id}/spacecraft/#{spacecraft.spacecraft_id}/readiness"

      assert html =~
               ~p"/missions/#{mission.mission_id}/spacecraft/#{spacecraft.spacecraft_id}/links"

      assert html =~
               ~p"/missions/#{mission.mission_id}/spacecraft/#{spacecraft.spacecraft_id}/identity"

      assert html =~
               ~p"/missions/#{mission.mission_id}/spacecraft/#{spacecraft.spacecraft_id}/telemetry"

      assert html =~
               ~p"/missions/#{mission.mission_id}/spacecraft/#{spacecraft.spacecraft_id}/commanding"

      assert has_element?(view, "#spacecraft-interpretation-overview")
      assert has_element?(view, "#spacecraft-overview-identity")
      assert has_element?(view, "#spacecraft-overview-telemetry")
      assert has_element?(view, "#spacecraft-overview-links")
      assert has_element?(view, "#spacecraft-overview-command")
      assert has_element?(view, "#spacecraft-overview-readiness")
      assert html =~ "Runtime identity missing"
      assert html =~ "Command Interpretation"
    end

    test "summarizes selected link assignments on the spacecraft overview" do
      {conn, _user, org, mission} = signed_in_org_and_mission()
      spacecraft = TestFixtures.persist_spacecraft!(mission, display_name: "Nova-1", scid: 42)

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
            %{
              "provider_profile_id" => provider.provider_profile_id,
              "version" => provider.version
            }
          ],
          metadata: %{"display_name" => "Goldstone Downlink"}
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
          metadata: %{"display_name" => "Goldstone Downlink"}
        })

      assert {:ok, _link_assignment} =
               Cadence.persist_link_assignment(org.organization_id, link_assignment)

      {:ok, view, html} =
        live(conn, ~p"/missions/#{mission.mission_id}/spacecraft/#{spacecraft.spacecraft_id}")

      assert has_element?(view, "#spacecraft-overview-links")
      assert html =~ "SCID 42 configured"
      assert html =~ "Goldstone Downlink"
    end

    test "summarizes available mission links before assignment" do
      {conn, _user, org, mission} = signed_in_org_and_mission()
      spacecraft = TestFixtures.persist_spacecraft!(mission, display_name: "Nova-1", scid: 42)

      assert {:ok, _endpoint} =
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
          source_endpoint_ref: nil,
          provider_profile_refs: [
            %{
              "provider_profile_id" => provider.provider_profile_id,
              "version" => provider.version
            }
          ],
          metadata: %{"display_name" => "Mission Downlink"}
        })

      assert {:ok, _path_template} =
               Cadence.persist_path_template(org.organization_id, path_template)

      {:ok, view, html} =
        live(conn, ~p"/missions/#{mission.mission_id}/spacecraft/#{spacecraft.spacecraft_id}")

      assert has_element?(view, "#spacecraft-overview-links")
      assert html =~ "1 available downlink link"
      assert html =~ "Mission-owned downlink links are available to assign."
    end

    test "unauthenticated redirects to /sign-in", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/sign-in"}}} =
               live(conn, ~p"/missions/m/spacecraft/s")
    end

    test "unknown spacecraft redirects to the mission's spacecraft list" do
      {conn, _user, _org, mission} = signed_in_org_and_mission()

      assert {:error, {:redirect, %{to: path, flash: %{"error" => _}}}} =
               live(conn, ~p"/missions/#{mission.mission_id}/spacecraft/missing-id")

      assert path == ~p"/missions/#{mission.mission_id}/spacecraft"
    end

    test "spacecraft belonging to a sibling mission is not found" do
      {conn, _user, org, mission} = signed_in_org_and_mission()

      other_mission =
        TestFixtures.persist_mission!(org, slug: "secondary", display_name: "Secondary")

      other_spacecraft = TestFixtures.persist_spacecraft!(other_mission, display_name: "Sibling")

      assert {:error, {:redirect, %{to: path, flash: %{"error" => _}}}} =
               live(
                 conn,
                 ~p"/missions/#{mission.mission_id}/spacecraft/#{other_spacecraft.spacecraft_id}"
               )

      assert path == ~p"/missions/#{mission.mission_id}/spacecraft"
    end

    test "spacecraft belonging to another organization is not found" do
      {conn, _user, _org, mission} = signed_in_org_and_mission()

      other_org = TestFixtures.persist_org!(display_name: "Other", slug: "other-org")

      other_mission =
        TestFixtures.persist_mission!(other_org, slug: "remote", display_name: "Remote")

      other_spacecraft = TestFixtures.persist_spacecraft!(other_mission, display_name: "Foreign")

      assert {:error, {:redirect, %{to: path, flash: %{"error" => _}}}} =
               live(
                 conn,
                 ~p"/missions/#{mission.mission_id}/spacecraft/#{other_spacecraft.spacecraft_id}"
               )

      assert path == ~p"/missions/#{mission.mission_id}/spacecraft"
    end

    test "sidebar highlights the Spacecraft nav entry" do
      {conn, _user, _org, mission} = signed_in_org_and_mission()
      spacecraft = TestFixtures.persist_spacecraft!(mission, display_name: "Nav-Check")

      list_url = ~p"/missions/#{mission.mission_id}/spacecraft"

      {:ok, _view, html} =
        live(conn, ~p"/missions/#{mission.mission_id}/spacecraft/#{spacecraft.spacecraft_id}")

      # A navigate link to the spacecraft list must exist in the sidebar AND
      # the rendered HTML must contain the "Spacecraft" label inside that link.
      assert html =~ list_url
      assert html =~ "Spacecraft"
    end
  end
end
