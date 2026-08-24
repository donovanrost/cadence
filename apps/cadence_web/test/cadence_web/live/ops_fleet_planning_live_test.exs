defmodule CadenceWeb.OpsFleetPlanningLiveTest do
  use CadenceWeb.ConnCase, async: false

  import CadenceWeb.AsyncLiveViewTestSupport,
    only: [render_async: 2, track_async_view: 1]

  import CadenceWeb.OpsNavTestSupport
  import Phoenix.LiveViewTest, except: [render_async: 2]

  use Phoenix.VerifiedRoutes,
    endpoint: CadenceWeb.Endpoint,
    router: CadenceWeb.Router,
    statics: CadenceWeb.static_paths()

  alias Cadence.Auth.Scope

  alias Cadence.ContactPlanning.{
    ContactRequirements,
    ContactRequirementTemplates,
    FleetPlanningPolicies,
    FleetPlanningRuns,
    Planner
  }

  alias CadenceWeb.TestFixtures

  test "authenticated mission operators can navigate the planning journey and see stopped state" do
    {member_conn, _scope, _org, mission, _spacecraft} = signed_in_scope(:member)

    {:ok, view, _html} =
      live(member_conn, ~p"/missions/#{mission.mission_id}/ops/planning")

    assert has_element?(view, "#ops-fleet-planning-component.contents")

    assert ops_nav_item(ops_nav_vue(view), "planning") == %{
             "active" => true,
             "href" => "/missions/#{mission.mission_id}/ops/planning",
             "icon" => "hero-chart-bar-square",
             "key" => "planning",
             "label" => "Planning"
           }

    planning_vue = fleet_planning_vue(view)

    assert planning_vue.component == "OpsFleetPlanning"
    assert planning_vue.class == "contents"
    assert planning_vue.ssr == false
    assert planning_vue.slots == %{}

    assert planning_vue.handlers == %{
             "refresh-planning" => Phoenix.LiveView.JS.push("refresh-planning")
           }

    assert planning_vue.props ==
             workspace_props(
               mission,
               stopped_control_metrics(),
               stopped_policy_props(mission),
               ledger_props(0, ledger_empty_props())
             )

    assert fleet_run_stream_mutations(planning_vue) == [
             ["replace", "/fleet_runs", []]
           ]

    assert_json_safe_fleet_planning_vue(planning_vue)

    {:ok, new_view, _html} =
      live(member_conn, ~p"/missions/#{mission.mission_id}/ops/planning/new")

    assert has_element?(new_view, "#ops-fleet-planning-new-component")
    refute has_element?(new_view, "#ops-fleet-planning-new-page")
    refute has_element?(new_view, "#fleet-planning-new-policy-required")
    refute has_element?(new_view, "#fleet-planning-run-form")

    new_vue = LiveVue.Test.get_vue(new_view, id: "ops-fleet-planning-new-component")

    assert new_vue.component == "OpsFleetPlanningNew"
    assert new_vue.class == "contents"
    assert new_vue.ssr == false
    assert new_vue.props == Jason.decode!(Jason.encode!(new_vue.props))

    assert new_vue.handlers == %{
             "create-fleet-run" => Phoenix.LiveView.JS.push("create-fleet-run"),
             "validate-fleet-run" => Phoenix.LiveView.JS.push("validate-fleet-run")
           }

    assert new_vue.props == %{
             "form" => nil,
             "header" => %{
               "id" => "ops-fleet-planning-new-page",
               "back" => %{
                 "id" => "fleet-planning-back-link",
                 "icon" => "hero-arrow-left",
                 "label" => "Fleet planning"
               },
               "title" => "Plan a mission horizon",
               "copy" =>
                 "Choose only the time boundary. The active policy supplies concurrency, resource, quota, budget, scoring, repair, and automation rules."
             },
             "paths" => %{
               "planning" => "/missions/#{mission.mission_id}/ops/planning",
               "policy" => "/missions/#{mission.mission_id}/ops/planning/policy"
             },
             "policy_state" => %{
               "active" => false,
               "required" => %{
                 "id" => "fleet-planning-new-policy-required",
                 "icon" => "hero-lock-closed",
                 "title" => "An approved policy is required",
                 "copy" =>
                   "Provider searches remain stopped until an organization administrator approves the fleet boundary.",
                 "action_id" => "fleet-planning-open-policy-link",
                 "action_label" => "Open policy"
               }
             },
             "preview" => nil
           }

    {:ok, policy_view, _html} =
      live(member_conn, ~p"/missions/#{mission.mission_id}/ops/planning/policy")

    assert has_element?(policy_view, "#ops-fleet-planning-policy-page")
    assert has_element?(policy_view, "#fleet-policy-admin-required")
    refute has_element?(policy_view, "#fleet-policy-form")

    {:ok, template_view, _html} =
      live(member_conn, ~p"/missions/#{mission.mission_id}/ops/requirement-templates")

    assert contact_requirement_template_vue(template_view).props["page"]["id"] ==
             "ops-requirement-templates-page"

    assert contact_requirement_template_vue(template_view).props["authorization"][
             "admin_required"
           ]["id"] == "requirement-template-admin-required"
  end

  test "planning workspace refresh replaces the ledger with exact run contracts" do
    {conn, scope, _org, mission, spacecraft} = signed_in_scope(:organization_admin)
    activate_policy!(scope, mission)

    now = DateTime.utc_now() |> DateTime.truncate(:second)
    horizon_end = DateTime.add(now, 6, :hour)

    assert {:ok, requirement, _version} =
             ContactRequirements.create(
               scope,
               mission.mission_id,
               requirement_attrs(spacecraft.spacecraft_id, now),
               now: now
             )

    {:ok, view, _html} =
      live(conn, ~p"/missions/#{mission.mission_id}/ops/planning")

    initial_vue = fleet_planning_vue(view)

    assert initial_vue.props ==
             workspace_props(
               mission,
               active_control_metrics("0"),
               nil,
               ledger_props(0, ledger_empty_props())
             )

    assert fleet_run_stream_mutations(initial_vue) == [
             ["replace", "/fleet_runs", []]
           ]

    assert {:ok, queued_run, [_queued_ref]} =
             FleetPlanningRuns.create(scope, mission.mission_id, %{
               horizon_start: now,
               horizon_end: horizon_end,
               trigger_kind: :manual
             })

    assert {:ok, partial_source, [_partial_ref]} =
             FleetPlanningRuns.create(scope, mission.mission_id, %{
               horizon_start: now,
               horizon_end: horizon_end,
               trigger_kind: :scheduled
             })

    assert {:ok, failed_source, [_failed_ref]} =
             FleetPlanningRuns.create(scope, mission.mission_id, %{
               horizon_start: now,
               horizon_end: horizon_end,
               trigger_kind: :manual
             })

    partial_run = finish_partial_run!(scope, mission, partial_source, requirement)

    assert {:ok, failed_run} =
             FleetPlanningRuns.fail(
               scope,
               mission.mission_id,
               failed_source.fleet_planning_run_id,
               :queued,
               %{"code" => "provider_search_unavailable"}
             )

    render_hook(view, "refresh-planning", %{})

    refreshed_vue = fleet_planning_vue(view)

    assert refreshed_vue.props ==
             workspace_props(
               mission,
               active_control_metrics("2"),
               nil,
               ledger_props(3, nil)
             )

    expected_rows = %{
      queued_run.fleet_planning_run_id => queued_run_props(queued_run, mission),
      partial_run.fleet_planning_run_id => partial_run_props(partial_run, mission),
      failed_run.fleet_planning_run_id => failed_run_props(failed_run, mission)
    }

    assert Map.new(fleet_run_upserts(refreshed_vue), &{&1["fleet_planning_run_id"], &1}) ==
             expected_rows

    assert [
             ["replace", "/fleet_runs", []],
             ["upsert", "/fleet_runs/-", _first_run],
             ["upsert", "/fleet_runs/-", _second_run],
             ["upsert", "/fleet_runs/-", _third_run]
           ] = fleet_run_stream_mutations(refreshed_vue)

    assert_json_safe_fleet_planning_vue(refreshed_vue)
  end

  test "an organization administrator creates and activates the exact fleet policy in UI" do
    {conn, _scope, org, mission, _spacecraft} = signed_in_scope(:organization_admin)

    {:ok, view, _html} =
      live(conn, ~p"/missions/#{mission.mission_id}/ops/planning/policy")

    initial_vue = fleet_policy_vue(view)

    assert initial_vue.component == "OpsFleetPlanningPolicy"
    assert initial_vue.class == "contents"
    assert initial_vue.ssr == false
    assert initial_vue.slots == %{}

    assert initial_vue.handlers == %{
             "approve-policy" => Phoenix.LiveView.JS.push("approve-policy"),
             "issue-grant" => Phoenix.LiveView.JS.push("issue-grant"),
             "revoke-grant" => Phoenix.LiveView.JS.push("revoke-grant"),
             "save-policy" => Phoenix.LiveView.JS.push("save-policy"),
             "validate-grant" => Phoenix.LiveView.JS.push("validate-grant"),
             "validate-policy" => Phoenix.LiveView.JS.push("validate-policy")
           }

    assert initial_vue.props["page"] == %{
             "back" => %{
               "href" => "/missions/#{mission.mission_id}/ops/planning",
               "icon" => "hero-arrow-left",
               "label" => "Fleet planning"
             },
             "header" => %{
               "copy" =>
                 "Operators declare mission needs. Organization administrators approve the bounded horizon, capacity, cost, repair, and unattended authority Cadence may use.",
               "eyebrow" => "Administrative boundary",
               "title" => "Fleet Policy & Automation"
             },
             "manifest" => %{
               "content_sha256" => nil,
               "empty" => %{
                 "copy" =>
                   "Fleet runs and automation remain stopped until an administrator creates and approves a policy.",
                 "icon" => "hero-adjustments-horizontal",
                 "id" => "fleet-policy-empty",
                 "title" => "No scheduling boundary exists"
               },
               "id" => "fleet-policy-manifest",
               "sections" => [],
               "version_label" => "not configured"
             },
             "state" => %{
               "class" =>
                 "border border-warning/40 bg-warning/10 px-2 py-1 font-mono text-xs uppercase text-warning",
               "id" => "fleet-policy-state",
               "label" => "stopped"
             }
           }

    assert Map.take(initial_vue.props["policy_form"], [
             "id",
             "open",
             "panel_id",
             "redundancy",
             "submit",
             "summary"
           ]) == %{
             "id" => "fleet-policy-form",
             "open" => true,
             "panel_id" => "fleet-policy-editor",
             "redundancy" => %{
               "id" => "fleet-policy-redundancy-details",
               "summary" => "Redundancy constraints"
             },
             "submit" => %{
               "id" => "save-fleet-policy",
               "label" => "Create draft policy"
             },
             "summary" => "Create the initial policy"
           }

    assert initial_vue.props["authorization"] == %{
             "admin_required" => nil,
             "organization_admin" => true
           }

    assert initial_vue.props["grant_ledger"] == %{
             "active_count" => 0,
             "active_label" => "0 active",
             "empty" => %{
               "copy" => "No automation authority issued.",
               "id" => "automation-grants-empty"
             },
             "id" => "automation-grant-ledger",
             "list_id" => "automation-grants"
           }

    assert initial_vue.props["approval_form"] == nil
    assert initial_vue.props["grant_form"] == nil
    assert initial_vue.props["revocation_form"] == nil

    assert policy_form_field_contract(initial_vue.props["policy_form"]) ==
             initial_policy_form_field_contract()

    assert fleet_policy_stream_mutations(initial_vue) == [
             ["replace", "/automation_grants", []]
           ]

    assert_json_safe_fleet_policy_vue(initial_vue)

    policy_params = %{
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
      "repair_horizon_hours" => "12",
      "distinct_provider_required" => "false",
      "distinct_station_required" => "false",
      "distinct_service_pool_required" => "false"
    }

    render_hook(view, "validate-policy", %{"policy" => policy_params})

    validated_vue = fleet_policy_vue(view)

    assert Map.new(validated_vue.props["policy_form"]["fields"], fn {field, contract} ->
             {field, contract["value"]}
           end) ==
             Map.merge(policy_params, %{
               "automatic_submission" => false,
               "distinct_provider_required" => false,
               "distinct_service_pool_required" => false,
               "distinct_station_required" => false
             })

    render_hook(view, "save-policy", %{"policy" => policy_params})

    draft_vue = fleet_policy_vue(view)

    assert draft_vue.props["approval_form"]["id"] == "fleet-policy-approval-form"
    assert draft_vue.props["approval_form"]["reason"]["value"] == ""
    assert draft_vue.props["approval_form"]["submit"]["label"] == "Approve exact v1"
    assert draft_vue.props["page"]["state"]["label"] == "draft"
    assert draft_vue.props["page"]["state"]["id"] == "fleet-policy-state"
    assert draft_vue.props["page"]["manifest"]["version_label"] == "v1"
    assert draft_vue.props["page"]["manifest"]["content_sha256"] =~ ~r/\A[0-9a-f]{64}\z/

    assert draft_vue.props["page"]["manifest"]["sections"] == [
             %{
               "facts" => [
                 %{"term" => "Maximum horizon", "value" => "24.0 h"},
                 %{"term" => "Requirement workers", "value" => "8"},
                 %{"term" => "Provider workers", "value" => "4"},
                 %{"term" => "Evidence reuse", "value" => "300 sec"}
               ],
               "title" => "Horizon & search"
             },
             %{
               "facts" => [
                 %{"term" => "Contact ceiling", "value" => "300"},
                 %{"term" => "Cost ceiling", "value" => "none"},
                 %{"term" => "Critical reserve", "value" => "5"},
                 %{"term" => "Default capacity", "value" => "1"}
               ],
               "title" => "Quota & budget"
             },
             %{
               "facts" => [
                 %{"term" => "Mode", "value" => "advisory"},
                 %{"term" => "Automatic submission", "value" => "no"},
                 %{"term" => "Execution workers", "value" => "4"},
                 %{"term" => "Repair attempts", "value" => "3"}
               ],
               "title" => "Automation"
             },
             %{
               "facts" => [
                 %{"term" => "Distinct provider", "value" => "no"},
                 %{"term" => "Distinct station", "value" => "no"},
                 %{"term" => "Distinct pool", "value" => "no"},
                 %{"term" => "Repair horizon", "value" => "12.0 h"}
               ],
               "title" => "Redundancy"
             }
           ]

    draft_content_sha256 = draft_vue.props["page"]["manifest"]["content_sha256"]
    assert has_element?(view, "#flash-info", "Draft policy created.")

    {:ok, view, _html} =
      live(conn, ~p"/missions/#{mission.mission_id}/ops/planning/policy")

    render_hook(view, "approve-policy", %{
      "decision" => %{"reason" => "Bound mission-scale provider demand"}
    })

    active_vue = fleet_policy_vue(view)

    assert active_vue.props["page"]["state"]["label"] == "active"
    assert active_vue.props["approval_form"] == nil

    assert has_element?(
             view,
             "#flash-info",
             "Exact policy version approved and activated."
           )

    assert {:ok, policy, version} =
             FleetPlanningPolicies.fetch_active(
               org.organization_id,
               mission.mission_id
             )

    assert policy.active_version == version.version
    assert version.budget_quota_document["max_contacts"] == 300
    assert version.budget_quota_document["critical_contact_reserve"] == 5
    assert version.content_sha256 == draft_content_sha256

    assert [approval] =
             FleetPlanningPolicies.list_approvals(
               org.organization_id,
               mission.mission_id,
               policy.fleet_planning_policy_id
             )

    assert approval.fleet_planning_policy_version == version.version
    assert approval.content_sha256 == version.content_sha256
    assert approval.reason == "Bound mission-scale provider demand"
  end

  test "fleet policy LiveVue keeps non-admin presentation read-only and server actions closed" do
    {conn, _scope, org, mission, _spacecraft} = signed_in_scope(:member)

    {:ok, view, _html} =
      live(conn, ~p"/missions/#{mission.mission_id}/ops/planning/policy")

    assert has_element?(view, "#ops-fleet-planning-policy-page")
    assert has_element?(view, "#fleet-policy-admin-required")

    vue = fleet_policy_vue(view)

    assert vue.props["authorization"] == %{
             "admin_required" => %{
               "copy" =>
                 "Organization administrator authority is required to change policy or grants."
             },
             "organization_admin" => false
           }

    assert vue.props["policy_form"] == nil
    assert vue.props["approval_form"] == nil
    assert vue.props["grant_form"] == nil
    assert vue.props["revocation_form"] == nil

    render_hook(view, "save-policy", %{
      "policy" => %{
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
    })

    assert has_element?(
             view,
             "#flash-error",
             "Organization administrator authority is required."
           )

    assert {:error, :fleet_planning_policy_not_found} =
             FleetPlanningPolicies.fetch(org.organization_id, mission.mission_id)

    assert_json_safe_fleet_policy_vue(fleet_policy_vue(view))
  end

  test "fleet policy LiveVue validates, issues, streams, and exactly revokes automation grants" do
    {conn, scope, _org, mission, _spacecraft} = signed_in_scope(:organization_admin)
    activate_policy!(scope, mission)

    service_identity =
      Cadence.Auth.ServiceIdentity.new(%{
        service_identity_id: "svc-fleet-policy",
        organization_id: scope.organization_id,
        mission_id: mission.mission_id,
        display_name: "Fleet policy automation",
        capabilities: [:mission_admin]
      })

    assert {:ok, %{service_identity: %{service_identity_id: "svc-fleet-policy"}}} =
             Cadence.Auth.issue_service_identity(service_identity)

    {:ok, view, _html} =
      live(conn, ~p"/missions/#{mission.mission_id}/ops/planning/policy")

    initial_vue = fleet_policy_vue(view)
    grant_form = initial_vue.props["grant_form"]

    assert grant_form["id"] == "automation-grant-form"

    assert grant_form["fields"]["service_identity_id"]["options"] == [
             %{"label" => "Fleet policy automation", "value" => "svc-fleet-policy"}
           ]

    assert Map.new(grant_form["fields"], fn {field, contract} ->
             {field, contract["value"]}
           end) == %{
             "approval_reason" => "",
             "maximum_contacts" => "100",
             "maximum_execution_concurrency" => "2",
             "maximum_horizon_hours" => "24",
             "service_identity_id" => "svc-fleet-policy",
             "valid_days" => "30"
           }

    grant_params = %{
      "service_identity_id" => "svc-fleet-policy",
      "maximum_horizon_hours" => "12",
      "maximum_contacts" => "40",
      "maximum_execution_concurrency" => "2",
      "valid_days" => "30",
      "approval_reason" => "Bound unattended fleet search"
    }

    render_hook(view, "validate-grant", %{"grant" => grant_params})

    validated_vue = fleet_policy_vue(view)

    assert Map.new(validated_vue.props["grant_form"]["fields"], fn {field, contract} ->
             {field, contract["value"]}
           end) == grant_params

    render_hook(view, "issue-grant", %{"grant" => grant_params})

    assert has_element?(view, "#flash-info", "Exact service automation grant issued.")

    [grant] =
      Cadence.ContactPlanning.AutomationGrants.list(
        scope.organization_id,
        mission.mission_id
      )

    issued_vue = fleet_policy_vue(view)

    assert issued_vue.props["grant_ledger"]["active_count"] == 1
    assert issued_vue.props["grant_ledger"]["active_label"] == "1 active"

    assert [row] = fleet_policy_grant_upserts(issued_vue)

    assert row == %{
             "__dom_id" => "automation-grant-#{grant.automation_grant_id}",
             "automation_grant_id" => grant.automation_grant_id,
             "boundary" => "≤ 40 contacts · ≤ 12.0 h",
             "expiry" => "expires #{Calendar.strftime(grant.valid_until, "%d %b %Y %H:%MZ")}",
             "lifecycle_state" => "active",
             "lifecycle_state_class" => "font-mono text-[0.58rem] uppercase text-success",
             "policy_evidence" => "policy v1 · plan, repair",
             "service_identity_id" => "svc-fleet-policy"
           }

    assert [
             ["replace", "/automation_grants", []],
             ["upsert", "/automation_grants/-", ^row]
           ] = fleet_policy_stream_mutations(issued_vue)

    assert issued_vue.props["revocation_form"]["fields"]["automation_grant_id"][
             "options"
           ] == [
             %{
               "label" => "svc-fleet-policy",
               "value" => grant.automation_grant_id
             }
           ]

    {:ok, view, _html} =
      live(conn, ~p"/missions/#{mission.mission_id}/ops/planning/policy")

    render_hook(view, "revoke-grant", %{
      "revocation" => %{
        "automation_grant_id" => grant.automation_grant_id,
        "reason" => "Return scheduling to attended operations"
      }
    })

    assert has_element?(view, "#flash-info", "Automation grant revoked immediately.")

    revoked_vue = fleet_policy_vue(view)
    assert revoked_vue.props["grant_ledger"]["active_count"] == 0
    assert revoked_vue.props["revocation_form"] == nil

    assert [revoked_row] = fleet_policy_grant_upserts(revoked_vue)
    assert revoked_row["automation_grant_id"] == grant.automation_grant_id
    assert revoked_row["lifecycle_state"] == "revoked"

    assert revoked_row["lifecycle_state_class"] ==
             "font-mono text-[0.58rem] uppercase text-base-content/45"

    assert {:ok, revoked} =
             Cadence.ContactPlanning.AutomationGrants.fetch(
               scope.organization_id,
               mission.mission_id,
               grant.automation_grant_id
             )

    assert revoked.lifecycle_state == :revoked
    assert revoked.revocation_reason == "Return scheduling to attended operations"
    assert_json_safe_fleet_policy_vue(revoked_vue)
  end

  test "administrator creates and pauses a progressively rendered recurring Requirement Template" do
    {conn, _scope, org, mission, spacecraft} = signed_in_scope(:organization_admin)

    {:ok, view, _html} =
      live(conn, ~p"/missions/#{mission.mission_id}/ops/requirement-templates")

    initial_vue = contact_requirement_template_vue(view)

    assert initial_vue.component == "OpsContactRequirementTemplate"
    assert initial_vue.class == "contents"
    assert initial_vue.ssr == false
    assert initial_vue.slots == %{}

    assert initial_vue.handlers == %{
             "activate-template" => Phoenix.LiveView.JS.push("activate-template"),
             "close-template" => Phoenix.LiveView.JS.push("close-template"),
             "create-template" => Phoenix.LiveView.JS.push("create-template"),
             "pause-template" => Phoenix.LiveView.JS.push("pause-template"),
             "validate-template" => Phoenix.LiveView.JS.push("validate-template")
           }

    assert initial_vue.props["page"] == %{
             "id" => "ops-requirement-templates-page",
             "back" => %{
               "href" => "/missions/#{mission.mission_id}/ops/planning",
               "icon" => "hero-arrow-left",
               "label" => "Fleet planning"
             },
             "header" => %{
               "eyebrow" => "Recurring demand definition",
               "title" => "Requirement Templates",
               "copy" =>
                 "Define a UTC recurrence once. Each due occurrence materializes exactly one ordinary Contact Requirement with immutable provenance."
             }
           }

    assert initial_vue.props["authorization"] == %{
             "admin_required" => nil,
             "organization_admin" => true
           }

    assert initial_vue.props["template_form"]["id"] == "requirement-template-form"
    assert initial_vue.props["template_form"]["panel_id"] == "requirement-template-editor"

    initial_values = template_form_values(initial_vue.props["template_form"])

    assert Enum.all?(initial_values, fn {_field, value} -> is_binary(value) end)

    assert Map.take(initial_values, [
             "schedule_type",
             "interval_minutes",
             "window_offset_minutes",
             "window_duration_minutes",
             "success_measure",
             "minimum_duration_seconds",
             "minimum_data_volume_bytes",
             "contact_count",
             "priority",
             "approval_mode",
             "maximum_occurrences_per_run",
             "maximum_lookback_hours"
           ]) == %{
             "schedule_type" => "fixed_interval",
             "interval_minutes" => "360",
             "window_offset_minutes" => "0",
             "window_duration_minutes" => "30",
             "success_measure" => "minimum_duration",
             "minimum_duration_seconds" => "600",
             "minimum_data_volume_bytes" => "",
             "contact_count" => "1",
             "priority" => "high",
             "approval_mode" => "manual",
             "maximum_occurrences_per_run" => "100",
             "maximum_lookback_hours" => "168"
           }

    assert initial_vue.props["template_form"]["fields"]["interval_minutes"]["id"] ==
             "template-interval-minutes"

    assert initial_vue.props["template_form"]["fields"]["time_utc"]["id"] ==
             "template-time-utc"

    assert contact_requirement_template_stream_mutations(initial_vue) == [
             ["replace", "/templates", []]
           ]

    assert_json_safe_contact_requirement_template_vue(initial_vue)

    params = template_params(spacecraft)

    daily_params = Map.put(params, "schedule_type", "daily")

    render_hook(view, "validate-template", %{"template" => daily_params})

    validated_vue = contact_requirement_template_vue(view)

    assert template_form_values(validated_vue.props["template_form"]) == daily_params
    assert validated_vue.props["template_form"]["fields"]["schedule_type"]["value"] == "daily"
    assert validated_vue.props["template_form"]["fields"]["time_utc"]["value"] == "12:00:00"
    assert validated_vue.props["template_form"]["fields"]["interval_minutes"]["value"] == "360"

    render_hook(view, "validate-template", %{"template" => params})

    fixed_vue = contact_requirement_template_vue(view)

    assert template_form_values(fixed_vue.props["template_form"]) == params

    render_hook(view, "create-template", %{"template" => params})

    [{template, version}] =
      ContactRequirementTemplates.list(
        org.organization_id,
        mission.mission_id
      )

    assert version.spacecraft_id == spacecraft.spacecraft_id
    assert version.schedule_document["type"] == "fixed_interval"
    assert version.schedule_document["interval_seconds"] == 21_600

    created_vue = contact_requirement_template_vue(view)

    assert created_vue.props["ledger"]["count"] == 1
    assert created_vue.props["ledger"]["empty"] == nil

    assert [created_row] = contact_requirement_template_upserts(created_vue)

    assert created_row == %{
             "__dom_id" => "requirement-template-#{template.contact_requirement_template_id}",
             "actions" => %{
               "activate" => nil,
               "close" => %{
                 "class" => "btn btn-ghost btn-xs text-error",
                 "id" => "close-template-#{template.contact_requirement_template_id}",
                 "label" => "Close"
               },
               "pause" => %{
                 "class" => "btn btn-ghost btn-xs",
                 "id" => "pause-template-#{template.contact_requirement_template_id}",
                 "label" => "Pause"
               }
             },
             "content_sha256" => version.content_sha256,
             "id" => template.contact_requirement_template_id,
             "lifecycle" => %{
               "class" =>
                 "border border-success/35 bg-success/10 px-1.5 py-0.5 font-mono text-[0.58rem] uppercase text-success",
               "state" => "active"
             },
             "schedule" => "Every 360 min · 45 min window",
             "title" => "#{spacecraft.spacecraft_id} · recurring payload downlink",
             "version_label" => "v1"
           }

    render_hook(view, "pause-template", %{"id" => template.contact_requirement_template_id})

    [{paused, _version}] =
      ContactRequirementTemplates.list(
        org.organization_id,
        mission.mission_id
      )

    assert paused.lifecycle_state == :paused

    paused_vue = contact_requirement_template_vue(view)
    assert [paused_row] = contact_requirement_template_upserts(paused_vue)
    assert paused_row["lifecycle"]["state"] == "paused"
    assert paused_row["actions"]["pause"] == nil

    assert paused_row["actions"]["activate"]["id"] ==
             "activate-template-#{template.contact_requirement_template_id}"

    member = TestFixtures.persist_user!()
    TestFixtures.grant_membership!(member, org, role: :member)

    {:ok, member_view, _html} =
      live(
        TestFixtures.member_conn(member),
        ~p"/missions/#{mission.mission_id}/ops/requirement-templates"
      )

    member_vue = contact_requirement_template_vue(member_view)

    assert member_vue.props["template_form"] == nil

    assert member_vue.props["authorization"] == %{
             "admin_required" => %{
               "id" => "requirement-template-admin-required",
               "copy" =>
                 "Organization administrator authority is required to manage recurring demand."
             },
             "organization_admin" => false
           }

    assert [member_row] = contact_requirement_template_upserts(member_vue)
    refute Map.has_key?(member_row, "actions")

    render_hook(member_view, "activate-template", %{
      "id" => template.contact_requirement_template_id
    })

    assert has_element?(
             member_view,
             "#flash-error",
             "Organization administrator authority is required."
           )

    [{still_paused, _version}] =
      ContactRequirementTemplates.list(
        org.organization_id,
        mission.mission_id
      )

    assert still_paused.lifecycle_state == :paused
    assert_json_safe_contact_requirement_template_vue(member_vue)
  end

  test "starting a horizon persists first and the run workspace resumes durable phases" do
    {conn, scope, org, mission, spacecraft} = signed_in_scope(:organization_admin)
    activate_policy!(scope, mission)

    now = DateTime.utc_now() |> DateTime.truncate(:second)

    assert {:ok, requirement, _version} =
             ContactRequirements.create(
               scope,
               mission.mission_id,
               requirement_attrs(spacecraft.spacecraft_id, now),
               now: now
             )

    {:ok, view, _html} =
      live(conn, ~p"/missions/#{mission.mission_id}/ops/planning/new")

    assert has_element?(view, "#ops-fleet-planning-new-component")
    refute has_element?(view, "#fleet-planning-run-form")
    refute has_element?(view, "#fleet-run-policy-preview")
    refute has_element?(view, "#fleet-run-policy-progressive-details")

    initial_vue = LiveVue.Test.get_vue(view, id: "ops-fleet-planning-new-component")

    assert initial_vue.component == "OpsFleetPlanningNew"
    assert initial_vue.class == "contents"
    assert initial_vue.ssr == false

    assert initial_vue.handlers == %{
             "create-fleet-run" => Phoenix.LiveView.JS.push("create-fleet-run"),
             "validate-fleet-run" => Phoenix.LiveView.JS.push("validate-fleet-run")
           }

    assert initial_vue.props["form"]["id"] == "fleet-planning-run-form"
    assert initial_vue.props["preview"]["id"] == "fleet-run-policy-preview"

    assert initial_vue.props["preview"]["details"]["id"] ==
             "fleet-run-policy-progressive-details"

    horizon_end = DateTime.add(now, 6, :hour)

    fleet_run_params = %{
      "horizon_start" => datetime_local(now),
      "horizon_end" => datetime_local(horizon_end),
      "include_recurring" => "true"
    }

    render_hook(view, "validate-fleet-run", %{"fleet_run" => fleet_run_params})

    validated_vue = LiveVue.Test.get_vue(view, id: "ops-fleet-planning-new-component")

    assert validated_vue.props == %{
             "form" => %{
               "id" => "fleet-planning-run-form",
               "fields" => %{
                 "horizon_start" => %{
                   "id" => "fleet-run-horizon-start",
                   "name" => "fleet_run[horizon_start]",
                   "type" => "datetime-local",
                   "label" => "Horizon starts (UTC)",
                   "required" => true,
                   "value" => datetime_local(now),
                   "errors" => []
                 },
                 "horizon_end" => %{
                   "id" => "fleet-run-horizon-end",
                   "name" => "fleet_run[horizon_end]",
                   "type" => "datetime-local",
                   "label" => "Horizon ends (UTC)",
                   "required" => true,
                   "value" => datetime_local(horizon_end),
                   "errors" => []
                 },
                 "include_recurring" => %{
                   "id" => "fleet-run-include-recurring",
                   "name" => "fleet_run[include_recurring]",
                   "type" => "checkbox",
                   "label" => "Materialize recurring Requirement Templates in this horizon",
                   "value" => true,
                   "errors" => []
                 }
               },
               "snapshot" => %{
                 "label" => "Snapshot boundary",
                 "copy" =>
                   "Starting the run freezes exact Requirement and policy versions. Later edits stop the run closed rather than silently changing its inputs."
               },
               "submit" => %{
                 "id" => "start-fleet-planning-run",
                 "label" => "Start durable planning run"
               }
             },
             "header" => %{
               "id" => "ops-fleet-planning-new-page",
               "back" => %{
                 "id" => "fleet-planning-back-link",
                 "icon" => "hero-arrow-left",
                 "label" => "Fleet planning"
               },
               "title" => "Plan a mission horizon",
               "copy" =>
                 "Choose only the time boundary. The active policy supplies concurrency, resource, quota, budget, scoring, repair, and automation rules."
             },
             "paths" => %{
               "planning" => "/missions/#{mission.mission_id}/ops/planning",
               "policy" => "/missions/#{mission.mission_id}/ops/planning/policy"
             },
             "policy_state" => %{"active" => true, "required" => nil},
             "preview" => %{
               "id" => "fleet-run-policy-preview",
               "eyebrow" => "Active policy",
               "version" => "v1",
               "facts" => [
                 %{"term" => "Maximum horizon", "value" => "24 hours"},
                 %{"term" => "Requirement workers", "value" => "4"},
                 %{"term" => "Provider searches", "value" => "2"},
                 %{"term" => "Contact ceiling", "value" => "100"},
                 %{"term" => "Automation", "value" => "advisory"}
               ],
               "details" => %{
                 "id" => "fleet-run-policy-progressive-details",
                 "summary" => "Why these settings?",
                 "copy" =>
                   "Operators choose demand and horizon. Administrators own organizational risk: provider concurrency, cost, quotas, and unattended authority."
               }
             }
           }

    assert validated_vue.props == Jason.decode!(Jason.encode!(validated_vue.props))

    render_hook(view, "create-fleet-run", %{"fleet_run" => fleet_run_params})

    [run] = FleetPlanningRuns.list(org.organization_id, mission.mission_id)

    assert_redirect(
      view,
      ~p"/missions/#{mission.mission_id}/ops/planning/runs/#{run.fleet_planning_run_id}"
    )

    {:ok, run_view, initial_run_html} =
      live(
        conn,
        ~p"/missions/#{mission.mission_id}/ops/planning/runs/#{run.fleet_planning_run_id}"
      )

    track_async_view(run_view)

    assert has_element?(run_view, "#ops-fleet-planning-run-component.contents")
    refute has_element?(run_view, "#ops-fleet-planning-run-page")
    refute has_element?(run_view, "#fleet-run-phase-strip")
    refute has_element?(run_view, "#fleet-coverage-matrix")
    refute has_element?(run_view, "#fleet-decision-inspector")
    refute has_element?(run_view, "#fleet-requirement-rows")

    initial_run_vue = fleet_planning_run_vue(initial_run_html)

    assert initial_run_vue.component == "OpsFleetPlanningRun"
    assert initial_run_vue.class == "contents"
    assert initial_run_vue.ssr == false
    assert initial_run_vue.slots == %{}
    assert initial_run_vue.props["planning"] == true

    assert initial_run_vue.handlers == %{
             "refresh-fleet-run" => Phoenix.LiveView.JS.push("refresh-fleet-run"),
             "repair-fleet-run" => Phoenix.LiveView.JS.push("repair-fleet-run")
           }

    assert initial_run_vue.props["page"]["header"]["run_id"] ==
             run.fleet_planning_run_id

    assert [requirement_row] =
             fleet_planning_run_stream_upserts(initial_run_vue, "requirement_rows")

    assert requirement_row["__dom_id"] ==
             "fleet-requirement-#{requirement.contact_requirement_id}"

    assert requirement_row["requirement_href"] ==
             "/missions/#{mission.mission_id}/ops/requirements/#{requirement.contact_requirement_id}"

    assert fleet_planning_run_replaced_streams(initial_run_vue) ==
             ~w(automation_actions decisions exceptions horizon_commitments requirement_rows resource_pressure)

    assert_json_safe_fleet_planning_run_vue(initial_run_vue)

    render_async(run_view, 5_000)

    finished_vue = fleet_planning_run_vue(run_view)

    assert finished_vue.props["planning"] == false

    assert %{"state" => "finished"} =
             Enum.find(
               finished_vue.props["page"]["phase_strip"]["phases"],
               & &1["current"]
             )

    assert_json_safe_fleet_planning_run_vue(finished_vue)

    render_hook(run_view, "refresh-fleet-run", %{})

    refreshed_vue = fleet_planning_run_vue(run_view)
    assert refreshed_vue.props["planning"] == false

    assert fleet_planning_run_replaced_streams(refreshed_vue) ==
             ~w(automation_actions decisions exceptions horizon_commitments requirement_rows resource_pressure)

    assert_json_safe_fleet_planning_run_vue(refreshed_vue)

    assert {:ok, finished} =
             FleetPlanningRuns.fetch(
               org.organization_id,
               mission.mission_id,
               run.fleet_planning_run_id
             )

    assert finished.phase == :finished
  end

  test "fleet run LiveVue exposes terminal evidence through six JSON-safe stream contracts" do
    {conn, scope, _org, mission, spacecraft} = signed_in_scope(:organization_admin)
    activate_policy!(scope, mission)

    now = DateTime.utc_now() |> DateTime.truncate(:second)
    horizon_end = DateTime.add(now, 6, :hour)

    assert {:ok, requirement, requirement_version} =
             ContactRequirements.create(
               scope,
               mission.mission_id,
               requirement_attrs(spacecraft.spacecraft_id, now)
               |> Map.put(:metadata, %{"secret" => "requirement-sensitive-marker"}),
               now: now
             )

    opportunity = %{
      "id" => "opportunity-provider-pressure",
      "spacecraft_ref" => "SC-PROVIDER-PRESSURE",
      "ground_station_ref" => "station-pressure",
      "antenna_or_service_pool_ref" => "pool-pressure",
      "service_profile_ref" => "service-downlink",
      "starts_at" => now |> DateTime.add(1_200, :second) |> DateTime.to_iso8601(),
      "ends_at" => now |> DateTime.add(2_100, :second) |> DateTime.to_iso8601(),
      "expires_at" => now |> DateTime.add(3_600, :second) |> DateTime.to_iso8601(),
      "availability" => "available",
      "estimated_capacity" => %{"bytes" => 1_000_000},
      "synthetic" => true,
      "extensions" => %{"orbit_readiness" => %{"status" => "current"}}
    }

    assert {:ok, planning} =
             Planner.run(
               scope,
               mission.mission_id,
               requirement.contact_requirement_id,
               requirement_version.version,
               now: now,
               list_routes: fn _, _, _ ->
                 {:ok,
                  %{
                    routes: [
                      %{
                        route_key: "route-provider-pressure",
                        spacecraft_id: spacecraft.spacecraft_id,
                        provider_spacecraft_ref: "SC-PROVIDER-PRESSURE",
                        source_endpoint_id: "source-provider-pressure",
                        routing_rule_id: "routing-provider-pressure",
                        link_assignment_id: "link-provider-pressure",
                        path_template_id: "path-provider-pressure",
                        path_template_version: 1,
                        transport_id: "transport-provider-pressure",
                        transport_version: 1,
                        provider_id: "provider-pressure",
                        provider_version: 1,
                        provider_account_id: "account-provider-pressure",
                        provider_account_version: 1,
                        provider_account_grant_id: "grant-provider-pressure",
                        provider_account_grant_version: 1,
                        provider_profile_id: "runtime-provider-pressure",
                        provider_profile_version: 1,
                        service_profile_ref: %{"id" => "service-downlink", "version" => 1},
                        delivery_profile_ref: %{"id" => "delivery-cadence", "version" => 1},
                        delivery_policy_document: %{},
                        provider_display_name: "Provider pressure",
                        service_display_name: "Downlink",
                        delivery_display_name: "Cadence",
                        route_display_name: "Provider pressure route",
                        client: __MODULE__
                      }
                    ],
                    findings: []
                  }}
               end,
               search_opportunities: fn _, _, _, _, _ ->
                 {:ok, %{opportunities: [opportunity]}}
               end
             )

    assert [snapshot] = planning.snapshots

    assert {:ok, run, [_ref]} =
             FleetPlanningRuns.create(scope, mission.mission_id, %{
               horizon_start: now,
               horizon_end: horizon_end,
               trigger_kind: :manual
             })

    assert {:ok, _materializing} =
             FleetPlanningRuns.advance_phase(
               scope,
               mission.mission_id,
               run.fleet_planning_run_id,
               :queued,
               :materializing
             )

    assert {:ok, _searching} =
             FleetPlanningRuns.advance_phase(
               scope,
               mission.mission_id,
               run.fleet_planning_run_id,
               :materializing,
               :searching
             )

    assert {:ok, _failed_ref} =
             FleetPlanningRuns.update_requirement_progress(
               scope,
               mission.mission_id,
               run.fleet_planning_run_id,
               requirement.contact_requirement_id,
               :failed,
               :unsatisfied,
               %{
                 contact_planning_run_id: planning.run.contact_planning_run_id,
                 explanation_document: %{"code" => "provider_search_unavailable"}
               }
             )

    assert {:ok, _optimizing} =
             FleetPlanningRuns.advance_phase(
               scope,
               mission.mission_id,
               run.fleet_planning_run_id,
               :searching,
               :optimizing
             )

    assert {:ok, [decision]} =
             FleetPlanningRuns.persist_decisions(
               scope,
               mission.mission_id,
               run.fleet_planning_run_id,
               [
                 %{
                   contact_opportunity_snapshot_id: snapshot.contact_opportunity_snapshot_id,
                   disposition: :ineligible,
                   score: -10,
                   hard_constraint_document: %{
                     "failures" => [%{"code" => "provider_capacity_exceeded"}]
                   },
                   score_document: %{},
                   explanation_document: %{
                     "code" => "no_eligible_window",
                     "message" => "Provider capacity was exhausted."
                   }
                 }
               ]
             )

    assert {:ok, _materializing_plan} =
             FleetPlanningRuns.advance_phase(
               scope,
               mission.mission_id,
               run.fleet_planning_run_id,
               :optimizing,
               :materializing_plan,
               %{
                 result_summary_document: %{
                   "resources" => %{
                     "resources" => %{
                       "provider-alpha" => %{
                         "peak_parallel" => 3,
                         "capacity" => 2,
                         "over_capacity" => true
                       }
                     }
                   }
                 }
               }
             )

    assert {:ok, failed} =
             FleetPlanningRuns.fail(
               scope,
               mission.mission_id,
               run.fleet_planning_run_id,
               :materializing_plan,
               %{
                 "reason_code" => "provider_search_unavailable",
                 "phase" => "materializing_plan",
                 "credentials" => "failure-sensitive-marker"
               }
             )

    {:ok, view, _html} =
      live(
        conn,
        ~p"/missions/#{mission.mission_id}/ops/planning/runs/#{failed.fleet_planning_run_id}"
      )

    vue = fleet_planning_run_vue(view)

    assert vue.component == "OpsFleetPlanningRun"
    assert vue.class == "contents"
    assert vue.ssr == false
    assert vue.slots == %{}
    assert vue.props["planning"] == false
    assert vue.props["repair_form"] == nil

    assert vue.handlers == %{
             "refresh-fleet-run" => Phoenix.LiveView.JS.push("refresh-fleet-run"),
             "repair-fleet-run" => Phoenix.LiveView.JS.push("repair-fleet-run")
           }

    assert vue.props["page"]["failure"] == %{
             "id" => "fleet-run-failure",
             "label" => "Stopped safely",
             "phase" => "materializing_plan",
             "reason" => "provider search unavailable"
           }

    assert Enum.map(vue.props["page"]["phase_strip"]["phases"], fn phase ->
             Map.take(phase, ["state", "complete", "current"])
           end) == [
             %{"state" => "queued", "complete" => true, "current" => false},
             %{"state" => "materializing", "complete" => true, "current" => false},
             %{"state" => "searching", "complete" => true, "current" => false},
             %{"state" => "optimizing", "complete" => true, "current" => false},
             %{"state" => "materializing_plan", "complete" => true, "current" => false},
             %{"state" => "finished", "complete" => false, "current" => true}
           ]

    assert fleet_planning_run_replaced_streams(vue) ==
             ~w(automation_actions decisions exceptions horizon_commitments requirement_rows resource_pressure)

    assert [requirement_row] = fleet_planning_run_stream_upserts(vue, "requirement_rows")

    assert Map.take(requirement_row, [
             "__dom_id",
             "spacecraft_id",
             "contact_requirement_id",
             "contact_requirement_version",
             "requirement_href",
             "input",
             "coverage",
             "contact_planning_run_id"
           ]) == %{
             "__dom_id" => "fleet-requirement-#{requirement.contact_requirement_id}",
             "spacecraft_id" => spacecraft.spacecraft_id,
             "contact_requirement_id" => requirement.contact_requirement_id,
             "contact_requirement_version" => 1,
             "requirement_href" =>
               "/missions/#{mission.mission_id}/ops/requirements/#{requirement.contact_requirement_id}",
             "input" => %{
               "state" => "failed",
               "label" => "failed",
               "class" => "font-mono text-[0.62rem] uppercase text-error"
             },
             "coverage" => %{
               "state" => "unsatisfied",
               "label" => "unsatisfied",
               "class" => "font-mono text-[0.62rem] uppercase text-warning"
             },
             "contact_planning_run_id" => planning.run.contact_planning_run_id
           }

    assert [exception] = fleet_planning_run_stream_upserts(vue, "exceptions")

    assert exception == %{
             "id" => requirement.contact_requirement_id,
             "__dom_id" => "fleet-exception-#{requirement.contact_requirement_id}",
             "contact_requirement_id" => requirement.contact_requirement_id,
             "result" => %{"state" => "unsatisfied", "label" => "unsatisfied"}
           }

    assert [decision_row] = fleet_planning_run_stream_upserts(vue, "decisions")

    assert Map.take(decision_row, [
             "__dom_id",
             "fleet_planning_decision_id",
             "disposition",
             "title",
             "contact_opportunity_snapshot_id",
             "score",
             "operational_rationale",
             "hard_constraints"
           ]) == %{
             "__dom_id" => "fleet-decision-#{decision.fleet_planning_decision_id}",
             "fleet_planning_decision_id" => decision.fleet_planning_decision_id,
             "disposition" => %{
               "state" => "ineligible",
               "label" => "ineligible",
               "class" =>
                 "border border-error/35 bg-error/[0.07] px-1.5 py-0.5 font-mono text-[0.58rem] uppercase text-error"
             },
             "title" => "Provider pressure · station-pressure",
             "contact_opportunity_snapshot_id" => snapshot.contact_opportunity_snapshot_id,
             "score" => -10,
             "operational_rationale" => "Provider capacity was exhausted.",
             "hard_constraints" => "provider capacity exceeded"
           }

    assert [resource] = fleet_planning_run_stream_upserts(vue, "resource_pressure")

    assert resource == %{
             "id" => "provider-alpha",
             "__dom_id" => "fleet-resource-provider-alpha",
             "peak_parallel" => 3,
             "capacity" => 2,
             "over_capacity" => true,
             "pressure_percent" => 100
           }

    assert fleet_planning_run_stream_upserts(vue, "horizon_commitments") == []
    assert fleet_planning_run_stream_upserts(vue, "automation_actions") == []
    assert_json_safe_fleet_planning_run_vue(vue)

    encoded_contract = Jason.encode!(%{"props" => vue.props, "streams_diff" => vue.streams_diff})
    refute encoded_contract =~ scope.user.email
    refute encoded_contract =~ "requirement-sensitive-marker"
    refute encoded_contract =~ "failure-sensitive-marker"
    refute encoded_contract =~ "trigger_actor_document"
    refute encoded_contract =~ "capabilities"
    refute encoded_contract =~ "credentials"
    refute encoded_contract =~ "metadata"

    render_hook(view, "refresh-fleet-run", %{})

    refreshed_vue = fleet_planning_run_vue(view)
    assert refreshed_vue.props["page"]["failure"] == vue.props["page"]["failure"]
    assert_json_safe_fleet_planning_run_vue(refreshed_vue)
  end

  test "fleet run LiveVue keeps repair values as strings and submits the exact authorized payload" do
    {conn, scope, org, mission, spacecraft} = signed_in_scope(:organization_admin)
    activate_policy!(scope, mission)

    now = DateTime.utc_now() |> DateTime.truncate(:second)
    horizon_end = DateTime.add(now, 6, :hour)

    assert {:ok, requirement, _version} =
             ContactRequirements.create(
               scope,
               mission.mission_id,
               requirement_attrs(spacecraft.spacecraft_id, now),
               now: now
             )

    assert {:ok, source_run, [_ref]} =
             FleetPlanningRuns.create(scope, mission.mission_id, %{
               horizon_start: now,
               horizon_end: horizon_end,
               trigger_kind: :manual
             })

    assert {:ok, result} =
             Cadence.ContactPlanning.FleetPlanner.run(
               scope,
               mission.mission_id,
               source_run.fleet_planning_run_id
             )

    assert result.run.lifecycle_state in [:completed, :partial]
    assert %{} = result.plan
    assert %{} = result.plan_version

    plan_row =
      Cadence.Repo.get_by!(Cadence.Management.Contacts.Store.ContactPlanRow,
        organization_id: org.organization_id,
        mission_id: mission.mission_id,
        contact_plan_id: result.plan.contact_plan_id
      )

    assert {:ok, _failed_plan_row} =
             plan_row
             |> Cadence.Management.Contacts.Store.ContactPlanRow.projection_changeset(%{
               lifecycle_state: "failed",
               lifecycle_changed_at: DateTime.utc_now(),
               lifecycle_reason: "Exercise authorized repair presentation"
             })
             |> Cadence.Repo.update()

    {:ok, view, _html} =
      live(
        conn,
        ~p"/missions/#{mission.mission_id}/ops/planning/runs/#{result.run.fleet_planning_run_id}"
      )

    vue = fleet_planning_run_vue(view)
    repair_form = vue.props["repair_form"]

    assert vue.props["planning"] == false

    assert vue.handlers == %{
             "refresh-fleet-run" => Phoenix.LiveView.JS.push("refresh-fleet-run"),
             "repair-fleet-run" => Phoenix.LiveView.JS.push("repair-fleet-run")
           }

    assert vue.props["page"]["header"]["candidate_plan"] == %{
             "id" => "fleet-run-candidate-plan-link",
             "href" => "/missions/#{mission.mission_id}/ops/plans/#{result.plan.contact_plan_id}",
             "label" => "Open candidate Plan",
             "icon" => "hero-arrow-right"
           }

    assert repair_form["panel_id"] == "fleet-repair-panel"
    assert repair_form["id"] == "fleet-repair-form"
    assert repair_form["sync_key"] == result.run.fleet_planning_run_id
    assert repair_form["submit"] == %{"id" => "start-fleet-repair", "label" => "Start repair run"}

    assert repair_form["fields"]["horizon_start"] == %{
             "id" => "fleet-repair-horizon-start",
             "name" => "repair[horizon_start]",
             "type" => "datetime-local",
             "label" => "Repair starts (UTC)",
             "required" => true,
             "value" => repair_form["fields"]["horizon_start"]["value"]
           }

    assert repair_form["fields"]["horizon_end"] == %{
             "id" => "fleet-repair-horizon-end",
             "name" => "repair[horizon_end]",
             "type" => "datetime-local",
             "label" => "Repair ends (UTC)",
             "required" => true,
             "value" => repair_form["fields"]["horizon_end"]["value"]
           }

    repair_params = %{
      "horizon_start" => repair_form["fields"]["horizon_start"]["value"],
      "horizon_end" => repair_form["fields"]["horizon_end"]["value"]
    }

    assert Enum.all?(Map.values(repair_params), &is_binary/1)
    assert repair_params["horizon_start"] =~ ~r/\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\z/
    assert repair_params["horizon_end"] =~ ~r/\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\z/

    assert [requirement_row] = fleet_planning_run_stream_upserts(vue, "requirement_rows")

    assert requirement_row["requirement_href"] ==
             "/missions/#{mission.mission_id}/ops/requirements/#{requirement.contact_requirement_id}"

    assert_json_safe_fleet_planning_run_vue(vue)

    render_hook(view, "repair-fleet-run", %{"repair" => repair_params})

    repair_run =
      FleetPlanningRuns.list(org.organization_id, mission.mission_id)
      |> Enum.find(&(&1.trigger_kind == :repair))

    assert repair_run.source_fleet_planning_run_id == result.run.fleet_planning_run_id
    assert repair_run.source_contact_plan_id == result.plan.contact_plan_id
    assert repair_run.source_contact_plan_version == result.plan_version.version

    assert_redirect(
      view,
      ~p"/missions/#{mission.mission_id}/ops/planning/runs/#{repair_run.fleet_planning_run_id}"
    )
  end

  defp fleet_planning_run_vue(view) do
    LiveVue.Test.get_vue(view, id: "ops-fleet-planning-run-component")
  end

  defp contact_requirement_template_vue(view) do
    LiveVue.Test.get_vue(view, id: "ops-contact-requirement-template-component")
  end

  defp contact_requirement_template_upserts(vue) do
    vue.streams_diff
    |> Enum.filter(fn
      ["upsert", "/templates/" <> _index, _template] -> true
      _operation -> false
    end)
    |> Enum.map(fn ["upsert", _path, template] -> template end)
  end

  defp contact_requirement_template_stream_mutations(vue) do
    Enum.reject(vue.streams_diff, fn
      ["test", "", _value] -> true
      _operation -> false
    end)
  end

  defp template_form_values(form) do
    Map.new(form["fields"], fn {field, contract} -> {field, contract["value"]} end)
  end

  defp assert_json_safe_contact_requirement_template_vue(vue) do
    contract = %{"props" => vue.props, "streams_diff" => vue.streams_diff}
    assert contract == Jason.decode!(Jason.encode!(contract))
  end

  defp fleet_planning_run_stream_upserts(vue, stream_name) do
    prefix = "/#{stream_name}/"

    vue.streams_diff
    |> Enum.filter(fn
      ["upsert", path, _row] -> String.starts_with?(path, prefix)
      _operation -> false
    end)
    |> Enum.map(fn ["upsert", _path, row] -> row end)
  end

  defp fleet_planning_run_replaced_streams(vue) do
    vue
    |> fleet_planning_run_stream_mutations()
    |> Enum.flat_map(fn
      ["replace", "/" <> stream_name, []] -> [stream_name]
      _operation -> []
    end)
    |> Enum.sort()
  end

  defp fleet_planning_run_stream_mutations(vue) do
    Enum.reject(vue.streams_diff, fn
      ["test", "", _value] -> true
      _operation -> false
    end)
  end

  defp assert_json_safe_fleet_planning_run_vue(vue) do
    contract = %{"props" => vue.props, "streams_diff" => vue.streams_diff}
    assert contract == Jason.decode!(Jason.encode!(contract))
  end

  defp fleet_policy_vue(view) do
    LiveVue.Test.get_vue(view, id: "ops-fleet-planning-policy-component")
  end

  defp policy_form_field_contract(form) do
    Map.new(form["fields"], fn {field, contract} ->
      {field,
       {
         contract["id"],
         contract["name"],
         contract["type"],
         contract["label"],
         contract["required"],
         contract["min"],
         contract["options"],
         contract["value"],
         contract["errors"]
       }}
    end)
  end

  defp initial_policy_form_field_contract do
    %{
      "automatic_submission" =>
        {"policy-automatic-submission", "policy[automatic_submission]", "checkbox",
         "Allow exact candidate Plans to be submitted automatically", nil, nil, nil, false, []},
      "automation_mode" =>
        {"policy-automation-mode", "policy[automation_mode]", "select", "Mode", false, nil,
         [
           %{"label" => "Advisory", "value" => "advisory"},
           %{"label" => "Approval required", "value" => "approval_required"},
           %{"label" => "Bounded automatic", "value" => "bounded_automatic"}
         ], "advisory", []},
      "critical_contact_reserve" =>
        {"policy-critical-reserve", "policy[critical_contact_reserve]", "number",
         "Critical reserve", true, 0, [], "0", []},
      "currency" =>
        {"policy-currency", "policy[currency]", "text", "Currency", false, nil, [], "", []},
      "distinct_provider_required" =>
        {"policy-distinct-provider", "policy[distinct_provider_required]", "checkbox",
         "Distinct providers", nil, nil, nil, false, []},
      "distinct_service_pool_required" =>
        {"policy-distinct-pool", "policy[distinct_service_pool_required]", "checkbox",
         "Distinct service pools", nil, nil, nil, false, []},
      "distinct_station_required" =>
        {"policy-distinct-station", "policy[distinct_station_required]", "checkbox",
         "Distinct stations", nil, nil, nil, false, []},
      "execution_concurrency" =>
        {"policy-execution-concurrency", "policy[execution_concurrency]", "number",
         "Execution workers", true, 1, [], "4", []},
      "max_contacts" =>
        {"policy-max-contacts", "policy[max_contacts]", "number", "Contact ceiling", true, 1, [],
         "500", []},
      "max_estimated_cost_micros" =>
        {"policy-max-cost", "policy[max_estimated_cost_micros]", "number",
         "Cost micros (optional)", false, 0, [], "", []},
      "max_horizon_hours" =>
        {"policy-max-horizon-hours", "policy[max_horizon_hours]", "number", "Maximum hours", true,
         1, [], "24", []},
      "max_repair_attempts" =>
        {"policy-repair-attempts", "policy[max_repair_attempts]", "number", "Repair attempts",
         true, 0, [], "3", []},
      "provider_search_concurrency" =>
        {"policy-provider-concurrency", "policy[provider_search_concurrency]", "number",
         "Provider workers", true, 1, [], "4", []},
      "repair_horizon_hours" =>
        {"policy-repair-horizon-hours", "policy[repair_horizon_hours]", "number", "Repair hours",
         true, 1, [], "24", []},
      "requirement_concurrency" =>
        {"policy-requirement-concurrency", "policy[requirement_concurrency]", "number",
         "Requirement workers", true, 1, [], "8", []},
      "reuse_freshness_seconds" =>
        {"policy-reuse-seconds", "policy[reuse_freshness_seconds]", "number", "Reuse seconds",
         true, 0, [], "300", []}
    }
  end

  defp fleet_policy_grant_upserts(vue) do
    vue.streams_diff
    |> Enum.filter(fn
      ["upsert", "/automation_grants/" <> _index, _grant] -> true
      _operation -> false
    end)
    |> Enum.map(fn ["upsert", _path, grant] -> grant end)
  end

  defp fleet_policy_stream_mutations(vue) do
    Enum.reject(vue.streams_diff, fn
      ["test", "", _value] -> true
      _operation -> false
    end)
  end

  defp assert_json_safe_fleet_policy_vue(vue) do
    contract = %{"props" => vue.props, "streams_diff" => vue.streams_diff}
    assert contract == Jason.decode!(Jason.encode!(contract))
  end

  defp fleet_planning_vue(view) do
    LiveVue.Test.get_vue(view, id: "ops-fleet-planning-component")
  end

  defp fleet_run_upserts(vue) do
    vue.streams_diff
    |> Enum.filter(fn
      ["upsert", "/fleet_runs/" <> _index, _run] -> true
      _operation -> false
    end)
    |> Enum.map(fn ["upsert", _path, run] -> run end)
  end

  defp fleet_run_stream_mutations(vue) do
    Enum.reject(vue.streams_diff, fn
      ["test", "", _value] -> true
      _operation -> false
    end)
  end

  defp assert_json_safe_fleet_planning_vue(vue) do
    contract = %{"props" => vue.props, "streams_diff" => vue.streams_diff}
    assert contract == Jason.decode!(Jason.encode!(contract))
  end

  defp workspace_props(mission, control_metrics, stopped_policy, ledger) do
    %{
      "page" => %{
        "id" => "ops-fleet-planning-page",
        "header" => %{
          "eyebrow" => "Mission operations / fleet horizon",
          "title" => "Fleet Planning",
          "copy" =>
            "Turn exact mission needs into one explainable provider commitment manifest. Healthy capacity stays quiet; gaps, contested resources, and stale evidence rise here."
        }
      },
      "actions" => %{
        "refresh" => %{
          "id" => "refresh-fleet-planning",
          "icon" => "hero-arrow-path",
          "label" => "Refresh"
        },
        "policy" => %{
          "id" => "fleet-planning-policy-link",
          "href" => "/missions/#{mission.mission_id}/ops/planning/policy",
          "icon" => "hero-adjustments-horizontal",
          "label" => "Policy"
        },
        "new_run" => %{
          "id" => "new-fleet-planning-run-link",
          "href" => "/missions/#{mission.mission_id}/ops/planning/new",
          "icon" => "hero-play",
          "label" => "Plan horizon"
        }
      },
      "control_metrics" => control_metrics,
      "stopped_policy" => stopped_policy,
      "ledger" => ledger,
      "journey" => %{
        "id" => "fleet-planning-journey",
        "eyebrow" => "Operating loop",
        "steps" => [
          %{
            "id" => "fleet-planning-journey-01",
            "number" => "01",
            "label" => "Demand",
            "detail" => "Requirements and recurring templates"
          },
          %{
            "id" => "fleet-planning-journey-02",
            "number" => "02",
            "label" => "Search",
            "detail" => "Provider-owned opportunities"
          },
          %{
            "id" => "fleet-planning-journey-03",
            "number" => "03",
            "label" => "Allocate",
            "detail" => "Hard constraints before score"
          },
          %{
            "id" => "fleet-planning-journey-04",
            "number" => "04",
            "label" => "Commit",
            "detail" => "Exact Plan approval and execution"
          },
          %{
            "id" => "fleet-planning-journey-05",
            "number" => "05",
            "label" => "Repair",
            "detail" => "Preserve uncertain and successful work"
          }
        ]
      },
      "recurring_demand" => %{
        "id" => "fleet-planning-recurring-demand-panel",
        "eyebrow" => "Recurring demand",
        "copy" =>
          "Templates generate ordinary Requirements. They do not bypass the planning or approval journey.",
        "action" => %{
          "id" => "requirement-templates-link",
          "href" => "/missions/#{mission.mission_id}/ops/requirement-templates",
          "label" => "Manage templates",
          "icon" => "hero-arrow-right"
        }
      }
    }
  end

  defp stopped_control_metrics do
    [
      control_metric_props(
        "fleet-planning-active-policy",
        "Active policy",
        "STOPPED",
        "no approved boundary",
        "warning"
      ),
      control_metric_props(
        "fleet-planning-recurring-demand",
        "Recurring demand",
        "0",
        "active templates",
        "quiet"
      ),
      control_metric_props(
        "fleet-planning-automation",
        "Automation",
        "0",
        "active exact grants",
        "muted"
      ),
      control_metric_props(
        "fleet-planning-exceptions",
        "Exceptions",
        "0",
        "partial or failed runs",
        "quiet"
      )
    ]
  end

  defp active_control_metrics(exception_count) do
    [
      control_metric_props(
        "fleet-planning-active-policy",
        "Active policy",
        "v1",
        "24h maximum horizon",
        "quiet"
      ),
      control_metric_props(
        "fleet-planning-recurring-demand",
        "Recurring demand",
        "0",
        "active templates",
        "quiet"
      ),
      control_metric_props(
        "fleet-planning-automation",
        "Automation",
        "0",
        "active exact grants",
        "muted"
      ),
      control_metric_props(
        "fleet-planning-exceptions",
        "Exceptions",
        exception_count,
        "partial or failed runs",
        if(exception_count == "0", do: "quiet", else: "warning")
      )
    ]
  end

  defp control_metric_props(id, label, value, detail, tone) do
    %{"id" => id, "label" => label, "value" => value, "detail" => detail, "tone" => tone}
  end

  defp stopped_policy_props(mission) do
    %{
      "id" => "fleet-planning-policy-required",
      "eyebrow" => "Planning is intentionally stopped",
      "title" => "Approve a fleet policy before searching providers.",
      "copy" =>
        "The policy fixes horizon, concurrency, resource, budget, repair, and automation boundaries.",
      "action" => %{
        "id" => "configure-fleet-planning-policy",
        "href" => "/missions/#{mission.mission_id}/ops/planning/policy",
        "label" => "Configure policy"
      }
    }
  end

  defp ledger_props(count, empty) do
    %{
      "eyebrow" => "Run ledger",
      "copy" => "Immutable inputs, durable checkpoints, and ordinary candidate Plans.",
      "count" => count,
      "count_label" => "#{count} runs",
      "runs_id" => "fleet-planning-runs",
      "stream_empty_id" => "fleet-planning-runs-stream-empty",
      "empty" => empty
    }
  end

  defp ledger_empty_props do
    %{
      "id" => "fleet-planning-runs-empty",
      "icon" => "hero-chart-bar-square",
      "title" => "No fleet horizon has been planned",
      "copy" =>
        "Start with a bounded UTC horizon. Cadence will materialize recurring needs, search ready provider routes, and retain every decision."
    }
  end

  defp queued_run_props(run, mission) do
    fleet_run_props(
      run,
      mission,
      %{
        "state" => "queued",
        "label" => "queued",
        "tone" => "primary",
        "class" =>
          "border border-primary/40 bg-primary/10 px-1.5 py-0.5 font-mono text-[0.6rem] uppercase text-primary"
      },
      %{"kind" => "manual", "label" => "manual"},
      %{"state" => "queued", "width_class" => "h-full w-[8%] bg-primary/55"},
      %{"label" => "Coverage", "value" => "0/1", "shortfall" => false, "tone" => "quiet"}
    )
  end

  defp partial_run_props(run, mission) do
    fleet_run_props(
      run,
      mission,
      %{
        "state" => "partial",
        "label" => "partial",
        "tone" => "warning",
        "class" =>
          "border border-warning/40 bg-warning/10 px-1.5 py-0.5 font-mono text-[0.6rem] uppercase text-warning"
      },
      %{"kind" => "scheduled", "label" => "scheduled"},
      %{"state" => "finished", "width_class" => "h-full w-full bg-primary/80"},
      %{"label" => "Coverage", "value" => "1/1", "shortfall" => true, "tone" => "warning"}
    )
  end

  defp failed_run_props(run, mission) do
    fleet_run_props(
      run,
      mission,
      %{
        "state" => "failed",
        "label" => "failed",
        "tone" => "error",
        "class" =>
          "border border-error/40 bg-error/10 px-1.5 py-0.5 font-mono text-[0.6rem] uppercase text-error"
      },
      %{"kind" => "manual", "label" => "manual"},
      %{"state" => "finished", "width_class" => "h-full w-full bg-primary/80"},
      %{
        "label" => "Coverage",
        "value" => "Stopped",
        "shortfall" => true,
        "tone" => "warning"
      }
    )
  end

  defp fleet_run_props(run, mission, lifecycle, trigger, phase, coverage) do
    horizon_start = fleet_time(run.horizon_start)
    horizon_end = fleet_time(run.horizon_end)

    %{
      "id" => run.fleet_planning_run_id,
      "__dom_id" => "fleet-planning-run-#{run.fleet_planning_run_id}",
      "fleet_planning_run_id" => run.fleet_planning_run_id,
      "href" => "/missions/#{mission.mission_id}/ops/planning/runs/#{run.fleet_planning_run_id}",
      "lifecycle" => lifecycle,
      "trigger" => trigger,
      "horizon" => %{
        "label" => "UTC horizon",
        "start" => horizon_start,
        "end" => horizon_end,
        "value" => "#{horizon_start} → #{horizon_end}"
      },
      "phase" => phase,
      "coverage" => coverage,
      "open_icon" => "hero-chevron-right"
    }
  end

  defp finish_partial_run!(scope, mission, run, requirement) do
    [
      {:queued, :materializing, %{}},
      {:materializing, :searching, %{}},
      {:searching, :optimizing, %{}},
      {:optimizing, :materializing_plan, %{}},
      {:materializing_plan, :finished,
       %{
         outcome: :partial,
         result_summary_document: %{
           "coverage" => %{
             requirement.contact_requirement_id => %{"state" => "satisfied"}
           }
         }
       }}
    ]
    |> Enum.reduce(run, fn {expected, next, attrs}, current ->
      assert {:ok, advanced} =
               FleetPlanningRuns.advance_phase(
                 scope,
                 mission.mission_id,
                 current.fleet_planning_run_id,
                 expected,
                 next,
                 attrs
               )

      advanced
    end)
  end

  defp fleet_time(datetime), do: Calendar.strftime(datetime, "%d %b %H:%MZ")

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
