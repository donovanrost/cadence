defmodule CadenceWeb.SpacecraftLinksLiveTest do
  use CadenceWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias Cadence.Contacts.{LinkAssignment, PathTemplate, ProviderProfile, TransportProfile}
  alias CadenceWeb.TestFixtures

  defp signed_in_org_and_mission do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _ = TestFixtures.grant_membership!(user, org)
    mission = TestFixtures.persist_mission!(org, slug: "primary", display_name: "Primary Mission")
    {TestFixtures.member_conn(user), org, mission}
  end

  describe "mount" do
    test "shows missing runtime identity before links can be assigned" do
      {conn, _org, mission} = signed_in_org_and_mission()
      spacecraft = TestFixtures.persist_spacecraft!(mission, display_name: "Nova-1")

      {:ok, view, html} =
        live(
          conn,
          ~p"/missions/#{mission.mission_id}/spacecraft/#{spacecraft.spacecraft_id}/links"
        )

      assert has_element?(view, "#spacecraft-links-page")
      assert has_element?(view, "#spacecraft-links-runtime-identity-empty")
      assert html =~ "Runtime Identity"
      assert html =~ "Not created"
      assert html =~ "Create or sync runtime identity"

      assert html =~
               ~p"/missions/#{mission.mission_id}/spacecraft/#{spacecraft.spacecraft_id}/identity"
    end

    test "lists assigned mission link templates for the spacecraft runtime identity" do
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

      transport =
        TransportProfile.new(%{
          mission_id: mission.mission_id,
          family_key: :heartbeat_monitor,
          target_scope: :path,
          metadata: %{"display_name" => "Heartbeat Monitor"}
        })

      assert {:ok, transport} = Cadence.persist_transport_profile(org.organization_id, transport)

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
          transport_profile_refs: [
            %{
              "transport_profile_id" => transport.transport_profile_id,
              "version" => transport.version
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
          provider_path_ref: "goldstone-downlink",
          provider_profile_refs: path_template.provider_profile_refs,
          transport_profile_refs: path_template.transport_profile_refs,
          metadata: %{"display_name" => "Goldstone Downlink"}
        })

      assert {:ok, link_assignment} =
               Cadence.persist_link_assignment(org.organization_id, link_assignment)

      available_template =
        PathTemplate.new(%{
          mission_id: mission.mission_id,
          direction: :downlink,
          selection_role: :candidate,
          source_endpoint_ref: nil,
          provider_profile_refs: [
            %{
              "provider_profile_id" => provider.provider_profile_id,
              "version" => provider.version
            }
          ],
          metadata: %{"display_name" => "Shared TCP Downlink"}
        })

      assert {:ok, available_template} =
               Cadence.persist_path_template(org.organization_id, available_template)

      sibling = TestFixtures.persist_spacecraft!(mission, display_name: "Nova-2", scid: 43)

      assert {:ok, sibling_endpoint} =
               Cadence.ensure_managed_spacecraft_source_endpoint(org.organization_id, sibling)

      sibling_template =
        PathTemplate.new(%{
          mission_id: mission.mission_id,
          direction: :uplink,
          selection_role: :selected,
          source_endpoint_ref: sibling_endpoint.source_endpoint_id,
          provider_profile_refs: [
            %{
              "provider_profile_id" => provider.provider_profile_id,
              "version" => provider.version
            }
          ],
          metadata: %{"display_name" => "Sibling Uplink"}
        })

      assert {:ok, _sibling_template} =
               Cadence.persist_path_template(org.organization_id, sibling_template)

      {:ok, view, html} =
        live(
          conn,
          ~p"/missions/#{mission.mission_id}/spacecraft/#{spacecraft.spacecraft_id}/links"
        )

      assert has_element?(view, "#spacecraft-link-assignments-table")
      assert html =~ "1 assigned / 3 mission templates"
      assert html =~ "Mission Link Templates"
      assert html =~ "New Mission Link"
      assert html =~ "Goldstone Downlink"
      assert html =~ "Shared TCP Downlink"
      assert html =~ "Sibling Uplink"
      assert html =~ "Assigned"
      assert html =~ "Available"
      assert html =~ "Available"
      assert html =~ "DOWNLINK"
      assert html =~ "TCP Provider v1"
      assert html =~ "Heartbeat Monitor v1"
      refute html =~ "Runtime Identity: spacecraft_runtime:#{sibling.spacecraft_id}"

      assert has_element?(
               view,
               "a[href='/missions/#{mission.mission_id}/comms/link-templates/#{path_template.path_template_id}']",
               "View"
             )

      updated_html =
        view
        |> element(
          "button[phx-click='assign_link'][phx-value-path-template-id='#{available_template.path_template_id}']",
          "Assign"
        )
        |> render_click()

      assert updated_html =~ "2 assigned / 3 mission templates"

      assert {:ok, assigned_template} =
               Cadence.fetch_path_template(
                 org.organization_id,
                 mission.mission_id,
                 available_template.path_template_id
               )

      assert assigned_template.version == available_template.version
      assert assigned_template.source_endpoint_ref == nil

      assert Enum.any?(
               Cadence.list_link_assignments(org.organization_id, mission.mission_id),
               &(&1.path_template_id == available_template.path_template_id and
                   &1.source_endpoint_ref == endpoint.source_endpoint_id)
             )

      unassigned_html =
        view
        |> element(
          "button[phx-click='unassign_link'][phx-value-link-assignment-id='#{link_assignment.link_assignment_id}']",
          "Unassign"
        )
        |> render_click()

      assert unassigned_html =~ "1 assigned / 3 mission templates"

      assert {:error, :contact_link_assignment_not_found} =
               Cadence.fetch_link_assignment(
                 org.organization_id,
                 mission.mission_id,
                 link_assignment.link_assignment_id
               )
    end

    test "unauthenticated redirects to /sign-in", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/sign-in"}}} =
               live(conn, ~p"/missions/m/spacecraft/s/links")
    end
  end
end
