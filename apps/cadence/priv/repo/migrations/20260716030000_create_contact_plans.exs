defmodule Cadence.Repo.Migrations.CreateContactPlans do
  use Ecto.Migration

  def up do
    create table(:contact_plans, primary_key: false) do
      add(:contact_plan_id, :string, primary_key: true)
      add(:organization_id, :string, null: false)
      add(:mission_id, :string, null: false)
      add(:current_version, :integer, null: false)
      add(:lifecycle_state, :string, null: false)
      add(:created_by, :string, null: false)
      add(:lifecycle_changed_by, :string, null: false)
      add(:lifecycle_changed_at, :utc_datetime_usec, null: false)
      add(:lifecycle_reason, :text, null: false, default: "")
      add(:approved_version, :integer)
      add(:approved_at, :utc_datetime_usec)
      add(:approved_by, :string)

      timestamps(type: :utc_datetime_usec)
    end

    create(
      unique_index(:contact_plans, [:organization_id, :mission_id, :contact_plan_id],
        name: :contact_plans_scope_idx
      )
    )

    create(
      index(:contact_plans, [:organization_id, :mission_id, :lifecycle_state],
        name: :contact_plans_mission_state_idx
      )
    )

    create(
      constraint(:contact_plans, :contact_plans_versions_positive,
        check: "current_version > 0 AND (approved_version IS NULL OR approved_version > 0)"
      )
    )

    create(
      constraint(:contact_plans, :contact_plans_state_check,
        check:
          "lifecycle_state IN ('draft', 'pending_approval', 'approved', 'executing', " <>
            "'partially_reserved', 'reserved', 'failed', 'canceled', 'superseded')"
      )
    )

    create(
      constraint(:contact_plans, :contact_plans_approval_shape,
        check:
          "(approved_version IS NULL AND approved_at IS NULL AND approved_by IS NULL) OR " <>
            "(approved_version IS NOT NULL AND approved_at IS NOT NULL AND approved_by IS NOT NULL)"
      )
    )

    execute("""
    ALTER TABLE contact_plans
    ADD CONSTRAINT contact_plans_scope_uniq
    UNIQUE USING INDEX contact_plans_scope_idx
    """)

    execute("""
    ALTER TABLE contact_plans
    ADD CONSTRAINT contact_plans_mission_fk
    FOREIGN KEY (organization_id, mission_id)
    REFERENCES missions (organization_id, mission_id)
    """)

    create table(:contact_plan_versions, primary_key: false) do
      add(:contact_plan_version_id, :string, primary_key: true)
      add(:contact_plan_id, :string, null: false)
      add(:organization_id, :string, null: false)
      add(:mission_id, :string, null: false)
      add(:version, :integer, null: false)
      add(:requirement_refs_document, :map, null: false)
      add(:planning_run_refs_document, :map, null: false)
      add(:selected_snapshot_ids, {:array, :string}, null: false, default: [])
      add(:rejected_snapshot_ids, {:array, :string}, null: false, default: [])
      add(:coverage_document, :map, null: false)
      add(:conflict_document, :map, null: false)
      add(:unsatisfied_document, :map, null: false)
      add(:policy_snapshot_document, :map, null: false)
      add(:rationale, :text, null: false, default: "")
      add(:content_sha256, :string, null: false)
      add(:created_by, :string, null: false)
      add(:created_at, :utc_datetime_usec, null: false)
    end

    create(
      unique_index(
        :contact_plan_versions,
        [:organization_id, :mission_id, :contact_plan_id, :version],
        name: :contact_plan_versions_scope_idx
      )
    )

    create(
      constraint(:contact_plan_versions, :contact_plan_versions_positive, check: "version > 0")
    )

    execute("""
    ALTER TABLE contact_plan_versions
    ADD CONSTRAINT contact_plan_versions_scope_uniq
    UNIQUE USING INDEX contact_plan_versions_scope_idx
    """)

    execute("""
    ALTER TABLE contact_plan_versions
    ADD CONSTRAINT contact_plan_versions_plan_fk
    FOREIGN KEY (organization_id, mission_id, contact_plan_id)
    REFERENCES contact_plans (organization_id, mission_id, contact_plan_id)
    """)

    execute("""
    ALTER TABLE contact_plans
    ADD CONSTRAINT contact_plans_current_version_fk
    FOREIGN KEY (organization_id, mission_id, contact_plan_id, current_version)
    REFERENCES contact_plan_versions (organization_id, mission_id, contact_plan_id, version)
    DEFERRABLE INITIALLY DEFERRED
    """)

    execute("""
    ALTER TABLE contact_plans
    ADD CONSTRAINT contact_plans_approved_version_fk
    FOREIGN KEY (organization_id, mission_id, contact_plan_id, approved_version)
    REFERENCES contact_plan_versions (organization_id, mission_id, contact_plan_id, version)
    DEFERRABLE INITIALLY DEFERRED
    """)

    create table(:contact_plan_requirement_refs, primary_key: false) do
      add(:contact_plan_requirement_ref_id, :string, primary_key: true)
      add(:organization_id, :string, null: false)
      add(:mission_id, :string, null: false)
      add(:contact_plan_id, :string, null: false)
      add(:contact_plan_version, :integer, null: false)
      add(:contact_requirement_id, :string, null: false)
      add(:contact_requirement_version, :integer, null: false)
    end

    create(
      unique_index(
        :contact_plan_requirement_refs,
        [:contact_plan_id, :contact_plan_version, :contact_requirement_id],
        name: :contact_plan_requirement_refs_identity_idx
      )
    )

    execute("""
    ALTER TABLE contact_plan_requirement_refs
    ADD CONSTRAINT contact_plan_requirement_refs_plan_version_fk
    FOREIGN KEY (organization_id, mission_id, contact_plan_id, contact_plan_version)
    REFERENCES contact_plan_versions (organization_id, mission_id, contact_plan_id, version)
    """)

    execute("""
    ALTER TABLE contact_plan_requirement_refs
    ADD CONSTRAINT contact_plan_requirement_refs_requirement_version_fk
    FOREIGN KEY (
      organization_id, mission_id, contact_requirement_id, contact_requirement_version
    )
    REFERENCES contact_requirement_versions (
      organization_id, mission_id, contact_requirement_id, version
    )
    """)

    create table(:contact_plan_run_refs, primary_key: false) do
      add(:contact_plan_run_ref_id, :string, primary_key: true)
      add(:organization_id, :string, null: false)
      add(:mission_id, :string, null: false)
      add(:contact_plan_id, :string, null: false)
      add(:contact_plan_version, :integer, null: false)
      add(:contact_planning_run_id, :string, null: false)
    end

    create(
      unique_index(
        :contact_plan_run_refs,
        [:contact_plan_id, :contact_plan_version, :contact_planning_run_id],
        name: :contact_plan_run_refs_identity_idx
      )
    )

    execute("""
    ALTER TABLE contact_plan_run_refs
    ADD CONSTRAINT contact_plan_run_refs_plan_version_fk
    FOREIGN KEY (organization_id, mission_id, contact_plan_id, contact_plan_version)
    REFERENCES contact_plan_versions (organization_id, mission_id, contact_plan_id, version)
    """)

    execute("""
    ALTER TABLE contact_plan_run_refs
    ADD CONSTRAINT contact_plan_run_refs_run_fk
    FOREIGN KEY (contact_planning_run_id)
    REFERENCES contact_planning_runs (contact_planning_run_id)
    """)

    create table(:contact_plan_opportunity_refs, primary_key: false) do
      add(:contact_plan_opportunity_ref_id, :string, primary_key: true)
      add(:organization_id, :string, null: false)
      add(:mission_id, :string, null: false)
      add(:contact_plan_id, :string, null: false)
      add(:contact_plan_version, :integer, null: false)
      add(:contact_opportunity_snapshot_id, :string, null: false)
      add(:disposition, :string, null: false)
      add(:selection_order, :integer, null: false)
      add(:reason_document, :map, null: false, default: %{})
    end

    create(
      unique_index(
        :contact_plan_opportunity_refs,
        [:contact_plan_id, :contact_plan_version, :contact_opportunity_snapshot_id],
        name: :contact_plan_opportunity_refs_identity_idx
      )
    )

    create(
      constraint(:contact_plan_opportunity_refs, :contact_plan_opportunity_refs_disposition_check,
        check: "disposition IN ('selected', 'rejected')"
      )
    )

    create(
      constraint(:contact_plan_opportunity_refs, :contact_plan_opportunity_refs_order_check,
        check: "selection_order >= 0"
      )
    )

    execute("""
    ALTER TABLE contact_plan_opportunity_refs
    ADD CONSTRAINT contact_plan_opportunity_refs_plan_version_fk
    FOREIGN KEY (organization_id, mission_id, contact_plan_id, contact_plan_version)
    REFERENCES contact_plan_versions (organization_id, mission_id, contact_plan_id, version)
    """)

    execute("""
    ALTER TABLE contact_plan_opportunity_refs
    ADD CONSTRAINT contact_plan_opportunity_refs_snapshot_fk
    FOREIGN KEY (contact_opportunity_snapshot_id)
    REFERENCES contact_opportunity_snapshots (contact_opportunity_snapshot_id)
    """)

    create table(:contact_plan_approvals, primary_key: false) do
      add(:contact_plan_approval_id, :string, primary_key: true)
      add(:organization_id, :string, null: false)
      add(:mission_id, :string, null: false)
      add(:contact_plan_id, :string, null: false)
      add(:contact_plan_version, :integer, null: false)
      add(:decision, :string, null: false)
      add(:content_sha256, :string, null: false)
      add(:reason, :text, null: false)
      add(:actor_user_id, :string, null: false)
      add(:actor_document, :map, null: false)
      add(:decided_at, :utc_datetime_usec, null: false)

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create(
      unique_index(:contact_plan_approvals, [:contact_plan_id, :contact_plan_version],
        name: :contact_plan_approvals_version_idx
      )
    )

    create(
      constraint(:contact_plan_approvals, :contact_plan_approvals_decision_check,
        check: "decision IN ('approved', 'rejected')"
      )
    )

    execute("""
    ALTER TABLE contact_plan_approvals
    ADD CONSTRAINT contact_plan_approvals_plan_version_fk
    FOREIGN KEY (organization_id, mission_id, contact_plan_id, contact_plan_version)
    REFERENCES contact_plan_versions (organization_id, mission_id, contact_plan_id, version)
    """)
  end

  def down do
    execute("""
    ALTER TABLE contact_plans
    DROP CONSTRAINT IF EXISTS contact_plans_approved_version_fk
    """)

    execute("""
    ALTER TABLE contact_plans
    DROP CONSTRAINT IF EXISTS contact_plans_current_version_fk
    """)

    drop(table(:contact_plan_approvals))
    drop(table(:contact_plan_opportunity_refs))
    drop(table(:contact_plan_run_refs))
    drop(table(:contact_plan_requirement_refs))
    drop(table(:contact_plan_versions))
    drop(table(:contact_plans))
  end
end
