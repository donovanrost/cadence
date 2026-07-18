defmodule Cadence.ContactPlanning.RequirementEvaluatorTest do
  use ExUnit.Case, async: true

  alias Cadence.ContactPlanning.{
    ContactOpportunitySnapshot,
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
               "outcome" => "failed"
             }
           ]
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
