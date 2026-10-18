defmodule Cadence.Reads.ApplicationSurfaces.ContactRequirementShowTest do
  use Cadence.DataCase, async: false

  alias Cadence.Accounts.{OrganizationMembership, User}
  alias Cadence.Applications.{ActionRequest, HostContext, SurfaceQueryRequest}
  alias Cadence.Applications.OpsConsole.Actions.ContactPlanning, as: Actions
  alias Cadence.Auth.Scope
  alias Cadence.ContactPlanning.{ContactPlans, ContactRequirements, Planner}
  alias Cadence.Reads.ApplicationSurfaces.OpsConsole
  alias Cadence.Spacecraft

  @org "org-requirement-show"
  @mission "mission-requirement-show"
  @craft "craft-requirement-show"
  @now ~U[2027-01-01 00:00:00Z]
  @checker Path.expand(
             "../../../../../../frontend/modules/planning-and-contacts/src/test-support/producer-render-check.mjs",
             __DIR__
           )
  @decision_checker Path.expand(
                      "../../../../../../frontend/modules/planning-and-contacts/src/features/contact-requirements/decision-producer-check.mjs",
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
    Map.put(context, :planning, planning(context))
  end

  test "a valid requirement passes subject admission and renders through the domain Vue entry",
       context do
    props = props(context)
    detail = props["detail"]
    assert detail["contract_version"] == 1
    assert detail["context"]["actor_id"] == context.scope.user.user_id
    assert detail["requirement"]["content_sha256"] == context.version.content_sha256
    assert detail["requirement"]["outcome"] == "At least 60 seconds"
    assert detail["selected_run"] == nil
    assert detail["opportunities"]["entries"] == []
    render(props, ["ops-contact-requirement-show-page", "requirement-opportunities-empty"])
  end

  test "an explicitly reviewed run projects immutable evidence without raw provider documents",
       context do
    run_id = context.planning.run.contact_planning_run_id
    props = props(context, %{"planning_run_id" => run_id, "version" => "1"})
    detail = props["detail"]
    assert detail["selected_run"]["id"] == run_id
    assert [row] = detail["opportunities"]["entries"]
    assert [snapshot] = context.planning.snapshots
    assert row["id"] == snapshot.contact_opportunity_snapshot_id
    assert row["content_sha256"] == snapshot.content_sha256
    assert row["eligible"]
    assert row["synthetic"]
    refute Map.has_key?(row, "provider_evidence_document")
    refute Map.has_key?(row, "normalized_opportunity_document")
    assert inspect(snapshot.normalized_opportunity_document) =~ "private-evidence-sentinel"
    refute Jason.encode!(props) =~ "private-evidence-sentinel"

    render(props, [
      "ops-contact-requirement-show-page",
      "requirement-selected-run",
      "select-" <> row["id"]
    ])
  end

  test "real producer props and native Vue selection persist the explicitly reviewed proposal",
       context do
    run_id = context.planning.run.contact_planning_run_id
    review = props(context, %{"planning_run_id" => run_id, "version" => "1"})

    {output, status} =
      System.cmd("node", [@decision_checker, Jason.encode!(review)], stderr_to_stdout: true)

    assert status == 0, output
    assert [_, json] = Regex.run(~r/REVIEW_PAYLOAD=(\{[^\n]+\})/, output)
    params = Jason.decode!(json)
    assert params["requirement_evidence"]["content_sha256"] == context.version.content_sha256
    assert params["planning_run_id"] == run_id

    # A newer search must not replace the run selected in the actual Vue control.
    newer = planning(context, 60)
    refute newer.run.contact_planning_run_id == run_id

    assert {:ok, %{"contactPlanId" => plan_id} = result} =
             Actions.execute(
               context.scope,
               HostContext.mission(@mission),
               "contact_requirement_show",
               %ActionRequest{
                 application_key: "ops_console",
                 application_version: 1,
                 action_id: "create-plan",
                 params: params
               }
             )

    assert {:ok, _, version} = ContactPlans.fetch(@org, @mission, plan_id)
    assert version.selected_snapshot_ids == params["selected_snapshot_ids"]
    assert version.planning_run_refs_document["runs"] == [run_id]
    assert result["requirementEvidence"] == params["requirement_evidence"]
    assert result["navigation"]["href"] == "/missions/#{@mission}/ops/plans/#{plan_id}"
  end

  test "historical review is explicit and cannot silently bind to the current version", context do
    assert {:ok, _, _} =
             ContactRequirements.version(
               context.scope,
               @mission,
               context.requirement.contact_requirement_id,
               1,
               %{minimum_duration_seconds: 61}
             )

    run_id = context.planning.run.contact_planning_run_id

    assert {:error, :unsupported_application_surface_query} =
             load(context, %{"planning_run_id" => run_id})

    historical = props(context, %{"planning_run_id" => run_id, "version" => "1"})
    assert historical["detail"]["requirement"]["current_version"] == 2
    assert historical["detail"]["requirement"]["version"] == 1
    assert historical["detail"]["selected_run"]["id"] == run_id
    render(historical, ["requirement-review-readonly", "review-current-requirement"])
    assert props(context)["detail"]["requirement"]["version"] == 2
  end

  test "another requirement's run is not admitted even inside the same mission", context do
    attrs = context.version |> Map.from_struct() |> Map.delete(:contact_requirement_id)
    assert {:ok, other, _} = ContactRequirements.create(context.scope, @mission, attrs)

    assert {:error, :unsupported_application_surface_query} =
             load(context, %{
               "contact_requirement_id" => other.contact_requirement_id,
               "planning_run_id" => context.planning.run.contact_planning_run_id,
               "version" => "1"
             })
  end

  test "query admission, mission scope and permissions reject invalid reviews", context do
    for params <- [
          %{"version" => "0"},
          %{"version" => "01"},
          %{"version" => "2"},
          %{"version" => 1},
          %{"runs_page" => "1000001"},
          %{"opportunities_page" => "2"},
          %{"unknown" => "x"},
          %{"planning_run_id" => "missing"},
          %{"contact_requirement_id" => "missing"},
          %{"mission_id" => "another-mission"}
        ] do
      assert {:error, :unsupported_application_surface_query} = load(context, params)
    end

    for scope <- [
          %{context.scope | organization_membership: nil},
          %{context.scope | organization_id: "foreign"},
          %{context.scope | mission_id: "foreign"}
        ] do
      assert {:error, :unsupported_application_surface_query} =
               load(%{context | scope: scope}, %{})
    end
  end

  test "run-history pagination preserves the explicitly selected older run", context do
    for index <- 1..25, do: planning(context, index)
    query = %{"planning_run_id" => context.planning.run.contact_planning_run_id, "version" => "1"}
    first = props(context, query)["detail"]
    assert first["runs"]["more"]
    assert length(first["runs"]["entries"]) == 25
    second = props(context, Map.put(query, "runs_page", "2"))["detail"]
    assert second["runs"]["page"] == 2
    refute second["runs"]["more"]
    assert length(second["runs"]["entries"]) == 1
    assert second["selected_run"] == first["selected_run"]
    assert second["opportunities"] == first["opportunities"]
  end

  test "version history pages are anchored at the explicitly reviewed version", context do
    for version <- 2..26 do
      assert {:ok, _, _} =
               ContactRequirements.version(
                 context.scope,
                 @mission,
                 context.requirement.contact_requirement_id,
                 version - 1,
                 %{minimum_duration_seconds: 60 + version}
               )
    end

    detail = props(context, %{"version" => "26", "versions_page" => "2"})["detail"]
    assert [%{"version" => 1}] = detail["versions"]["entries"]
    assert detail["query"]["versions_page"] == 2
    assert detail["requirement"]["version"] == 26
    refute detail["versions"]["more"]
  end

  defp load(context, params) do
    OpsConsole.load(context.scope, HostContext.mission(@mission), %SurfaceQueryRequest{
      application_key: "ops_console",
      application_version: 1,
      surface_id: "contact_requirement_show",
      surface_version: 1,
      query_id: "cadence.ops.contact_requirement_show",
      query_version: 1,
      params:
        Map.merge(
          %{"contact_requirement_id" => context.requirement.contact_requirement_id},
          params
        )
    })
  end

  defp props(context, params \\ %{}) do
    assert {:ok,
            %{
              "data" => %{
                "presentation" => %{"component" => "OpsContactRequirementShow", "props" => props}
              }
            }} = load(context, params)

    props
  end

  defp render(props, ids) do
    {output, status} =
      System.cmd(
        "node",
        [
          @checker,
          Jason.encode!([
            %{
              component: "OpsContactRequirementShow",
              props: props,
              expected: %{presentIds: ids, absentIds: ["requirement-detail-unavailable"]}
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
                 {:ok, %{opportunities: [opportunity()]}}
               end
             )

    assert [snapshot] = result.snapshots
    assert snapshot.eligible
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

  defp opportunity,
    do: %{
      "id" => "opportunity-review",
      "spacecraft_ref" => "SC-review",
      "ground_station_ref" => "station-review",
      "antenna_or_service_pool_ref" => "pool-review",
      "service_profile_ref" => "service-review",
      "starts_at" => iso(3600),
      "ends_at" => iso(4500),
      "expires_at" => iso(18_000),
      "availability" => "available",
      "estimated_capacity" => %{"bytes" => 2_000_000_000},
      "synthetic" => true,
      "extensions" => %{
        "private_note" => "private-evidence-sentinel",
        "orbit_readiness" => %{"status" => "current", "valid_until" => iso(28_800)}
      }
    }

  defp iso(seconds), do: @now |> DateTime.add(seconds) |> DateTime.to_iso8601()
end
