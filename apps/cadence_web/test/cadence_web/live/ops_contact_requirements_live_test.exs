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
        "__dom_id" =>
          "contact-requirement-#{planned_requirement.contact_requirement_id}",
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
        "__dom_id" =>
          "contact-requirement-#{searched_requirement.contact_requirement_id}",
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
        "__dom_id" =>
          "contact-requirement-#{declared_requirement.contact_requirement_id}",
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
               Enum.map(Enum.with_index(expected_rows), fn {row, index} ->
                 ["upsert", "/requirements/#{index}", row]
               end)

    assert_json_safe(vue)
  end

  test "outcome-first form progressively changes and creates a durable Requirement" do
    {conn, _scope, org, mission, spacecraft} = signed_in_scope()

    {:ok, view, _html} =
      live(conn, ~p"/missions/#{mission.mission_id}/ops/requirements/new")

    assert has_element?(view, "#contact-requirement-form")
    assert has_element?(view, "#requirement-minimum-data-volume")
    assert has_element?(view, "#requirement-preferred-duration")
    assert has_element?(view, "#requirement-advanced-constraints")

    params = requirement_form_params(spacecraft)

    view
    |> form("#contact-requirement-form",
      contact_requirement: Map.put(params, "success_measure", "contact_count")
    )
    |> render_change()

    refute has_element?(view, "#requirement-minimum-data-volume")
    assert has_element?(view, "#requirement-contact-count")

    view
    |> form(
      "#contact-requirement-form",
      contact_requirement:
        Map.drop(params, ["minimum_data_volume_bytes", "minimum_duration_seconds"])
    )
    |> render_change()

    view
    |> form("#contact-requirement-form", contact_requirement: params)
    |> render_submit()

    [{requirement, version}] =
      ContactRequirements.list(org.organization_id, mission.mission_id)

    assert_redirect(
      view,
      ~p"/missions/#{mission.mission_id}/ops/requirements/#{requirement.contact_requirement_id}"
    )

    assert version.spacecraft_id == spacecraft.spacecraft_id
    assert version.success_measure == :minimum_data_volume
    assert version.minimum_data_volume_bytes == 1_500_000_000
    assert version.preferred_duration_seconds == 900
    assert version.provider_constraints_document["allowed"] == ["provider-a"]
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
