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

    assert has_element?(view, "#ops-contact-requirement-show-page")
    assert has_element?(view, "#plan-contact-requirement")
    assert has_element?(view, "#planning-searches-empty")

    view |> element("#plan-contact-requirement") |> render_click()
    render_async(view)

    assert has_element?(view, "#planning-searches [id^=planning-search-]")
    assert has_element?(view, "[id^=planning-search-evidence-]")
    assert has_element?(view, "#planning-run-state", "failed")
    assert has_element?(view, "#planning-opportunities-empty")
  end

  test "Plan page renders an exact manifest and separates submission from admin approval" do
    {member_conn, member_scope, org, mission, spacecraft} = signed_in_scope()
    {requirement, requirement_version} = create_requirement(member_scope, mission, spacecraft)
    route = route(spacecraft.spacecraft_id)

    assert {:ok, planning} =
             Planner.run(
               member_scope,
               mission.mission_id,
               requirement.contact_requirement_id,
               requirement_version.version,
               now: fixed_now(),
               list_routes: fn _, _, _ -> {:ok, %{routes: [route], findings: []}} end,
               search_opportunities: fn _, _, _, _, _ ->
                 {:ok, %{opportunities: [opportunity()]}}
               end
             )

    [snapshot] = planning.snapshots

    assert {:ok, plan, plan_version} =
             ContactPlans.create(member_scope, mission.mission_id, %{
               planning_run_ids: [planning.run.contact_planning_run_id],
               selected_snapshot_ids: [snapshot.contact_opportunity_snapshot_id],
               rationale: "Use the provider's first eligible pass"
             })

    {:ok, member_view, _html} =
      live(member_conn, ~p"/missions/#{mission.mission_id}/ops/plans/#{plan.contact_plan_id}")

    assert has_element?(member_view, "#ops-contact-plan-show-page")
    assert has_element?(member_view, "#contact-plan-content-hash", plan_version.content_sha256)
    assert has_element?(member_view, "#plan-selections [id^=plan-selection-]")
    assert has_element?(member_view, "#contact-plan-submit-form")
    refute has_element?(member_view, "#contact-plan-approve-form")

    member_view
    |> form("#contact-plan-submit-form", submission: %{reason: "Ready for admin review"})
    |> render_submit()

    assert has_element?(member_view, "#contact-plan-admin-required")

    admin = TestFixtures.persist_user!()
    admin_membership = TestFixtures.grant_membership!(admin, org, role: :organization_admin)
    admin_conn = TestFixtures.member_conn(admin)

    assert admin_membership.role == :organization_admin

    {:ok, admin_view, _html} =
      live(admin_conn, ~p"/missions/#{mission.mission_id}/ops/plans/#{plan.contact_plan_id}")

    assert has_element?(admin_view, "#contact-plan-approve-form")
    assert has_element?(admin_view, "#contact-plan-rejection-disclosure")
    assert has_element?(admin_view, "#plan-execution-items-empty")
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
