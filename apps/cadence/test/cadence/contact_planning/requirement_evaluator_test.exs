defmodule Cadence.ContactPlanning.RequirementEvaluatorTest do
  use Cadence.UnitCase, async: true

  alias Cadence.ContactPlanning.{
    ContactOpportunitySnapshot,
    ContactRequirements,
    ContactRequirementVersion,
    ContentHash,
    RequirementEvaluator
  }

  @now ~U[2026-07-16 20:00:00.000000Z]

  test "opportunity equality boundaries are eligible and facts are explicit" do
    requirement = requirement()

    evaluation =
      RequirementEvaluator.evaluate_opportunity(
        requirement,
        opportunity(%{
          "starts_at" => DateTime.to_iso8601(requirement.earliest_start),
          "ends_at" =>
            requirement.earliest_start
            |> DateTime.add(600, :second)
            |> DateTime.to_iso8601(),
          "estimated_capacity" => %{"bytes" => 1_500_000_000}
        }),
        route(),
        now: @now
      )

    assert evaluation["eligible"]
    assert evaluation["hard_failures"] == []
    assert evaluation["facts"]["duration_seconds"] == 600
    assert evaluation["facts"]["estimated_volume_bytes"] == 1_500_000_000
  end

  test "unknown required volume, expired windows, and restrictions have stable reason order" do
    requirement =
      requirement(%{
        provider_constraints_document: %{"allowed" => ["provider-beta"], "excluded" => []},
        station_constraints_document: %{"allowed" => [], "excluded" => ["station-alpha"]}
      })

    evaluation =
      RequirementEvaluator.evaluate_opportunity(
        requirement,
        opportunity(%{
          "expires_at" => DateTime.to_iso8601(@now),
          "estimated_capacity" => nil
        }),
        route(),
        now: @now
      )

    refute evaluation["eligible"]

    assert Enum.map(evaluation["hard_failures"], & &1["code"]) == [
             "opportunity_expired",
             "provider_not_allowed",
             "station_not_allowed",
             "estimated_volume_unknown"
           ]
  end

  test "selection evaluation separates aggregate volume, overlap, and search failures" do
    requirement =
      requirement(%{
        contact_count: 2,
        minimum_data_volume_bytes: 2_000,
        minimum_separation_seconds: 300
      })

    first = snapshot(requirement, "first", 0, 600, 1_000)
    second = snapshot(requirement, "second", 700, 1_300, 1_500)

    evaluation =
      RequirementEvaluator.evaluate_selection(requirement, [second, first], [
        %{route_key: "route-alpha", outcome: :succeeded_with_results},
        %{route_key: "route-beta", outcome: :failed}
      ])

    refute evaluation["satisfied"]

    assert Enum.map(evaluation["hard_failures"], & &1["code"]) == [
             "minimum_separation_not_met"
           ]

    assert evaluation["facts"]["aggregate_estimated_volume_bytes"] == 2_500

    assert evaluation["search_failures"] == [
             %{
               "code" => "provider_search_unavailable",
               "route_key" => "route-beta",
               "route_keys" => ["route-beta"],
               "outcome" => "failed"
             }
           ]
  end

  describe "max_gap_seconds (DECISIONS #74)" do
    test "a gap equal to the limit is met; one second over fails with the gap's facts" do
      met = gap_requirement(24_600)

      assert RequirementEvaluator.evaluate_selection(met, [snapshot(met, "a", 0, 600, 1)])[
               "satisfied"
             ]

      over = gap_requirement(24_599)
      evaluation = RequirementEvaluator.evaluate_selection(over, [snapshot(over, "a", 0, 600, 1)])

      refute evaluation["satisfied"]

      assert [failure] = evaluation["hard_failures"]

      assert failure == %{
               "code" => "max_gap_exceeded",
               "message" => failure["message"],
               "longest_gap_seconds" => 24_600,
               "from" =>
                 over.earliest_start
                 |> DateTime.add(600)
                 |> DateTime.truncate(:second)
                 |> DateTime.to_iso8601(),
               "to" => over.latest_end |> DateTime.truncate(:second) |> DateTime.to_iso8601(),
               "max_gap_seconds" => 24_599
             }
    end

    test "no limit adds nothing and keeps the content hash" do
      plain = requirement(%{success_measure: :any_contact, minimum_data_volume_bytes: nil})

      evaluation =
        RequirementEvaluator.evaluate_selection(plain, [snapshot(plain, "a", 0, 600, 1)])

      assert evaluation["satisfied"]
      refute Map.has_key?(ContactRequirementVersion.content_document(plain), "max_gap_seconds")

      assert ContactRequirementVersion.content_document(gap_requirement(3_600))["max_gap_seconds"] ==
               3_600
    end

    test "the limit is 600 s to 7 days and no longer than the window" do
      for {limit, message} <- [
            {599, "must be between 600 and 604800 seconds"},
            {25_201, "must not be longer than the window"}
          ] do
        assert {:error, {:contact_requirement_field_invalid, :max_gap_seconds, ^message}} =
                 ContactRequirements.validate_content(gap_requirement(limit))
      end

      assert ContactRequirements.validate_content(gap_requirement(25_200)) == :ok
      assert ContactRequirements.validate_content(gap_requirement(nil)) == :ok
    end
  end

  describe "qa #26" do
    test "failed searches on several routes are one failure naming the routes" do
      requirement = requirement(%{})

      evaluation =
        RequirementEvaluator.evaluate_selection(
          requirement,
          [],
          [
            %{route_key: "route-alpha", outcome: :failed},
            %{route_key: "route-beta", outcome: :not_ready}
          ],
          now: DateTime.add(requirement.earliest_start, -3600)
        )

      assert [
               %{
                 "code" => "provider_search_unavailable",
                 "route_keys" => ["route-alpha", "route-beta"]
               }
             ] =
               evaluation["search_failures"]
    end

    test "a window that has already passed says so, once, instead of search failures" do
      requirement = requirement(%{})

      evaluation =
        RequirementEvaluator.evaluate_selection(
          requirement,
          [],
          [
            %{route_key: "route-alpha", outcome: :failed},
            %{route_key: "route-beta", outcome: :failed}
          ],
          now: DateTime.add(requirement.latest_end, 60)
        )

      refute evaluation["satisfied"]
      assert [%{"code" => "window_passed"}] = evaluation["hard_failures"]
      assert evaluation["search_failures"] == []
    end
  end

  test "missing optional capacity is a warning but does not make duration planning ineligible" do
    requirement =
      requirement(%{
        success_measure: :minimum_duration,
        minimum_data_volume_bytes: nil
      })

    evaluation =
      RequirementEvaluator.evaluate_opportunity(
        requirement,
        opportunity(%{"estimated_capacity" => nil}),
        route(),
        now: @now
      )

    assert evaluation["eligible"]

    assert Enum.map(evaluation["warnings"], & &1["code"]) == [
             "estimated_volume_unavailable"
           ]
  end

  # The window is 7 h; one 10 min pass at its start leaves 6 h 50 min (24600 s) to its end.
  defp gap_requirement(limit),
    do:
      requirement(%{
        success_measure: :any_contact,
        minimum_data_volume_bytes: nil,
        max_gap_seconds: limit
      })

  defp requirement(overrides \\ %{}) do
    ContactRequirementVersion.new(
      Map.merge(
        %{
          contact_requirement_id: "requirement-alpha",
          organization_id: "org-alpha",
          mission_id: "mission-alpha",
          version: 1,
          spacecraft_id: "spacecraft-alpha",
          service_direction: :downlink,
          contact_intent: "payload_downlink",
          earliest_start: DateTime.add(@now, 3_600, :second),
          latest_end: DateTime.add(@now, 28_800, :second),
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
          rationale: "Recorder downlink",
          metadata: %{},
          created_by: "user-alpha",
          created_at: @now
        },
        overrides
      )
    )
  end

  defp opportunity(overrides) do
    Map.merge(
      %{
        "id" => "opportunity-alpha",
        "spacecraft_ref" => "SC-001",
        "ground_station_ref" => "station-alpha",
        "antenna_or_service_pool_ref" => "pool-alpha",
        "service_profile_ref" => "service-downlink",
        "starts_at" => DateTime.add(@now, 3_600, :second) |> DateTime.to_iso8601(),
        "ends_at" => DateTime.add(@now, 4_500, :second) |> DateTime.to_iso8601(),
        "expires_at" => DateTime.add(@now, 3_000, :second) |> DateTime.to_iso8601(),
        "availability" => "available",
        "estimated_capacity" => %{"bytes" => 1_500_000_000},
        "synthetic" => true,
        "extensions" => %{}
      },
      overrides
    )
  end

  defp route do
    %{"provider_id" => "provider-alpha"}
  end

  defp snapshot(requirement, id, starts_offset, ends_offset, bytes) do
    starts_at = DateTime.add(requirement.earliest_start, starts_offset, :second)
    ends_at = DateTime.add(requirement.earliest_start, ends_offset, :second)

    ContactOpportunitySnapshot.new(%{
      contact_opportunity_snapshot_id: "snapshot-#{id}",
      contact_planning_run_id: "run-alpha",
      contact_planning_search_id: "search-alpha",
      organization_id: requirement.organization_id,
      mission_id: requirement.mission_id,
      contact_requirement_id: requirement.contact_requirement_id,
      contact_requirement_version: requirement.version,
      provider_opportunity_ref: id,
      starts_at: starts_at,
      ends_at: ends_at,
      expires_at: DateTime.add(@now, 1_800, :second),
      availability: :available,
      estimated_capacity_document: %{"bytes" => bytes},
      synthetic: true,
      route_binding_document: route(),
      normalized_opportunity_document: %{"id" => id},
      provider_evidence_document: %{"id" => id},
      evaluation_document: %{"eligible" => true},
      eligible: true,
      content_sha256: ContentHash.sha256(id),
      captured_at: @now
    })
  end
end
