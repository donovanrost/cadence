defmodule CadenceWeb.OpsDashboardLibraryLiveTest do
  use CadenceWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias Cadence.Dashboards.{Management, Placement, PlacementEditor, WidgetDef}
  alias CadenceWeb.TestFixtures

  test "library versions expose update posture without rewriting pinned consumers" do
    {conn, user, org, mission} = signed_in_user_org_and_mission()
    widget_v1 = widget_definition("Reusable battery voltage")

    assert {:ok, item} =
             Management.create_library_item(
               org.organization_id,
               mission.mission_id,
               %{
                 "name" => "Battery voltage trend",
                 "description" => "Shared flight power widget",
                 "widget_definition" => widget_v1
               },
               created_by: user.user_id
             )

    dashboard =
      TestFixtures.persist_dashboard_document!(mission,
        name: "Pinned consumer",
        placements: [library_placement(item.dashboard_library_item_id, 1)]
      )

    widget_v2 = Map.put(widget_v1, :title, "Reusable battery voltage v2")

    assert {:ok, item_v2} =
             Management.add_library_version(
               org.organization_id,
               mission.mission_id,
               item.dashboard_library_item_id,
               widget_v2,
               created_by: user.user_id,
               change_summary: "Tune title"
             )

    assert item_v2.latest_version == 2

    assert %{consumer_count: 1, outdated_count: 1, consumers: [consumer]} =
             Management.library_usage(org.organization_id, mission.mission_id, item_v2)

    assert consumer.dashboard_id == dashboard.dashboard_id
    assert consumer.version == 1
    assert consumer.update_available?

    assert {:ok, persisted} =
             Cadence.Dashboards.fetch_document(
               org.organization_id,
               mission.mission_id,
               dashboard.dashboard_id
             )

    assert [%Placement{content_kind: :library, library_version: 1}] = persisted.placements

    {:ok, library, _html} =
      live(conn, ~p"/missions/#{mission.mission_id}/ops/dashboards/library")

    assert has_element?(library, "#ops-context-rail")
    assert has_element?(library, "#dashboard-library-item-#{item.dashboard_library_item_id}")

    assert has_element?(
             library,
             "#library-version-#{List.first(Management.list_library_versions(item.dashboard_library_item_id)).dashboard_library_version_id}"
           )
  end

  test "adding a library item stages the exact version and persists only on Editor Save" do
    {conn, user, org, mission} = signed_in_user_org_and_mission()
    dashboard = TestFixtures.persist_dashboard_document!(mission, name: "Library target")

    assert {:ok, item} =
             Management.create_library_item(
               org.organization_id,
               mission.mission_id,
               %{"name" => "Reusable trend", "widget_definition" => widget_definition("Trend")},
               created_by: user.user_id
             )

    path =
      ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}/edit?#{[candidate_source: "library", candidate_library_item_id: item.dashboard_library_item_id, candidate_library_version: 1]}"

    {:ok, editor, _html} = live(conn, path)
    assert has_element?(editor, ~s(#ops-dashboard-show-page[data-editor-dirty="true"]))

    assert {:ok, %{placements: []}} =
             Cadence.Dashboards.fetch_document(
               org.organization_id,
               mission.mission_id,
               dashboard.dashboard_id
             )

    editor |> element("#dashboard-editor-save") |> render_click()

    assert {:ok, persisted} =
             Cadence.Dashboards.fetch_document(
               org.organization_id,
               mission.mission_id,
               dashboard.dashboard_id
             )

    assert [placement] = persisted.placements
    assert placement.content_kind == :library
    assert placement.library_widget_id == item.dashboard_library_item_id
    assert placement.library_version == 1
  end

  defp widget_definition(title) do
    params = %{
      "type" => "time_series",
      "title" => title,
      "mode" => "context",
      "spacecraft_id" => "",
      "binding_source" => "telemetry"
    }

    assert {:ok, placement} = PlacementEditor.build_placement(params, ["BATTERY_V"], :add_widget)
    WidgetDef.to_map(placement.widget_def)
  end

  defp library_placement(item_id, version) do
    %Placement{
      placement_id: Cadence.Ids.new("placement"),
      layout: %{x: 0, y: 0, w: 6, h: 6},
      content_kind: :library,
      library_widget_id: item_id,
      library_version: version
    }
  end

  defp signed_in_user_org_and_mission do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org)
    mission = TestFixtures.persist_mission!(org, slug: "dashboard-library")
    {TestFixtures.member_conn(user), user, org, mission}
  end
end
