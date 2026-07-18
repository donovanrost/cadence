defmodule CadenceWeb.OpsFleetPlanningLiveTest do
  use CadenceWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias Cadence.Auth.Scope
  alias Cadence.ContactPlanning.{ContactRequirements, FleetPlanningPolicies}
  alias CadenceWeb.TestFixtures

  test "authenticated mission operators can navigate the planning journey and see stopped state",
       %{conn: conn} do
    {member_conn, _scope, _org, mission, _spacecraft} = signed_in_scope(:member)

    {:ok, view, _html} =
      live(member_conn, ~p"/missions/#{mission.mission_id}/ops/planning")

    assert has_element?(view, "#ops-fleet-planning-page")
    assert has_element?(view, "#fleet-planning-runs-empty")
    assert has_element?(view, "#fleet-planning-policy-required")
    assert has_element?(view, "#new-fleet-planning-run-link")
    assert has_element?(view, "#requirement-templates-link")

    assert has_element?(
             view,
             ~s(#ops-nav-rail a[href="/missions/#{mission.mission_id}/ops/planning"][class*="text-primary"])
           )

    {:ok, new_view, _html} =
      live(member_conn, ~p"/missions/#{mission.mission_id}/ops/planning/new")

    assert has_element?(new_view, "#ops-fleet-planning-new-page")
    assert has_element?(new_view, "#fleet-planning-new-policy-required")
    refute has_element?(new_view, "#fleet-planning-run-form")

    {:ok, policy_view, _html} =
      live(member_conn, ~p"/missions/#{mission.mission_id}/ops/planning/policy")

    assert has_element?(policy_view, "#ops-fleet-planning-policy-page")
    assert has_element?(policy_view, "#fleet-policy-admin-required")
    refute has_element?(policy_view, "#fleet-policy-form")

    {:ok, template_view, _html} =
      live(member_conn, ~p"/missions/#{mission.mission_id}/ops/requirement-templates")

    assert has_element?(template_view, "#ops-requirement-templates-page")
    assert has_element?(template_view, "#requirement-template-admin-required")

    assert {:error, {:redirect, %{to: "/sign-in"}}} =
             live(conn, ~p"/missions/#{mission.mission_id}/ops/planning")
  end

  test "an organization administrator creates and activates the exact fleet policy in UI" do
    {conn, _scope, org, mission, _spacecraft} = signed_in_scope(:organization_admin)

    {:ok, view, _html} =
      live(conn, ~p"/missions/#{mission.mission_id}/ops/planning/policy")

    assert has_element?(view, "#fleet-policy-empty")
    assert has_element?(view, "#fleet-policy-form")

    view
    |> form("#fleet-policy-form",
      policy: %{
        "max_horizon_hours" => "24",
        "requirement_concurrency" => "8",
        "provider_search_concurrency" => "4",
        "reuse_freshness_seconds" => "300",
        "max_contacts" => "300",
        "max_estimated_cost_micros" => "",
        "currency" => "",
        "critical_contact_reserve" => "5",
        "automation_mode" => "advisory",
        "execution_concurrency" => "4",
        "max_repair_attempts" => "3",
        "repair_horizon_hours" => "12"
      }
    )
    |> render_submit()

    assert has_element?(view, "#fleet-policy-approval-form")
    assert has_element?(view, "#fleet-policy-state", "draft")

    view
    |> form("#fleet-policy-approval-form",
      decision: %{reason: "Bound mission-scale provider demand"}
    )
    |> render_submit()

    assert has_element?(view, "#fleet-policy-state", "active")
    refute has_element?(view, "#fleet-policy-approval-form")

    assert {:ok, policy, version} =
             Cadence.fetch_active_fleet_planning_policy(
               org.organization_id,
               mission.mission_id
             )

    assert policy.active_version == version.version
    assert version.budget_quota_document["max_contacts"] == 300
    assert version.budget_quota_document["critical_contact_reserve"] == 5
  end

  test "administrator creates and pauses a progressively rendered recurring Requirement Template" do
    {conn, _scope, org, mission, spacecraft} = signed_in_scope(:organization_admin)

    {:ok, view, _html} =
      live(conn, ~p"/missions/#{mission.mission_id}/ops/requirement-templates")

    assert has_element?(view, "#requirement-template-form")
    assert has_element?(view, "#template-interval-minutes")
    refute has_element?(view, "#template-time-utc")

    params = template_params(spacecraft)

    view
    |> form("#requirement-template-form",
      template:
        params
        |> Map.drop(["interval_minutes", "minimum_data_volume_bytes", "time_utc"])
        |> Map.put("schedule_type", "daily")
    )
    |> render_change()

    assert has_element?(view, "#template-time-utc")
    refute has_element?(view, "#template-interval-minutes")

    view
    |> form("#requirement-template-form",
      template: Map.drop(params, ["interval_minutes", "minimum_data_volume_bytes"])
    )
    |> render_change()

    view
    |> form("#requirement-template-form",
      template: Map.drop(params, ["minimum_data_volume_bytes", "time_utc"])
    )
    |> render_submit()

    [{template, version}] =
      Cadence.list_contact_requirement_templates(
        org.organization_id,
        mission.mission_id
      )

    assert version.spacecraft_id == spacecraft.spacecraft_id
    assert version.schedule_document["type"] == "fixed_interval"
    assert version.schedule_document["interval_seconds"] == 21_600
    assert has_element?(view, "#requirement-template-#{template.contact_requirement_template_id}")

    view
    |> element("#pause-template-#{template.contact_requirement_template_id}")
    |> render_click()

    [{paused, _version}] =
      Cadence.list_contact_requirement_templates(
        org.organization_id,
        mission.mission_id
      )

    assert paused.lifecycle_state == :paused
    assert has_element?(view, "#activate-template-#{template.contact_requirement_template_id}")
  end

  test "starting a horizon persists first and the run workspace resumes durable phases" do
    {conn, scope, org, mission, spacecraft} = signed_in_scope(:organization_admin)
    activate_policy!(scope, mission)

    now = DateTime.utc_now() |> DateTime.truncate(:second)

    assert {:ok, _requirement, _version} =
             ContactRequirements.create(
               scope,
               mission.mission_id,
               requirement_attrs(spacecraft.spacecraft_id, now),
               now: now
             )

    {:ok, view, _html} =
      live(conn, ~p"/missions/#{mission.mission_id}/ops/planning/new")

    assert has_element?(view, "#fleet-planning-run-form")
    assert has_element?(view, "#fleet-run-policy-preview")
    assert has_element?(view, "#fleet-run-policy-progressive-details")

    horizon_end = DateTime.add(now, 6, :hour)

    view
    |> form("#fleet-planning-run-form",
      fleet_run: %{
        "horizon_start" => datetime_local(now),
        "horizon_end" => datetime_local(horizon_end),
        "include_recurring" => "true"
      }
    )
    |> render_submit()

    [run] = Cadence.list_fleet_planning_runs(org.organization_id, mission.mission_id)

    assert_redirect(
      view,
      ~p"/missions/#{mission.mission_id}/ops/planning/runs/#{run.fleet_planning_run_id}"
    )

    {:ok, run_view, _html} =
      live(
        conn,
        ~p"/missions/#{mission.mission_id}/ops/planning/runs/#{run.fleet_planning_run_id}"
      )

    assert has_element?(run_view, "#ops-fleet-planning-run-page")
    assert has_element?(run_view, "#fleet-run-phase-strip")
    assert has_element?(run_view, "#fleet-coverage-matrix")
    assert has_element?(run_view, "#fleet-decision-inspector")
    assert has_element?(run_view, "#fleet-requirement-rows [id^=fleet-requirement-]")

    render_async(run_view, 5_000)

    assert {:ok, finished} =
             Cadence.fetch_fleet_planning_run(
               org.organization_id,
               mission.mission_id,
               run.fleet_planning_run_id
             )

    assert finished.phase == :finished
  end

  defp activate_policy!(scope, mission) do
    assert {:ok, policy, version} =
             FleetPlanningPolicies.create(scope, mission.mission_id, policy_attrs())

    assert {:ok, _active, ^version, _approval} =
             FleetPlanningPolicies.approve(
               scope,
               mission.mission_id,
               policy.fleet_planning_policy_id,
               version.version,
               version.content_sha256,
               "Enable LiveView fleet planning"
             )
  end

  defp signed_in_scope(role) do
    user = TestFixtures.persist_user!()
    org = TestFixtures.persist_org!()
    membership = TestFixtures.grant_membership!(user, org, role: role)

    mission =
      TestFixtures.persist_mission!(org,
        slug: "fleet-planning",
        display_name: "Fleet Planning Mission"
      )

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

  defp template_params(spacecraft) do
    now = DateTime.utc_now() |> DateTime.add(3_600, :second) |> DateTime.truncate(:second)

    %{
      "spacecraft_id" => spacecraft.spacecraft_id,
      "schedule_type" => "fixed_interval",
      "anchor_at" => datetime_local(now),
      "time_utc" => "12:00:00",
      "interval_minutes" => "360",
      "window_offset_minutes" => "10",
      "window_duration_minutes" => "45",
      "contact_intent" => "recurring_payload_downlink",
      "success_measure" => "minimum_duration",
      "minimum_duration_seconds" => "600",
      "preferred_duration_seconds" => "900",
      "minimum_data_volume_bytes" => "",
      "contact_count" => "1",
      "minimum_separation_seconds" => "0",
      "priority" => "high",
      "approval_mode" => "manual",
      "maximum_occurrences_per_run" => "50",
      "maximum_lookback_hours" => "72",
      "rationale" => "Routine recorder relief"
    }
  end

  defp requirement_attrs(spacecraft_id, now) do
    %{
      spacecraft_id: spacecraft_id,
      service_direction: :downlink,
      contact_intent: "payload_downlink",
      earliest_start: DateTime.add(now, 600, :second),
      latest_end: DateTime.add(now, 18_000, :second),
      success_measure: :minimum_duration,
      minimum_duration_seconds: 600,
      preferred_duration_seconds: 900,
      minimum_data_volume_bytes: nil,
      contact_count: 1,
      minimum_separation_seconds: 0,
      priority: :high,
      provider_constraints_document: %{"allowed" => [], "excluded" => []},
      station_constraints_document: %{"allowed" => [], "excluded" => []},
      policy_constraints_document: %{},
      approval_policy_document: %{"mode" => "manual"},
      rationale: "LiveView fleet planning proof",
      metadata: %{}
    }
  end

  defp policy_attrs do
    %{
      horizon_document: %{
        "max_horizon_seconds" => 86_400,
        "requirement_concurrency" => 4,
        "provider_search_concurrency" => 2,
        "reuse_freshness_seconds" => 300
      },
      scoring_document: %{},
      resource_policy_document: %{},
      budget_quota_document: %{
        "max_contacts" => 100,
        "max_estimated_cost_micros" => nil,
        "currency" => nil,
        "per_provider" => %{},
        "critical_contact_reserve" => 0,
        "critical_cost_reserve_micros" => 0
      },
      redundancy_document: %{},
      automation_repair_document: %{
        "mode" => "advisory",
        "execution_concurrency" => 2,
        "max_repair_attempts" => 2,
        "repair_horizon_seconds" => 43_200,
        "automatic_submission" => false
      }
    }
  end

  defp datetime_local(datetime), do: Calendar.strftime(datetime, "%Y-%m-%dT%H:%M:%S")
end
