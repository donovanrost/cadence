defmodule CadenceWeb.SpacecraftEditLiveTest do
  use CadenceWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias CadenceWeb.TestFixtures

  defp signed_in_org_and_mission do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _ = TestFixtures.grant_membership!(user, org)
    mission = TestFixtures.persist_mission!(org, slug: "primary", display_name: "Primary Mission")
    {TestFixtures.member_conn(user), org, mission}
  end

  describe "mount" do
    test "renders the edit form" do
      {conn, _org, mission} = signed_in_org_and_mission()
      spacecraft = TestFixtures.persist_spacecraft!(mission, display_name: "Nova-1", scid: 42)

      {:ok, _view, html} =
        live(
          conn,
          ~p"/missions/#{mission.mission_id}/spacecraft/#{spacecraft.spacecraft_id}/edit"
        )

      assert html =~ "Spacecraft Identity"
      assert html =~ "Display Name"
      assert html =~ "SCID"
      assert html =~ "Save Identity"
    end

    test "renders through the spacecraft identity route" do
      {conn, _org, mission} = signed_in_org_and_mission()
      spacecraft = TestFixtures.persist_spacecraft!(mission, display_name: "Nova-1", scid: 42)

      {:ok, view, html} =
        live(
          conn,
          ~p"/missions/#{mission.mission_id}/spacecraft/#{spacecraft.spacecraft_id}/identity"
        )

      assert has_element?(view, "#spacecraft-edit-form")
      assert html =~ "Spacecraft Identity"
      assert html =~ "SCID"
    end
  end

  describe "save" do
    test "updates spacecraft identity and creates the managed source endpoint" do
      {conn, org, mission} = signed_in_org_and_mission()
      spacecraft = TestFixtures.persist_spacecraft!(mission, display_name: "Nova-1")

      {:ok, view, _html} =
        live(
          conn,
          ~p"/missions/#{mission.mission_id}/spacecraft/#{spacecraft.spacecraft_id}/edit"
        )

      assert {:error, {:live_redirect, %{to: target}}} =
               view
               |> form("#spacecraft-edit-form",
                 spacecraft: %{display_name: "Nova-1 Prime", scid: "51"}
               )
               |> render_submit()

      assert target == ~p"/missions/#{mission.mission_id}/spacecraft/#{spacecraft.spacecraft_id}"

      assert {:ok, updated_spacecraft} =
               Cadence.SpacecraftStore.fetch_spacecraft(
                 org.organization_id,
                 mission.mission_id,
                 spacecraft.spacecraft_id
               )

      assert updated_spacecraft.display_name == "Nova-1 Prime"
      assert updated_spacecraft.scid == 51

      assert [endpoint] =
               Cadence.SourceEndpoints.list_source_endpoints(
                 org.organization_id,
                 mission.mission_id,
                 spacecraft_id: spacecraft.spacecraft_id
               )

      assert endpoint.source_endpoint_id == "spacecraft_runtime:" <> spacecraft.spacecraft_id
      assert endpoint.display_name == "Nova-1 Prime"
      assert endpoint.scid == 51
      assert endpoint.metadata["managed_by"] == "spacecraft"
    end

    test "clearing SCID updates an existing managed source endpoint instead of leaving stale identity" do
      {conn, org, mission} = signed_in_org_and_mission()
      spacecraft = TestFixtures.persist_spacecraft!(mission, display_name: "Nova-1", scid: 42)

      assert {:ok, _endpoint} =
               Cadence.SourceEndpoints.ensure_managed_source_endpoint(
                 org.organization_id,
                 spacecraft
               )

      {:ok, view, _html} =
        live(
          conn,
          ~p"/missions/#{mission.mission_id}/spacecraft/#{spacecraft.spacecraft_id}/edit"
        )

      assert {:error, {:live_redirect, %{to: _target}}} =
               view
               |> form("#spacecraft-edit-form",
                 spacecraft: %{display_name: "Nova-1", scid: ""}
               )
               |> render_submit()

      assert {:ok, updated_spacecraft} =
               Cadence.SpacecraftStore.fetch_spacecraft(
                 org.organization_id,
                 mission.mission_id,
                 spacecraft.spacecraft_id
               )

      assert updated_spacecraft.scid == nil

      assert {:ok, endpoint} =
               Cadence.SourceEndpoints.fetch_source_endpoint(
                 org.organization_id,
                 mission.mission_id,
                 "spacecraft_runtime:" <> spacecraft.spacecraft_id
               )

      assert endpoint.scid == nil
    end

    test "invalid SCID stays on page with a validation message" do
      {conn, _org, mission} = signed_in_org_and_mission()
      spacecraft = TestFixtures.persist_spacecraft!(mission, display_name: "Nova-1")

      {:ok, view, _html} =
        live(
          conn,
          ~p"/missions/#{mission.mission_id}/spacecraft/#{spacecraft.spacecraft_id}/edit"
        )

      html =
        view
        |> form("#spacecraft-edit-form",
          spacecraft: %{display_name: "Nova-1", scid: "2048"}
        )
        |> render_submit()

      assert html =~ "SCID must be an integer from 0 to 1023."
    end
  end
end
