defmodule Cadence.Reads.ApplicationSurfaces.ContactPlanShowTest do
  use Cadence.DataCase, async: false
  alias Cadence.Accounts.{OrganizationMembership, User}
  alias Cadence.Applications.{ActionRequest, HostContext, SurfaceQueryRequest}
  alias Cadence.Applications.OpsConsole.Actions.ContactPlanning, as: Actions
  alias Cadence.Auth.Scope
  alias Cadence.ContactPlanning.{ContactPlans, ContactRequirements, Planner}
  alias Cadence.Management.Contacts, as: ManagementContacts
  alias Cadence.Reads.ApplicationSurfaces.OpsConsole
  alias Cadence.Reads.ApplicationSurfaces.Planning.PlanDetailProjection
  alias Cadence.Spacecraft
  @org "org-plan-show"
  @mission "mission-plan-show"
  @craft "craft-plan-show"
  @now ~U[2027-01-01 00:00:00Z]
  @checker Path.expand(
             "../../../../../../frontend/modules/planning-and-contacts/src/features/contact-plans/decision-producer-check.mjs",
             __DIR__
           )
  @renderer Path.expand(
              "../../../../../../frontend/modules/planning-and-contacts/src/test-support/producer-render-check.mjs",
              __DIR__
            )
  setup do
    %{organization: organization} = persist_mission_scope(@org, @mission)

    user =
      User.new(%{
        user_id: "requirement-reviewer",
        email: "reviewer@example.test",
        display_name: "Reviewer"
      })

    membership =
      OrganizationMembership.new(%{user_id: user.user_id, organization_id: @org, role: :member})

    scope =
      Scope.new(%{
        user: user,
        organization_id: @org,
        organization: organization,
        organization_membership: membership
      })

    assert {:ok, _} =
             Cadence.SpacecraftStore.persist_spacecraft(
               @org,
               Spacecraft.new(%{
                 spacecraft_id: @craft,
                 mission_id: @mission,
                 display_name: "Review spacecraft"
               })
             )

    assert {:ok, requirement, version} =
             ContactRequirements.create(scope, @mission, %{
               spacecraft_id: @craft,
               service_direction: :downlink,
               contact_intent: "payload_downlink",
               earliest_start: DateTime.add(@now, 3600),
               latest_end: DateTime.add(@now, 28_800),
               success_measure: :minimum_duration,
               minimum_duration_seconds: 60,
               priority: :high,
               rationale: "Reviewed requirement"
             })

    context = %{scope: scope, requirement: requirement, version: version}
    planning = planning(context)

    assert {:ok, plan, plan_version} =
             ContactPlans.create(scope, @mission, %{
               planning_run_ids: [planning.run.contact_planning_run_id],
               selected_snapshot_ids:
                 Enum.map(Enum.take(planning.snapshots, 26), & &1.contact_opportunity_snapshot_id),
               locked_snapshot_ids: [
                 Enum.at(planning.snapshots, 26).contact_opportunity_snapshot_id
               ],
               rationale: "Reviewed plan"
             })

    admin_user =
      User.new(%{
        user_id: "plan-review-admin",
        email: "plan-review-admin@example.test",
        display_name: "Plan administrator"
      })

    admin =
      Scope.new(%{
        user: admin_user,
        organization_id: @org,
        organization: organization,
        organization_membership:
          OrganizationMembership.new(%{
            user_id: admin_user.user_id,
            organization_id: @org,
            role: :organization_admin
          })
      })

    Map.merge(context, %{planning: planning, plan: plan, plan_version: plan_version, admin: admin})
  end

  test "real plan evidence is paged and renders through the module entry", c do
    model = props(c)
    d = model["detail"]
    assert d["plan"]["content_sha256"] == c.plan_version.content_sha256
    assert d["plan"]["selected_count"] == 26
    assert d["plan"]["locked_count"] == 1
    assert d["plan"]["rejected_count"] == 1
    assert d["opportunities"]["more"]
    assert length(d["opportunities"]["entries"]) == 25
    assert d["permissions"] == %{"operate" => true, "decide" => false}
    refute Jason.encode!(model) =~ "provider_evidence_document"
    render(model, ["ops-contact-plan-show-page", "plan-reviewed-hash", "plan-admin-required"])
    last = props(c, %{"version" => "1", "opportunities_page" => "2"})

    assert Enum.map(last["detail"]["opportunities"]["entries"], & &1["disposition"]) == [
             "selected",
             "locked",
             "rejected"
           ]

    render(last, ["opportunities_page-previous"])
  end

  test "review labels distinguish constraint findings from provider search failures", c do
    cases = [
      {%{"code" => "selected_contacts_overlap"}, "Selected contacts overlap."},
      {%{"code" => "minimum_separation_not_met"},
       "Selected contacts do not meet the minimum separation."},
      {%{"code" => "provider_search_unavailable"},
       "Provider search was unavailable for this requirement."},
      {%{"code" => "future_constraint"}, "Requirement review reported an issue."},
      {%{"code" => "selected_contacts_overlap", "message" => "Exact domain evidence"},
       "Exact domain evidence"}
    ]

    for {finding, expected} <- cases do
      [requirement] = c.plan_version.coverage_document["requirements"]
      requirement = %{requirement | "hard_failures" => [finding], "search_failures" => []}
      version = %{c.plan_version | coverage_document: %{"requirements" => [requirement]}}
      empty = %{entries: [], more?: false}
      evidence = %{versions: empty, approvals: empty, opportunities: empty, execution: empty}

      query =
        Map.new(
          ~w(versions_page approvals_page opportunities_page execution_page requirements_page issues_page),
          &{&1, 1}
        )

      detail =
        PlanDetailProjection.project(
          c.scope,
          c.plan,
          version,
          nil,
          query,
          evidence
        )

      assert [issue] = detail.issues.entries
      assert issue.message == expected
      assert issue.code == finding["code"]
      assert issue.requirement_id == c.requirement.contact_requirement_id
    end
  end

  test "native Vue submission and approval persist the exact producer review", c do
    submission = native_payload(props(c), "submit-plan")
    assert submission["plan_evidence"]["content_sha256"] == c.plan_version.content_sha256
    assert {:ok, _} = execute(c.scope, "submit-plan", submission)
    admin = %{c | scope: c.admin}
    pending = props(admin)
    assert pending["detail"]["plan"]["lifecycle_state"] == "pending_approval"
    approval = native_payload(pending, "approve-plan")
    assert {:ok, _} = execute(c.admin, "approve-plan", approval)
    approved = props(admin)
    assert approved["detail"]["plan"]["reviewed_decision"]["decision"] == "approved"
    assert approved["detail"]["plan"]["approved_version"] == 1
    assert approved["detail"]["execution"]["more"]
    execute_input = native_payload(approved, "execute-plan")
    assert execute_input["plan_evidence"] == approval["plan_evidence"]

    # Do not contact a provider: execution authority and provider effects have their own domain tests.
  end

  test "historical reviews cannot substitute current content or reuse stale decision evidence",
       c do
    old = props(c)
    submission = native_payload(old, "submit-plan")

    assert {:ok, _, newer} =
             ContactPlans.version(c.scope, @mission, c.plan.contact_plan_id, 1, %{
               rationale: "New proposal"
             })

    assert {:error, :stale_contact_plan_evidence} = execute(c.scope, "submit-plan", submission)
    historical = props(c, %{"version" => "1"})
    assert historical["detail"]["plan"]["version"] == 1
    assert historical["detail"]["plan"]["current_version"] == 2
    assert historical["detail"]["plan"]["content_sha256"] == c.plan_version.content_sha256
    assert props(c)["detail"]["plan"]["content_sha256"] == newer.content_sha256
    render(historical, ["plan-review-historical", "review-current-plan"])
    assert {:ok, plan, _} = ManagementContacts.fetch_plan(@org, @mission, c.plan.contact_plan_id)
    assert plan.lifecycle_state == :draft
  end

  test "query bounds, resource identity and scope are independently admitted", c do
    for query <- [
          %{"version" => "0"},
          %{"version" => "01"},
          %{"version" => 1},
          %{"version" => "2"},
          %{"version" => "2147483648"},
          %{"opportunities_page" => "1000001"},
          %{"execution_page" => "-1"},
          %{"unknown" => "value"},
          %{"contact_plan_id" => "missing"},
          %{"mission_id" => "other"}
        ] do
      assert {:error, :unsupported_application_surface_query} = load(c, query)
    end

    for scope <- [
          %{c.scope | organization_id: "foreign"},
          %{c.scope | mission_id: "foreign"},
          %{c.scope | organization_membership: nil}
        ] do
      assert {:error, :unsupported_application_surface_query} = load(%{c | scope: scope}, %{})
    end
  end

  defp load(c, query) do
    OpsConsole.load(c.scope, HostContext.mission(@mission), %SurfaceQueryRequest{
      application_key: "ops_console",
      application_version: 1,
      surface_id: "contact_plan_show",
      surface_version: 1,
      query_id: "cadence.ops.contact_plan_show",
      query_version: 1,
      params: Map.merge(%{"contact_plan_id" => c.plan.contact_plan_id}, query)
    })
  end

  defp props(c, query \\ %{}) do
    assert {:ok,
            %{
              "data" => %{
                "presentation" => %{"component" => "OpsContactPlanShow", "props" => props}
              }
            }} = load(c, query)

    props
  end

  defp execute(scope, action, params),
    do:
      Actions.execute(scope, HostContext.mission(@mission), "contact_plan_show", %ActionRequest{
        application_key: "ops_console",
        application_version: 1,
        action_id: action,
        params: params
      })

  defp native_payload(props, action) do
    {output, status} =
      System.cmd("node", [@checker, Jason.encode!(props), action], stderr_to_stdout: true)

    assert status == 0, output
    assert [_, json] = Regex.run(~r/PLAN_PAYLOAD=(\{[^\n]+\})/, output)
    Jason.decode!(json)
  end

  defp render(props, ids) do
    {output, status} =
      System.cmd(
        "node",
        [
          @renderer,
          Jason.encode!([
            %{
              component: "OpsContactPlanShow",
              props: props,
              expected: %{presentIds: ids, absentIds: ["plan-detail-unavailable"]}
            }
          ])
        ],
        stderr_to_stdout: true
      )

    assert status == 0, output
  end

  defp planning(context, offset \\ 0) do
    assert {:ok, result} =
             Planner.run(
               context.scope,
               @mission,
               context.requirement.contact_requirement_id,
               context.version.version,
               now: DateTime.add(@now, offset),
               list_routes: fn _, _, _ -> {:ok, %{routes: [route()], findings: []}} end,
               search_opportunities: fn _, _, _, _, _ ->
                 {:ok, %{opportunities: Enum.map(1..28, &opportunity/1)}}
               end
             )

    assert length(result.snapshots) == 28
    assert Enum.all?(result.snapshots, & &1.eligible)
    result
  end

  defp route,
    do: %{
      route_key: "review-route",
      spacecraft_id: @craft,
      provider_spacecraft_ref: "SC-review",
      source_endpoint_id: "source-review",
      routing_rule_id: "routing-review",
      link_assignment_id: "link-review",
      path_template_id: "path-review",
      path_template_version: 1,
      transport_id: "transport-review",
      transport_version: 1,
      provider_id: "provider-review",
      provider_version: 1,
      provider_account_id: "account-review",
      provider_account_version: 1,
      provider_account_grant_id: "grant-review",
      provider_account_grant_version: 1,
      provider_profile_id: "runtime-review",
      provider_profile_version: 1,
      service_profile_ref: %{"id" => "service-review", "version" => 1},
      delivery_profile_ref: %{"id" => "delivery-review", "version" => 1},
      delivery_policy_document: %{"mode" => "approval_required", "version" => 1},
      provider_display_name: "Review Provider",
      service_display_name: "Downlink",
      delivery_display_name: "Primary",
      route_display_name: "Review route"
    }

  defp opportunity(index),
    do: %{
      "id" => "opportunity-review-#{index}",
      "spacecraft_ref" => "SC-review",
      "ground_station_ref" => "station-review",
      "antenna_or_service_pool_ref" => "pool-review",
      "service_profile_ref" => "service-review",
      "starts_at" => iso(3600 + index * 120),
      "ends_at" => iso(3660 + index * 120),
      "expires_at" => iso(18_000),
      "availability" => "available",
      "estimated_capacity" => %{"bytes" => 2_000_000_000},
      "synthetic" => true,
      "extensions" => %{
        "orbit_readiness" => %{"status" => "current", "valid_until" => iso(28_800)}
      }
    }

  defp iso(seconds), do: @now |> DateTime.add(seconds) |> DateTime.to_iso8601()
end
