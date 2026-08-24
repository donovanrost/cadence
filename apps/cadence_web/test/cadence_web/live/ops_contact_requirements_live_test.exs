defmodule CadenceWeb.OpsContactRequirementsLiveTest do
  use CadenceWeb.ConnCase, async: false

  import CadenceWeb.AsyncLiveViewTestSupport,
    only: [render_async: 1, track_async_view: 1]

  import Phoenix.LiveViewTest, except: [render_async: 1]

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias Cadence.Auth.Scope
  alias Cadence.ContactPlanning.{ContactPlans, ContactRequirements, Planner}
  alias CadenceWeb.TestFixtures

  test "authenticated Ops routes expose Requirements navigation" do
    {member_conn, _scope, _org, mission, _spacecraft} = signed_in_scope()

    {:ok, view, _html} =
      live(member_conn, ~p"/missions/#{mission.mission_id}/ops/requirements")

    assert has_element?(view, "#ops-contact-requirements-component.contents")

    vue = contact_requirements_vue(view)

    assert vue.props["page"]["id"] == "ops-contact-requirements-page"

    assert vue.props["page"]["header"]["create_action"]["id"] ==
             "new-contact-requirement-link"

    assert has_element?(
             view,
             ~s(#ops-nav-rail a[href="/missions/#{mission.mission_id}/ops/requirements"][class*="text-primary"])
           )
  end

  test "list page exposes an exact JSON-safe empty LiveVue contract" do
    {member_conn, _scope, _org, mission, _spacecraft} = signed_in_scope()

    {:ok, view, _html} =
      live(member_conn, ~p"/missions/#{mission.mission_id}/ops/requirements")

    vue = contact_requirements_vue(view)

    assert vue.component == "OpsContactRequirementList"
    assert vue.class == "contents"
    assert vue.ssr == false
    assert vue.props == %{"page" => contact_requirements_page_props(mission.mission_id)}
    assert requirement_rows(vue) == []

    assert requirement_stream_mutations(vue) == [
             ["replace", "/requirements", []]
           ]

    assert_json_safe(vue)
  end

  test "list page initially replaces and upserts exact requirement row contracts" do
    {member_conn, scope, _org, mission, spacecraft} = signed_in_scope()

    {planned_requirement, planned_version} =
      create_requirement_with(scope, mission, spacecraft, %{
        latest_end: DateTime.add(fixed_now(), 36_000, :second),
        priority: :critical
      })

    {searched_requirement, searched_version} =
      create_requirement_with(scope, mission, spacecraft, %{
        contact_intent: "telemetry_downlink",
        latest_end: DateTime.add(fixed_now(), 72_000, :second),
        success_measure: :minimum_duration,
        priority: :high
      })

    {declared_requirement, _declared_version} =
      create_requirement_with(scope, mission, spacecraft, %{
        service_direction: :tracking,
        contact_intent: "tracking_support",
        latest_end: DateTime.add(fixed_now(), 108_000, :second),
        success_measure: :contact_count,
        contact_count: 3,
        priority: :routine
      })

    planned = run_planning(scope, mission, spacecraft, planned_requirement, planned_version)
    searched = run_planning(scope, mission, spacecraft, searched_requirement, searched_version)
    [planned_snapshot] = planned.snapshots

    assert {:ok, plan, _plan_version} =
             ContactPlans.create(
               scope,
               mission.mission_id,
               %{
                 planning_run_ids: [planned.run.contact_planning_run_id],
                 selected_snapshot_ids: [planned_snapshot.contact_opportunity_snapshot_id],
                 rationale: "Commit the first eligible pass"
               },
               now: fixed_now()
             )

    assert plan.lifecycle_state == :draft
    assert searched.run.lifecycle_state == :completed

    {:ok, view, _html} =
      live(member_conn, ~p"/missions/#{mission.mission_id}/ops/requirements")

    vue = contact_requirements_vue(view)

    expected_rows = [
      %{
        "__dom_id" => "contact-requirement-#{planned_requirement.contact_requirement_id}",
        "id" => planned_requirement.contact_requirement_id,
        "priority" => %{
          "label" => "critical",
          "tone" => "error",
          "class" =>
            "border border-error/40 bg-error/10 px-1.5 py-0.5 font-mono text-[0.6rem] uppercase text-error"
        },
        "version_direction" => "v1 · downlink",
        "intent_label" => "Payload downlink",
        "outcome_detail" => "Deliver at least 1.5 GB across 1 contact(s).",
        "window" => %{
          "label" => "Acceptable UTC window",
          "detail" => "16 Jul 21:00Z → 17 Jul 06:00Z"
        },
        "journey" => %{
          "label" => "Plan draft",
          "detail" => "draft"
        },
        "detail_href" =>
          "/missions/#{mission.mission_id}/ops/requirements/#{planned_requirement.contact_requirement_id}"
      },
      %{
        "__dom_id" => "contact-requirement-#{searched_requirement.contact_requirement_id}",
        "id" => searched_requirement.contact_requirement_id,
        "priority" => %{
          "label" => "high",
          "tone" => "warning",
          "class" =>
            "border border-warning/40 bg-warning/10 px-1.5 py-0.5 font-mono text-[0.6rem] uppercase text-warning"
        },
        "version_direction" => "v1 · downlink",
        "intent_label" => "Telemetry downlink",
        "outcome_detail" => "Secure at least 600 seconds of contact time.",
        "window" => %{
          "label" => "Acceptable UTC window",
          "detail" => "16 Jul 21:00Z → 17 Jul 16:00Z"
        },
        "journey" => %{
          "label" => "Options captured",
          "detail" => "completed"
        },
        "detail_href" =>
          "/missions/#{mission.mission_id}/ops/requirements/#{searched_requirement.contact_requirement_id}"
      },
      %{
        "__dom_id" => "contact-requirement-#{declared_requirement.contact_requirement_id}",
        "id" => declared_requirement.contact_requirement_id,
        "priority" => %{
          "label" => "routine",
          "tone" => "neutral",
          "class" =>
            "border border-base-300 px-1.5 py-0.5 font-mono text-[0.6rem] uppercase text-base-content/55"
        },
        "version_direction" => "v1 · tracking",
        "intent_label" => "Tracking support",
        "outcome_detail" => "Secure 3 separated contact window(s).",
        "window" => %{
          "label" => "Acceptable UTC window",
          "detail" => "16 Jul 21:00Z → 18 Jul 02:00Z"
        },
        "journey" => %{
          "label" => "Need declared",
          "detail" => "Search not run"
        },
        "detail_href" =>
          "/missions/#{mission.mission_id}/ops/requirements/#{declared_requirement.contact_requirement_id}"
      }
    ]

    assert requirement_rows(vue) == expected_rows

    assert requirement_stream_mutations(vue) ==
             [["replace", "/requirements", []]] ++
               Enum.map(expected_rows, &["upsert", "/requirements/-", &1])

    assert_json_safe(vue)
  end

  test "outcome-first form progressively changes and creates a durable Requirement" do
    {conn, _scope, org, mission, spacecraft} = signed_in_scope()
    before_mount = DateTime.utc_now()

    sibling_mission =
      TestFixtures.persist_mission!(org,
        slug: "secondary-planning",
        display_name: "Secondary Planning"
      )

    _foreign_spacecraft =
      TestFixtures.persist_spacecraft!(sibling_mission, display_name: "Foreign Spacecraft")

    {:ok, view, _html} =
      live(conn, ~p"/missions/#{mission.mission_id}/ops/requirements/new")

    assert has_element?(view, "#ops-contact-requirement-new-component")
    refute has_element?(view, "#contact-requirement-form")

    vue = contact_requirement_new_vue(view)
    props = vue.props
    fields = props["form"]["fields"]
    earliest_start = fields["earliest_start"]["value"]
    latest_end = fields["latest_end"]["value"]

    assert {:ok, earliest_naive} = NaiveDateTime.from_iso8601(earliest_start)
    assert {:ok, latest_naive} = NaiveDateTime.from_iso8601(latest_end)
    assert NaiveDateTime.diff(latest_naive, earliest_naive, :second) == 24 * 60 * 60

    earliest_datetime = DateTime.from_naive!(earliest_naive, "Etc/UTC")
    assert DateTime.diff(earliest_datetime, before_mount, :second) in (14 * 60)..(16 * 60)

    assert props["page"] == %{
             "id" => "ops-contact-requirement-new-page",
             "eyebrow" => "Need / outcome-first declaration",
             "heading" => "What does the mission need?",
             "description" =>
               "Describe success and the acceptable horizon. Provider, station, and route choices remain planning concerns—not part of the need itself."
           }

    assert props["journey"] == %{
             "outcome" => %{
               "id" => "contact-requirement-outcome-section",
               "step" => "01",
               "title" => "Mission outcome",
               "copy" => "The operator-readable reason this contact must exist."
             },
             "horizon" => %{
               "id" => "contact-requirement-horizon-section",
               "step" => "02",
               "title" => "Acceptable horizon",
               "copy" => "All times are coordinated universal time."
             },
             "advanced" => %{
               "id" => "requirement-advanced-constraints",
               "title" => "Advanced constraints",
               "copy" => "Optional provider and station boundaries"
             },
             "rationale" => %{"id" => "contact-requirement-rationale-section"},
             "progressive" => %{
               "minimum_data_volume" => %{
                 "id" => "requirement-minimum-data-volume-section",
                 "visible" => true,
                 "visible_for" => ["minimum_data_volume"]
               },
               "minimum_duration" => %{
                 "id" => "requirement-minimum-duration-section",
                 "visible" => true,
                 "visible_for" => ["minimum_duration", "minimum_data_volume"]
               }
             }
           }

    assert props["actions"] == %{
             "back" => %{
               "id" => "contact-requirements-back-link",
               "label" => "Requirements",
               "href" => "/missions/#{mission.mission_id}/ops/requirements",
               "icon" => "hero-arrow-left"
             },
             "cancel" => %{
               "id" => "cancel-contact-requirement",
               "label" => "Cancel",
               "href" => "/missions/#{mission.mission_id}/ops/requirements"
             },
             "submit" => %{
               "id" => "save-contact-requirement",
               "label" => "Declare need"
             }
           }

    assert props["form"] == %{
             "id" => "contact-requirement-form",
             "fields" =>
               expected_contact_requirement_fields(spacecraft, earliest_start, latest_end),
             "error" => nil
           }

    params =
      spacecraft
      |> requirement_form_params()
      |> Map.put("allowed_providers", " provider-a, provider-a, ")

    minimum_duration_params =
      params
      |> Map.put("success_measure", "minimum_duration")
      |> Map.put("minimum_data_volume_bytes", "")

    render_hook(view, "validate", %{"contact_requirement" => minimum_duration_params})

    progressive = contact_requirement_new_vue(view).props["journey"]["progressive"]

    refute progressive["minimum_data_volume"]["visible"]
    assert progressive["minimum_duration"]["visible"]

    contact_count_params =
      params
      |> Map.put("success_measure", "contact_count")
      |> Map.drop(["minimum_data_volume_bytes", "minimum_duration_seconds"])

    render_hook(view, "validate", %{"contact_requirement" => contact_count_params})

    progressive = contact_requirement_new_vue(view).props["journey"]["progressive"]
    fields = contact_requirement_new_vue(view).props["form"]["fields"]

    refute progressive["minimum_data_volume"]["visible"]
    refute progressive["minimum_duration"]["visible"]
    assert fields["success_measure"]["value"] == "contact_count"
    assert fields["minimum_data_volume_bytes"]["value"] == ""
    assert fields["minimum_duration_seconds"]["value"] == ""

    params_without_progressive_values =
      Map.drop(params, ["minimum_data_volume_bytes", "minimum_duration_seconds"])

    render_hook(view, "validate", %{
      "contact_requirement" => params_without_progressive_values
    })

    progressive = contact_requirement_new_vue(view).props["journey"]["progressive"]
    fields = contact_requirement_new_vue(view).props["form"]["fields"]

    assert progressive["minimum_data_volume"]["visible"]
    assert progressive["minimum_duration"]["visible"]
    assert fields["minimum_data_volume_bytes"]["value"] == ""
    assert fields["minimum_duration_seconds"]["value"] == ""

    render_hook(view, "save", %{"contact_requirement" => params})

    [{requirement, version}] =
      ContactRequirements.list(org.organization_id, mission.mission_id)

    expected_path =
      ~p"/missions/#{mission.mission_id}/ops/requirements/#{requirement.contact_requirement_id}"

    assert {^expected_path, %{}} = assert_redirect(view)

    assert version.spacecraft_id == spacecraft.spacecraft_id
    assert version.service_direction == :downlink
    assert version.contact_intent == "payload_downlink"
    assert version.earliest_start == parsed_form_datetime(params["earliest_start"])
    assert version.latest_end == parsed_form_datetime(params["latest_end"])
    assert version.success_measure == :minimum_data_volume
    assert version.minimum_duration_seconds == 600
    assert version.minimum_data_volume_bytes == 1_500_000_000
    assert version.preferred_duration_seconds == 900
    assert version.contact_count == 1
    assert version.minimum_separation_seconds == 0
    assert version.priority == :high
    assert version.provider_constraints_document["allowed"] == ["provider-a"]
    assert version.provider_constraints_document["excluded"] == []

    assert version.station_constraints_document == %{
             "allowed" => [],
             "excluded" => ["station-c"]
           }

    assert version.policy_constraints_document == %{}
    assert version.approval_policy_document == %{"mode" => "manual"}
    assert version.rationale == "Recorder pressure requires a downlink"
    assert version.metadata == %{"source" => "ops_contact_requirement_form"}
  end

  test "new Requirement form keeps server validation values and errors authoritative" do
    {conn, _scope, org, mission, spacecraft} = signed_in_scope()

    {:ok, view, _html} =
      live(conn, ~p"/missions/#{mission.mission_id}/ops/requirements/new")

    valid_params = requirement_form_params(spacecraft)

    validation_cases = [
      {Map.put(valid_params, "earliest_start", "not-a-time"),
       "Enter a valid UTC start and end time."},
      {Map.put(valid_params, "minimum_separation_seconds", "-1"),
       "Numeric outcomes must be positive whole numbers."},
      {Map.put(valid_params, "latest_end", valid_params["earliest_start"]),
       "latest_end must be after earliest_start"},
      {valid_params
       |> Map.put("allowed_providers", "provider-a")
       |> Map.put("excluded_providers", "provider-a"),
       "Cadence could not declare this need. Review the outcome and constraints."}
    ]

    for {invalid_params, message} <- validation_cases do
      render_hook(view, "save", %{"contact_requirement" => invalid_params})

      form = contact_requirement_new_vue(view).props["form"]

      assert form["error"] == %{
               "id" => "contact-requirement-form-error",
               "message" => message
             }

      for {field, value} <- invalid_params do
        assert form["fields"][field]["value"] == value
      end

      assert ContactRequirements.list(org.organization_id, mission.mission_id) == []

      render_hook(view, "validate", %{"contact_requirement" => valid_params})
      assert contact_requirement_new_vue(view).props["form"]["error"] == nil
    end
  end

  test "new Requirement route requires authenticated mission scope", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/sign-in"}}} =
             live(conn, ~p"/missions/mission-test/ops/requirements/new")
  end

  defp contact_requirement_new_vue(view) do
    vue = LiveVue.Test.get_vue(view, id: "ops-contact-requirement-new-component")

    assert vue.component == "OpsContactRequirementNew"
    assert vue.class == "contents"
    assert vue.ssr == false
    assert vue.props == Jason.decode!(Jason.encode!(vue.props))
    assert Enum.sort(Map.keys(vue.props)) == ["actions", "form", "journey", "page"]

    assert vue.handlers == %{
             "save" => Phoenix.LiveView.JS.push("save"),
             "validate" => Phoenix.LiveView.JS.push("validate")
           }

    vue
  end

  defp expected_contact_requirement_fields(spacecraft, earliest_start, latest_end) do
    %{
      "spacecraft_id" => %{
        "id" => "requirement-spacecraft",
        "name" => "contact_requirement[spacecraft_id]",
        "type" => "select",
        "label" => "Spacecraft",
        "required" => true,
        "value" => spacecraft.spacecraft_id,
        "options" => [
          %{"label" => spacecraft.display_name, "value" => spacecraft.spacecraft_id}
        ]
      },
      "contact_intent" => %{
        "id" => "requirement-intent",
        "name" => "contact_requirement[contact_intent]",
        "type" => "select",
        "label" => "Contact intent",
        "required" => false,
        "value" => "payload_downlink",
        "options" => [
          %{"label" => "Payload downlink", "value" => "payload_downlink"},
          %{"label" => "Health and safety", "value" => "health_and_safety"},
          %{"label" => "TT&C maintenance", "value" => "ttc_maintenance"},
          %{"label" => "Commissioning", "value" => "commissioning"}
        ]
      },
      "success_measure" => %{
        "id" => "requirement-success-measure",
        "name" => "contact_requirement[success_measure]",
        "type" => "select",
        "label" => "Success means",
        "required" => false,
        "value" => "minimum_data_volume",
        "options" => [
          %{"label" => "Minimum data volume", "value" => "minimum_data_volume"},
          %{"label" => "Minimum contact duration", "value" => "minimum_duration"},
          %{"label" => "Number of contacts", "value" => "contact_count"},
          %{"label" => "Any eligible contact", "value" => "any_contact"}
        ]
      },
      "priority" => %{
        "id" => "requirement-priority",
        "name" => "contact_requirement[priority]",
        "type" => "select",
        "label" => "Operational priority",
        "required" => false,
        "value" => "high",
        "options" => [
          %{"label" => "Routine", "value" => "routine"},
          %{"label" => "High", "value" => "high"},
          %{"label" => "Critical", "value" => "critical"}
        ]
      },
      "earliest_start" => %{
        "id" => "requirement-earliest-start",
        "name" => "contact_requirement[earliest_start]",
        "type" => "datetime-local",
        "label" => "Earliest start (UTC)",
        "required" => true,
        "value" => earliest_start
      },
      "latest_end" => %{
        "id" => "requirement-latest-end",
        "name" => "contact_requirement[latest_end]",
        "type" => "datetime-local",
        "label" => "Latest end (UTC)",
        "required" => true,
        "value" => latest_end
      },
      "minimum_data_volume_bytes" => %{
        "id" => "requirement-minimum-data-volume",
        "name" => "contact_requirement[minimum_data_volume_bytes]",
        "type" => "number",
        "label" => "Minimum data volume (bytes)",
        "required" => false,
        "value" => "1000000000",
        "min" => "1"
      },
      "minimum_duration_seconds" => %{
        "id" => "requirement-minimum-duration",
        "name" => "contact_requirement[minimum_duration_seconds]",
        "type" => "number",
        "label" => "Minimum window duration (seconds)",
        "required" => false,
        "value" => "600",
        "min" => "1"
      },
      "preferred_duration_seconds" => %{
        "id" => "requirement-preferred-duration",
        "name" => "contact_requirement[preferred_duration_seconds]",
        "type" => "number",
        "label" => "Preferred window duration (seconds)",
        "required" => false,
        "value" => "900",
        "min" => "1"
      },
      "contact_count" => %{
        "id" => "requirement-contact-count",
        "name" => "contact_requirement[contact_count]",
        "type" => "number",
        "label" => "Required contact count",
        "required" => false,
        "value" => "1",
        "min" => "1"
      },
      "minimum_separation_seconds" => %{
        "id" => "requirement-minimum-separation",
        "name" => "contact_requirement[minimum_separation_seconds]",
        "type" => "number",
        "label" => "Minimum separation (seconds)",
        "required" => false,
        "value" => "0",
        "min" => "0"
      },
      "allowed_providers" => %{
        "id" => "requirement-allowed-providers",
        "name" => "contact_requirement[allowed_providers]",
        "type" => "text",
        "label" => "Allowed provider IDs",
        "required" => false,
        "value" => "",
        "placeholder" => "provider-a, provider-b"
      },
      "excluded_providers" => %{
        "id" => "requirement-excluded-providers",
        "name" => "contact_requirement[excluded_providers]",
        "type" => "text",
        "label" => "Excluded provider IDs",
        "required" => false,
        "value" => "",
        "placeholder" => "provider-c"
      },
      "allowed_stations" => %{
        "id" => "requirement-allowed-stations",
        "name" => "contact_requirement[allowed_stations]",
        "type" => "text",
        "label" => "Allowed station refs",
        "required" => false,
        "value" => "",
        "placeholder" => "station-a, station-b"
      },
      "excluded_stations" => %{
        "id" => "requirement-excluded-stations",
        "name" => "contact_requirement[excluded_stations]",
        "type" => "text",
        "label" => "Excluded station refs",
        "required" => false,
        "value" => "",
        "placeholder" => "station-c"
      },
      "rationale" => %{
        "id" => "requirement-rationale",
        "name" => "contact_requirement[rationale]",
        "type" => "textarea",
        "label" => "Operator rationale",
        "required" => true,
        "value" => "",
        "placeholder" => "Why this outcome and horizon are operationally important",
        "maxlength" => "2000"
      }
    }
  end

  defp parsed_form_datetime(value) do
    datetime =
      value
      |> NaiveDateTime.from_iso8601!()
      |> DateTime.from_naive!("Etc/UTC")

    %{datetime | microsecond: {0, 6}}
  end

  test "Requirement detail preserves no-route readiness as evidence rather than no availability" do
    {conn, scope, _org, mission, spacecraft} = signed_in_scope()
    {requirement, _version} = create_requirement(scope, mission, spacecraft)

    {:ok, view, _html} =
      live(
        conn,
        ~p"/missions/#{mission.mission_id}/ops/requirements/#{requirement.contact_requirement_id}"
      )

    track_async_view(view)

    initial_vue = contact_requirement_show_vue(view)
    initial_page = initial_vue.props["page"]

    assert initial_page["id"] == "ops-contact-requirement-show-page"
    assert initial_page["header"]["plan_action"]["id"] == "plan-contact-requirement"
    assert initial_page["planning"]["searches"]["empty"]["id"] == "planning-searches-empty"
    assert contact_requirement_stream_rows(initial_vue, "planning_searches") == []

    render_hook(view, "plan", %{})
    render_async(view)

    planned_vue = contact_requirement_show_vue(view)
    planned_page = planned_vue.props["page"]
    [search] = contact_requirement_stream_rows(planned_vue, "planning_searches")

    [run] =
      Planner.list_runs(
        scope.organization_id,
        mission.mission_id,
        requirement.contact_requirement_id
      )

    [durable_search] =
      Planner.list_searches(
        scope.organization_id,
        mission.mission_id,
        run.contact_planning_run_id
      )

    assert search == %{
             "__dom_id" => "planning-search-#{durable_search.contact_planning_search_id}",
             "contact_planning_search_id" => durable_search.contact_planning_search_id,
             "provider_label" =>
               durable_search.readiness_document["message"] || "Route readiness",
             "route_key" => durable_search.route_key,
             "evidence" => %{
               "id" => "planning-search-evidence-#{durable_search.contact_planning_search_id}",
               "summary" => "Provider or route readiness prevented opportunity evaluation."
             },
             "outcome" => %{
               "label" => "not ready",
               "class" => "font-mono text-[0.65rem] uppercase text-warning"
             },
             "opportunity_count" => "0 options"
           }

    assert planned_page["planning"]["run_state"] == %{
             "id" => "planning-run-state",
             "label" => "failed"
           }

    assert planned_page["opportunities"]["list"]["empty"]["id"] ==
             "planning-opportunities-empty"

    assert contact_requirement_stream_rows(planned_vue, "opportunities") == []
    assert_requirement_detail_json_safe(planned_vue)
  end

  test "Requirement detail exposes an exact JSON-safe page and initial stream contract" do
    {conn, scope, _org, mission, spacecraft} = signed_in_scope()
    {requirement, version} = create_requirement(scope, mission, spacecraft)

    {:ok, view, _html} =
      live(
        conn,
        ~p"/missions/#{mission.mission_id}/ops/requirements/#{requirement.contact_requirement_id}"
      )

    vue = contact_requirement_show_vue(view)

    assert vue.component == "OpsContactRequirementShow"
    assert vue.class == "contents"
    assert vue.ssr == false

    assert vue.props == %{
             "page" =>
               contact_requirement_show_page_props(
                 mission.mission_id,
                 spacecraft.spacecraft_id
               )
           }

    expected_version = %{
      "__dom_id" => "requirement-version-#{version.contact_requirement_version_id}",
      "contact_requirement_version_id" => version.contact_requirement_version_id,
      "version_label" => "v1",
      "created_at" => "16 Jul 2026 20:00Z",
      "rationale" => "Recorder pressure requires a downlink",
      "content_sha256" => version.content_sha256
    }

    assert contact_requirement_stream_mutations(vue, "requirement_versions") == [
             ["replace", "/requirement_versions", []],
             ["upsert", "/requirement_versions/-", expected_version]
           ]

    assert contact_requirement_stream_mutations(vue, "planning_searches") == [
             ["replace", "/planning_searches", []]
           ]

    assert contact_requirement_stream_mutations(vue, "opportunities") == [
             ["replace", "/opportunities", []]
           ]

    assert_requirement_detail_json_safe(vue)
  end

  test "Requirement detail preserves exact opportunity selection and draft Plan construction" do
    {conn, scope, _org, mission, spacecraft} = signed_in_scope()
    {requirement, version} = create_requirement(scope, mission, spacecraft)
    planning = run_planning(scope, mission, spacecraft, requirement, version)
    [planning_search] = planning.searches
    [snapshot] = planning.snapshots

    {:ok, view, _html} =
      live(
        conn,
        ~p"/missions/#{mission.mission_id}/ops/requirements/#{requirement.contact_requirement_id}"
      )

    initial_vue = contact_requirement_show_vue(view)
    initial_page = initial_vue.props["page"]

    assert initial_page["planning"]["run_state"] == %{
             "id" => "planning-run-state",
             "label" => "completed"
           }

    assert initial_page["journey"]["steps"] == [
             %{"label" => "Need", "state" => "Declared", "complete" => true},
             %{"label" => "Options", "state" => "completed", "complete" => true},
             %{"label" => "Plan", "state" => "Pending", "complete" => false},
             %{"label" => "Reserved", "state" => "Pending", "complete" => false}
           ]

    expected_search = %{
      "__dom_id" => "planning-search-#{planning_search.contact_planning_search_id}",
      "contact_planning_search_id" => planning_search.contact_planning_search_id,
      "provider_label" => "Ground Network Simulator",
      "route_key" => "route-live-test",
      "evidence" => %{
        "id" => "planning-search-evidence-#{planning_search.contact_planning_search_id}",
        "summary" => "Provider orbit data current"
      },
      "outcome" => %{
        "label" => "succeeded with results",
        "class" => "font-mono text-[0.65rem] uppercase text-success"
      },
      "opportunity_count" => "1 options"
    }

    expected_opportunity = %{
      "__dom_id" => "planning-opportunity-#{snapshot.contact_opportunity_snapshot_id}",
      "contact_opportunity_snapshot_id" => snapshot.contact_opportunity_snapshot_id,
      "provider_display_name" => "Ground Network Simulator",
      "ground_station_ref" => "station-live",
      "starts_at" => "16 Jul 2026 21:00Z",
      "duration" => "900 sec",
      "eligibility" => %{
        "label" => "Eligible",
        "class" => "mt-1 text-xs text-success"
      },
      "eligible" => true,
      "selected" => false,
      "toggle_action" => %{
        "id" => "toggle-#{snapshot.contact_opportunity_snapshot_id}",
        "event" => "toggle-opportunity",
        "payload" => %{"snapshot_id" => snapshot.contact_opportunity_snapshot_id},
        "disabled" => false,
        "aria_label" => "Toggle opportunity selection"
      }
    }

    assert contact_requirement_stream_rows(initial_vue, "planning_searches") == [
             expected_search
           ]

    assert contact_requirement_stream_rows(initial_vue, "opportunities") == [
             expected_opportunity
           ]

    assert initial_page["opportunities"]["selected_count"] == %{
             "id" => "selected-opportunity-count",
             "label" => "0 selected"
           }

    assert initial_page["opportunities"]["create_action"] == %{
             "id" => "create-contact-plan",
             "event" => "create-plan",
             "payload" => %{},
             "label" => "Build draft Plan",
             "disabled" => true
           }

    render_hook(view, "toggle-opportunity", %{
      "snapshot_id" => snapshot.contact_opportunity_snapshot_id
    })

    selected_vue = contact_requirement_show_vue(view)
    selected_page = selected_vue.props["page"]
    selected_opportunity = put_in(expected_opportunity["selected"], true)

    assert selected_page["opportunities"]["selected_count"] == %{
             "id" => "selected-opportunity-count",
             "label" => "1 selected"
           }

    assert selected_page["opportunities"]["create_action"]["disabled"] == false

    assert contact_requirement_stream_mutations(selected_vue, "opportunities") == [
             ["replace", "/opportunities", []],
             ["upsert", "/opportunities/-", selected_opportunity]
           ]

    render_hook(view, "create-plan", %{})

    [{plan, plan_version}] = ContactPlans.list(scope.organization_id, mission.mission_id)

    assert plan.lifecycle_state == :draft
    assert plan_version.selected_snapshot_ids == [snapshot.contact_opportunity_snapshot_id]

    assert plan_version.planning_run_refs_document == %{
             "runs" => [planning.run.contact_planning_run_id]
           }

    assert plan_version.rationale ==
             "Operator-selected provider windows for payload_downlink"

    assert_redirect(
      view,
      ~p"/missions/#{mission.mission_id}/ops/plans/#{plan.contact_plan_id}"
    )
  end

  test "Requirement detail keeps terminal requirements and ineligible opportunities disabled" do
    {conn, scope, _org, mission, spacecraft} = signed_in_scope()
    {requirement, version} = create_requirement(scope, mission, spacecraft)
    unavailable_opportunity = Map.put(opportunity(), "availability", "unavailable")

    assert {:ok, planning} =
             Planner.run(
               scope,
               mission.mission_id,
               requirement.contact_requirement_id,
               version.version,
               now: fixed_now(),
               list_routes: fn _, _, _ ->
                 {:ok, %{routes: [route(spacecraft.spacecraft_id)], findings: []}}
               end,
               search_opportunities: fn _, _, _, _, _ ->
                 {:ok, %{opportunities: [unavailable_opportunity]}}
               end
             )

    assert {:ok, closed_requirement} =
             ContactRequirements.close(
               scope,
               mission.mission_id,
               requirement.contact_requirement_id,
               version.version,
               "Requirement is no longer operationally active",
               now: fixed_now()
             )

    assert closed_requirement.lifecycle_state == :closed
    [snapshot] = planning.snapshots

    {:ok, view, _html} =
      live(
        conn,
        ~p"/missions/#{mission.mission_id}/ops/requirements/#{requirement.contact_requirement_id}"
      )

    vue = contact_requirement_show_vue(view)
    page = vue.props["page"]
    [opportunity_row] = contact_requirement_stream_rows(vue, "opportunities")

    assert page["header"]["plan_action"] == %{
             "id" => "plan-contact-requirement",
             "event" => "plan",
             "payload" => %{},
             "label" => "Find options",
             "disabled" => true
           }

    assert opportunity_row["contact_opportunity_snapshot_id"] ==
             snapshot.contact_opportunity_snapshot_id

    assert opportunity_row["eligibility"] == %{
             "label" => "provider unavailable",
             "class" => "mt-1 text-xs text-error"
           }

    assert opportunity_row["eligible"] == false
    assert opportunity_row["selected"] == false
    assert opportunity_row["toggle_action"]["disabled"] == true
    assert page["opportunities"]["create_action"]["disabled"] == true
    assert_requirement_detail_json_safe(vue)
  end

  test "Requirement detail renders the exact asynchronous planner error" do
    {conn, scope, _org, mission, spacecraft} = signed_in_scope()

    {requirement, _version} =
      create_requirement_with(scope, mission, spacecraft, %{
        service_direction: :tracking,
        contact_intent: "tracking_support"
      })

    {:ok, view, _html} =
      live(
        conn,
        ~p"/missions/#{mission.mission_id}/ops/requirements/#{requirement.contact_requirement_id}"
      )

    track_async_view(view)
    render_hook(view, "plan", %{})
    render_async(view)

    vue = contact_requirement_show_vue(view)
    page = vue.props["page"]

    assert page["header"]["plan_action"] == %{
             "id" => "plan-contact-requirement",
             "event" => "plan",
             "payload" => %{},
             "label" => "Find options",
             "disabled" => false
           }

    assert page["planning"]["run_state"] == %{
             "id" => "planning-run-state",
             "label" => "not run"
           }

    assert page["planning"]["error"] == %{
             "id" => "contact-planning-error",
             "message" => "Only downlink Requirements can be planned in this stage."
           }

    assert_requirement_detail_json_safe(vue)
  end

  defp contact_requirement_show_vue(view) do
    LiveVue.Test.get_vue(view, id: "ops-contact-requirement-show-component")
  end

  defp contact_requirement_stream_mutations(vue, stream_name) do
    stream_path = "/#{stream_name}"

    Enum.filter(vue.streams_diff, fn
      ["replace", ^stream_path, _items] -> true
      ["upsert", path, _item] -> String.starts_with?(path, stream_path <> "/")
      ["remove", path] -> String.starts_with?(path, stream_path <> "/")
      _operation -> false
    end)
  end

  defp contact_requirement_stream_rows(vue, stream_name) do
    vue
    |> contact_requirement_stream_mutations(stream_name)
    |> Enum.flat_map(fn
      ["upsert", _path, row] -> [row]
      _operation -> []
    end)
  end

  defp assert_requirement_detail_json_safe(vue) do
    contract = %{"props" => vue.props, "streams_diff" => vue.streams_diff}
    assert contract == Jason.decode!(Jason.encode!(contract))
  end

  defp contact_requirement_show_page_props(mission_id, spacecraft_id) do
    %{
      "id" => "ops-contact-requirement-show-page",
      "back_action" => %{
        "label" => "Requirements",
        "href" => "/missions/#{mission_id}/ops/requirements"
      },
      "header" => %{
        "priority" => "high",
        "version_label" => "Requirement v1",
        "intent" => "Payload downlink",
        "outcome" => "Downlink at least 1500000000 bytes across 1 eligible contact(s).",
        "plan_action" => %{
          "id" => "plan-contact-requirement",
          "event" => "plan",
          "payload" => %{},
          "label" => "Find options",
          "disabled" => false
        }
      },
      "horizon" => %{
        "id" => "requirement-horizon",
        "fields" => [
          %{
            "label" => "Earliest acceptable",
            "value" => "16 Jul 2026 21:00Z",
            "class" => "mt-1 font-mono text-sm tabular-nums"
          },
          %{
            "label" => "Latest acceptable",
            "value" => "17 Jul 2026 04:00Z",
            "class" => "mt-1 font-mono text-sm tabular-nums"
          },
          %{
            "label" => "Spacecraft",
            "value" => spacecraft_id,
            "class" => "mt-1 truncate font-mono text-sm"
          }
        ],
        "rationale" => "Recorder pressure requires a downlink"
      },
      "planning" => %{
        "heading" => "Provider search evidence",
        "description" => "No availability and a failed search remain separate operational facts.",
        "run_state" => %{"id" => "planning-run-state", "label" => "not run"},
        "error" => %{"id" => "contact-planning-error", "message" => nil},
        "searches" => %{
          "id" => "planning-searches",
          "empty" => %{
            "id" => "planning-searches-empty",
            "message" => "Run planning to query every provider-ready route."
          }
        }
      },
      "opportunities" => %{
        "heading" => "Opportunity comparison",
        "description" => "Choose exact immutable snapshots for a draft Plan.",
        "selected_count" => %{
          "id" => "selected-opportunity-count",
          "label" => "0 selected"
        },
        "list" => %{
          "id" => "planning-opportunities",
          "empty" => %{
            "id" => "planning-opportunities-empty",
            "message" => "No provider opportunities were captured in the latest run."
          }
        },
        "footer" => "A draft records every considered option, including rejected alternatives.",
        "create_action" => %{
          "id" => "create-contact-plan",
          "event" => "create-plan",
          "payload" => %{},
          "label" => "Build draft Plan",
          "disabled" => true
        }
      },
      "journey" => %{
        "heading" => "Need → Options → Plan → Reserved",
        "steps" => [
          %{"label" => "Need", "state" => "Declared", "complete" => true},
          %{"label" => "Options", "state" => "Pending", "complete" => false},
          %{"label" => "Plan", "state" => "Pending", "complete" => false},
          %{"label" => "Reserved", "state" => "Pending", "complete" => false}
        ]
      },
      "versions" => %{
        "heading" => "Immutable versions",
        "id" => "requirement-versions"
      }
    }
  end

  test "Plan page renders an exact manifest and separates submission from admin approval" do
    {member_conn, member_scope, org, mission, spacecraft} = signed_in_scope()
    fixture = plan_show_fixture(member_scope, mission, spacecraft)
    %{plan: plan, plan_version: plan_version, snapshot: snapshot} = fixture

    {:ok, member_view, _html} =
      live(member_conn, ~p"/missions/#{mission.mission_id}/ops/plans/#{plan.contact_plan_id}")

    assert has_element?(member_view, "#ops-contact-plan-show-component.contents")
    refute has_element?(member_view, "#ops-contact-plan-show-page")

    member_vue = contact_plan_show_vue(member_view)
    page = member_vue.props["page"]

    assert member_vue.component == "OpsContactPlanShow"
    assert member_vue.class == "contents"
    assert member_vue.ssr == false

    assert member_vue.handlers == %{
             "approve-plan" => Phoenix.LiveView.JS.push("approve-plan"),
             "execute-plan" => Phoenix.LiveView.JS.push("execute-plan"),
             "reject-plan" => Phoenix.LiveView.JS.push("reject-plan"),
             "submit-plan" => Phoenix.LiveView.JS.push("submit-plan")
           }

    assert Enum.sort(Map.keys(member_vue.props)) == [
             "admin_controls",
             "page",
             "submission_form"
           ]

    assert page["id"] == "ops-contact-plan-show-page"

    assert page["back_action"] == %{
             "label" => "Requirement",
             "href" =>
               "/missions/#{mission.mission_id}/ops/requirements/#{fixture.requirement.contact_requirement_id}"
           }

    assert page["header"] == %{
             "state" => %{
               "label" => "draft",
               "class" =>
                 "border border-base-300 px-1.5 py-0.5 font-mono text-[0.6rem] uppercase text-base-content/60"
             },
             "version_label" => "Plan v1",
             "heading" => "Contact commitment manifest",
             "description" =>
               "Exact Requirement, opportunity, provider route, policy, and expiry evidence for this commitment.",
             "execute_action" => nil
           }

    assert page["summary"] == %{
             "id" => "plan-commitment-summary",
             "coverage" => %{
               "label" => "Satisfied",
               "class" => "mt-1 text-sm font-semibold text-success"
             },
             "selected_count" => 1,
             "approval_identity" => "Not approved",
             "content_hash" => %{
               "id" => "contact-plan-content-hash",
               "value" => plan_version.content_sha256
             }
           }

    assert [policy_selection] = page["policy"]["selections"]

    assert Enum.sort(Map.keys(policy_selection)) == [
             "contact_opportunity_snapshot_id",
             "policy_summary",
             "route_display_name"
           ]

    assert policy_selection["contact_opportunity_snapshot_id"] ==
             snapshot.contact_opportunity_snapshot_id

    assert policy_selection["route_display_name"] == "Simulator route"

    assert policy_selection["policy_summary"] ==
             "Effective policy: approval required · automatic revision allowed"

    assert member_vue.props["submission_form"] == %{
             "id" => "contact-plan-submit-form",
             "field" => %{
               "id" => "contact-plan-submit-reason",
               "name" => "submission[reason]",
               "type" => "textarea",
               "label" => "Review note",
               "required" => true,
               "value" => "Ready for commitment review"
             },
             "action" => %{
               "id" => "submit-contact-plan",
               "label" => "Submit exact v1"
             }
           }

    assert member_vue.props["admin_controls"] == nil

    expected_selection = %{
      "__dom_id" => "plan-selection-#{snapshot.contact_opportunity_snapshot_id}",
      "contact_opportunity_snapshot_id" => snapshot.contact_opportunity_snapshot_id,
      "provider_display_name" => "Ground Network Simulator",
      "ground_station_ref" => "station-live",
      "starts_at" => Calendar.strftime(snapshot.starts_at, "%d %b %Y %H:%MZ"),
      "duration" => "900 sec",
      "expiry" => %{
        "value" => Calendar.strftime(snapshot.expires_at, "%d %b %Y %H:%MZ"),
        "class" => "mt-1 font-mono text-xs text-base-content/65"
      }
    }

    assert contact_plan_stream_rows(member_vue, "selected_opportunities") == [
             expected_selection
           ]

    assert contact_plan_stream_mutations(member_vue, "selected_opportunities") == [
             ["replace", "/selected_opportunities", []],
             ["upsert", "/selected_opportunities/-", expected_selection]
           ]

    assert contact_plan_stream_mutations(member_vue, "execution_items") == [
             ["replace", "/execution_items", []]
           ]

    assert contact_plan_stream_mutations(member_vue, "approvals") == [
             ["replace", "/approvals", []]
           ]

    assert_contact_plan_json_safe(member_vue)
    refute_contact_plan_sensitive_data(member_vue, member_scope.user)

    render_hook(member_view, "submit-plan", %{
      "submission" => %{"reason" => "Ready for admin review"}
    })

    assert {:ok, submitted_plan, ^plan_version} =
             ContactPlans.fetch(org.organization_id, mission.mission_id, plan.contact_plan_id)

    assert submitted_plan.lifecycle_state == :pending_approval
    assert submitted_plan.lifecycle_reason == "Ready for admin review"

    submitted_vue = contact_plan_show_vue(member_view)
    assert submitted_vue.props["submission_form"] == nil
    assert submitted_vue.props["admin_controls"] == nil

    assert submitted_vue.props["page"]["decision"] == %{
             "heading" => "Administrator decision",
             "description" =>
               "Approval rechecks Requirement versions, expiry, route/grant readiness, and policy narrowing.",
             "admin_required" => %{
               "id" => "contact-plan-admin-required",
               "message" => "Organization administrator approval required."
             }
           }

    admin = TestFixtures.persist_user!()
    admin_membership = TestFixtures.grant_membership!(admin, org, role: :organization_admin)
    admin_conn = TestFixtures.member_conn(admin)

    assert admin_membership.role == :organization_admin

    {:ok, admin_view, _html} =
      live(admin_conn, ~p"/missions/#{mission.mission_id}/ops/plans/#{plan.contact_plan_id}")

    admin_vue = contact_plan_show_vue(admin_view)
    admin_controls = admin_vue.props["admin_controls"]

    assert admin_vue.props["submission_form"] == nil
    assert admin_vue.props["page"]["decision"]["admin_required"] == nil
    assert admin_controls["approve_form"]["id"] == "contact-plan-approve-form"
    assert admin_controls["approve_form"]["field"]["name"] == "decision[reason]"
    assert admin_controls["approve_form"]["field"]["value"] == ""
    assert admin_controls["rejection"]["id"] == "contact-plan-rejection-disclosure"
    assert admin_controls["rejection"]["form"]["id"] == "contact-plan-reject-form"
    assert admin_controls["rejection"]["form"]["field"]["name"] == "decision[reason]"
    assert admin_controls["rejection"]["form"]["field"]["value"] == ""
    assert contact_plan_stream_rows(admin_vue, "execution_items") == []
    assert_contact_plan_json_safe(admin_vue)
  end

  test "Plan handlers enforce member authorization and keep admin-only controls out of member DTOs" do
    {member_conn, member_scope, org, mission, spacecraft} = signed_in_scope()
    %{plan: plan} = plan_show_fixture(member_scope, mission, spacecraft)

    {:ok, member_view, _html} =
      live(member_conn, ~p"/missions/#{mission.mission_id}/ops/plans/#{plan.contact_plan_id}")

    render_hook(member_view, "submit-plan", %{
      "submission" => %{"reason" => "Review this exact commitment"}
    })

    render_hook(member_view, "approve-plan", %{
      "decision" => %{"reason" => "Member must not approve"}
    })

    render_hook(member_view, "reject-plan", %{
      "decision" => %{"reason" => "Member must not reject"}
    })

    assert {:ok, still_pending, _version} =
             ContactPlans.fetch(org.organization_id, mission.mission_id, plan.contact_plan_id)

    assert still_pending.lifecycle_state == :pending_approval

    assert Cadence.Management.Contacts.list_approvals(
             org.organization_id,
             mission.mission_id,
             plan.contact_plan_id
           ) == []

    member_vue = contact_plan_show_vue(member_view)
    assert member_vue.props["admin_controls"] == nil

    assert member_vue.props["page"]["decision"]["admin_required"]["id"] ==
             "contact-plan-admin-required"

    refute_contact_plan_sensitive_data(member_vue, member_scope.user)
  end

  test "Plan approval and rejection handlers persist exact reasons and refresh stream DTOs" do
    {approve_conn, approve_scope, approve_org, approve_mission, approve_spacecraft} =
      signed_in_scope()

    %{plan: approve_plan} =
      plan_show_fixture(approve_scope, approve_mission, approve_spacecraft)

    {:ok, approve_member_view, _html} =
      live(
        approve_conn,
        ~p"/missions/#{approve_mission.mission_id}/ops/plans/#{approve_plan.contact_plan_id}"
      )

    render_hook(approve_member_view, "submit-plan", %{
      "submission" => %{"reason" => "Ready to approve"}
    })

    {approve_admin_conn, approve_admin} = plan_admin_conn(approve_org)

    {:ok, approve_admin_view, _html} =
      live(
        approve_admin_conn,
        ~p"/missions/#{approve_mission.mission_id}/ops/plans/#{approve_plan.contact_plan_id}"
      )

    render_hook(approve_admin_view, "approve-plan", %{
      "decision" => %{"reason" => "Provider, policy, and expiry reviewed"}
    })

    assert {:ok, approved_plan, approved_version} =
             ContactPlans.fetch(
               approve_org.organization_id,
               approve_mission.mission_id,
               approve_plan.contact_plan_id
             )

    assert approved_plan.lifecycle_state == :approved
    assert approved_plan.approved_by == approve_admin.user_id

    assert [approval] =
             Cadence.Management.Contacts.list_approvals(
               approve_org.organization_id,
               approve_mission.mission_id,
               approve_plan.contact_plan_id
             )

    assert approval.decision == :approved
    assert approval.reason == "Provider, policy, and expiry reviewed"

    approved_vue = contact_plan_show_vue(approve_admin_view)
    assert approved_vue.props["admin_controls"] == nil
    assert approved_vue.props["submission_form"] == nil
    assert approved_vue.props["page"]["decision"] == nil

    assert approved_vue.props["page"]["header"]["execute_action"] == %{
             "id" => "execute-contact-plan",
             "event" => "execute-plan",
             "payload" => %{},
             "label" => "Execute approved Plan",
             "disabled" => false
           }

    assert [approval_row] = contact_plan_stream_rows(approved_vue, "approvals")

    assert approval_row == %{
             "__dom_id" => "plan-approval-#{approval.contact_plan_approval_id}",
             "contact_plan_approval_id" => approval.contact_plan_approval_id,
             "decision" => %{
               "label" => "approved",
               "class" => "text-sm font-semibold text-success"
             },
             "version_label" => "v#{approval.contact_plan_version}",
             "reason" => "Provider, policy, and expiry reviewed",
             "actor_summary" =>
               "#{approve_admin.display_name} · #{Calendar.strftime(approval.decided_at, "%d %b %Y %H:%MZ")}"
           }

    assert contact_plan_stream_mutations(approved_vue, "approvals") == [
             ["replace", "/approvals", []],
             ["upsert", "/approvals/-", approval_row]
           ]

    assert [execution_item] =
             Cadence.Control.Contacts.list_plan_execution(
               approve_org.organization_id,
               approve_mission.mission_id,
               approve_plan.contact_plan_id,
               approved_version.version
             )

    execution_row = %{
      "__dom_id" => "plan-execution-item-#{execution_item.contact_plan_execution_item_id}",
      "contact_plan_execution_item_id" => execution_item.contact_plan_execution_item_id,
      "contact_opportunity_snapshot_id" => execution_item.contact_opportunity_snapshot_id,
      "attempt_count" => 0,
      "state" => %{
        "label" => "pending",
        "class" => "font-mono text-[0.65rem] uppercase text-primary"
      },
      "contact_link" => nil
    }

    assert contact_plan_stream_rows(approved_vue, "execution_items") == [execution_row]

    assert contact_plan_stream_mutations(approved_vue, "execution_items") == [
             ["replace", "/execution_items", []],
             ["upsert", "/execution_items/-", execution_row]
           ]

    assert_contact_plan_json_safe(approved_vue)

    {reject_conn, reject_scope, reject_org, reject_mission, reject_spacecraft} =
      signed_in_scope()

    %{plan: reject_plan} = plan_show_fixture(reject_scope, reject_mission, reject_spacecraft)

    {:ok, reject_member_view, _html} =
      live(
        reject_conn,
        ~p"/missions/#{reject_mission.mission_id}/ops/plans/#{reject_plan.contact_plan_id}"
      )

    render_hook(reject_member_view, "submit-plan", %{
      "submission" => %{"reason" => "Ready for a decision"}
    })

    {reject_admin_conn, _reject_admin} = plan_admin_conn(reject_org)

    {:ok, reject_admin_view, _html} =
      live(
        reject_admin_conn,
        ~p"/missions/#{reject_mission.mission_id}/ops/plans/#{reject_plan.contact_plan_id}"
      )

    render_hook(reject_admin_view, "reject-plan", %{
      "decision" => %{"reason" => "Use the later station window"}
    })

    assert {:ok, rejected_plan, _version} =
             ContactPlans.fetch(
               reject_org.organization_id,
               reject_mission.mission_id,
               reject_plan.contact_plan_id
             )

    assert rejected_plan.lifecycle_state == :draft

    assert [rejection] =
             Cadence.Management.Contacts.list_approvals(
               reject_org.organization_id,
               reject_mission.mission_id,
               reject_plan.contact_plan_id
             )

    assert rejection.decision == :rejected
    assert rejection.reason == "Use the later station window"

    rejected_vue = contact_plan_show_vue(reject_admin_view)
    assert rejected_vue.props["admin_controls"] == nil
    assert rejected_vue.props["submission_form"] == nil
    assert rejected_vue.props["page"]["submission"] == nil
    assert rejected_vue.props["page"]["decision"] == nil

    assert [rejection_row] = contact_plan_stream_rows(rejected_vue, "approvals")
    assert rejection_row["decision"]["label"] == "rejected"
    assert rejection_row["decision"]["class"] == "text-sm font-semibold text-error"
    assert rejection_row["reason"] == "Use the later station window"
    assert contact_plan_stream_rows(rejected_vue, "execution_items") == []
    assert_contact_plan_json_safe(rejected_vue)
  end

  test "Plan execution action publishes disabled progress state and refreshes the execution ledger" do
    {member_conn, member_scope, org, mission, spacecraft} = signed_in_scope()
    %{plan: plan} = plan_show_fixture(member_scope, mission, spacecraft)

    {:ok, member_view, _html} =
      live(member_conn, ~p"/missions/#{mission.mission_id}/ops/plans/#{plan.contact_plan_id}")

    render_hook(member_view, "submit-plan", %{
      "submission" => %{"reason" => "Ready to execute after approval"}
    })

    {admin_conn, _admin} = plan_admin_conn(org)

    {:ok, admin_view, _html} =
      live(admin_conn, ~p"/missions/#{mission.mission_id}/ops/plans/#{plan.contact_plan_id}")

    render_hook(admin_view, "approve-plan", %{
      "decision" => %{"reason" => "Exact commitment approved"}
    })

    track_async_view(admin_view)
    executing_html = render_hook(admin_view, "execute-plan", %{})
    executing_vue = contact_plan_show_vue(executing_html)

    assert executing_vue.props["page"]["header"]["execute_action"] == %{
             "id" => "execute-contact-plan",
             "event" => "execute-plan",
             "payload" => %{},
             "label" => "Executing",
             "disabled" => true
           }

    render_async(admin_view)

    completed_vue = contact_plan_show_vue(admin_view)
    completed_action = completed_vue.props["page"]["header"]["execute_action"]

    assert completed_action["label"] == "Execute approved Plan"
    assert completed_action["disabled"] == false

    assert [completed_item] = contact_plan_stream_rows(completed_vue, "execution_items")
    assert completed_item["attempt_count"] == 1
    assert completed_item["state"]["label"] == "failed"

    assert completed_item["state"]["class"] ==
             "font-mono text-[0.65rem] uppercase text-warning"

    assert_contact_plan_json_safe(completed_vue)
  end

  defp contact_plan_show_vue(view_or_html) do
    LiveVue.Test.get_vue(view_or_html, id: "ops-contact-plan-show-component")
  end

  defp contact_plan_stream_mutations(vue, stream_name) do
    stream_path = "/#{stream_name}"

    Enum.filter(vue.streams_diff, fn
      ["replace", ^stream_path, _items] -> true
      ["upsert", path, _item] -> String.starts_with?(path, stream_path <> "/")
      ["remove", path] -> String.starts_with?(path, stream_path <> "/")
      _operation -> false
    end)
  end

  defp contact_plan_stream_rows(vue, stream_name) do
    vue
    |> contact_plan_stream_mutations(stream_name)
    |> Enum.flat_map(fn
      ["upsert", _path, row] -> [row]
      _operation -> []
    end)
  end

  defp assert_contact_plan_json_safe(vue) do
    contract = %{"props" => vue.props, "streams_diff" => vue.streams_diff}
    assert contract == Jason.decode!(Jason.encode!(contract))
  end

  defp refute_contact_plan_sensitive_data(vue, user) do
    contract = %{"props" => vue.props, "streams_diff" => vue.streams_diff}
    encoded = Jason.encode!(contract)
    keys = plan_contract_keys(Jason.decode!(encoded))

    refute encoded =~ user.email

    assert MapSet.disjoint?(
             keys,
             MapSet.new(
               ~w(current_scope current_user user users capabilities token tokens secrets)
             )
           )
  end

  defp plan_contract_keys(value) when is_map(value) do
    Enum.reduce(value, MapSet.new(), fn {key, nested}, keys ->
      keys
      |> MapSet.put(to_string(key))
      |> MapSet.union(plan_contract_keys(nested))
    end)
  end

  defp plan_contract_keys(value) when is_list(value) do
    Enum.reduce(value, MapSet.new(), fn nested, keys ->
      MapSet.union(keys, plan_contract_keys(nested))
    end)
  end

  defp plan_contract_keys(_value), do: MapSet.new()

  defp plan_show_fixture(scope, mission, spacecraft) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    {requirement, requirement_version} =
      create_requirement_with(scope, mission, spacecraft, %{
        earliest_start: DateTime.add(now, 3_600, :second),
        latest_end: DateTime.add(now, 28_800, :second)
      })

    available_opportunity =
      opportunity()
      |> Map.put("starts_at", now |> DateTime.add(3_600, :second) |> DateTime.to_iso8601())
      |> Map.put("ends_at", now |> DateTime.add(4_500, :second) |> DateTime.to_iso8601())
      |> Map.put("expires_at", now |> DateTime.add(18_000, :second) |> DateTime.to_iso8601())

    assert {:ok, planning} =
             Planner.run(
               scope,
               mission.mission_id,
               requirement.contact_requirement_id,
               requirement_version.version,
               now: now,
               list_routes: fn _, _, _ ->
                 {:ok, %{routes: [route(spacecraft.spacecraft_id)], findings: []}}
               end,
               search_opportunities: fn _, _, _, _, _ ->
                 {:ok, %{opportunities: [available_opportunity]}}
               end
             )

    [snapshot] = planning.snapshots

    assert {:ok, plan, plan_version} =
             ContactPlans.create(
               scope,
               mission.mission_id,
               %{
                 planning_run_ids: [planning.run.contact_planning_run_id],
                 selected_snapshot_ids: [snapshot.contact_opportunity_snapshot_id],
                 rationale: "Use the provider's first eligible pass"
               },
               now: now
             )

    %{
      requirement: requirement,
      plan: plan,
      plan_version: plan_version,
      snapshot: snapshot
    }
  end

  defp plan_admin_conn(org) do
    admin = TestFixtures.persist_user!()
    membership = TestFixtures.grant_membership!(admin, org, role: :organization_admin)
    assert membership.role == :organization_admin
    {TestFixtures.member_conn(admin), admin}
  end

  defp signed_in_scope do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    membership = TestFixtures.grant_membership!(user, org)

    mission =
      TestFixtures.persist_mission!(org, slug: "planning", display_name: "Planning Mission")

    spacecraft = TestFixtures.persist_spacecraft!(mission, display_name: "Asteria")

    scope =
      Scope.new(%{
        user: user,
        organization_id: org.organization_id,
        organization: org,
        organization_membership: membership
      })

    {TestFixtures.member_conn(user), scope, org, mission, spacecraft}
  end

  defp create_requirement(scope, mission, spacecraft) do
    assert {:ok, requirement, version} =
             ContactRequirements.create(
               scope,
               mission.mission_id,
               requirement_attrs(spacecraft.spacecraft_id),
               now: fixed_now()
             )

    {requirement, version}
  end

  defp requirement_form_params(spacecraft) do
    starts_at = DateTime.utc_now() |> DateTime.add(3_600, :second) |> DateTime.truncate(:second)

    %{
      "spacecraft_id" => spacecraft.spacecraft_id,
      "contact_intent" => "payload_downlink",
      "earliest_start" => Calendar.strftime(starts_at, "%Y-%m-%dT%H:%M:%S"),
      "latest_end" =>
        starts_at |> DateTime.add(21_600, :second) |> Calendar.strftime("%Y-%m-%dT%H:%M:%S"),
      "success_measure" => "minimum_data_volume",
      "minimum_duration_seconds" => "600",
      "preferred_duration_seconds" => "900",
      "minimum_data_volume_bytes" => "1500000000",
      "contact_count" => "1",
      "minimum_separation_seconds" => "0",
      "priority" => "high",
      "allowed_providers" => "provider-a",
      "excluded_providers" => "",
      "allowed_stations" => "",
      "excluded_stations" => "station-c",
      "rationale" => "Recorder pressure requires a downlink"
    }
  end

  defp requirement_attrs(spacecraft_id) do
    %{
      spacecraft_id: spacecraft_id,
      service_direction: :downlink,
      contact_intent: "payload_downlink",
      earliest_start: DateTime.add(fixed_now(), 3_600, :second),
      latest_end: DateTime.add(fixed_now(), 28_800, :second),
      success_measure: :minimum_data_volume,
      minimum_duration_seconds: 600,
      preferred_duration_seconds: 900,
      minimum_data_volume_bytes: 1_500_000_000,
      contact_count: 1,
      minimum_separation_seconds: 0,
      priority: :high,
      provider_constraints_document: %{"allowed" => [], "excluded" => []},
      station_constraints_document: %{"allowed" => [], "excluded" => []},
      policy_constraints_document: %{},
      approval_policy_document: %{"mode" => "manual"},
      rationale: "Recorder pressure requires a downlink",
      metadata: %{}
    }
  end

  defp route(spacecraft_id) do
    %{
      route_key: "route-live-test",
      spacecraft_id: spacecraft_id,
      provider_spacecraft_ref: "SC-LIVE",
      source_endpoint_id: "source-live",
      routing_rule_id: "routing-live",
      link_assignment_id: "link-live",
      path_template_id: "path-live",
      path_template_version: 1,
      transport_id: "transport-live",
      transport_version: 1,
      provider_id: "provider-live",
      provider_version: 1,
      provider_account_id: "account-live",
      provider_account_version: 1,
      provider_account_grant_id: "grant-live",
      provider_account_grant_version: 1,
      provider_profile_id: "runtime-live",
      provider_profile_version: 1,
      service_profile_ref: %{"id" => "service-downlink", "version" => 1},
      delivery_profile_ref: %{"id" => "delivery-cadence", "version" => 1},
      delivery_policy_document: %{},
      provider_display_name: "Ground Network Simulator",
      service_display_name: "Downlink",
      delivery_display_name: "Cadence",
      route_display_name: "Simulator route",
      client: OpsContactRequirementsLiveTest.FakeClient
    }
  end

  defp opportunity do
    %{
      "id" => "opportunity-live",
      "spacecraft_ref" => "SC-LIVE",
      "ground_station_ref" => "station-live",
      "antenna_or_service_pool_ref" => "pool-live",
      "service_profile_ref" => "service-downlink",
      "starts_at" => fixed_now() |> DateTime.add(3_600, :second) |> DateTime.to_iso8601(),
      "ends_at" => fixed_now() |> DateTime.add(4_500, :second) |> DateTime.to_iso8601(),
      "expires_at" => fixed_now() |> DateTime.add(18_000, :second) |> DateTime.to_iso8601(),
      "availability" => "available",
      "estimated_capacity" => %{"bytes" => 2_000_000_000},
      "synthetic" => true,
      "extensions" => %{"orbit_readiness" => %{"status" => "current"}}
    }
  end

  defp fixed_now, do: ~U[2026-07-16 20:00:00.000000Z]

  defp contact_requirements_page_props(mission_id) do
    %{
      "id" => "ops-contact-requirements-page",
      "header" => %{
        "eyebrow" => "Mission operations / planning horizon",
        "title" => "Contact Requirements",
        "description" =>
          "Declare the mission outcome first. Cadence searches every ready provider route, preserves their evidence, and lets operators commit an exact plan.",
        "create_action" => %{
          "id" => "new-contact-requirement-link",
          "label" => "Declare need",
          "href" => "/missions/#{mission_id}/ops/requirements/new"
        }
      },
      "journey_steps" => [
        %{
          "number" => "01",
          "label" => "Need",
          "detail" => "Mission outcome",
          "active" => true
        },
        %{
          "number" => "02",
          "label" => "Options",
          "detail" => "Provider evidence",
          "active" => false
        },
        %{
          "number" => "03",
          "label" => "Plan",
          "detail" => "Exact commitment",
          "active" => false
        },
        %{
          "number" => "04",
          "label" => "Reserved",
          "detail" => "Provider capacity",
          "active" => false
        }
      ],
      "empty_state" => %{
        "id" => "contact-requirements-empty",
        "title" => "No contact needs in this horizon",
        "description" =>
          "Start with the outcome the spacecraft needs—data volume, duration, or contact count. Provider details come later."
      },
      "list_id" => "contact-requirements"
    }
  end

  defp create_requirement_with(scope, mission, spacecraft, overrides) do
    attrs =
      spacecraft.spacecraft_id
      |> requirement_attrs()
      |> Map.merge(overrides)

    assert {:ok, requirement, version} =
             ContactRequirements.create(scope, mission.mission_id, attrs, now: fixed_now())

    {requirement, version}
  end

  defp run_planning(scope, mission, spacecraft, requirement, version) do
    assert {:ok, planning} =
             Planner.run(
               scope,
               mission.mission_id,
               requirement.contact_requirement_id,
               version.version,
               now: fixed_now(),
               list_routes: fn _, _, _ ->
                 {:ok, %{routes: [route(spacecraft.spacecraft_id)], findings: []}}
               end,
               search_opportunities: fn _, _, _, _, _ ->
                 {:ok, %{opportunities: [opportunity()]}}
               end
             )

    planning
  end

  defp contact_requirements_vue(view) do
    LiveVue.Test.get_vue(view, id: "ops-contact-requirements-component")
  end

  defp requirement_rows(vue) do
    vue.streams_diff
    |> Enum.filter(fn
      ["upsert", "/requirements/" <> _index, _requirement] -> true
      _operation -> false
    end)
    |> Enum.map(fn ["upsert", _path, requirement] -> requirement end)
  end

  defp requirement_stream_mutations(vue) do
    Enum.reject(vue.streams_diff, fn
      ["test", "", _value] -> true
      _operation -> false
    end)
  end

  defp assert_json_safe(vue) do
    contract = %{"props" => vue.props, "streams_diff" => vue.streams_diff}
    assert contract == Jason.decode!(Jason.encode!(contract))
  end
end
