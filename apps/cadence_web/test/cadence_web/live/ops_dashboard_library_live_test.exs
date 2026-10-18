defmodule CadenceWeb.OpsDashboardLibraryLiveTest do
  use CadenceWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias Cadence.Dashboards.{DocumentCodec, Documents, Management, WidgetDef}
  alias CadenceWeb.TestFixtures

  @fixture Path.expand(
             "../../../../cadence/test/fixtures/dashboards/value_tile_latest.v1.json",
             __DIR__
           )

  test "dashboard library mounts its compiled contribution without an installation" do
    {conn, mission} = signed_in()

    {:ok, view, _html} = live(conn, ~p"/missions/#{mission.mission_id}/ops/dashboards/library")

    page = page(view)
    assert page["id"] == "dashboards.library"
    assert page["status"] == "ready"
    assert page["context"]["missionId"] == mission.mission_id
    assert page["data"]["model"]["items"] == []
  end

  test "dashboard library remains authentication scoped" do
    {_conn, _user, _organization, mission} = signed_in_user_org_and_mission()

    assert {:error, {:redirect, %{to: "/sign-in"}}} =
             live(build_conn(), ~p"/missions/#{mission.mission_id}/ops/dashboards/library")
  end

  test "host creates once, binds selected versions and target drafts, and rejects retired tokens" do
    {conn, user, org, mission} = signed_in_user_org_and_mission()
    path = "/missions/#{mission.mission_id}/ops/dashboards/library"
    base = DocumentCodec.load!(@fixture)

    {:ok, document} =
      Documents.persist(org.organization_id, %{
        base
        | organization_id: org.organization_id,
          mission_id: mission.mission_id,
          dashboard_id: "library-target"
      })

    json = hd(document.placements).widget_def |> WidgetDef.to_map() |> Jason.encode!()
    {:ok, view, _} = live(conn, path)
    page = page(view)

    command = %{
      "name" => "Power",
      "description" => "Reusable",
      "change_summary" => "Initial",
      "widget_json" => json
    }

    assert action(view, path, %{page | "token" => "wrong"}, "create_item", 1, command)["ok"] ==
             false

    reply = action(view, path, page, "create_item", 1, command)["snapshot"]
    assert reply["status"] == "ok"
    assert action(view, path, page, "create_item", 1, command)["snapshot"]["status"] == "rejected"
    id = reply["receipt"]["item_id"]
    selected_path = path <> "?item_id=#{id}&version=1&target_id=library-target"
    refresh(view, selected_path)
    selected = page(view)
    refute selected["token"] == page["token"]
    assert action(view, path, page, "create_item", 2, command)["ok"] == false

    pin = %{
      "item_id" => id,
      "version" => 1,
      "dashboard_id" => document.dashboard_id,
      "expected_version" => 1
    }

    assert action(view, selected_path, selected, "add_to_draft", 1, %{pin | "version" => 2})[
             "snapshot"
           ]["status"] == "rejected"

    assert action(view, selected_path, selected, "add_to_draft", 1, pin)["snapshot"]["status"] ==
             "ok"

    refresh(view, selected_path)
    assert page(view)["data"]["model"]["target"]["version"] == 2
    [item] = Management.list_library_items(org.organization_id, mission.mission_id)
    assert item.created_by == user.user_id
  end

  test "stale library append remains locked through refresh until explicit reload" do
    {conn, _, org, mission} = signed_in_user_org_and_mission()

    widget =
      DocumentCodec.load!(@fixture).placements
      |> hd()
      |> Map.fetch!(:widget_def)
      |> WidgetDef.to_map()

    {:ok, item} =
      Management.create_library_item(org.organization_id, mission.mission_id, %{
        "name" => "Power",
        "widget_definition" => widget
      })

    path =
      "/missions/#{mission.mission_id}/ops/dashboards/library?item_id=#{item.dashboard_library_item_id}"

    {:ok, view, _} = live(conn, path)
    page = page(view)

    {:ok, _} =
      Management.add_library_version(
        org.organization_id,
        mission.mission_id,
        item.dashboard_library_item_id,
        widget,
        expected_version: 1
      )

    command = %{
      "item_id" => item.dashboard_library_item_id,
      "expected_version" => 1,
      "change_summary" => "Stale",
      "widget_json" => Jason.encode!(widget)
    }

    assert action(view, path, page, "add_version", 1, command)["snapshot"]["status"] == "conflict"
    refresh(view, path)
    assert page(view)["data"]["phase"] == "review"
    command = %{command | "expected_version" => 2}
    assert action(view, path, page, "add_version", 2, command)["snapshot"]["status"] == "rejected"
    assert action(view, path, page, "reload_library", 2, %{})["snapshot"]["status"] == "ok"
    assert action(view, path, page, "add_version", 3, command)["snapshot"]["status"] == "ok"
    :ok = Cadence.Auth.revoke_user_session(get_session(conn, :user_session_token))

    render_hook(view, "host:ops-page", %{
      "id" => page["id"],
      "token" => page["token"],
      "path" => path,
      "event" => "reload_library",
      "input" => %{"sequence" => 4, "command" => %{}}
    })

    assert_redirect(view, "/sign-in")
  end

  defp signed_in do
    {conn, _user, _organization, mission} = signed_in_user_org_and_mission()
    {conn, mission}
  end

  defp signed_in_user_org_and_mission do
    user = TestFixtures.persist_user!()
    organization = TestFixtures.persist_org!()
    TestFixtures.grant_membership!(user, organization)
    mission = TestFixtures.persist_mission!(organization)
    {TestFixtures.member_conn(user), user, organization, mission}
  end

  defp page(view),
    do: LiveVue.Test.get_vue(view, id: "application-shell").props["snapshot"]["ops_page"]

  defp refresh(view, path) do
    render_hook(view, "host:context", %{"path" => path})
    assert_reply(view, %{ok: true})
  end

  defp action(view, path, page, event, sequence, command) do
    render_hook(view, "host:ops-page", %{
      "id" => page["id"],
      "token" => page["token"],
      "path" => path,
      "event" => event,
      "input" => %{"sequence" => sequence, "command" => command}
    })

    assert_reply(view, reply)
    reply |> Jason.encode!() |> Jason.decode!()
  end
end
