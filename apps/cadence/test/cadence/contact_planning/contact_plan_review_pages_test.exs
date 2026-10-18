defmodule Cadence.ContactPlanning.ContactPlanReviewPagesTest do
  use Cadence.DataCase, async: false

  alias Cadence.Accounts.{OrganizationMembership, User}
  alias Cadence.Auth.Scope

  alias Cadence.ContactPlanning.{
    ContactPlanApprovals,
    ContactPlans,
    ContactPlanVersion,
    ContactRequirements,
    Planner
  }

  alias Cadence.Control.Contacts, as: ControlContacts
  alias Cadence.Management.Contacts, as: ManagementContacts
  alias Cadence.Management.Contacts.Store.ContactPlanVersionRow
  alias Cadence.Repo
  alias Cadence.Spacecraft

  @org "org-plan-review-pages"
  @mission "mission-plan-review-pages"
  @craft "craft-plan-review-pages"
  @now ~U[2027-01-01 00:00:00Z]

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

  test "manifest pages preserve ordering and distinguish bookings, commitments and rejections",
       c do
    assert {:ok, %{entries: first, more?: true}} = opportunities(c, 1, 1)
    assert length(first) == 25
    assert Enum.all?(first, &(&1.disposition == :selected))
    assert {:ok, %{entries: last, more?: false}} = opportunities(c, 1, 2)
    assert Enum.map(last, & &1.disposition) == [:selected, :locked, :rejected]

    expected =
      c.plan_version.selected_snapshot_ids ++
        c.plan_version.locked_snapshot_ids ++ c.plan_version.rejected_snapshot_ids

    assert Enum.map(first ++ last, & &1.snapshot.contact_opportunity_snapshot_id) == expected
    assert {:ok, %{entries: [], more?: false}} = opportunities(c, 1, 3)

    assert {:ok, _, newer} =
             ContactPlans.version(c.scope, @mission, c.plan.contact_plan_id, 1, %{
               selected_snapshot_ids: c.plan_version.rejected_snapshot_ids,
               locked_snapshot_ids: [],
               rationale: "Review another selection"
             })

    assert {:ok, %{entries: ^first, more?: true}} = opportunities(c, 1, 1)
    assert {:ok, %{entries: [new_first | _]}} = opportunities(c, newer.version, 1)
    assert new_first.disposition == :selected

    assert new_first.snapshot.contact_opportunity_snapshot_id ==
             hd(c.plan_version.rejected_snapshot_ids)
  end

  test "version and decision histories remain anchored after newer reviews", c do
    Enum.reduce(1..26, c.plan_version, fn number, version ->
      assert {:ok, _} =
               ContactPlans.submit(c.scope, @mission, c.plan.contact_plan_id, number, "Review",
                 now: @now
               )

      assert {:ok, _, _, _} =
               ContactPlanApprovals.reject(
                 c.admin,
                 @mission,
                 c.plan.contact_plan_id,
                 number,
                 version.content_sha256,
                 "Revise",
                 now: @now
               )

      assert {:ok, _, next} =
               ContactPlans.version(
                 c.scope,
                 @mission,
                 c.plan.contact_plan_id,
                 number,
                 %{rationale: "Revision #{number + 1}"},
                 now: @now
               )

      next
    end)

    for {read, field} <- [
          {&ManagementContacts.list_plan_versions_page/5, :version},
          {&ManagementContacts.list_plan_approvals_page/5, :contact_plan_version}
        ] do
      assert {:ok, %{entries: first, more?: true}} =
               read.(@org, @mission, c.plan.contact_plan_id, 26, 1)

      assert Enum.map(first, &Map.fetch!(&1, field)) == Enum.to_list(26..2//-1)

      assert {:ok, %{entries: [last], more?: false}} =
               read.(@org, @mission, c.plan.contact_plan_id, 26, 2)

      assert Map.fetch!(last, field) == 1

      assert {:ok, %{entries: [], more?: false}} =
               read.(@org, @mission, c.plan.contact_plan_id, 26, 3)
    end

    assert {:ok, %{entries: [latest | _]}} =
             ManagementContacts.list_plan_versions_page(
               @org,
               @mission,
               c.plan.contact_plan_id,
               27,
               1
             )

    assert latest.version == 27

    assert {:ok, reviewed} =
             ManagementContacts.fetch_plan_version(@org, @mission, c.plan.contact_plan_id, 1)

    assert reviewed == c.plan_version
  end

  test "execution pages contain only selected opportunities from the exact accepted version", c do
    assert {:ok, _, version} =
             ContactPlans.version(c.scope, @mission, c.plan.contact_plan_id, 1, %{
               rationale: "New draft"
             })

    assert {:ok, _} =
             ContactPlans.submit(c.scope, @mission, c.plan.contact_plan_id, 2, "Review",
               now: @now
             )

    assert {:ok, _} =
             ControlContacts.approve_and_accept_plan(
               c.admin,
               @mission,
               c.plan.contact_plan_id,
               2,
               version.content_sha256,
               "Approved",
               now: @now
             )

    assert {:ok, %{entries: [], more?: false}} = execution(c, 1, 1)
    assert {:ok, %{entries: first, more?: true}} = execution(c, 2, 1)
    assert length(first) == 25
    assert {:ok, %{entries: [last], more?: false}} = execution(c, 2, 2)
    items = first ++ [last]
    assert Enum.all?(items, &(&1.contact_plan_version == 2 and &1.lifecycle_state == :pending))

    assert Enum.sort(Enum.map(items, & &1.contact_opportunity_snapshot_id)) ==
             Enum.sort(version.selected_snapshot_ids)

    assert {:ok, %{entries: [], more?: false}} = execution(c, 2, 3)
    assert {:ok, %{entries: ^first, more?: true}} = execution(c, 2, 1)
  end

  test "read boundaries isolate organization, mission and plan", c do
    assert {:ok, _} =
             ContactPlans.submit(c.scope, @mission, c.plan.contact_plan_id, 1, "Review",
               now: @now
             )

    assert {:ok, _} =
             ControlContacts.approve_and_accept_plan(
               c.admin,
               @mission,
               c.plan.contact_plan_id,
               1,
               c.plan_version.content_sha256,
               "Approved",
               now: @now
             )

    for args <- [
          ["foreign-org", @mission, c.plan.contact_plan_id, 1, 1],
          [@org, "foreign-mission", c.plan.contact_plan_id, 1, 1],
          [@org, @mission, "other-plan", 1, 1]
        ] do
      for read <- [
            &ManagementContacts.list_plan_versions_page/5,
            &ManagementContacts.list_plan_approvals_page/5,
            &ControlContacts.list_plan_execution_page/5
          ] do
        assert {:ok, %{entries: [], more?: false}} = apply(read, args)
      end

      assert {:error, :contact_plan_version_not_found} =
               apply(&ManagementContacts.list_plan_opportunities_page/5, args)
    end
  end

  test "missing manifest evidence is reported only on its requested page", c do
    broken = %{
      c.plan_version
      | contact_plan_version_id: "broken-version",
        version: 2,
        rejected_snapshot_ids: ["missing-snapshot"],
        content_sha256: nil
    }

    broken = ContactPlanVersion.new(Map.from_struct(broken))
    assert {:ok, _} = Repo.insert(ContactPlanVersionRow.changeset(broken))
    assert {:ok, %{entries: first, more?: true}} = opportunities(c, 2, 1)
    assert length(first) == 25
    assert {:error, :contact_plan_opportunity_evidence_missing} = opportunities(c, 2, 2)
    assert {:error, :contact_plan_version_not_found} = opportunities(c, 3, 1)
  end

  test "a snapshot outside the manifest's declared runs cannot supply evidence", c do
    broken = %{
      c.plan_version
      | contact_plan_version_id: "wrong-run-version",
        version: 2,
        planning_run_refs_document: %{"runs" => ["different-run"]},
        content_sha256: nil
    }

    broken = ContactPlanVersion.new(Map.from_struct(broken))
    assert {:ok, _} = Repo.insert(ContactPlanVersionRow.changeset(broken))
    assert {:error, :contact_plan_opportunity_evidence_missing} = opportunities(c, 2, 1)
  end

  test "the maximum stored version remains a valid read bound", c do
    assert {:ok, %{entries: [version], more?: false}} =
             ManagementContacts.list_plan_versions_page(
               @org,
               @mission,
               c.plan.contact_plan_id,
               2_147_483_647,
               1
             )

    assert version == c.plan_version

    assert {:ok, %{entries: [], more?: false}} =
             ManagementContacts.list_plan_approvals_page(
               @org,
               @mission,
               c.plan.contact_plan_id,
               2_147_483_647,
               1
             )

    assert {:ok, %{entries: [], more?: false}} = execution(c, 2_147_483_647, 1)
    assert {:error, :contact_plan_version_not_found} = opportunities(c, 2_147_483_647, 1)
  end

  test "invalid bounds fail before reading", c do
    reads = [
      &ManagementContacts.list_plan_versions_page/5,
      &ManagementContacts.list_plan_approvals_page/5,
      &ManagementContacts.list_plan_opportunities_page/5,
      &ControlContacts.list_plan_execution_page/5
    ]

    for read <- reads do
      for page <- [nil, 0, -1, 1.0, "1", 1_000_001, %{}] do
        assert {:error, :invalid_contact_plan_review_page} =
                 read.(@org, @mission, c.plan.contact_plan_id, 1, page)
      end

      for version <- [
            nil,
            0,
            -1,
            1.0,
            "1",
            2_147_483_648,
            9_007_199_254_740_991,
            9_007_199_254_740_992
          ] do
        assert {:error, :invalid_contact_plan_review_page} =
                 read.(@org, @mission, c.plan.contact_plan_id, version, 1)
      end
    end
  end

  defp opportunities(c, version, page),
    do:
      ManagementContacts.list_plan_opportunities_page(
        @org,
        @mission,
        c.plan.contact_plan_id,
        version,
        page
      )

  defp execution(c, version, page),
    do:
      ControlContacts.list_plan_execution_page(
        @org,
        @mission,
        c.plan.contact_plan_id,
        version,
        page
      )

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
