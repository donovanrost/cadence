defmodule CadenceWeb.OpsDashboardActivityLiveTest do
  use CadenceWeb.ConnCase, async: false

  import CadenceWeb.OpsDashboardShowLive.ViewTestSupport
  import Phoenix.LiveViewTest

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias Cadence.Dashboards.Document
  alias CadenceWeb.TestFixtures

  test "version selection is URL-addressable and publish reads the canonical lifecycle store" do
    {conn, user, org, mission} = signed_in_user_org_and_mission()
    %Document{} = dashboard = TestFixtures.persist_dashboard_document!(mission, name: "Activity")

    assert {:ok, %Document{} = updated} =
             Cadence.Dashboards.update_document(
               org.organization_id,
               mission.mission_id,
               dashboard.dashboard_id,
               %Document{dashboard | description: "Second version"},
               expected_version: 1,
               change_summary: "Added activity description"
             )

    activity_path =
      ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}/activity"

    version_1_path = activity_path <> "?version=1"
    version_2_path = activity_path <> "?version=2"

    {:ok, view, _html} = live(conn, version_1_path)

    track_dashboard_view(view)

    versions =
      Cadence.Dashboards.list_versions(
        org.organization_id,
        mission.mission_id,
        dashboard.dashboard_id
      )

    initial_page = activity_page_props(mission, dashboard, 2, 0)
    header_vue = activity_vue(view, :header)
    versions_vue = activity_vue(view, :versions)
    detail_vue = activity_vue(view, :detail)
    events_vue = activity_vue(view, :events)

    assert header_vue.props == %{"page" => initial_page, "surface" => "header"}
    assert header_vue.handlers == %{}

    assert versions_vue.props == %{
             "page" => initial_page,
             "selected_version_number" => 1,
             "surface" => "versions"
           }

    expected_versions =
      Enum.map(versions, &dashboard_version_props(&1, mission, dashboard))

    assert stream_upserts(versions_vue, "dashboard_versions") == expected_versions

    assert stream_mutations(versions_vue) ==
             [
               ["replace", "/dashboard_versions", []]
             ] ++
               Enum.map(expected_versions, fn version ->
                 ["upsert", "/dashboard_versions/-", version]
               end)

    assert detail_vue.props == %{
             "page" => initial_page,
             "selected_version_detail" =>
               selected_version_props(Enum.at(versions, 0), 2, "active", "initial document"),
             "surface" => "detail"
           }

    assert detail_vue.handlers == %{
             "publish_version" => Phoenix.LiveView.JS.push("publish_version"),
             "restore_version" => Phoenix.LiveView.JS.push("restore_version")
           }

    assert events_vue.props == %{"page" => initial_page, "surface" => "activity"}

    assert stream_mutations(events_vue) == [
             ["replace", "/dashboard_activity", []]
           ]

    Enum.each([header_vue, versions_vue, detail_vue, events_vue], &assert_json_safe_vue/1)

    assert has_element?(view, ~s(#dashboard-version-detail[data-selected-version="1"]))

    publish_validation = publish_validation_vue(view).props["presentation"]

    assert publish_validation["root"]["id"] == "dashboard-publish-validation"

    assert publish_validation["header"]["refresh"]["attrs"]["phx-click"] ==
             "refresh_publish_readiness"

    render_click(view, "refresh_publish_readiness")

    selected_link = Enum.find(expected_versions, &(&1["version"] == 2))
    assert selected_link["href"] == version_2_path

    render_patch(view, version_2_path)

    assert has_element?(view, ~s(#dashboard-version-detail[data-selected-version="2"]))

    assert activity_vue(view, :versions).props["selected_version_number"] == 2

    assert activity_vue(view, :detail).props["selected_version_detail"] ==
             selected_version_props(
               Enum.at(versions, 1),
               2,
               "active",
               "description, metadata"
             )

    render_hook(view, "publish_version", %{"version" => "2"})

    assert has_element?(
             view,
             "#flash-info",
             "Dashboard version 2 published."
           )

    assert [%{published_version: 2, draft_version: nil}] =
             Cadence.Dashboards.list_dashboard_summaries(
               org.organization_id,
               mission.mission_id
             )

    assert Document.version(updated) == 2

    published_events =
      Cadence.Dashboards.list_lifecycle_events(
        org.organization_id,
        mission.mission_id,
        dashboard.dashboard_id
      )

    published_page = activity_page_props(mission, dashboard, 2, 1)
    published_events_vue = activity_vue(view, :events)
    [published_event] = Enum.map(Enum.reverse(published_events), &dashboard_activity_props/1)

    assert published_events_vue.props == %{
             "page" => published_page,
             "surface" => "activity"
           }

    assert stream_mutations(published_events_vue) == [
             ["replace", "/dashboard_activity", []],
             ["upsert", "/dashboard_activity/-", published_event]
           ]

    assert published_event["event_type"] == "published"
    assert published_event["label"] == "Published"
    assert published_event["dashboard_version"] == 2
    assert published_event["occurred"] =~ user.user_id
    assert_json_safe_vue(published_events_vue)

    render_patch(view, version_1_path)

    selected_v1 = activity_vue(view, :detail).props["selected_version_detail"]
    assert selected_v1["actions"]["restore"]["disabled"] == false
    assert selected_v1["actions"]["restore"]["payload"] == %{"version" => "1"}

    render_hook(view, "restore_version", %{"version" => "1"})

    assert has_element?(view, "#flash-info", "Version 1 restored as draft 3.")

    restored_versions =
      Cadence.Dashboards.list_versions(
        org.organization_id,
        mission.mission_id,
        dashboard.dashboard_id
      )

    assert Enum.map(restored_versions, & &1.version) == [1, 2, 3]

    restored_version_rows =
      Enum.map(restored_versions, &dashboard_version_props(&1, mission, dashboard))

    restored_versions_vue = activity_vue(view, :versions)
    assert stream_upserts(restored_versions_vue, "dashboard_versions") == restored_version_rows

    assert Enum.map(restored_version_rows, & &1["__dom_id"]) == [
             "dashboard-version-1",
             "dashboard-version-2",
             "dashboard-version-3"
           ]

    restored_events =
      Cadence.Dashboards.list_lifecycle_events(
        org.organization_id,
        mission.mission_id,
        dashboard.dashboard_id
      )

    restored_event_rows =
      restored_events
      |> Enum.reverse()
      |> Enum.map(&dashboard_activity_props/1)

    restored_events_vue = activity_vue(view, :events)
    assert stream_upserts(restored_events_vue, "dashboard_activity") == restored_event_rows
    assert Enum.map(restored_event_rows, & &1["event_type"]) == ["reverted", "published"]
    assert Enum.map(restored_event_rows, & &1["label"]) == ["Reverted", "Published"]

    assert Enum.map(restored_event_rows, & &1["__dom_id"]) ==
             Enum.map(restored_events |> Enum.reverse(), fn event ->
               "dashboard-activity-#{event.dashboard_lifecycle_event_id}"
             end)

    assert_json_safe_vue(restored_versions_vue)
    assert_json_safe_vue(restored_events_vue)

    assert :ok =
             Cadence.Dashboards.archive_document(
               org.organization_id,
               mission.mission_id,
               dashboard.dashboard_id,
               expected_version: 3,
               actor_id: user.user_id
             )

    {:ok, archived_view, _html} = live(conn, activity_path <> "?version=3")
    archived_detail = activity_vue(archived_view, :detail).props["selected_version_detail"]

    assert archived_detail["actions"]["visible"] == true
    assert archived_detail["actions"]["restore"]["disabled"] == true
    assert archived_detail["actions"]["publish"]["disabled"] == true
    assert archived_detail["actions"]["publish"]["payload"] == %{"version" => "3"}
    assert_json_safe_vue(activity_vue(archived_view, :detail))
  end

  defp activity_vue(view, surface) do
    id =
      case surface do
        :header -> "dashboard-activity-header-component"
        :versions -> "dashboard-activity-versions-component"
        :detail -> "dashboard-activity-detail-component"
        :events -> "dashboard-activity-events-component"
      end

    vue = LiveVue.Test.get_vue(view, id: id)
    assert vue.component == "OpsDashboardActivity"
    assert vue.class == "contents"
    assert vue.ssr == false
    assert vue.slots == %{}
    vue
  end

  defp publish_validation_vue(view) do
    vue = LiveVue.Test.get_vue(view, id: "dashboard-publish-validation-component")
    assert vue.component == "PublishValidation"
    assert vue.id == "dashboard-publish-validation-component"
    assert vue.class == "contents"
    assert vue.ssr == false
    assert vue.handlers == %{}
    assert vue.slots == %{}
    assert_json_safe_vue(vue)
    vue
  end

  defp stream_upserts(vue, stream_name) do
    vue.streams_diff
    |> Enum.filter(fn
      ["upsert", path, _item] -> String.starts_with?(path, "/#{stream_name}/")
      _operation -> false
    end)
    |> Enum.map(fn ["upsert", _path, item] -> item end)
  end

  defp stream_mutations(vue) do
    Enum.reject(vue.streams_diff, fn
      ["test", "", _value] -> true
      _operation -> false
    end)
  end

  defp assert_json_safe_vue(vue) do
    contract = %{"props" => vue.props, "streams_diff" => vue.streams_diff}
    assert contract == Jason.decode!(Jason.encode!(contract))
  end

  defp activity_page_props(mission, dashboard, version_count, activity_count) do
    %{
      "id" => "dashboard-activity-page",
      "header" => %{
        "eyebrow" => "Dashboard / Activity",
        "heading" => "Activity",
        "copy" => "Immutable drafts, semantic change summaries, publication, and lifecycle audit."
      },
      "actions" => %{
        "editor" => %{
          "id" => "dashboard-activity-editor",
          "label" => "Edit Dashboard",
          "href" =>
            ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}/edit",
          "visible" => true
        },
        "viewer" => %{
          "id" => "dashboard-activity-viewer",
          "label" => "Viewer",
          "href" => ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}"
        }
      },
      "versions" => %{
        "label" => "Versions",
        "count_id" => "dashboard-version-count",
        "count" => version_count,
        "container_id" => "dashboard-versions",
        "empty_id" => "dashboard-versions-empty",
        "empty" => "No saved versions."
      },
      "activity" => %{
        "label" => "Lifecycle audit",
        "count_id" => "dashboard-activity-count",
        "count" => activity_count,
        "container_id" => "dashboard-activity-events",
        "empty_id" => "dashboard-activity-empty",
        "empty" => "No lifecycle transitions recorded."
      }
    }
  end

  defp dashboard_version_props(version, mission, dashboard) do
    %{
      "id" => version.dashboard_version_id,
      "__dom_id" => "dashboard-version-#{version.version}",
      "version" => version.version,
      "href" =>
        ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}/activity?version=#{version.version}",
      "snapshot_kind" => to_string(version.snapshot_kind),
      "change_summary" => version.change_summary || "Dashboard created",
      "saved" =>
        "#{format_activity_time(version.inserted_at)} · #{version.created_by || "system"}"
    }
  end

  defp selected_version_props(version, latest_version, lifecycle_state, changed_fields) do
    payload = %{"version" => Integer.to_string(version.version)}

    %{
      "version" => version.version,
      "change_summary" => version.change_summary || "Dashboard created",
      "actions" => %{
        "visible" => true,
        "restore" => %{
          "id" => "dashboard-activity-restore",
          "label" => "Restore as Draft",
          "disabled" => version.version == latest_version,
          "payload" => payload
        },
        "publish" => %{
          "id" => "dashboard-activity-publish",
          "label" => "Publish Version",
          "disabled" => lifecycle_state == "archived",
          "payload" => payload
        }
      },
      "details" => [
        %{"label" => "Widgets", "value" => length(version.document.placements)},
        %{"label" => "Sections", "value" => length(version.document.sections)},
        %{"label" => "Changed fields", "value" => changed_fields}
      ]
    }
  end

  defp dashboard_activity_props(event) do
    %{
      "id" => event.dashboard_lifecycle_event_id,
      "__dom_id" => "dashboard-activity-#{event.dashboard_lifecycle_event_id}",
      "dashboard_lifecycle_event_id" => event.dashboard_lifecycle_event_id,
      "event_type" => to_string(event.event_type),
      "label" =>
        event.event_type |> to_string() |> String.replace("_", " ") |> String.capitalize(),
      "occurred" => "#{format_activity_time(event.occurred_at)} · #{event.actor_id || "system"}",
      "dashboard_version" => event.dashboard_version
    }
  end

  defp format_activity_time(%DateTime{} = value),
    do: Calendar.strftime(value, "%Y-%m-%d %H:%M:%S UTC")

  defp format_activity_time(_value), do: "time unavailable"

  test "Viewer routes page-sized workflows instead of exposing inline mutation controls" do
    {conn, _user, _org, mission} = signed_in_user_org_and_mission()
    dashboard = TestFixtures.persist_dashboard_document!(mission, name: "Viewer Boundaries")

    {:ok, viewer, _html} =
      await_live_result(live(conn, viewer_path(mission, dashboard)))

    assert dashboard_toolbar_menu_item(viewer, "dashboard-edit-link")
    assert dashboard_toolbar_menu_item(viewer, "dashboard-settings-button")
    assert dashboard_toolbar_menu_item(viewer, "dashboard-versions-button")
    assert dashboard_toolbar_menu_item(viewer, "dashboard-diagnostics-button")

    menu_json =
      viewer |> dashboard_toolbar_presentation() |> Map.fetch!("menu") |> Jason.encode!()

    refute menu_json =~ "publish_dashboard"
    refute menu_json =~ "archive_dashboard"
    refute menu_json =~ "open_rename"
  end

  defp viewer_path(mission, dashboard) do
    ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}"
  end

  defp signed_in_user_org_and_mission do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org)
    mission = TestFixtures.persist_mission!(org, slug: "dashboard-activity")
    {TestFixtures.member_conn(user), user, org, mission}
  end
end
