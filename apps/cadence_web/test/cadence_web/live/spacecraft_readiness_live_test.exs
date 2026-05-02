defmodule CadenceWeb.SpacecraftReadinessLiveTest do
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
    {TestFixtures.member_conn(user), org, mission}
  end

  describe "mount" do
    test "renders spacecraft readiness with missing identity and interpretation state" do
      {conn, _org, mission} = signed_in_org_and_mission()
      spacecraft = TestFixtures.persist_spacecraft!(mission, display_name: "Nova-1")

      {:ok, view, html} =
        live(
          conn,
          ~p"/missions/#{mission.mission_id}/spacecraft/#{spacecraft.spacecraft_id}/readiness"
        )

      assert has_element?(view, "#spacecraft-readiness-page")
      assert has_element?(view, "#spacecraft-readiness-identity")
      assert has_element?(view, "#spacecraft-readiness-telemetry")
      assert has_element?(view, "#spacecraft-readiness-links")
      assert has_element?(view, "#spacecraft-readiness-command")

      assert html =~ "Mission Comms owns shared network paths"
      assert html =~ "Missing SCID"
      assert html =~ "Not configured"
      assert html =~ "Needs downlink"
      assert html =~ "Command Interpretation"

      assert html =~
               ~p"/missions/#{mission.mission_id}/spacecraft/#{spacecraft.spacecraft_id}/identity"

      assert html =~
               ~p"/missions/#{mission.mission_id}/spacecraft/#{spacecraft.spacecraft_id}/telemetry"

      assert html =~
               ~p"/missions/#{mission.mission_id}/spacecraft/#{spacecraft.spacecraft_id}/commanding"
    end

    test "shows runtime identity and selected downlink link assignment" do
      {conn, org, mission} = signed_in_org_and_mission()
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
        live(
          conn,
          ~p"/missions/#{mission.mission_id}/spacecraft/#{spacecraft.spacecraft_id}/readiness"
        )

      assert has_element?(view, "#spacecraft-readiness-identity")
      assert html =~ endpoint.source_endpoint_id
      assert html =~ "Goldstone Downlink"
      assert html =~ "This spacecraft has a selected provider-backed downlink link template."

      assert html =~
               ~p"/missions/#{mission.mission_id}/spacecraft/#{spacecraft.spacecraft_id}/links"
    end

    test "shows available mission link templates as assignment-ready" do
      {conn, org, mission} = signed_in_org_and_mission()
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
        live(
          conn,
          ~p"/missions/#{mission.mission_id}/spacecraft/#{spacecraft.spacecraft_id}/readiness"
        )

      assert has_element?(view, "#spacecraft-readiness-links")
      assert html =~ endpoint.source_endpoint_id
      assert html =~ "Needs assignment"
      assert html =~ "Assign an available provider-backed downlink link template"
      assert html =~ "1 available downlink link template"

      assert html =~
               ~p"/missions/#{mission.mission_id}/spacecraft/#{spacecraft.spacecraft_id}/links"
    end

    test "unauthenticated redirects to /sign-in", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/sign-in"}}} =
               live(conn, ~p"/missions/m/spacecraft/s/readiness")
    end
  end
end
