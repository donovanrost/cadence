defmodule Cadence.ContactPlanning.FleetPlanningStartsTest do
  use Cadence.DataCase, async: false
  alias Cadence.FleetStartFixtures, as: Fixtures
  alias Cadence.Management.Contacts.Store.{ContactRequirementRow, ContactRequirementTemplateRow}
  alias Cadence.Repo
  alias Ecto.Changeset

  alias Cadence.ContactPlanning.{
    ContactRequirements,
    ContactRequirementTemplates,
    FleetPlanningPolicies,
    FleetPlanningRuns,
    FleetPlanningStarts
  }

  setup do: Fixtures.setup_start()

  test "review is read-only and creation preserves the exact input claim", c do
    params = Fixtures.params()
    assert {:ok, review} = FleetPlanningStarts.preview(c.scope, c.mission_id, params)
    assert review.requirements.total == 1
    assert review.templates.total == 0
    assert review.occurrence_count == 0
    assert review.policy.version == c.policy_version.version
    assert [%{id: id, version: 1}] = review.requirements.entries
    assert id == c.requirement.contact_requirement_id
    assert FleetPlanningRuns.list(c.organization_id, c.mission_id) == []

    assert {:ok, run, [ref]} =
             FleetPlanningStarts.create(
               c.scope,
               c.mission_id,
               Map.put(params, "evidence", review.evidence)
             )

    assert run.phase == :queued
    assert run.lifecycle_state == :queued
    assert run.input_document["creation_review"] == review.evidence
    assert run.input_document["template_materialization"]["skipped"]
    assert ref.contact_requirement_id == id
    assert ref.contact_requirement_version == 1
  end

  test "policy, requirement, template and window drift are rejected before materialization", c do
    assert {:ok, t, _} =
             ContactRequirementTemplates.create(c.admin, c.mission_id, Fixtures.template_attrs())

    params = Fixtures.params(true)
    assert {:ok, review} = FleetPlanningStarts.preview(c.scope, c.mission_id, params)
    assert review.occurrence_count == 5

    assert ContactRequirementTemplates.list_occurrences(
             c.organization_id,
             c.mission_id,
             t.contact_requirement_template_id
           ) == []

    changed = put_in(params, ["fleet_run", "horizon_end"], "2026-07-17T09:00:00.000000Z")

    assert {:error, :fleet_planning_review_changed} =
             FleetPlanningStarts.create(
               c.scope,
               c.mission_id,
               Map.put(changed, "evidence", review.evidence)
             )

    assert {:ok, _, _} =
             ContactRequirements.version(
               c.scope,
               c.mission_id,
               c.requirement.contact_requirement_id,
               1,
               %{priority: :critical}
             )

    assert {:error, :fleet_planning_review_changed} =
             FleetPlanningStarts.create(
               c.scope,
               c.mission_id,
               Map.put(params, "evidence", review.evidence)
             )

    assert {:ok, review} = FleetPlanningStarts.preview(c.scope, c.mission_id, params)

    assert {:ok, _} =
             ContactRequirementTemplates.pause(
               c.admin,
               c.mission_id,
               t.contact_requirement_template_id,
               1,
               "Pause recurring demand"
             )

    assert {:error, :fleet_planning_review_changed} =
             FleetPlanningStarts.create(
               c.scope,
               c.mission_id,
               Map.put(params, "evidence", review.evidence)
             )

    assert {:ok, review} = FleetPlanningStarts.preview(c.scope, c.mission_id, params)

    assert {:ok, _, v2} =
             FleetPlanningPolicies.version(
               c.admin,
               c.mission_id,
               c.policy.fleet_planning_policy_id,
               1,
               Fixtures.policy_attrs()
             )

    assert {:ok, _, _, _} =
             FleetPlanningPolicies.approve(
               c.admin,
               c.mission_id,
               c.policy.fleet_planning_policy_id,
               2,
               v2.content_sha256,
               "Revised boundary"
             )

    assert {:error, :fleet_planning_review_changed} =
             FleetPlanningStarts.create(
               c.scope,
               c.mission_id,
               Map.put(params, "evidence", review.evidence)
             )

    assert FleetPlanningRuns.list(c.organization_id, c.mission_id) == []

    assert ContactRequirementTemplates.list_occurrences(
             c.organization_id,
             c.mission_id,
             t.contact_requirement_template_id
           ) == []
  end

  test "recurring demand and the queued run are persisted together", c do
    assert {:ok, t, _} =
             ContactRequirementTemplates.create(c.admin, c.mission_id, Fixtures.template_attrs())

    params = Fixtures.params(true)
    assert {:ok, review} = FleetPlanningStarts.preview(c.scope, c.mission_id, params)

    assert {:ok, run, refs} =
             FleetPlanningStarts.create(
               c.scope,
               c.mission_id,
               Map.put(params, "evidence", review.evidence)
             )

    assert length(refs) == 5
    assert run.phase == :queued
    assert run.input_document["template_materialization"]["created_count"] == 5

    assert length(
             ContactRequirementTemplates.list_occurrences(
               c.organization_id,
               c.mission_id,
               t.contact_requirement_template_id
             )
           ) == 5
  end

  test "failure after recurring materialization rolls back every generated requirement", c do
    assert {:ok, _} =
             ContactRequirements.cancel(
               c.scope,
               c.mission_id,
               c.requirement.contact_requirement_id,
               1,
               "No demand in this horizon"
             )

    attrs = Fixtures.template_attrs()
    attrs = put_in(attrs, [:schedule_document, "window_offset_seconds"], 36_000)
    assert {:ok, t, _} = ContactRequirementTemplates.create(c.admin, c.mission_id, attrs)
    params = Fixtures.params(true)
    assert {:ok, review} = FleetPlanningStarts.preview(c.scope, c.mission_id, params)
    assert review.requirements.total == 0
    assert review.occurrence_count == 5
    before = ContactRequirements.list(c.organization_id, c.mission_id)

    assert {:error, :fleet_planning_run_has_no_requirements} =
             FleetPlanningStarts.create(
               c.scope,
               c.mission_id,
               Map.put(params, "evidence", review.evidence)
             )

    assert ContactRequirements.list(c.organization_id, c.mission_id) == before
    assert FleetPlanningRuns.list(c.organization_id, c.mission_id) == []

    assert ContactRequirementTemplates.list_occurrences(
             c.organization_id,
             c.mission_id,
             t.contact_requirement_template_id
           ) == []
  end

  test "scope, exact evidence shape and horizon bounds fail before effects", c do
    params = Fixtures.params()
    assert {:ok, review} = FleetPlanningStarts.preview(c.scope, c.mission_id, params)
    denied = %{c.scope | organization_membership: nil}
    assert {:error, :forbidden} = FleetPlanningStarts.preview(denied, c.mission_id, params)

    for evidence <- [
          nil,
          Map.put(review.evidence, "policy_version", "1"),
          Map.put(review.evidence, "extra", "x")
        ] do
      assert {:error, :fleet_planning_start_input_invalid} =
               FleetPlanningStarts.create(
                 c.scope,
                 c.mission_id,
                 Map.put(params, "evidence", evidence)
               )
    end

    assert {:error, :fleet_planning_review_changed} =
             FleetPlanningStarts.create(
               c.scope,
               c.mission_id,
               Map.put(params, "evidence", Map.put(review.evidence, "mission_id", "foreign"))
             )

    over = put_in(params, ["fleet_run", "horizon_end"], "2026-07-18T04:00:00.000001Z")

    assert {:error, :fleet_planning_horizon_exceeds_policy} =
             FleetPlanningStarts.preview(c.scope, c.mission_id, over)

    assert FleetPlanningRuns.list(c.organization_id, c.mission_id) == []
  end

  test "review pages retain one exact fingerprint and new demand invalidates it", c do
    for _ <- 1..26 do
      assert {:ok, _, _} =
               ContactRequirements.create(c.scope, c.mission_id, Fixtures.requirement_attrs())
    end

    params = Fixtures.params()
    assert {:ok, first} = FleetPlanningStarts.preview(c.scope, c.mission_id, params)

    assert {:ok, second} =
             FleetPlanningStarts.preview(
               c.scope,
               c.mission_id,
               Map.put(params, "requirements_page", 2)
             )

    assert first.requirements.total == 27
    assert length(first.requirements.entries) == 25
    assert first.requirements.more
    assert length(second.requirements.entries) == 2
    refute second.requirements.more

    assert length(
             Enum.uniq_by(first.requirements.entries ++ second.requirements.entries, & &1.id)
           ) == 27

    assert first.evidence == second.evidence

    assert {:ok, _, _} =
             ContactRequirements.create(c.scope, c.mission_id, Fixtures.requirement_attrs())

    assert {:error, :fleet_planning_review_changed} =
             FleetPlanningStarts.create(
               c.scope,
               c.mission_id,
               Map.put(params, "evidence", first.evidence)
             )

    assert FleetPlanningRuns.list(c.organization_id, c.mission_id) == []
  end

  test "previously generated closed demand is not advertised or recreated as new demand", c do
    assert {:ok, template, _} =
             ContactRequirementTemplates.create(c.admin, c.mission_id, Fixtures.template_attrs())

    params = Fixtures.params(true)
    assert {:ok, before} = FleetPlanningStarts.preview(c.scope, c.mission_id, params)
    assert before.eligible_occurrence_count == 4

    assert {:ok, generated} =
             ContactRequirementTemplates.materialize(
               c.scope,
               c.mission_id,
               template.contact_requirement_template_id,
               ~U[2026-07-17 04:00:00.000000Z],
               ~U[2026-07-17 08:00:00.000000Z]
             )

    for result <- generated do
      assert {:ok, _} =
               ContactRequirements.cancel(
                 c.scope,
                 c.mission_id,
                 result.requirement.contact_requirement_id,
                 result.requirement.current_version,
                 "Demand withdrawn"
               )
    end

    assert {:ok, after_review} = FleetPlanningStarts.preview(c.scope, c.mission_id, params)
    assert after_review.eligible_occurrence_count == 0
    assert after_review.requirements.total == 1
    refute before.evidence == after_review.evidence

    assert {:error, :fleet_planning_review_changed} =
             FleetPlanningStarts.create(
               c.scope,
               c.mission_id,
               Map.put(params, "evidence", before.evidence)
             )

    assert {:ok, _, [ref]} =
             FleetPlanningStarts.create(
               c.scope,
               c.mission_id,
               Map.put(params, "evidence", after_review.evidence)
             )

    assert ref.contact_requirement_id == c.requirement.contact_requirement_id
  end

  test "missing current versions fail review instead of silently removing demand", c do
    requirement_row =
      Repo.get_by!(ContactRequirementRow,
        contact_requirement_id: c.requirement.contact_requirement_id
      )

    requirement_row = Repo.update!(Changeset.change(requirement_row, current_version: 2))

    assert {:error, :fleet_planning_requirement_version_unavailable} =
             FleetPlanningStarts.preview(c.scope, c.mission_id, Fixtures.params())

    Repo.update!(Changeset.change(requirement_row, current_version: 1))

    assert {:ok, template, _} =
             ContactRequirementTemplates.create(c.admin, c.mission_id, Fixtures.template_attrs())

    template_row =
      Repo.get_by!(ContactRequirementTemplateRow,
        contact_requirement_template_id: template.contact_requirement_template_id
      )

    Repo.update!(Changeset.change(template_row, current_version: 2))

    assert {:error, :fleet_planning_template_version_unavailable} =
             FleetPlanningStarts.preview(c.scope, c.mission_id, Fixtures.params(true))

    assert {:ok, review} = FleetPlanningStarts.preview(c.scope, c.mission_id, Fixtures.params())
    assert review.templates.total == 0
    assert FleetPlanningRuns.list(c.organization_id, c.mission_id) == []
  end

  test "generated requirements revised outside the horizon do not restore their original versions",
       c do
    assert {:ok, template, _} =
             ContactRequirementTemplates.create(c.admin, c.mission_id, Fixtures.template_attrs())

    assert {:ok, generated} =
             ContactRequirementTemplates.materialize(
               c.scope,
               c.mission_id,
               template.contact_requirement_template_id,
               ~U[2026-07-17 04:00:00.000000Z],
               ~U[2026-07-17 08:00:00.000000Z]
             )

    for result <- generated do
      assert {:ok, _, _} =
               ContactRequirements.version(
                 c.scope,
                 c.mission_id,
                 result.requirement.contact_requirement_id,
                 1,
                 %{
                   earliest_start: ~U[2026-07-18 04:00:00.000000Z],
                   latest_end: ~U[2026-07-18 08:00:00.000000Z]
                 }
               )
    end

    params = Fixtures.params(true)
    assert {:ok, review} = FleetPlanningStarts.preview(c.scope, c.mission_id, params)
    assert review.requirements.total == 1
    assert review.eligible_occurrence_count == 0

    assert {:ok, _, [ref]} =
             FleetPlanningStarts.create(
               c.scope,
               c.mission_id,
               Map.put(params, "evidence", review.evidence)
             )

    assert ref.contact_requirement_id == c.requirement.contact_requirement_id
  end
end
