defmodule Cadence.Repo.Migrations.CreateFleetPlanningPolicies do
  use Ecto.Migration

  def up do
    create table(:fleet_planning_policies, primary_key: false) do
      add(:fleet_planning_policy_id, :string, primary_key: true)
      add(:organization_id, :string, null: false)
      add(:mission_id, :string, null: false)
      add(:current_version, :integer, null: false)
      add(:active_version, :integer)
      add(:lifecycle_state, :string, null: false)
      add(:created_by, :string, null: false)
      add(:lifecycle_changed_by, :string, null: false)
      add(:lifecycle_changed_at, :utc_datetime_usec, null: false)
      add(:lifecycle_reason, :text, null: false, default: "")

      timestamps(type: :utc_datetime_usec)
    end

    create(
      unique_index(:fleet_planning_policies, [:organization_id, :mission_id],
        name: :fleet_planning_policies_mission_uniq
      )
    )

    create(
      unique_index(
        :fleet_planning_policies,
        [:organization_id, :mission_id, :fleet_planning_policy_id],
        name: :fleet_planning_policies_scope_idx
      )
    )

    create(
      constraint(:fleet_planning_policies, :fleet_planning_policies_versions_positive,
        check: "current_version > 0 AND (active_version IS NULL OR active_version > 0)"
      )
    )

    create(
      constraint(:fleet_planning_policies, :fleet_planning_policies_lifecycle_state_check,
        check: "lifecycle_state IN ('draft', 'active', 'retired')"
      )
    )

    execute("""
    ALTER TABLE fleet_planning_policies
    ADD CONSTRAINT fleet_planning_policies_scope_uniq
    UNIQUE USING INDEX fleet_planning_policies_scope_idx
    """)

    execute("""
    ALTER TABLE fleet_planning_policies
    ADD CONSTRAINT fleet_planning_policies_mission_fk
    FOREIGN KEY (organization_id, mission_id)
    REFERENCES missions (organization_id, mission_id)
    """)

    create table(:fleet_planning_policy_versions, primary_key: false) do
      add(:fleet_planning_policy_version_id, :string, primary_key: true)
      add(:fleet_planning_policy_id, :string, null: false)
      add(:organization_id, :string, null: false)
      add(:mission_id, :string, null: false)
      add(:version, :integer, null: false)
      add(:horizon_document, :map, null: false)
      add(:scoring_document, :map, null: false)
      add(:resource_policy_document, :map, null: false)
      add(:budget_quota_document, :map, null: false)
      add(:redundancy_document, :map, null: false)
      add(:automation_repair_document, :map, null: false)
      add(:content_sha256, :string, null: false)
      add(:created_by, :string, null: false)
      add(:created_at, :utc_datetime_usec, null: false)
    end

    create(
      unique_index(
        :fleet_planning_policy_versions,
        [:organization_id, :mission_id, :fleet_planning_policy_id, :version],
        name: :fleet_planning_policy_versions_scope_idx
      )
    )

    create(
      constraint(
        :fleet_planning_policy_versions,
        :fleet_planning_policy_versions_version_positive,
        check: "version > 0"
      )
    )

    execute("""
    ALTER TABLE fleet_planning_policy_versions
    ADD CONSTRAINT fleet_planning_policy_versions_scope_uniq
    UNIQUE USING INDEX fleet_planning_policy_versions_scope_idx
    """)

    execute("""
    ALTER TABLE fleet_planning_policy_versions
    ADD CONSTRAINT fleet_planning_policy_versions_policy_fk
    FOREIGN KEY (organization_id, mission_id, fleet_planning_policy_id)
    REFERENCES fleet_planning_policies (
      organization_id, mission_id, fleet_planning_policy_id
    )
    """)

    execute("""
    ALTER TABLE fleet_planning_policies
    ADD CONSTRAINT fleet_planning_policies_current_version_fk
    FOREIGN KEY (organization_id, mission_id, fleet_planning_policy_id, current_version)
    REFERENCES fleet_planning_policy_versions (
      organization_id, mission_id, fleet_planning_policy_id, version
    )
    DEFERRABLE INITIALLY DEFERRED
    """)

    execute("""
    ALTER TABLE fleet_planning_policies
    ADD CONSTRAINT fleet_planning_policies_active_version_fk
    FOREIGN KEY (organization_id, mission_id, fleet_planning_policy_id, active_version)
    REFERENCES fleet_planning_policy_versions (
      organization_id, mission_id, fleet_planning_policy_id, version
    )
    DEFERRABLE INITIALLY DEFERRED
    """)

    create table(:fleet_planning_policy_approvals, primary_key: false) do
      add(:fleet_planning_policy_approval_id, :string, primary_key: true)
      add(:organization_id, :string, null: false)
      add(:mission_id, :string, null: false)
      add(:fleet_planning_policy_id, :string, null: false)
      add(:fleet_planning_policy_version, :integer, null: false)
      add(:decision, :string, null: false)
      add(:content_sha256, :string, null: false)
      add(:reason, :text, null: false)
      add(:actor_user_id, :string, null: false)
      add(:actor_document, :map, null: false)
      add(:decided_at, :utc_datetime_usec, null: false)

      timestamps(updated_at: false, type: :utc_datetime_usec)
    end

    create(
      unique_index(
        :fleet_planning_policy_approvals,
        [
          :organization_id,
          :mission_id,
          :fleet_planning_policy_id,
          :fleet_planning_policy_version
        ],
        name: :fleet_planning_policy_approvals_version_uniq
      )
    )

    create(
      constraint(
        :fleet_planning_policy_approvals,
        :fleet_planning_policy_approvals_version_positive,
        check: "fleet_planning_policy_version > 0"
      )
    )

    create(
      constraint(
        :fleet_planning_policy_approvals,
        :fleet_planning_policy_approvals_decision_check,
        check: "decision IN ('approved', 'rejected')"
      )
    )

    execute("""
    ALTER TABLE fleet_planning_policy_approvals
    ADD CONSTRAINT fleet_planning_policy_approvals_version_fk
    FOREIGN KEY (
      organization_id, mission_id, fleet_planning_policy_id, fleet_planning_policy_version
    )
    REFERENCES fleet_planning_policy_versions (
      organization_id, mission_id, fleet_planning_policy_id, version
    )
    """)
  end

  def down do
    drop(table(:fleet_planning_policy_approvals))

    execute("""
    ALTER TABLE fleet_planning_policies
    DROP CONSTRAINT IF EXISTS fleet_planning_policies_active_version_fk
    """)

    execute("""
    ALTER TABLE fleet_planning_policies
    DROP CONSTRAINT IF EXISTS fleet_planning_policies_current_version_fk
    """)

    drop(table(:fleet_planning_policy_versions))
    drop(table(:fleet_planning_policies))
  end
end
