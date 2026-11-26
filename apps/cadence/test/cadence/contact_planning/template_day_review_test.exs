defmodule Cadence.ContactPlanning.TemplateDayReviewTest do
  @moduledoc """
  U48 (DECISIONS #86): the template edit's dry run lists the days an edit won't regenerate:
  planned or started, closed, and canceled by an operator. A future, untaken day isn't listed (the
  edit replaces it), and neither is a day an earlier edit superseded.
  """
  use Cadence.DataCase, async: false

  alias Cadence.Accounts.{OrganizationMembership, User}
  alias Cadence.Auth.Scope

  alias Cadence.ContactPlanning.{
    ContactPlanVersion,
    ContactRequirements,
    ContactRequirementTemplates
  }

  alias Cadence.ContactPlanning.{RequirementListing, TemplateDayReview}
  alias Cadence.Reads.ContactPlanOverview.Demand
  alias Cadence.{Repo, Spacecraft}
  alias Cadence.SpacecraftStore.SpacecraftRow

  @org "org-template-day-review"
  @mission "mission-template-day-review"
  @spacecraft "spacecraft-day-review"
  @now ~U[2026-07-17 00:00:00.000000Z]

  setup do
    %{organization: organization} = persist_mission_scope(@org, @mission)

    {:ok, _} =
      Cadence.SpacecraftStore.persist_spacecraft(
        @org,
        Spacecraft.new(%{spacecraft_id: @spacecraft, mission_id: @mission, display_name: "Days"})
      )

    scope = scope(organization)
    {:ok, template, _v1} = ContactRequirementTemplates.create(scope, @mission, attrs(), now: @now)

    # Days whose windows open at +10, +70, +130 and +190 min.
    {:ok, created} =
      ContactRequirementTemplates.materialize(
        scope,
        @mission,
        template.contact_requirement_template_id,
        @now,
        DateTime.add(@now, 10_800, :second),
        now: @now
      )

    %{scope: scope, template: template, v1: Enum.map(created, & &1.requirement)}
  end

  test "groups the kept and done days, one entry per instant, oldest first", c do
    [started, closed, canceled, _future] = c.v1
    {:ok, _} = transition(c, closed, :close, "Not needed that day")
    {:ok, _} = transition(c, canceled, :cancel, "Station closed")

    # 15 minutes in, the first day's window has begun.
    later = DateTime.add(@now, 900, :second)
    id = c.template.contact_requirement_template_id

    assert %{
             decided: %{planned_or_started: [kept], closed: [done], canceled: [gone]},
             decided_counts: counts
           } = TemplateDayReview.review(@org, @mission, id, later)

    assert Map.values(counts) ==
             List.duplicate(
               %{
                 days: 1,
                 requirements: 1,
                 dates: ["2026-07-17"],
                 first_date: "2026-07-17",
                 last_date: "2026-07-17"
               },
               3
             )

    assert kept == %{
             occurrence_at: occurrence_at(started),
             date: "2026-07-17",
             spacecraft_ids: [@spacecraft]
           }

    assert done.occurrence_at == occurrence_at(closed)
    assert gone.occurrence_at == occurrence_at(canceled)

    # Before anything started or was decided, nothing is listed.
    assert TemplateDayReview.decided(@org, "other-mission", id, later) ==
             %{planned_or_started: [], closed: [], canceled: []}
  end

  test "a template-generated requirement row names its template version (U48 Source)", c do
    [requirement | _] = c.v1

    [{_requirement, version} | _] =
      ContactRequirements.list(@org, @mission, lifecycle_state: :active)

    assert RequirementListing.template_version(version) == 1
    assert RequirementListing.template_id(version) == c.template.contact_requirement_template_id
    assert RequirementListing.template_version(%{metadata: %{}}) == nil
    assert requirement.contact_requirement_id
  end

  test "template day and plan coverage counts include all 1,000 spacecraft", c do
    ids = [@spacecraft | Enum.map(2..1_000, &"day-review-fleet-#{&1}")]
    id = c.template.contact_requirement_template_id
    later = DateTime.add(@now, 4_500, :second)

    ids
    |> tl()
    |> Enum.map(fn spacecraft_id ->
      %{
        spacecraft_id: spacecraft_id,
        organization_id: @org,
        mission_id: @mission,
        display_name: spacecraft_id,
        lifecycle_state: "active",
        metadata: %{},
        inserted_at: @now
      }
    end)
    |> Enum.chunk_every(250)
    |> Enum.each(&Repo.insert_all(SpacecraftRow, &1))

    assert {:ok, generated} =
             ContactRequirementTemplates.materialize(
               c.scope,
               @mission,
               id,
               @now,
               DateTime.add(@now, 3_599, :second),
               now: @now,
               targets: ids,
               supersede: false
             )

    assert length(generated) == 1_000

    assert %{days: 1, requirements: 1_001, dates: ["2026-07-17"]} =
             TemplateDayReview.review(@org, @mission, id, later).decided_counts.planned_or_started

    evaluations =
      for {%{requirement: requirement}, index} <- Enum.with_index(generated) do
        covered = rem(index, 2) == 0

        %{
          "contact_requirement_id" => requirement.contact_requirement_id,
          "contact_requirement_version" => requirement.current_version,
          "satisfied" => covered,
          "facts" => %{"selected_count" => if(covered, do: 1, else: 0)}
        }
      end

    unmet = Enum.reject(evaluations, & &1["satisfied"])

    version = %ContactPlanVersion{
      coverage_document: %{"requirements" => evaluations},
      unsatisfied_document: %{"requirements" => unmet}
    }

    assert %{
             rule_total: 1_000,
             rule_met: 500,
             coverage: %{spacecraft_uncovered: 500, contacts_short: 500, gaps: 500}
           } = Demand.demand(@org, @mission, version, [])
  end

  defp occurrence_at(requirement) do
    [{_requirement, version}] =
      @org
      |> ContactRequirements.list(@mission, [])
      |> Enum.filter(fn {r, _v} ->
        r.contact_requirement_id == requirement.contact_requirement_id
      end)

    {:ok, at, 0} = DateTime.from_iso8601(version.metadata["generation"]["occurrence_at"])
    at
  end

  defp transition(c, requirement, action, reason),
    do:
      apply(ContactRequirements, action, [
        c.scope,
        @mission,
        requirement.contact_requirement_id,
        requirement.current_version,
        reason,
        [now: @now]
      ])

  defp attrs do
    %{
      name: "Days",
      target_document: %{"kind" => "spacecraft_ids", "spacecraft_ids" => [@spacecraft]},
      schedule_document: %{
        "type" => "fixed_interval",
        "anchor_at" => DateTime.to_iso8601(@now),
        "interval_seconds" => 3_600,
        "window_offset_seconds" => 600,
        "window_duration_seconds" => 1_800
      },
      requirement_document: %{
        "service_direction" => "downlink",
        "contact_intent" => "recurring_payload_downlink",
        "success_measure" => "minimum_duration",
        "minimum_duration_seconds" => 300,
        "preferred_duration_seconds" => 300,
        "minimum_data_volume_bytes" => nil,
        "contact_count" => 1,
        "minimum_separation_seconds" => 0,
        "priority" => "routine",
        "provider_constraints_document" => %{"allowed" => [], "excluded" => []},
        "station_constraints_document" => %{"allowed" => [], "excluded" => []},
        "policy_constraints_document" => %{},
        "approval_policy_document" => %{"mode" => "manual"},
        "rationale" => "Template day review test",
        "metadata" => %{}
      },
      catch_up_policy_document: %{
        "maximum_occurrences_per_run" => 10,
        "maximum_lookback_seconds" => 86_400
      }
    }
  end

  defp scope(organization) do
    user =
      User.new(%{
        user_id: "template-day-review-admin",
        email: "template-day-review-admin@example.test",
        display_name: "Review Admin"
      })

    Scope.new(%{
      user: user,
      organization_id: organization.organization_id,
      organization: organization,
      organization_membership:
        OrganizationMembership.new(%{
          user_id: user.user_id,
          organization_id: organization.organization_id,
          role: :organization_admin
        })
    })
  end
end
