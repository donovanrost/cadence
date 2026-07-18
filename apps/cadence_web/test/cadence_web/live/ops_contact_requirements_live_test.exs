defmodule CadenceWeb.OpsContactRequirementsLiveTest do
  use CadenceWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias Cadence.Auth.Scope
  alias Cadence.ContactPlanning.{ContactPlans, ContactRequirements, Planner}
  alias CadenceWeb.TestFixtures

  test "authenticated Ops routes expose Requirements navigation and enforce mission membership",
       %{
         conn: conn
       } do
    {member_conn, _scope, _org, mission, _spacecraft} = signed_in_scope()

    {:ok, view, _html} =
      live(member_conn, ~p"/missions/#{mission.mission_id}/ops/requirements")

    assert has_element?(view, "#ops-contact-requirements-page")
    assert has_element?(view, "#new-contact-requirement-link")

    assert has_element?(
             view,
             ~s(#ops-nav-rail a[href="/missions/#{mission.mission_id}/ops/requirements"][class*="text-primary"])
           )

    assert {:error, {:redirect, %{to: "/sign-in"}}} =
             live(conn, ~p"/missions/#{mission.mission_id}/ops/requirements")

    outsider = TestFixtures.persist_user!()
    outsider_org = TestFixtures.persist_org!()
    _membership = TestFixtures.grant_membership!(outsider, outsider_org)

    assert {:error, {:redirect, %{to: "/missions", flash: %{"error" => _message}}}} =
             live(
               TestFixtures.member_conn(outsider),
               ~p"/missions/#{mission.mission_id}/ops/requirements"
             )
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
      Cadence.list_contact_requirements(org.organization_id, mission.mission_id)

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
end
