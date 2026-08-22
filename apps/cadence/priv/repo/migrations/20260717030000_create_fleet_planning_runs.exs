defmodule Cadence.Repo.Migrations.CreateFleetPlanningRuns do
  use Ecto.Migration

  def up do
    create table(:fleet_planning_runs, primary_key: false) do
      add(:fleet_planning_run_id, :string, primary_key: true)
      add(:organization_id, :string, null: false)
      add(:mission_id, :string, null: false)
      add(:lifecycle_state, :string, null: false)
      add(:phase, :string, null: false)
      add(:trigger_kind, :string, null: false)
      add(:fleet_planning_policy_id, :string, null: false)
      add(:fleet_planning_policy_version, :integer, null: false)
      add(:algorithm_key, :string, null: false)
      add(:algorithm_version, :integer, null: false)
      add(:horizon_start, :utc_datetime_usec, null: false)
      add(:horizon_end, :utc_datetime_usec, null: false)
      add(:source_fleet_planning_run_id, :string)
      add(:source_contact_plan_id, :string)
      add(:source_contact_plan_version, :integer)
      add(:candidate_contact_plan_id, :string)
      add(:candidate_contact_plan_version, :integer)
      add(:input_document, :map, null: false, default: %{})
      add(:progress_document, :map, null: false, default: %{})
      add(:result_summary_document, :map, null: false, default: %{})
      add(:failure_document, :map, null: false, default: %{})
      add(:trigger_actor_document, :map, null: false)
      add(:triggered_by, :string, null: false)
      add(:started_at, :utc_datetime_usec)
      add(:completed_at, :utc_datetime_usec)

      timestamps(type: :utc_datetime_usec)
    end

    create(
      index(
        :fleet_planning_runs,
        [:organization_id, :mission_id, :inserted_at],
        name: :fleet_planning_runs_mission_idx
      )
    )

    create(
      index(
        :fleet_planning_runs,
        [:organization_id, :mission_id, :lifecycle_state, :phase],
        name: :fleet_planning_runs_progress_idx
      )
    )

    create(
      constraint(:fleet_planning_runs, :fleet_planning_runs_versions_positive,
        check:
          "fleet_planning_policy_version > 0 AND algorithm_version > 0 AND " <>
            "(source_contact_plan_version IS NULL OR source_contact_plan_version > 0) AND " <>
            "(candidate_contact_plan_version IS NULL OR candidate_contact_plan_version > 0)"
      )
    )

    create(
      constraint(:fleet_planning_runs, :fleet_planning_runs_horizon_check,
        check: "horizon_start < horizon_end"
      )
    )

    create(
      constraint(:fleet_planning_runs, :fleet_planning_runs_state_check,
        check:
          "lifecycle_state IN ('queued', 'running', 'completed', 'partial', 'failed', 'canceled')"
      )
    )

    create(
      constraint(:fleet_planning_runs, :fleet_planning_runs_phase_check,
        check:
          "phase IN ('queued', 'materializing', 'searching', 'optimizing', " <>
            "'materializing_plan', 'finished')"
      )
    )

    create(
      constraint(:fleet_planning_runs, :fleet_planning_runs_trigger_check,
        check: "trigger_kind IN ('manual', 'scheduled', 'repair')"
      )
    )

    create(
      constraint(:fleet_planning_runs, :fleet_planning_runs_source_binding_check,
        check:
          "(trigger_kind <> 'repair') OR " <>
            "(source_fleet_planning_run_id IS NOT NULL AND source_contact_plan_id IS NOT NULL " <>
            "AND source_contact_plan_version IS NOT NULL)"
      )
    )

    create(
      constraint(:fleet_planning_runs, :fleet_planning_runs_candidate_binding_check,
        check: "(candidate_contact_plan_id IS NULL) = (candidate_contact_plan_version IS NULL)"
      )
    )

    execute("""
    ALTER TABLE fleet_planning_runs
    ADD CONSTRAINT fleet_planning_runs_policy_version_fk
    FOREIGN KEY (
      organization_id, mission_id, fleet_planning_policy_id, fleet_planning_policy_version
    )
    REFERENCES fleet_planning_policy_versions (
      organization_id, mission_id, fleet_planning_policy_id, version
    )
    """)

    execute("""
    ALTER TABLE fleet_planning_runs
    ADD CONSTRAINT fleet_planning_runs_source_run_fk
    FOREIGN KEY (source_fleet_planning_run_id)
    REFERENCES fleet_planning_runs (fleet_planning_run_id)
    """)

    execute("""
    ALTER TABLE fleet_planning_runs
    ADD CONSTRAINT fleet_planning_runs_source_plan_fk
    FOREIGN KEY (
      organization_id, mission_id, source_contact_plan_id, source_contact_plan_version
    )
    REFERENCES contact_plan_versions (
      organization_id, mission_id, contact_plan_id, version
    )
    """)

    execute("""
    ALTER TABLE fleet_planning_runs
    ADD CONSTRAINT fleet_planning_runs_candidate_plan_fk
    FOREIGN KEY (
      organization_id, mission_id, candidate_contact_plan_id, candidate_contact_plan_version
    )
    REFERENCES contact_plan_versions (
      organization_id, mission_id, contact_plan_id, version
    )
    """)

    create table(:fleet_planning_run_requirement_refs, primary_key: false) do
      add(:fleet_planning_run_requirement_ref_id, :string, primary_key: true)
      add(:fleet_planning_run_id, :string, null: false)
      add(:organization_id, :string, null: false)
      add(:mission_id, :string, null: false)
      add(:contact_requirement_id, :string, null: false)
      add(:contact_requirement_version, :integer, null: false)
      add(:contact_planning_run_id, :string)
      add(:input_state, :string, null: false)
      add(:result_state, :string, null: false)
      add(:explanation_document, :map, null: false, default: %{})

      timestamps(type: :utc_datetime_usec)
    end

    create(
      unique_index(
        :fleet_planning_run_requirement_refs,
        [:fleet_planning_run_id, :contact_requirement_id, :contact_requirement_version],
        name: :fleet_planning_run_requirement_refs_input_uniq
      )
    )

    create(
      index(
        :fleet_planning_run_requirement_refs,
        [:organization_id, :mission_id, :input_state, :result_state],
        name: :fleet_planning_run_requirement_refs_progress_idx
      )
    )

    create(
      constraint(
        :fleet_planning_run_requirement_refs,
        :fleet_planning_run_requirement_refs_version_positive,
        check: "contact_requirement_version > 0"
      )
    )

    create(
      constraint(
        :fleet_planning_run_requirement_refs,
        :fleet_planning_run_requirement_refs_input_state_check,
        check: "input_state IN ('pending', 'searching', 'searched', 'failed')"
      )
    )

    create(
      constraint(
        :fleet_planning_run_requirement_refs,
        :fleet_planning_run_requirement_refs_result_state_check,
        check: "result_state IN ('pending', 'satisfied', 'partial', 'unsatisfied', 'failed')"
      )
    )

    execute("""
    ALTER TABLE fleet_planning_run_requirement_refs
    ADD CONSTRAINT fleet_planning_run_requirement_refs_run_fk
    FOREIGN KEY (fleet_planning_run_id)
    REFERENCES fleet_planning_runs (fleet_planning_run_id)
    """)

    execute("""
    ALTER TABLE fleet_planning_run_requirement_refs
    ADD CONSTRAINT fleet_planning_run_requirement_refs_requirement_fk
    FOREIGN KEY (
      organization_id, mission_id, contact_requirement_id, contact_requirement_version
    )
    REFERENCES contact_requirement_versions (
      organization_id, mission_id, contact_requirement_id, version
    )
    """)

    execute("""
    ALTER TABLE fleet_planning_run_requirement_refs
    ADD CONSTRAINT fleet_planning_run_requirement_refs_planning_run_fk
    FOREIGN KEY (contact_planning_run_id)
    REFERENCES contact_planning_runs (contact_planning_run_id)
    """)

    create table(:fleet_planning_decisions, primary_key: false) do
      add(:fleet_planning_decision_id, :string, primary_key: true)
      add(:fleet_planning_run_id, :string, null: false)
      add(:organization_id, :string, null: false)
      add(:mission_id, :string, null: false)
      add(:contact_opportunity_snapshot_id, :string, null: false)
      add(:disposition, :string, null: false)
      add(:score, :bigint, null: false)
      add(:rank, :integer)
      add(:hard_constraint_document, :map, null: false, default: %{})
      add(:score_document, :map, null: false, default: %{})
      add(:explanation_document, :map, null: false, default: %{})

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create(
      unique_index(
        :fleet_planning_decisions,
        [:fleet_planning_run_id, :contact_opportunity_snapshot_id],
        name: :fleet_planning_decisions_snapshot_uniq
      )
    )

    create(
      index(
        :fleet_planning_decisions,
        [:organization_id, :mission_id, :disposition, :score],
        name: :fleet_planning_decisions_review_idx
      )
    )

    create(
      constraint(:fleet_planning_decisions, :fleet_planning_decisions_rank_positive,
        check: "rank IS NULL OR rank > 0"
      )
    )

    create(
      constraint(:fleet_planning_decisions, :fleet_planning_decisions_disposition_check,
        check: "disposition IN ('selected', 'displaced', 'ineligible', 'locked')"
      )
    )

    execute("""
    ALTER TABLE fleet_planning_decisions
    ADD CONSTRAINT fleet_planning_decisions_run_fk
    FOREIGN KEY (fleet_planning_run_id)
    REFERENCES fleet_planning_runs (fleet_planning_run_id)
    """)

    execute("""
    ALTER TABLE fleet_planning_decisions
    ADD CONSTRAINT fleet_planning_decisions_snapshot_fk
    FOREIGN KEY (contact_opportunity_snapshot_id)
    REFERENCES contact_opportunity_snapshots (contact_opportunity_snapshot_id)
    """)
  end

  def down do
    drop(table(:fleet_planning_decisions))
    drop(table(:fleet_planning_run_requirement_refs))
    drop(table(:fleet_planning_runs))
  end
end
