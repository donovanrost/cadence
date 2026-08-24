defmodule CadenceWeb.OpsDashboardLibraryLiveTest do
  use CadenceWeb.ConnCase, async: false

  import CadenceWeb.OpsDashboardShowLive.ViewTestSupport
  import Phoenix.LiveViewTest

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias Cadence.Dashboards.{Management, Placement, PlacementEditor, WidgetDef}
  alias CadenceWeb.TestFixtures
  alias Phoenix.LiveView.JS

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

    usage = Management.library_usage(org.organization_id, mission.mission_id, item_v2)
    assert %{consumer_count: 1, outdated_count: 1, consumers: [consumer]} = usage

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

    track_dashboard_view(library)

    assert has_element?(library, "#ops-context-rail")
    assert has_element?(library, "#dashboard-library-component.contents")
    refute has_element?(library, "#dashboard-library-page")

    initial_vue = library_vue(library)
    versions = Management.list_library_versions(item.dashboard_library_item_id)
    [row] = library_item_upserts(initial_vue)

    assert initial_vue.component == "OpsDashboardLibrary"
    assert initial_vue.class == "contents"
    assert initial_vue.ssr == false

    assert initial_vue.handlers == %{
             "add-library-version" => JS.push("add_library_version"),
             "create-library-item" => JS.push("create_library_item"),
             "stage-library-item" => JS.push("stage_library_item")
           }

    assert initial_vue.props ==
             library_props(
               mission.mission_id,
               [%{"label" => "Pinned consumer", "value" => dashboard.dashboard_id}],
               [
                 %{
                   "label" => "Battery voltage trend (latest v2)",
                   "value" => item.dashboard_library_item_id,
                   "latest_version" => 2
                 }
               ],
               0
             )

    assert row == expected_library_row(mission.mission_id, item_v2, versions, usage)

    assert library_stream_mutations(initial_vue) == [
             ["replace", "/library_items", []],
             ["replace", "/library_items", []],
             ["upsert", "/library_items/-", row]
           ]

    assert_json_safe(initial_vue)

    # One-to-one preservation of the original Vue-owned row and latest-version ID assertions.
    assert row["__dom_id"] == "dashboard-library-item-#{item.dashboard_library_item_id}"

    latest_version_id = List.first(versions).dashboard_library_version_id

    assert Enum.any?(
             row["versions"],
             &(&1["badge"]["id"] == "library-version-#{latest_version_id}")
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

    {:ok, editor, _html} = await_live_result(live(conn, path))
    assert has_element?(editor, ~s(#ops-dashboard-show-page[data-editor-dirty="true"]))

    assert {:ok, %{placements: []}} =
             Cadence.Dashboards.fetch_document(
               org.organization_id,
               mission.mission_id,
               dashboard.dashboard_id
             )

    click_editor_action(editor, "dashboard-editor-save")

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

  test "Vue create emit rejects invalid JSON then creates attributed version 1 with a reset patch" do
    {conn, user, org, mission} = signed_in_user_org_and_mission()

    {:ok, library, _html} =
      live(conn, ~p"/missions/#{mission.mission_id}/ops/dashboards/library")

    track_dashboard_view(library)

    initial_vue = library_vue(library)

    assert initial_vue.props == library_props(mission.mission_id, [], [], 0)
    assert library_item_upserts(initial_vue) == []
    assert_json_safe(initial_vue)

    render_hook(library, "create_library_item", %{
      "library_item" => %{
        "name" => "Invalid definition",
        "description" => "Must not persist",
        "change_summary" => "Invalid",
        "widget_json" => "[]"
      }
    })

    assert Management.list_library_items(org.organization_id, mission.mission_id) == []

    assert has_element?(
             library,
             "#flash-error",
             "Failed to create library item: Widget definition must be a JSON object."
           )

    invalid_vue = library_vue(library)
    assert invalid_vue.props == initial_vue.props
    assert_no_library_stream_mutations(invalid_vue)
    assert_json_safe(invalid_vue)

    definition = widget_definition("Created in Vue")

    render_hook(library, "create_library_item", %{
      "library_item" => %{
        "name" => "Reusable current",
        "description" => "Shared operations trend",
        "change_summary" => "Initial operations contract",
        "widget_json" => Jason.encode!(definition)
      }
    })

    assert [created] = Management.list_library_items(org.organization_id, mission.mission_id)
    assert created.name == "Reusable current"
    assert created.description == "Shared operations trend"
    assert created.latest_version == 1
    assert created.created_by == user.user_id
    assert created.updated_by == user.user_id

    assert [version] = Management.list_library_versions(created.dashboard_library_item_id)
    assert version.version == 1
    assert version.change_summary == "Initial operations contract"
    assert version.created_by == user.user_id

    assert has_element?(library, "#flash-info", "Reusable widget created at version 1.")

    usage = Management.library_usage(org.organization_id, mission.mission_id, created)
    expected_row = expected_library_row(mission.mission_id, created, [version], usage)
    created_vue = library_vue(library)

    assert created_vue.props ==
             library_props(
               mission.mission_id,
               [],
               [
                 %{
                   "label" => "Reusable current (latest v1)",
                   "value" => created.dashboard_library_item_id,
                   "latest_version" => 1
                 }
               ],
               1
             )

    assert_reset_replace(created_vue, [expected_row])
    assert_json_safe(created_vue)
  end

  test "Vue version emit validates selection and JSON then preserves pinned consumers" do
    {conn, user, org, mission} = signed_in_user_org_and_mission()
    definition_v1 = widget_definition("Pinned immutable trend")

    assert {:ok, item} =
             Management.create_library_item(
               org.organization_id,
               mission.mission_id,
               %{
                 "name" => "Immutable trend",
                 "description" => "Pinned contract",
                 "widget_definition" => definition_v1
               },
               created_by: user.user_id
             )

    dashboard =
      TestFixtures.persist_dashboard_document!(mission,
        name: "Immutable consumer",
        placements: [library_placement(item.dashboard_library_item_id, 1)]
      )

    {:ok, library, _html} =
      live(conn, ~p"/missions/#{mission.mission_id}/ops/dashboards/library")

    track_dashboard_view(library)

    render_hook(library, "add_library_version", %{
      "library_version" => %{
        "item_id" => "",
        "change_summary" => "Not selected",
        "widget_json" => Jason.encode!(definition_v1)
      }
    })

    assert has_element?(library, "#flash-error", "Choose a library item.")
    selection_error_vue = library_vue(library)
    assert_no_library_stream_mutations(selection_error_vue)

    {:ok, library, _html} =
      live(conn, ~p"/missions/#{mission.mission_id}/ops/dashboards/library")

    track_dashboard_view(library)

    render_hook(library, "add_library_version", %{
      "library_version" => %{
        "item_id" => item.dashboard_library_item_id,
        "change_summary" => "Invalid JSON",
        "widget_json" => "{"
      }
    })

    assert has_element?(
             library,
             "#flash-error",
             "Failed to add version: Widget definition must be a JSON object."
           )

    json_error_vue = library_vue(library)
    assert_no_library_stream_mutations(json_error_vue)

    {:ok, library, _html} =
      live(conn, ~p"/missions/#{mission.mission_id}/ops/dashboards/library")

    track_dashboard_view(library)

    definition_v2 = Map.put(definition_v1, :title, "Pinned immutable trend v2")

    render_hook(library, "add_library_version", %{
      "library_version" => %{
        "item_id" => item.dashboard_library_item_id,
        "change_summary" => "Refine immutable contract",
        "widget_json" => Jason.encode!(definition_v2)
      }
    })

    assert [item_v2] = Management.list_library_items(org.organization_id, mission.mission_id)
    assert item_v2.latest_version == 2
    assert item_v2.updated_by == user.user_id

    versions = Management.list_library_versions(item.dashboard_library_item_id)
    assert [version_v2, version_v1] = versions

    assert version_v2.version == 2
    assert version_v2.change_summary == "Refine immutable contract"
    assert version_v2.created_by == user.user_id
    assert version_v1.version == 1

    assert {:ok, persisted} =
             Cadence.Dashboards.fetch_document(
               org.organization_id,
               mission.mission_id,
               dashboard.dashboard_id
             )

    assert [%Placement{content_kind: :library, library_version: 1}] = persisted.placements

    usage = Management.library_usage(org.organization_id, mission.mission_id, item_v2)
    assert %{consumer_count: 1, outdated_count: 1, consumers: [consumer]} = usage
    assert consumer.version == 1
    assert consumer.update_available?

    assert has_element?(
             library,
             "#flash-info",
             "Immutable trend version 2 created. Consumers remain pinned."
           )

    versioned_vue = library_vue(library)

    assert versioned_vue.props["library_options"] == [
             %{
               "label" => "Immutable trend (latest v2)",
               "value" => item.dashboard_library_item_id,
               "latest_version" => 2
             }
           ]

    assert versioned_vue.props["version_form"] == version_form_props()

    assert_reset_replace(
      versioned_vue,
      [expected_library_row(mission.mission_id, item_v2, versions, usage)]
    )

    assert_json_safe(versioned_vue)
  end

  test "Vue staging emit rejects invalid selection and navigates with the exact pinned version" do
    {conn, user, org, mission} = signed_in_user_org_and_mission()
    dashboard = TestFixtures.persist_dashboard_document!(mission, name: "Exact staging target")

    assert {:ok, item} =
             Management.create_library_item(
               org.organization_id,
               mission.mission_id,
               %{
                 "name" => "Exact staging source",
                 "widget_definition" => widget_definition("Exact staging v1")
               },
               created_by: user.user_id
             )

    assert {:ok, _item_v2} =
             Management.add_library_version(
               org.organization_id,
               mission.mission_id,
               item.dashboard_library_item_id,
               widget_definition("Exact staging v2"),
               created_by: user.user_id,
               change_summary: "Keep version 1 selectable"
             )

    {:ok, library, _html} =
      live(conn, ~p"/missions/#{mission.mission_id}/ops/dashboards/library")

    track_dashboard_view(library)

    render_hook(library, "stage_library_item", %{
      "library_add" => %{
        "dashboard_id" => dashboard.dashboard_id,
        "item_id" => item.dashboard_library_item_id,
        "version" => "9"
      }
    })

    assert has_element?(
             library,
             "#flash-error",
             "Choose a dashboard and exact library version."
           )

    invalid_vue = library_vue(library)
    assert_no_library_stream_mutations(invalid_vue)

    render_hook(library, "stage_library_item", %{
      "library_add" => %{
        "dashboard_id" => dashboard.dashboard_id,
        "item_id" => item.dashboard_library_item_id,
        "version" => "1"
      }
    })

    expected_path =
      ~p"/missions/#{mission.mission_id}/ops/dashboards/#{dashboard.dashboard_id}/edit?#{[candidate_source: "library", candidate_library_item_id: item.dashboard_library_item_id, candidate_library_version: 1]}"

    assert_redirect(library, expected_path)
  end

  defp library_props(mission_id, dashboard_options, library_options, reset_revision) do
    %{
      "page" => %{
        "id" => "dashboard-library-page",
        "header" => %{
          "id" => "dashboard-library-header",
          "eyebrow" => "Dashboards / Library",
          "heading" => "Reusable widget library",
          "copy" =>
            "Every consumer pins an immutable version. New versions expose update posture but never rewrite a dashboard."
        },
        "list" => %{
          "id" => "dashboard-library-list",
          "empty" => %{
            "id" => "dashboard-library-empty",
            "copy" => "No reusable widgets yet."
          }
        },
        "paths" => %{
          "dashboards" => "/missions/#{mission_id}/ops/dashboards",
          "library" => "/missions/#{mission_id}/ops/dashboards/library"
        }
      },
      "dashboard_options" => dashboard_options,
      "library_options" => library_options,
      "stage_form" => stage_form_props(),
      "create_form" => create_form_props(reset_revision),
      "version_form" => version_form_props()
    }
  end

  defp stage_form_props do
    %{
      "id" => "dashboard-library-add-form",
      "eyebrow" => "Use exact version",
      "fields" => %{
        "dashboard_id" =>
          select_field_props(
            "library_add_dashboard_id",
            "library_add[dashboard_id]",
            "Dashboard",
            "Choose dashboard"
          ),
        "item_id" =>
          select_field_props(
            "library_add_item_id",
            "library_add[item_id]",
            "Library item",
            "Choose item"
          ),
        "version" => %{
          "id" => "library_add_version",
          "name" => "library_add[version]",
          "type" => "number",
          "label" => "Pinned version",
          "value" => "1",
          "required" => false,
          "min" => 1
        }
      },
      "action" => %{"id" => "dashboard-library-stage", "label" => "Stage in Editor"}
    }
  end

  defp create_form_props(reset_revision) do
    %{
      "id" => "dashboard-library-create-form",
      "reset_revision" => reset_revision,
      "details" => %{
        "id" => "dashboard-library-create-details",
        "summary_id" => "dashboard-library-create-summary",
        "summary" => "Create library item",
        "open" => true
      },
      "fields" => %{
        "name" =>
          text_field_props(
            "library_item_name",
            "library_item[name]",
            "Name",
            "text",
            "",
            true
          ),
        "description" =>
          text_field_props(
            "library_item_description",
            "library_item[description]",
            "Description",
            "textarea",
            "",
            false
          ),
        "change_summary" =>
          text_field_props(
            "library_item_change_summary",
            "library_item[change_summary]",
            "Version note",
            "text",
            "Initial version",
            false
          ),
        "widget_json" =>
          text_field_props(
            "library_item_widget_json",
            "library_item[widget_json]",
            "Widget definition JSON",
            "textarea",
            default_widget_json(),
            false
          )
      },
      "action" => %{"id" => "dashboard-library-create", "label" => "Create version 1"}
    }
  end

  defp version_form_props do
    %{
      "id" => "dashboard-library-version-form",
      "details" => %{
        "id" => "dashboard-library-version-details",
        "summary_id" => "dashboard-library-version-summary",
        "summary" => "Add immutable version",
        "open" => false
      },
      "fields" => %{
        "item_id" =>
          select_field_props(
            "library_version_item_id",
            "library_version[item_id]",
            "Library item",
            "Choose item"
          ),
        "change_summary" =>
          text_field_props(
            "library_version_change_summary",
            "library_version[change_summary]",
            "Change summary",
            "text",
            "",
            false
          ),
        "widget_json" =>
          text_field_props(
            "library_version_widget_json",
            "library_version[widget_json]",
            "Widget definition JSON",
            "textarea",
            default_widget_json(),
            false
          )
      },
      "action" => %{
        "id" => "dashboard-library-add-version",
        "label" => "Create next version"
      }
    }
  end

  defp select_field_props(id, name, label, placeholder) do
    %{
      "id" => id,
      "name" => name,
      "type" => "select",
      "label" => label,
      "value" => "",
      "required" => false,
      "placeholder" => placeholder
    }
  end

  defp text_field_props(id, name, label, type, value, required) do
    %{
      "id" => id,
      "name" => name,
      "type" => type,
      "label" => label,
      "value" => value,
      "required" => required
    }
  end

  defp expected_library_row(mission_id, item, versions, usage) do
    latest = List.first(versions)
    compatibility = latest.compatibility || %{}
    item_id = item.dashboard_library_item_id

    %{
      "__dom_id" => "dashboard-library-item-#{item_id}",
      "item" => %{
        "dashboard_library_item_id" => item_id,
        "name" => item.name,
        "description" => item.description || "",
        "latest_version" => item.latest_version,
        "created_by" => item.created_by,
        "updated_by" => item.updated_by
      },
      "versions" =>
        Enum.map(versions, fn version ->
          version_id = version.dashboard_library_version_id

          %{
            "dashboard_library_version_id" => version_id,
            "version" => version.version,
            "change_summary" => version.change_summary || "",
            "created_by" => version.created_by,
            "badge" => %{
              "id" => "library-version-#{version_id}",
              "label" => "v#{version.version}"
            },
            "detail_id" => "library-version-detail-#{version_id}"
          }
        end),
      "compatibility" => %{
        "widget_type_id" => compatibility["widget_type_id"] || "unknown",
        "widget_type_version" => compatibility["widget_type_version"],
        "binding_source" => compatibility["binding_source"]
      },
      "usage" => %{
        "consumer_count" => usage.consumer_count,
        "outdated_count" => usage.outdated_count,
        "consumers" =>
          Enum.map(usage.consumers, fn consumer ->
            %{
              "dashboard_id" => consumer.dashboard_id,
              "dashboard_name" => consumer.dashboard_name,
              "placement_id" => consumer.placement_id,
              "version" => consumer.version,
              "latest_version" => consumer.latest_version,
              "update_available" => consumer.update_available?,
              "id" => "dashboard-library-consumer-#{consumer.placement_id}",
              "action_id" => "dashboard-library-consumer-open-#{consumer.placement_id}",
              "path" => "/missions/#{mission_id}/ops/dashboards/#{consumer.dashboard_id}"
            }
          end)
      },
      "details" => %{
        "id" => "dashboard-library-details-#{item_id}",
        "summary_id" => "dashboard-library-details-summary-#{item_id}",
        "summary" => "Version and consumer details",
        "versions_id" => "dashboard-library-versions-#{item_id}",
        "consumers_id" => "dashboard-library-consumers-#{item_id}",
        "consumers_empty_id" => "dashboard-library-consumers-empty-#{item_id}"
      }
    }
  end

  defp click_editor_action(view, id) do
    assert has_element?(view, "#dashboard-editor-actions-component")
    vue = LiveVue.Test.get_vue(view, id: "dashboard-editor-actions-component")
    assert vue.component == "DashboardEditorActions"
    assert action = Enum.find(vue.props["presentation"]["elements"], &(&1["attrs"]["id"] == id))
    attrs = action["attrs"]

    render_click(
      view,
      Map.fetch!(attrs, "phx-click"),
      Enum.reduce(attrs, %{}, fn
        {"phx-value-" <> key, value}, params -> Map.put(params, key, value)
        {_attribute, _value}, params -> params
      end)
    )
  end

  defp library_vue(view) do
    LiveVue.Test.get_vue(view, id: "dashboard-library-component")
  end

  defp library_item_upserts(vue) do
    vue.streams_diff
    |> Enum.filter(fn
      ["upsert", "/library_items/" <> _index, _item] -> true
      _operation -> false
    end)
    |> Enum.map(fn ["upsert", _path, item] -> item end)
  end

  defp library_stream_mutations(vue) do
    Enum.reject(vue.streams_diff, fn
      ["test", "", _value] -> true
      _operation -> false
    end)
  end

  defp assert_no_library_stream_mutations(vue) do
    assert Enum.all?(vue.streams_diff, fn
             ["test", "", _value] -> true
             _operation -> false
           end)

    assert library_stream_mutations(vue) == []
  end

  defp assert_reset_replace(vue, rows) do
    assert library_stream_mutations(vue) ==
             [["replace", "/library_items", []]] ++
               Enum.map(rows, &["upsert", "/library_items/-", &1])
  end

  defp assert_json_safe(vue) do
    contract = %{"props" => vue.props, "streams_diff" => vue.streams_diff}
    assert contract == Jason.decode!(Jason.encode!(contract))
  end

  defp default_widget_json do
    Jason.encode!(
      %{
        "widget_type_id" => "time_series",
        "widget_type_version" => 1,
        "title" => "Reusable telemetry trend",
        "binding" => %{
          "source" => "telemetry",
          "observables" => ["telemetry.point"],
          "scope_mode" => "context",
          "data_mode" => "context",
          "sampling" => "raw_series"
        },
        "options" => %{}
      },
      pretty: true
    )
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
