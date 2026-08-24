defmodule CadenceWeb.MissionApplicationsLiveTest do
  use CadenceWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias Cadence.DerivedTelemetry.Definition, as: DerivedDefinition
  alias Cadence.Limits.{Event, Store}
  alias Cadence.Repo
  alias CadenceWeb.TestFixtures
  alias Phoenix.LiveView.JS

  setup do
    user = TestFixtures.persist_user!()
    organization = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(user, organization)

    mission =
      TestFixtures.persist_mission!(organization,
        slug: "declarative-applications",
        display_name: "Declarative Applications"
      )

    %{
      conn: TestFixtures.member_conn(user),
      mission: mission
    }
  end

  test "installs a registered mission application from the host inventory", context do
    {:ok, view, _html} =
      live(context.conn, ~p"/missions/#{context.mission.mission_id}/applications")

    assert has_element?(view, "#mission-applications-page-component")

    presentation = mission_applications_presentation(view)

    assert presentation["root"]["attrs"]["id"] == "mission-applications-page"

    assert presentation["applications_component"]["attrs"]["id"] ==
             "mission-applications-component"

    vue = mission_applications_vue(view)

    assert vue.component == "MissionApplicationsPage"
    assert vue.use_diff == false
    assert vue.handlers["install"] == JS.push("install_application")
    assert vue.handlers["disable"] == JS.push("disable_application")
    assert vue.handlers["uninstall"] == JS.push("uninstall_application")

    application = application_prop(view, "derived_telemetry")

    assert application["id"] == "mission-application-derived_telemetry"

    assert application["install_action"]["id"] ==
             "install-mission-application-derived_telemetry"

    assert application["install_action"]["label"] == "Install"

    assert application["status"] == %{
             "state" => "not_installed",
             "label" => "Not installed",
             "tone" => "info",
             "facts" => [
               %{
                 "id" => "workspace",
                 "label" => "Workspace",
                 "value" => "Install to configure"
               },
               %{
                 "id" => "application_version",
                 "label" => "Application version",
                 "value" => "v1"
               }
             ]
           }

    render_click(view, "install_application", %{"key" => "derived_telemetry"})

    application = application_prop(view, "derived_telemetry")

    assert application["manageable"]

    assert application["manage_path"] ==
             "/missions/#{context.mission.mission_id}/applications/derived_telemetry"

    disable_action = application["disable_action"]

    assert disable_action["id"] == "disable-mission-application-derived_telemetry"
    assert disable_action["action_id"] == "disable"
    assert disable_action["label"] == "Disable workspace"
    assert disable_action["confirmation"]["tone"] == "attention"

    assert disable_action["confirmation"]["prompt"] =~
             "active runtime state is unchanged"

    uninstall_action = application["uninstall_action"]

    assert uninstall_action["id"] == "uninstall-mission-application-derived_telemetry"
    assert uninstall_action["action_id"] == "uninstall"
    assert uninstall_action["label"] == "Uninstall"
    assert uninstall_action["confirmation"]["tone"] == "danger"
  end

  test "renders and submits a generated form through the declarative host", context do
    {:ok, inventory, _html} =
      live(context.conn, ~p"/missions/#{context.mission.mission_id}/applications")

    render_click(inventory, "install_application", %{"key" => "derived_telemetry"})

    application_path =
      ~p"/missions/#{context.mission.mission_id}/applications/derived_telemetry"

    {:ok, view, _html} = live(context.conn, application_path)

    assert has_element?(
             view,
             "#mission-application-host[data-application-key='derived_telemetry'][data-application-version='1'][data-surface-id='manage'][data-renderer='declarative']"
           )

    assert has_element?(view, "#application-host-component")

    vue = LiveVue.Test.get_vue(view, id: "application-host-component")
    assert vue.component == "ApplicationHost"
    assert vue.handlers["application_form_change"] == JS.push("application_form_change")
    assert vue.handlers["application_action"] == JS.push("application_action")
    assert vue.handlers["application_table_page"] == JS.push("application_table_page")

    stream_names =
      for ["replace", "/" <> stream_name, []] <- vue.streams_diff,
          do: stream_name

    assert Enum.sort(stream_names) ==
             ~w(application_surface_activity application_surface_packet_groups application_surface_rows)

    assert Map.take(vue.props["host"], [
             "dom_id",
             "application_key",
             "application_version",
             "surface_id",
             "renderer"
           ]) == %{
             "dom_id" => "mission-application-host",
             "application_key" => "derived_telemetry",
             "application_version" => 1,
             "surface_id" => "manage",
             "renderer" => "declarative"
           }

    surface = vue.props["declarative_surface"]
    assert surface["id"] == "declarative-application-surface"

    form = surface["form"]
    assert form["form_id"] == "derived-telemetry-definition-form-fields"

    assert form["action"] == %{
             "id" => "derived-telemetry-definition-form-submit",
             "action_id" => "save_definition",
             "label" => "Save definition",
             "version" => 1,
             "intent" => "configuration",
             "scope" => "mission",
             "effect" => "durable",
             "execution" => "immediate",
             "confirmation" => nil,
             "disabled" => false
           }

    point_id_field = Enum.find(form["fields"], &(&1["field"] == "point_id"))
    assert point_id_field["id"] == "derived-telemetry-definition-form-field-point_id"
    assert point_id_field["contract_type"] == "text"
    assert point_id_field["type"] == "text"
    assert point_id_field["name"] == "application_action[point_id]"
    assert point_id_field["value"] == ""
    assert point_id_field["reference"] == nil

    assert surface["table"]["rows_id"] == "derived-telemetry-definitions-rows"

    render_hook(view, "application_action", %{
      "action-id" => "save_definition",
      "application_action" => %{
        "point_id" => "DERIVED.bus_power",
        "point_name" => "Bus power",
        "expression" => "HK.voltage * HK.current"
      }
    })

    refreshed_vue = LiveVue.Test.get_vue(view, id: "application-host-component")

    assert refreshed_vue.props["declarative_surface"]["action_feedback"] == %{
             "id" => "application-action-feedback",
             "role" => "status",
             "kind" => "success",
             "code" => "action_completed",
             "label" => "Action complete",
             "message" => "Derived telemetry definition saved."
           }

    rows =
      for ["upsert", path, row] <- refreshed_vue.streams_diff,
          String.starts_with?(path, "/application_surface_rows/"),
          do: row

    assert [row] = rows
    assert row["__dom_id"] =~ "application-surface-row-"
    assert row["values"]["point"] == "DERIVED.bus_power"

    {:ok, remounted_view, _html} = live(context.conn, application_path)

    remounted_vue = LiveVue.Test.get_vue(remounted_view, id: "application-host-component")

    remounted_rows =
      for ["upsert", path, row] <- remounted_vue.streams_diff,
          String.starts_with?(path, "/application_surface_rows/"),
          do: row

    assert Enum.any?(remounted_rows, &(&1["values"]["point"] == "DERIVED.bus_power"))

    contract = %{"props" => refreshed_vue.props, "streams_diff" => refreshed_vue.streams_diff}
    assert contract == Jason.decode!(Jason.encode!(contract))
  end

  test "paginates declarative application tables through shareable host state", context do
    {:ok, inventory, _html} =
      live(context.conn, ~p"/missions/#{context.mission.mission_id}/applications")

    render_click(inventory, "install_application", %{"key" => "derived_telemetry"})

    for number <- 1..21 do
      suffix = number |> Integer.to_string() |> String.pad_leading(3, "0")

      definition =
        DerivedDefinition.new(%{
          mission_id: context.mission.mission_id,
          derived_definition_id: "live-paged-definition-#{suffix}",
          point_id: "DERIVED.live_paged_#{suffix}",
          point_name: "Live paged #{suffix}",
          expression: "HK.source_#{suffix} * 2"
        })

      assert {:ok, ^definition} = Cadence.Governance.persist_derived_definition(definition)
    end

    application_path =
      ~p"/missions/#{context.mission.mission_id}/applications/derived_telemetry"

    {:ok, view, _html} = live(context.conn, application_path)

    vue = LiveVue.Test.get_vue(view, id: "application-host-component")
    pagination = vue.props["declarative_surface"]["table"]["pagination"]
    assert pagination["id"] == "derived-telemetry-definitions-pagination"
    assert pagination["range_label"] == "1–20 of 21"
    assert pagination["next_label"] == "Next"
    assert pagination["next_page"] == 2

    page_one_rows =
      for ["upsert", path, row] <- vue.streams_diff,
          String.starts_with?(path, "/application_surface_rows/"),
          do: row

    assert Enum.any?(page_one_rows, &(&1["values"]["point"] == "DERIVED.live_paged_001"))
    refute Enum.any?(page_one_rows, &(&1["values"]["point"] == "DERIVED.live_paged_021"))

    render_hook(view, "application_table_page", %{"page" => "2"})

    page_two_path =
      "/missions/#{context.mission.mission_id}/applications/derived_telemetry/manage?page=2"

    assert_patch(view, page_two_path)

    page_two_vue = LiveVue.Test.get_vue(view, id: "application-host-component")
    page_two_pagination = page_two_vue.props["declarative_surface"]["table"]["pagination"]
    assert page_two_pagination["page"] == 2
    assert page_two_pagination["previous_label"] == "Prev"
    assert page_two_pagination["previous_page"] == 1

    page_two_rows =
      for ["upsert", path, row] <- page_two_vue.streams_diff,
          String.starts_with?(path, "/application_surface_rows/"),
          do: row

    assert Enum.any?(page_two_rows, &(&1["values"]["point"] == "DERIVED.live_paged_021"))
    refute Enum.any?(page_two_rows, &(&1["values"]["point"] == "DERIVED.live_paged_001"))

    {:ok, deep_linked_view, _html} = live(context.conn, page_two_path)

    deep_linked_vue = LiveVue.Test.get_vue(deep_linked_view, id: "application-host-component")

    deep_linked_rows =
      for ["upsert", path, row] <- deep_linked_vue.streams_diff,
          String.starts_with?(path, "/application_surface_rows/"),
          do: row

    assert deep_linked_vue.props["declarative_surface"]["table"]["pagination"]["page"] == 2
    assert Enum.any?(deep_linked_rows, &(&1["values"]["point"] == "DERIVED.live_paged_021"))
  end

  test "disables, uninstalls, and reinstalls a mission application", context do
    inventory_path = ~p"/missions/#{context.mission.mission_id}/applications"
    {:ok, view, _html} = live(context.conn, inventory_path)

    render_click(view, "install_application", %{"key" => "derived_telemetry"})

    application = application_prop(view, "derived_telemetry")
    assert application["disable_action"]["id"] == "disable-mission-application-derived_telemetry"

    assert application["uninstall_action"]["id"] ==
             "uninstall-mission-application-derived_telemetry"

    render_click(view, "disable_application", %{"key" => "derived_telemetry"})

    application = application_prop(view, "derived_telemetry")
    assert application["install_action"]["label"] == "Enable"

    assert application["uninstall_action"]["id"] ==
             "uninstall-mission-application-derived_telemetry"

    render_click(view, "install_application", %{"key" => "derived_telemetry"})

    render_click(view, "uninstall_application", %{"key" => "derived_telemetry"})

    application = application_prop(view, "derived_telemetry")
    assert application["install_action"]["label"] == "Reinstall"
    assert is_nil(application["uninstall_action"])

    assert {:error,
            {:live_redirect,
             %{
               to: ^inventory_path,
               flash: %{"error" => "Reinstall the application before opening it."}
             }}} =
             live(
               context.conn,
               ~p"/missions/#{context.mission.mission_id}/applications/derived_telemetry"
             )

    render_click(view, "install_application", %{"key" => "derived_telemetry"})

    assert application_prop(view, "derived_telemetry")["disable_action"]["id"] ==
             "disable-mission-application-derived_telemetry"
  end

  test "installs limits and versions a governed threshold definition through the host", context do
    derived_definition =
      DerivedDefinition.new(%{
        mission_id: context.mission.mission_id,
        derived_definition_id: "derived-definition-live-host",
        point_id: "DERIVED.bus_power",
        point_name: "Bus power",
        expression: "HK.voltage * HK.current"
      })

    assert {:ok, ^derived_definition} =
             Cadence.Governance.persist_derived_definition(derived_definition)

    {:ok, inventory, _html} =
      live(context.conn, ~p"/missions/#{context.mission.mission_id}/applications")

    limits_application = application_prop(inventory, "limits")
    assert limits_application["id"] == "mission-application-limits"
    assert limits_application["install_action"]["id"] == "install-mission-application-limits"
    assert limits_application["install_action"]["label"] == "Install"

    assert Enum.any?(
             limits_application["status"]["facts"],
             &(&1 == %{
                 "id" => "workspace",
                 "label" => "Workspace",
                 "value" => "Install to configure"
               })
           )

    render_click(inventory, "install_application", %{"key" => "limits"})

    application_path = ~p"/missions/#{context.mission.mission_id}/applications/limits"
    {:ok, view, _html} = live(context.conn, application_path)

    assert has_element?(
             view,
             "#mission-application-host[data-application-key='limits'][data-application-version='1'][data-surface-id='manage'][data-renderer='declarative']"
           )

    vue = LiveVue.Test.get_vue(view, id: "application-host-component")
    surface = vue.props["declarative_surface"]
    form = surface["form"]
    assert form["form_id"] == "limit-definition-form-fields"

    assert form["action"] == %{
             "id" => "limit-definition-form-submit",
             "action_id" => "save_limit_definition",
             "label" => "Save limit definition",
             "version" => 1,
             "intent" => "configuration",
             "scope" => "mission",
             "effect" => "durable",
             "execution" => "immediate",
             "confirmation" => nil,
             "disabled" => false
           }

    point_id_field = Enum.find(form["fields"], &(&1["field"] == "point_id"))
    assert point_id_field["id"] == "limit-definition-form-field-point_id"
    assert point_id_field["contract_type"] == "reference"
    assert point_id_field["type"] == "text"
    assert point_id_field["name"] == "application_action[point_id]"

    assert point_id_field["reference"] == %{
             "provider_id" => "cadence.telemetry.canonical_points",
             "version" => 1,
             "mode" => "search",
             "query" => "",
             "result_limit" => 20,
             "options_id" => "limit-definition-form-reference-point_id-options",
             "status_id" => "limit-definition-form-reference-point_id-status",
             "match_count" => 1,
             "more_matches" => false,
             "debounce_ms" => 250,
             "max_length" => 120,
             "result_summary" => "1 mission reference",
             "options" => [
               %{
                 "label" => "DERIVED.bus_power",
                 "value" => "DERIVED.bus_power",
                 "disabled" => false,
                 "description" => "Derived telemetry · Bus power"
               }
             ]
           }

    render_hook(view, "application_form_change", %{
      "_target" => ["application_action", "point_id"],
      "application_action" => %{"point_id" => "power"}
    })

    searched_vue = LiveVue.Test.get_vue(view, id: "application-host-component")
    searched_form = searched_vue.props["declarative_surface"]["form"]
    searched_point_id = Enum.find(searched_form["fields"], &(&1["field"] == "point_id"))
    assert searched_point_id["reference"]["query"] == "power"

    assert Enum.any?(
             searched_point_id["reference"]["options"],
             &(&1["value"] == "DERIVED.bus_power")
           )

    render_hook(view, "application_form_change", %{
      "_target" => ["application_action", "point_id"],
      "application_action" => %{"point_id" => "missing"}
    })

    missing_vue = LiveVue.Test.get_vue(view, id: "application-host-component")
    missing_form = missing_vue.props["declarative_surface"]["form"]
    missing_point_id = Enum.find(missing_form["fields"], &(&1["field"] == "point_id"))
    assert missing_point_id["reference"]["match_count"] == 0
    assert missing_point_id["reference"]["more_matches"] == false
    assert missing_point_id["reference"]["result_summary"] == "No matching mission references"
    assert missing_point_id["reference"]["options"] == []

    number_fields = Enum.filter(missing_form["fields"], &(&1["type"] == "number"))
    assert Enum.all?(number_fields, &(&1["step"] == "any"))

    assert missing_vue.props["declarative_surface"]["table"]["rows_id"] ==
             "limit-definitions-rows"

    assert missing_vue.props["declarative_surface"]["activity"] == nil

    navigation = missing_vue.props["navigation"]
    manage_item = Enum.find(navigation["items"], &(&1["surface_id"] == "manage"))
    assert manage_item["id"] == "application-surface-nav-manage"
    assert manage_item["current"]
    assert manage_item["label"] == "Definitions"

    activity_path =
      ~p"/missions/#{context.mission.mission_id}/applications/limits/activity"

    activity_item = Enum.find(navigation["items"], &(&1["surface_id"] == "activity"))
    assert activity_item["id"] == "application-surface-nav-activity"
    assert activity_item["href"] == activity_path
    assert activity_item["label"] == "Current posture"

    render_hook(view, "application_action", %{
      "action-id" => "save_limit_definition",
      "application_action" => %{
        "point_id" => "DERIVED.bus_power",
        "limit_set_name" => "FLIGHT",
        "red_high" => "hot"
      }
    })

    invalid_vue = LiveVue.Test.get_vue(view, id: "application-host-component")
    invalid_surface = invalid_vue.props["declarative_surface"]

    assert invalid_surface["action_feedback"] == %{
             "id" => "application-action-feedback",
             "role" => "alert",
             "kind" => "error",
             "code" => "invalid_number",
             "label" => "Action blocked",
             "message" => "Red high must be a number."
           }

    red_high_field =
      Enum.find(invalid_surface["form"]["fields"], &(&1["field"] == "red_high"))

    assert red_high_field["name"] == "application_action[red_high]"
    assert red_high_field["value"] == "hot"
    assert red_high_field["errors"] == ["Red high must be a number."]

    invalid_rows =
      for ["upsert", path, row] <- invalid_vue.streams_diff,
          String.starts_with?(path, "/application_surface_rows/"),
          do: row

    assert invalid_rows == []

    render_hook(view, "application_action", %{
      "action_id" => "save_limit_definition",
      "application_action" => %{
        "point_id" => "DERIVED.bus_power",
        "limit_set_name" => "FLIGHT",
        "yellow_low" => "25.5",
        "yellow_high" => "31.0",
        "red_low" => "24.0",
        "red_high" => "32.5"
      }
    })

    saved_vue = LiveVue.Test.get_vue(view, id: "application-host-component")
    assert saved_vue.props["declarative_surface"]["action_feedback"]["kind"] == "success"
    assert saved_vue.props["declarative_surface"]["action_feedback"]["code"] == "action_completed"

    assert saved_vue.props["declarative_surface"]["action_feedback"]["message"] ==
             "Limit definition saved."

    saved_rows =
      for ["upsert", path, row] <- saved_vue.streams_diff,
          String.starts_with?(path, "/application_surface_rows/"),
          do: row

    assert [saved_row] = saved_rows
    assert saved_row["values"]["point"] == "DERIVED.bus_power"
    assert saved_row["values"]["thresholds"] == "RL 24.0 · YL 25.5 · YH 31.0 · RH 32.5"

    now = DateTime.utc_now()

    event = %Event{
      limit_event_id: "limit-event-live-host",
      mission_id: context.mission.mission_id,
      spacecraft_id: nil,
      point_id: "HK.bus_voltage",
      point_name: "Bus voltage",
      source_sample_type: :telemetry_sample,
      sample_id: "sample-live-host",
      limit_definition_id: "limit-definition-live-host",
      limit_definition_version: 1,
      limit_set_name: "FLIGHT",
      evaluated_value: 33.2,
      limit_state: :red_high,
      normalized_state: :red,
      violation: true,
      generation_time: now,
      receipt_time: now,
      provenance: %{}
    }

    assert {:ok, [_row]} = Store.persist_latest_states(Repo, [event])

    {:ok, remounted_view, _html} = live(context.conn, application_path)
    remounted_vue = LiveVue.Test.get_vue(remounted_view, id: "application-host-component")

    remounted_rows =
      for ["upsert", path, row] <- remounted_vue.streams_diff,
          String.starts_with?(path, "/application_surface_rows/"),
          do: row

    assert Enum.any?(remounted_rows, &(&1["values"]["version"] == "v1"))
    assert remounted_vue.props["declarative_surface"]["activity"] == nil

    {:ok, activity_view, _html} = live(context.conn, activity_path)

    assert has_element?(
             activity_view,
             "#mission-application-host[data-application-key='limits'][data-surface-id='activity']"
           )

    activity_vue = LiveVue.Test.get_vue(activity_view, id: "application-host-component")
    activity_surface = activity_vue.props["declarative_surface"]
    activity_navigation = activity_vue.props["navigation"]

    current_activity_item =
      Enum.find(activity_navigation["items"], &(&1["surface_id"] == "activity"))

    assert current_activity_item["current"]
    assert current_activity_item["label"] == "Current posture"
    assert activity_surface["form"] == nil
    assert activity_surface["table"] == nil

    assert activity_surface["diagnostics"]["id"] == "limit-current-diagnostics"
    assert activity_surface["diagnostics"]["severity"] == "error"
    assert activity_surface["diagnostics"]["count"] == 1
    assert activity_surface["diagnostics"]["total_count"] == 1

    assert [diagnostic] = activity_surface["diagnostics"]["items"]
    assert diagnostic["id"] == "limit-current-diagnostics-item-red-departures"
    assert diagnostic["code"] == "limits.current.red"
    assert diagnostic["severity"] == "error"
    assert diagnostic["title"] == "Red limit departures"

    activity_rows =
      for ["upsert", path, item] <- activity_vue.streams_diff,
          String.starts_with?(path, "/application_surface_activity/"),
          do: item

    assert [activity_row] = activity_rows
    assert activity_row["__dom_id"] =~ "application-surface-activity-"
    assert activity_row["title"] == "Bus voltage"
    assert activity_row["value"] == "33.2"
  end

  test "known but uninstalled mission application redirects to the inventory", context do
    assert {:error,
            {:live_redirect,
             %{
               to: path,
               flash: %{"error" => "Install the application before opening it."}
             }}} =
             live(
               context.conn,
               ~p"/missions/#{context.mission.mission_id}/applications/derived_telemetry"
             )

    assert path == ~p"/missions/#{context.mission.mission_id}/applications"
  end

  test "projects the complete inventory shell through one JSON-safe non-SSR parent", context do
    {:ok, view, _html} =
      live(context.conn, ~p"/missions/#{context.mission.mission_id}/applications")

    assert has_element?(view, "#mission-applications-page-component")

    vue = mission_applications_vue(view)
    presentation = vue.props["presentation"]

    assert vue.component == "MissionApplicationsPage"
    assert vue.class == "contents"
    assert vue.ssr == false
    assert vue.use_diff == false
    assert Map.keys(vue.props) == ["presentation"]
    assert presentation == Jason.decode!(Jason.encode!(presentation))
    assert Map.keys(presentation) == ["applications_component", "header", "root"]

    assert presentation["root"] == %{
             "attrs" => %{"class" => "space-y-6", "id" => "mission-applications-page"}
           }

    assert presentation["header"] == %{
             "attrs" => %{"class" => "border-b border-primary/20 pb-4"},
             "body" => %{"attrs" => %{}},
             "content" => %{"attrs" => %{}},
             "breadcrumbs" => %{
               "attrs" => %{
                 "aria-label" => "Breadcrumb",
                 "class" =>
                   "flex flex-wrap items-center gap-2 text-[0.7rem] font-semibold uppercase tracking-[0.12em] text-base-content/60"
               },
               "items" => [
                 %{
                   "key" => "mission",
                   "separator" => nil,
                   "link" => %{
                     "attrs" => %{
                       "class" => "hover:text-primary transition-colors",
                       "data-phx-link" => "redirect",
                       "data-phx-link-state" => "push",
                       "href" => ~p"/missions/#{context.mission.mission_id}"
                     },
                     "text" => context.mission.display_name
                   },
                   "current" => nil
                 },
                 %{
                   "key" => "applications",
                   "separator" => %{
                     "attrs" => %{
                       "aria-hidden" => "true",
                       "class" => "text-base-content/20"
                     },
                     "text" => "/"
                   },
                   "link" => nil,
                   "current" => %{
                     "attrs" => %{"class" => "text-primary/90"},
                     "text" => "Applications"
                   }
                 }
               ]
             },
             "title" => %{
               "attrs" => %{
                 "class" => "mt-2 text-2xl font-bold text-base-content tracking-tight"
               },
               "text" => "Applications"
             },
             "subtitle" => %{
               "attrs" => %{
                 "class" => "mt-1 max-w-3xl text-sm text-base-content/70"
               },
               "text" =>
                 "Install mission-scoped product capabilities and open their host-rendered workspaces."
             }
           }

    assert presentation["applications_component"]["attrs"] == %{
             "id" => "mission-applications-component"
           }

    assert is_list(presentation["applications_component"]["props"]["applications"])
  end

  test "raw presentation attrs preserve HEEx nil false true string and number semantics" do
    attrs =
      CadenceWeb.MissionApplicationsLive.presentation_attrs(%{
        "nil" => nil,
        "false" => false,
        "true" => true,
        "string" => "retained",
        "number" => 7
      })

    assert attrs == %{
             "true" => "",
             "string" => "retained",
             "number" => "7"
           }
  end

  defp mission_applications_vue(view) do
    LiveVue.Test.get_vue(view, id: "mission-applications-page-component")
  end

  defp mission_applications_presentation(view) do
    mission_applications_vue(view).props["presentation"]
  end

  defp application_prop(view, application_key) do
    view
    |> mission_applications_presentation()
    |> get_in(["applications_component", "props", "applications"])
    |> Enum.find(&(&1["application_key"] == application_key))
  end
end
