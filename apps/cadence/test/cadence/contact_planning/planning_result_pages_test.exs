defmodule Cadence.ContactPlanning.PlanningResultPagesTest do
  use Cadence.DataCase, async: false

  alias Cadence.Accounts.{OrganizationMembership, User}
  alias Cadence.Auth.Scope

  alias Cadence.ContactPlanning.{
    ContactOpportunitySnapshot,
    ContactPlanningRun,
    ContactPlanningSearch,
    ContactRequirements,
    Planner
  }

  alias Cadence.Management.Contacts.PlanningResults
  alias Cadence.Spacecraft

  @now ~U[2027-01-01 00:00:00Z]
  @hash String.duplicate("a", 64)

  setup do
    fixture("pages", "pages")
  end

  test "run pages have a bounded total order and do not replace an explicit run", context do
    runs = for index <- 26..1//-1, do: run(context, "run-#{padded(index)}")
    ids = runs |> Enum.map(& &1.contact_planning_run_id) |> Enum.sort(:desc)

    assert {:ok, %{entries: first, more?: true}} = runs_page(context, 1)
    assert Enum.map(first, & &1.contact_planning_run_id) == Enum.take(ids, 25)
    assert {:ok, %{entries: [last], more?: false}} = runs_page(context, 2)
    assert last.contact_planning_run_id == List.last(ids)
    assert {:ok, %{entries: [], more?: false}} = runs_page(context, 3)

    selected_id = hd(first).contact_planning_run_id
    newer = run(context, "newer-run", DateTime.add(@now, 1))
    assert {:ok, %{entries: [head | _]}} = runs_page(context, 1)
    assert head.contact_planning_run_id == newer.contact_planning_run_id

    assert {:ok, selected} = Planner.fetch_run(context.org, context.mission, selected_id)
    assert selected.contact_planning_run_id == selected_id
  end

  test "search pages retain all route evidence in deterministic order", context do
    result = evidence(context, "search-pages")
    assert {:ok, %{entries: first, more?: true}} = searches_page(context, result.run, 1)
    assert length(first) == 25
    assert Enum.map(first, & &1.route_key) == Enum.map(1..25, &("route-" <> padded(&1)))
    assert {:ok, %{entries: [last], more?: false}} = searches_page(context, result.run, 2)
    assert last.route_key == "route-26"
    assert {:ok, %{entries: [], more?: false}} = searches_page(context, result.run, 3)
  end

  test "opportunity pages break timestamp and provider-reference ties without hiding ineligible rows",
       context do
    result = evidence(context, "snapshot-pages")
    assert {:ok, %{entries: first, more?: true}} = snapshots_page(context, result.run, 1)
    assert length(first) == 25
    assert {:ok, %{entries: [last], more?: false}} = snapshots_page(context, result.run, 2)
    actual = first ++ [last]

    assert Enum.map(actual, & &1.contact_opportunity_snapshot_id) ==
             Enum.map(1..26, &("snapshot-pages-snapshot-" <> padded(&1)))

    assert Enum.count(actual, & &1.eligible) == 13
    assert Enum.all?(actual, &(&1.provider_opportunity_ref == "same-provider-ref"))
    assert {:ok, %{entries: [], more?: false}} = snapshots_page(context, result.run, 3)
  end

  test "pages isolate organization, mission, requirement and run identities", context do
    own = evidence(context, "own")
    other = fixture("pages", "other-mission")
    foreign = fixture("foreign-org", "foreign-mission")
    other_result = evidence(other, "other")
    foreign_result = evidence(foreign, "foreign")

    for different <- [other, foreign] do
      assert {:ok, %{entries: [], more?: false}} =
               Planner.list_runs_page(context.org, context.mission, different.requirement_id, 1)

      assert {:ok, %{entries: [], more?: false}} =
               ContactRequirements.list_versions_page(
                 context.org,
                 context.mission,
                 different.requirement_id,
                 1,
                 1
               )
    end

    for result <- [other_result, foreign_result] do
      assert {:ok, %{entries: [], more?: false}} = searches_page(context, result.run, 1)
      assert {:ok, %{entries: [], more?: false}} = snapshots_page(context, result.run, 1)
    end

    for {org, mission} <- [{foreign.org, context.mission}, {context.org, other.mission}] do
      assert {:ok, %{entries: [], more?: false}} =
               Planner.list_runs_page(org, mission, context.requirement_id, 1)

      assert {:ok, %{entries: [], more?: false}} =
               Planner.list_searches_page(org, mission, own.run.contact_planning_run_id, 1)

      assert {:ok, %{entries: [], more?: false}} =
               Planner.list_snapshots_page(org, mission, own.run.contact_planning_run_id, 1)

      assert {:ok, %{entries: [], more?: false}} =
               ContactRequirements.list_versions_page(org, mission, context.requirement_id, 1, 1)
    end

    assert {:ok, %{entries: [own_run], more?: false}} = runs_page(context, 1)
    assert own_run.contact_planning_run_id == own.run.contact_planning_run_id
  end

  test "same-mission requirements and runs retain separate evidence", context do
    sibling = fixture(context.org, context.mission)
    sibling_result = evidence(sibling, "sibling")
    own = evidence(context, "own")
    refute sibling_result.run.contact_planning_run_id == own.run.contact_planning_run_id

    assert {:ok, %{entries: [own_run], more?: false}} = runs_page(context, 1)
    assert own_run.contact_planning_run_id == own.run.contact_planning_run_id
    assert {:ok, %{entries: [version], more?: false}} = versions_page(context, 1, 1)
    assert version.contact_requirement_id == context.requirement_id

    for read <- [&searches_page/3, &snapshots_page/3] do
      assert {:ok, %{entries: first, more?: true}} = read.(context, own.run, 1)
      assert {:ok, %{entries: [last], more?: false}} = read.(context, own.run, 2)
      assert length(first) == 25

      assert Enum.all?(
               first ++ [last],
               &(&1.contact_planning_run_id == own.run.contact_planning_run_id)
             )
    end
  end

  test "version history remains anchored when a newer immutable version is added", context do
    for version <- 2..26 do
      assert {:ok, _, _} =
               ContactRequirements.version(
                 context.scope,
                 context.mission,
                 context.requirement_id,
                 version - 1,
                 %{minimum_duration_seconds: 60 + version}
               )
    end

    assert {:ok, %{entries: first, more?: true}} = versions_page(context, 26, 1)
    assert Enum.map(first, & &1.version) == Enum.to_list(26..2//-1)

    assert {:ok, _, _} =
             ContactRequirements.version(
               context.scope,
               context.mission,
               context.requirement_id,
               26,
               %{minimum_duration_seconds: 87}
             )

    assert {:ok, %{entries: ^first, more?: true}} = versions_page(context, 26, 1)
    assert {:ok, %{entries: [last], more?: false}} = versions_page(context, 26, 2)
    assert last.version == 1
    assert {:ok, %{entries: [], more?: false}} = versions_page(context, 26, 3)
    assert {:ok, %{entries: [latest | _]}} = versions_page(context, 27, 1)
    assert latest.version == 27
  end

  test "invalid page and version bounds are rejected", context do
    for page <- [nil, 0, -1, 1.0, "1", 1_000_001, %{}] do
      assert {:error, :invalid_planning_result_page} = runs_page(context, page)

      assert {:error, :invalid_planning_result_page} =
               Planner.list_searches_page(context.org, context.mission, "unused", page)

      assert {:error, :invalid_planning_result_page} =
               Planner.list_snapshots_page(context.org, context.mission, "unused", page)

      assert {:error, :invalid_requirement_history_page} = versions_page(context, 1, page)
    end

    for version <- [nil, 0, -1, 1.0, "1", 9_007_199_254_740_992] do
      assert {:error, :invalid_requirement_history_page} = versions_page(context, version, 1)
    end
  end

  defp fixture(org, mission) do
    %{organization: organization} = persist_mission_scope(org, mission)

    user =
      User.new(%{user_id: "page-reviewer", email: "pages@example.test", display_name: "Reader"})

    membership =
      OrganizationMembership.new(%{user_id: user.user_id, organization_id: org, role: :member})

    scope =
      Scope.new(%{
        user: user,
        organization_id: org,
        organization: organization,
        organization_membership: membership
      })

    craft = "craft-#{mission}"

    assert {:ok, _} =
             Cadence.SpacecraftStore.persist_spacecraft(
               org,
               Spacecraft.new(%{
                 spacecraft_id: craft,
                 mission_id: mission,
                 display_name: "Page spacecraft"
               })
             )

    assert {:ok, requirement, _} =
             ContactRequirements.create(scope, mission, %{
               spacecraft_id: craft,
               service_direction: :downlink,
               contact_intent: "payload_downlink",
               earliest_start: @now,
               latest_end: DateTime.add(@now, 3600),
               success_measure: :minimum_duration,
               minimum_duration_seconds: 60,
               priority: :high,
               rationale: "Page fixture"
             })

    %{
      org: org,
      mission: mission,
      scope: scope,
      requirement_id: requirement.contact_requirement_id
    }
  end

  defp run(context, id, started_at \\ @now) do
    assert {:ok, result} =
             PlanningResults.start_run(
               ContactPlanningRun.new(%{
                 contact_planning_run_id: id,
                 organization_id: context.org,
                 mission_id: context.mission,
                 contact_requirement_id: context.requirement_id,
                 contact_requirement_version: 1,
                 requested_by: context.scope.user.user_id,
                 started_at: started_at
               })
             )

    result
  end

  defp evidence(context, prefix) do
    run = run(context, prefix <> "-run")

    pairs =
      for index <- 26..1//-1 do
        search =
          ContactPlanningSearch.new(%{
            contact_planning_search_id: "#{prefix}-search-#{padded(index)}",
            contact_planning_run_id: run.contact_planning_run_id,
            organization_id: context.org,
            mission_id: context.mission,
            route_key: "route-#{padded(index)}",
            route_order: 0,
            outcome: :succeeded_with_results,
            opportunity_count: 1,
            route_binding_document: %{},
            readiness_document: %{},
            error_document: %{},
            content_sha256: @hash,
            started_at: @now,
            completed_at: @now
          })

        snapshot =
          ContactOpportunitySnapshot.new(%{
            contact_opportunity_snapshot_id: "#{prefix}-snapshot-#{padded(index)}",
            contact_planning_run_id: run.contact_planning_run_id,
            contact_planning_search_id: search.contact_planning_search_id,
            organization_id: context.org,
            mission_id: context.mission,
            contact_requirement_id: context.requirement_id,
            contact_requirement_version: 1,
            provider_opportunity_ref: "same-provider-ref",
            starts_at: @now,
            ends_at: DateTime.add(@now, 60),
            expires_at: DateTime.add(@now, 3600),
            availability: :available,
            route_binding_document: %{},
            normalized_opportunity_document: %{},
            provider_evidence_document: %{},
            evaluation_document: %{},
            eligible: rem(index, 2) == 0,
            content_sha256: @hash,
            captured_at: @now
          })

        {search, snapshot}
      end

    {searches, snapshots} = Enum.unzip(pairs)

    assert {:ok, result} =
             PlanningResults.complete_run(run, searches, snapshots, :completed, @now, %{})

    result
  end

  defp runs_page(context, page),
    do: Planner.list_runs_page(context.org, context.mission, context.requirement_id, page)

  defp searches_page(context, run, page),
    do:
      Planner.list_searches_page(context.org, context.mission, run.contact_planning_run_id, page)

  defp snapshots_page(context, run, page),
    do:
      Planner.list_snapshots_page(context.org, context.mission, run.contact_planning_run_id, page)

  defp versions_page(context, version, page),
    do:
      ContactRequirements.list_versions_page(
        context.org,
        context.mission,
        context.requirement_id,
        version,
        page
      )

  defp padded(index), do: String.pad_leading(to_string(index), 2, "0")
end
