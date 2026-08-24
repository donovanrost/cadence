defmodule CadenceWeb.OpsDashboardDirectoryLiveTest do
  use CadenceWeb.ConnCase, async: false

  import CadenceWeb.OpsDashboardShowLive.ViewTestSupport
  import CadenceWeb.OpsNavTestSupport
  import Phoenix.LiveViewTest

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias CadenceWeb.TestFixtures

  test "exposes an exact JSON-safe empty LiveVue directory contract" do
    {conn, _user, _org, mission} = signed_in_user_org_and_mission()

    {:ok, view, _html} = live(conn, ~p"/missions/#{mission.mission_id}/ops/dashboards")
    track_dashboard_view(view)

    assert has_element?(view, "#ops-dashboard-directory-component.contents")
    assert has_element?(view, "#ops-context-rail-component")
    refute has_element?(view, "#ops-dashboards-page")

    vue = dashboard_directory_vue(view)

    assert vue.component == "OpsDashboardDirectory"
    assert vue.class == "contents"
    assert vue.ssr == false
    assert vue.slots == %{}

    assert vue.handlers == %{
             "filter_dashboards" => Phoenix.LiveView.JS.push("filter_dashboards"),
             "restore_dashboard" => Phoenix.LiveView.JS.push("restore_dashboard"),
             "toggle_dashboard_star" => Phoenix.LiveView.JS.push("toggle_dashboard_star")
           }

    assert vue.props == directory_props(mission, 0, [], default_filters())
    assert directory_rows(vue) == []

    assert directory_stream_mutations(vue) == [
             ["replace", "/dashboard_directory", []],
             ["replace", "/dashboard_directory", []]
           ]

    assert_json_safe_directory_vue(vue)
  end

  test "searches, sorts, and filters dashboard tags through restorable URL state" do
    {conn, _user, _org, mission} = signed_in_user_org_and_mission()

    thermal =
      TestFixtures.persist_dashboard_document!(mission,
        name: "Thermal Flight",
        description: "Payload temperatures",
        metadata: %{"tags" => ["thermal", "flight"]}
      )

    power =
      TestFixtures.persist_dashboard_document!(mission,
        name: "Power Ground",
        description: "Battery posture",
        metadata: %{"tags" => ["power", "ground"]}
      )

    {:ok, view, _html} = live(conn, ~p"/missions/#{mission.mission_id}/ops/dashboards")
    track_dashboard_view(view)

    initial_vue = dashboard_directory_vue(view)
    initial_rows = directory_rows(initial_vue)

    assert initial_vue.props ==
             directory_props(
               mission,
               2,
               ["flight", "ground", "power", "thermal"],
               default_filters()
             )

    assert Enum.sort_by(initial_rows, & &1["dashboard_id"]) ==
             Enum.sort_by(
               [active_row(thermal, mission), active_row(power, mission)],
               & &1["dashboard_id"]
             )

    assert ["replace", "/dashboard_directory", []] in directory_stream_mutations(initial_vue)

    assert_json_safe_directory_vue(initial_vue)

    filtered_values = %{
      "query" => " thermal ",
      "lifecycle" => "active",
      "tag" => "flight",
      "sort" => "name"
    }

    render_hook(view, "filter_dashboards", %{"directory" => filtered_values})

    assert_patch(
      view,
      "/missions/#{mission.mission_id}/ops/dashboards?query=thermal&sort=name&tag=flight"
    )

    filtered_vue = dashboard_directory_vue(view)
    [filtered_row] = directory_rows(filtered_vue)

    assert filtered_vue.props ==
             directory_props(
               mission,
               1,
               ["flight", "ground", "power", "thermal"],
               Map.put(filtered_values, "query", "thermal")
             )

    assert filtered_row == active_row(thermal, mission)

    assert directory_stream_mutations(filtered_vue) == [
             ["replace", "/dashboard_directory", []],
             ["upsert", "/dashboard_directory/-", filtered_row]
           ]

    assert_json_safe_directory_vue(filtered_vue)

    render_hook(view, "filter_dashboards", %{"directory" => default_filters()})
    assert_patch(view, "/missions/#{mission.mission_id}/ops/dashboards")

    reset_vue = dashboard_directory_vue(view)
    reset_rows = directory_rows(reset_vue)

    assert reset_vue.props ==
             directory_props(
               mission,
               2,
               ["flight", "ground", "power", "thermal"],
               default_filters()
             )

    assert directory_stream_mutations(reset_vue) ==
             [["replace", "/dashboard_directory", []]] ++
               Enum.map(reset_rows, &["upsert", "/dashboard_directory/-", &1])

    assert_json_safe_directory_vue(reset_vue)
  end

  test "stars are personal while opening a dashboard promotes it into recent navigation" do
    {conn, user, org, mission} = signed_in_user_org_and_mission()
    dashboard = TestFixtures.persist_dashboard_document!(mission, name: "Mission Power")

    {:ok, directory, _html} =
      live(conn, ~p"/missions/#{mission.mission_id}/ops/dashboards")

    track_dashboard_view(directory)

    initial_vue = dashboard_directory_vue(directory)
    [initial_row] = directory_rows(initial_vue)

    assert initial_row == active_row(dashboard, mission)

    assert initial_row["star"] == %{
             "id" => "dashboard-directory-star-#{dashboard.dashboard_id}",
             "payload" => %{
               "dashboard-id" => dashboard.dashboard_id,
               "starred" => "true"
             },
             "aria_label" => "Star Mission Power",
             "aria_pressed" => "false",
             "disabled" => false,
             "title" => nil,
             "icon" => "hero-star"
           }

    refute Map.has_key?(initial_row["star"], "confirm")

    render_hook(directory, "toggle_dashboard_star", initial_row["star"]["payload"])

    starred_vue = dashboard_directory_vue(directory)
    [starred_row] = directory_rows(starred_vue)

    assert starred_row == active_row(dashboard, mission, true)

    assert starred_row["star"] == %{
             "id" => "dashboard-directory-star-#{dashboard.dashboard_id}",
             "payload" => %{
               "dashboard-id" => dashboard.dashboard_id,
               "starred" => "false"
             },
             "aria_label" => "Unstar Mission Power",
             "aria_pressed" => "true",
             "disabled" => false,
             "title" => nil,
             "icon" => "hero-star-solid"
           }

    assert directory_stream_mutations(starred_vue) == [
             ["replace", "/dashboard_directory", []],
             ["upsert", "/dashboard_directory/-", starred_row]
           ]

    assert_json_safe_directory_vue(starred_vue)

    assert ops_dashboard_nav_item(
             ops_nav_vue(directory),
             "starred",
             dashboard.dashboard_id
           ) == %{
             "active" => false,
             "dashboard_id" => dashboard.dashboard_id,
             "href" => "/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}",
             "label" => "Mission Power"
           }

    second_user = TestFixtures.persist_user!()
    _membership = TestFixtures.grant_membership!(second_user, org)

    {:ok, second_directory, _html} =
      live(
        TestFixtures.member_conn(second_user),
        ~p"/missions/#{mission.mission_id}/ops/dashboards"
      )

    track_dashboard_view(second_directory)

    [second_user_row] = second_directory |> dashboard_directory_vue() |> directory_rows()
    assert second_user_row["starred"] == false
    assert second_user_row["star"]["aria_pressed"] == "false"

    refute ops_dashboard_nav_item(
             ops_nav_vue(second_directory),
             "starred",
             dashboard.dashboard_id
           )

    assert [%{dashboard_id: dashboard_id, starred: true}] =
             Cadence.Dashboards.list_dashboard_user_preferences(
               org.organization_id,
               mission.mission_id,
               user.user_id
             )

    {:ok, recent_view, _html} =
      await_live_result(
        live(
          TestFixtures.member_conn(second_user),
          ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}"
        )
      )

    assert dashboard_id == dashboard.dashboard_id

    assert ops_dashboard_nav_item(
             ops_nav_vue(recent_view),
             "recent",
             dashboard.dashboard_id
           ) == %{
             "active" => true,
             "dashboard_id" => dashboard.dashboard_id,
             "href" => "/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}",
             "label" => "Mission Power"
           }
  end

  test "archived dashboards have a dedicated filtered view and restore outcome" do
    {conn, user, org, mission} = signed_in_user_org_and_mission()

    dashboard =
      TestFixtures.persist_dashboard_document!(mission,
        name: "Archived Thermal",
        metadata: %{"tags" => []}
      )

    assert :ok =
             Cadence.Dashboards.archive_document(
               org.organization_id,
               mission.mission_id,
               dashboard.dashboard_id,
               expected_version: 1,
               actor_id: user.user_id
             )

    {:ok, view, _html} =
      live(
        conn,
        ~p"/missions/#{mission.mission_id}/ops/dashboards?#{%{lifecycle: "archived"}}"
      )

    track_dashboard_view(view)

    archived_vue = dashboard_directory_vue(view)
    [archived_row] = directory_rows(archived_vue)

    assert archived_vue.props ==
             directory_props(
               mission,
               1,
               [],
               Map.put(default_filters(), "lifecycle", "archived")
             )

    assert archived_row == expected_archived_row(dashboard)

    assert archived_row["star"] == %{
             "id" => "dashboard-directory-star-#{dashboard.dashboard_id}",
             "payload" => %{
               "dashboard-id" => dashboard.dashboard_id,
               "starred" => "true"
             },
             "aria_label" => "Star Archived Thermal",
             "aria_pressed" => "false",
             "disabled" => true,
             "title" => "Restore this dashboard before starring it",
             "icon" => "hero-star"
           }

    assert archived_row["restore"] == %{
             "id" => "restore-dashboard-#{dashboard.dashboard_id}",
             "label" => "Restore",
             "icon" => "hero-arrow-uturn-left",
             "payload" => %{
               "dashboard-id" => dashboard.dashboard_id,
               "expected-version" => "1"
             },
             "disabled" => false,
             "lifecycle_action" => "restore",
             "action_available" => "true"
           }

    refute Map.has_key?(archived_row, "clone")
    refute Map.has_key?(archived_row["restore"], "confirm")
    assert_json_safe_directory_vue(archived_vue)

    render_hook(view, "restore_dashboard", archived_row["restore"]["payload"])

    restored_vue = dashboard_directory_vue(view)

    assert restored_vue.props ==
             directory_props(
               mission,
               0,
               [],
               Map.put(default_filters(), "lifecycle", "archived")
             )

    assert directory_rows(restored_vue) == []

    assert directory_stream_mutations(restored_vue) == [
             ["replace", "/dashboard_directory", []]
           ]

    assert_json_safe_directory_vue(restored_vue)

    assert [%{dashboard_id: restored_id}] =
             Cadence.Dashboards.list_dashboard_summaries(
               org.organization_id,
               mission.mission_id
             )

    assert restored_id == dashboard.dashboard_id
  end

  defp dashboard_directory_vue(view) do
    LiveVue.Test.get_vue(view, id: "ops-dashboard-directory-component")
  end

  defp directory_rows(vue) do
    vue.streams_diff
    |> Enum.filter(fn
      ["upsert", "/dashboard_directory/" <> _index, _row] -> true
      _operation -> false
    end)
    |> Enum.map(fn ["upsert", _path, row] -> row end)
  end

  defp directory_stream_mutations(vue) do
    Enum.reject(vue.streams_diff, fn
      ["test", "", _value] -> true
      _operation -> false
    end)
  end

  defp assert_json_safe_directory_vue(vue) do
    contract = %{"props" => vue.props, "streams_diff" => vue.streams_diff}
    assert contract == Jason.decode!(Jason.encode!(contract))
  end

  defp directory_props(mission, count, tags, filters) do
    %{
      "page" => %{
        "id" => "ops-dashboards-page",
        "header" => %{
          "eyebrow" => "Observe / Dashboards",
          "heading" => "Dashboard Directory",
          "copy" =>
            "Find mission telemetry workspaces without crowding the navigation rail. Stars and recents are personal; dashboard definitions and tags remain mission shared.",
          "count" => %{
            "id" => "dashboard-directory-count",
            "value" => count,
            "suffix" => "matching"
          },
          "author_actions" => author_action_props(mission)
        },
        "list" => %{
          "id" => "dashboard-directory-list",
          "empty" => %{
            "id" => "dashboard-directory-empty",
            "icon" => "hero-magnifying-glass",
            "heading" => "No matching dashboards",
            "copy" =>
              "Change the search, tag, or lifecycle filter. The filter state is preserved in the URL."
          }
        }
      },
      "filters" => filter_props(tags, filters)
    }
  end

  defp author_action_props(mission) do
    mission_id = mission.mission_id

    [
      %{
        "id" => "dashboard-directory-new",
        "label" => "New Dashboard",
        "icon" => "hero-plus",
        "icon_class" => "h-4 w-4",
        "href" => "/missions/#{mission_id}/ops/dashboards/new",
        "class" => "btn btn-primary btn-sm"
      },
      %{
        "id" => "dashboard-directory-import",
        "label" => "Import",
        "icon" => "hero-arrow-down-tray",
        "icon_class" => "h-4 w-4",
        "href" => "/missions/#{mission_id}/ops/dashboards/new?mode=import",
        "class" => "btn btn-outline btn-sm"
      },
      %{
        "id" => "dashboard-directory-library",
        "label" => "Library",
        "icon" => "hero-squares-plus",
        "icon_class" => "h-4 w-4",
        "href" => "/missions/#{mission_id}/ops/dashboards/library",
        "class" => "btn btn-ghost btn-sm"
      },
      %{
        "id" => "dashboard-directory-playlists",
        "label" => "Playlists",
        "icon" => "hero-play-circle",
        "icon_class" => "h-4 w-4",
        "href" => "/missions/#{mission_id}/ops/dashboards/playlists",
        "class" => "btn btn-ghost btn-sm"
      }
    ]
  end

  defp filter_props(tags, values) do
    %{
      "id" => "dashboard-directory-filter-form",
      "values" => values,
      "fields" => %{
        "query" => %{
          "id" => "directory_query",
          "name" => "directory[query]",
          "type" => "search",
          "label" => "Search",
          "placeholder" => "Name, description, or tag",
          "debounce_ms" => 250
        },
        "lifecycle" =>
          select_props(
            "directory_lifecycle",
            "directory[lifecycle]",
            "Lifecycle",
            [{"Active", "active"}, {"Archived", "archived"}, {"All", "all"}]
          ),
        "tag" =>
          select_props(
            "directory_tag",
            "directory[tag]",
            "Tag",
            [{"All tags", "all"} | Enum.map(tags, &{&1, &1})]
          ),
        "sort" =>
          select_props(
            "directory_sort",
            "directory[sort]",
            "Sort",
            [
              {"Recently updated", "updated"},
              {"Name", "name"},
              {"Widget count", "widgets"}
            ]
          )
      }
    }
  end

  defp select_props(id, name, label, options) do
    %{
      "id" => id,
      "name" => name,
      "type" => "select",
      "label" => label,
      "options" =>
        Enum.map(options, fn {option_label, value} ->
          %{"label" => option_label, "value" => value}
        end)
    }
  end

  defp active_row(dashboard, mission, starred? \\ false) do
    dashboard_id = dashboard.dashboard_id

    %{
      "id" => dashboard_id,
      "__dom_id" => "dashboard-directory-row-#{dashboard_id}",
      "dashboard_id" => dashboard_id,
      "name" => dashboard.name,
      "description" => dashboard.description,
      "tags" => Enum.sort(dashboard.metadata["tags"] || []),
      "lifecycle" => %{
        "state" => "active",
        "class" =>
          "border px-1.5 py-0.5 font-mono text-[0.6rem] uppercase tracking-wider border-success/30 text-success"
      },
      "starred" => starred?,
      "open" => %{
        "id" => "dashboard-directory-open-#{dashboard_id}",
        "href" => "/missions/#{mission.mission_id}/ops/dashboards/#{dashboard_id}"
      },
      "star" => star_props(dashboard, starred?, false),
      "widget_version_label" => "#{length(dashboard.placements)} widgets · v1",
      "restore" => nil,
      "clone" => %{
        "id" => "clone-dashboard-#{dashboard_id}",
        "label" => "Clone",
        "icon" => "hero-document-duplicate",
        "href" =>
          "/missions/#{mission.mission_id}/ops/dashboards/new?source_dashboard_id=#{dashboard_id}"
      }
    }
  end

  defp expected_archived_row(dashboard) do
    dashboard_id = dashboard.dashboard_id

    %{
      "id" => dashboard_id,
      "__dom_id" => "dashboard-directory-row-#{dashboard_id}",
      "dashboard_id" => dashboard_id,
      "name" => dashboard.name,
      "description" => dashboard.description,
      "tags" => dashboard.metadata["tags"] || [],
      "lifecycle" => %{
        "state" => "archived",
        "class" =>
          "border px-1.5 py-0.5 font-mono text-[0.6rem] uppercase tracking-wider border-base-content/20 text-base-content/45"
      },
      "starred" => false,
      "open" => nil,
      "star" => star_props(dashboard, false, true),
      "widget_version_label" => "#{length(dashboard.placements)} widgets · v1",
      "restore" => %{
        "id" => "restore-dashboard-#{dashboard_id}",
        "label" => "Restore",
        "icon" => "hero-arrow-uturn-left",
        "payload" => %{
          "dashboard-id" => dashboard_id,
          "expected-version" => "1"
        },
        "disabled" => false,
        "lifecycle_action" => "restore",
        "action_available" => "true"
      }
    }
  end

  defp star_props(dashboard, starred?, archived?) do
    %{
      "id" => "dashboard-directory-star-#{dashboard.dashboard_id}",
      "payload" => %{
        "dashboard-id" => dashboard.dashboard_id,
        "starred" => to_string(not starred?)
      },
      "aria_label" =>
        if(starred?, do: "Unstar #{dashboard.name}", else: "Star #{dashboard.name}"),
      "aria_pressed" => to_string(starred?),
      "disabled" => archived?,
      "title" => if(archived?, do: "Restore this dashboard before starring it", else: nil),
      "icon" => if(starred?, do: "hero-star-solid", else: "hero-star")
    }
  end

  defp default_filters do
    %{"query" => "", "lifecycle" => "active", "tag" => "all", "sort" => "updated"}
  end

  defp signed_in_user_org_and_mission do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, org)

    mission =
      TestFixtures.persist_mission!(org,
        slug: "dashboard-directory",
        display_name: "Dashboard Directory"
      )

    {TestFixtures.member_conn(user), user, org, mission}
  end
end
