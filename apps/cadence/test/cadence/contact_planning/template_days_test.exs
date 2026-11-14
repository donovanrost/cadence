defmodule Cadence.ContactPlanning.TemplateDaysTest do
  @moduledoc """
  DECISIONS #86: one requirement per template day across versions. An edit doesn't give a day a
  second requirement when an older version's is planned or started, and doesn't bring back a day
  an operator closed or canceled (qa's EARENDIL-001 case, 11-13).
  """
  use Cadence.DataCase, async: false

  alias Cadence.Accounts.{OrganizationMembership, User}
  alias Cadence.Auth.Scope
  alias Cadence.ContactPlanning.{ContactRequirements, ContactRequirementTemplates, TemplateDays}
  alias Cadence.Spacecraft

  @org "org-template-days"
  @mission "mission-template-days"
  @spacecraft "spacecraft-template-days"
  @now ~U[2026-07-17 00:00:00.000000Z]

  setup do
    %{organization: organization} = persist_mission_scope(@org, @mission)

    {:ok, _} =
      Cadence.SpacecraftStore.persist_spacecraft(
        @org,
        Spacecraft.new(%{spacecraft_id: @spacecraft, mission_id: @mission, display_name: "Days"})
      )

    {:ok, template, _v1} =
      ContactRequirementTemplates.create(scope(organization), @mission, attrs(), now: @now)

    # Three days: windows open at +10 min, +70 min and +130 min.
    {:ok, first} = materialize(scope(organization), template, @now)
    assert Enum.all?(first, &(&1.status == :created))

    %{scope: scope(organization), template: template, v1: Enum.map(first, & &1.requirement)}
  end

  test "an edit keeps a started day's requirement and leaves a closed day closed", c do
    [started, closed, future] = c.v1
    close!(c, closed, "Not needed that day")

    # Edited 15 minutes in: the first day's window has begun.
    later = DateTime.add(@now, 900, :second)
    edit!(c, 1, later)
    {:ok, results} = materialize(c.scope, c.template, later)

    assert [
             %{status: :existing, requirement: %{contact_requirement_id: kept_id}},
             %{status: :existing, requirement: %{contact_requirement_id: done_id}},
             %{status: :created, requirement: replacement}
           ] = results

    assert kept_id == started.contact_requirement_id
    assert done_id == closed.contact_requirement_id

    # One active requirement per day: the started v1 and the new v2. The closed day stays closed.
    active = ids(:active)

    assert active ==
             Enum.sort([started.contact_requirement_id, replacement.contact_requirement_id])

    assert ids(:closed) == [closed.contact_requirement_id]

    assert [{superseded, _}] =
             ContactRequirements.list(@org, @mission, lifecycle_state: :canceled)

    assert superseded.contact_requirement_id == future.contact_requirement_id
    assert superseded.lifecycle_reason =~ "template_versioned"

    # A second run of the same version changes nothing.
    {:ok, again} = materialize(c.scope, c.template, later)
    assert Enum.all?(again, &(&1.status == :existing))
    assert ids(:active) == active
  end

  test "an operator's cancel stays; a day superseded by an earlier edit regenerates", c do
    [first, canceled, _third] = c.v1
    {:ok, _canceled} = cancel!(c, canceled, "Station closed")

    edit!(c, 1, @now)
    {:ok, _} = materialize(c.scope, c.template, @now)
    edit!(c, 2, @now)

    days =
      TemplateDays.classify(
        @org,
        @mission,
        c.template.contact_requirement_template_id,
        3,
        occurrences(),
        now: @now
      )

    # The first day's latest older requirement is v2's (active, future, unplanned): regenerate.
    # The second day's is v1's, canceled by an operator: done.
    assert [
             %{outcome: :generate, prior: %{template_version: 2}},
             %{outcome: :done, why: :canceled, prior: %{requirement_id: done_id}},
             %{outcome: :generate}
           ] = Enum.map(occurrences(), fn {at, sc} -> days[TemplateDays.key(at, sc)] end)

    assert done_id == canceled.contact_requirement_id
    refute first.contact_requirement_id == done_id

    {:ok, third_run} = materialize(c.scope, c.template, @now)
    assert Enum.map(third_run, & &1.status) == [:created, :existing, :created]
    assert length(ids(:active)) == 2
  end

  test "a day a plan has taken up is kept; one only in a draft is regenerated" do
    prior = %{
      requirement_id: "requirement-1",
      lifecycle_state: "active",
      lifecycle_reason: nil,
      earliest_start: DateTime.add(@now, 600, :second)
    }

    planned = MapSet.new(["requirement-1"])
    assert %{outcome: :kept, why: :planned} = TemplateDays.decide(prior, planned, @now)
    assert %{outcome: :generate} = TemplateDays.decide(prior, MapSet.new(), @now)

    superseded = %{
      prior
      | lifecycle_state: "canceled",
        lifecycle_reason: "left_template_target: x"
    }

    assert %{outcome: :generate} = TemplateDays.decide(superseded, MapSet.new(), @now)
    assert %{outcome: :generate, prior: nil} = TemplateDays.decide(nil, planned, @now)
  end

  defp ids(state) do
    @org
    |> ContactRequirements.list(@mission, lifecycle_state: state)
    |> Enum.map(fn {requirement, _version} -> requirement.contact_requirement_id end)
    |> Enum.sort()
  end

  defp occurrences, do: for(i <- 0..2, do: {DateTime.add(@now, i * 3_600, :second), @spacecraft})

  defp materialize(scope, template, now) do
    ContactRequirementTemplates.materialize(
      scope,
      @mission,
      template.contact_requirement_template_id,
      @now,
      DateTime.add(@now, 7_200, :second),
      now: now
    )
  end

  defp edit!(c, from_version, now) do
    {:ok, _, _} =
      ContactRequirementTemplates.version(
        c.scope,
        @mission,
        c.template.contact_requirement_template_id,
        from_version,
        %{name: "Days v#{from_version + 1}"},
        now: now
      )
  end

  defp close!(c, requirement, reason) do
    {:ok, _closed} =
      ContactRequirements.close(
        c.scope,
        @mission,
        requirement.contact_requirement_id,
        requirement.current_version,
        reason,
        now: @now
      )
  end

  defp cancel!(c, requirement, reason),
    do:
      ContactRequirements.cancel(
        c.scope,
        @mission,
        requirement.contact_requirement_id,
        requirement.current_version,
        reason,
        now: @now
      )

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
        "rationale" => "Template days test",
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
        user_id: "template-days-admin",
        email: "template-days-admin@example.test",
        display_name: "Days Admin"
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
