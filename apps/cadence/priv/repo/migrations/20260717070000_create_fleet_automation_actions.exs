defmodule Cadence.Repo.Migrations.CreateFleetAutomationActions do
  use Ecto.Migration

  def up do
    create table(:fleet_automation_actions, primary_key: false) do
      add(:fleet_automation_action_id, :string, primary_key: true)
      add(:idempotency_key, :string, null: false)
      add(:organization_id, :string, null: false)
      add(:mission_id, :string, null: false)
      add(:automation_grant_id, :string, null: false)
      add(:automation_grant_content_sha256, :string, null: false)
      add(:service_identity_id, :string, null: false)
      add(:fleet_planning_run_id, :string, null: false)
      add(:contact_plan_id, :string)
      add(:contact_plan_version, :integer)
      add(:action, :string, null: false)
      add(:lifecycle_state, :string, null: false)
      add(:attempt_count, :integer, null: false, default: 1)
      add(:evidence_document, :map, null: false, default: %{})
      add(:result_document, :map, null: false, default: %{})
      add(:error_document, :map, null: false, default: %{})
      add(:started_at, :utc_datetime_usec, null: false)
      add(:completed_at, :utc_datetime_usec)

      timestamps(type: :utc_datetime_usec)
    end

    create(
      unique_index(:fleet_automation_actions, [:idempotency_key],
        name: :fleet_automation_actions_idempotency_idx
      )
    )

    create(
      index(
        :fleet_automation_actions,
        [:organization_id, :mission_id, :fleet_planning_run_id, :action],
        name: :fleet_automation_actions_run_idx
      )
    )

    create(
      constraint(:fleet_automation_actions, :fleet_automation_actions_state_check,
        check: "lifecycle_state IN ('running', 'succeeded', 'failed', 'skipped')"
      )
    )

    create(
      constraint(:fleet_automation_actions, :fleet_automation_actions_action_check,
        check: "action IN ('plan', 'repair', 'submit', 'approve', 'execute')"
      )
    )

    create(
      constraint(:fleet_automation_actions, :fleet_automation_actions_plan_binding_check,
        check: "(contact_plan_id IS NULL) = (contact_plan_version IS NULL)"
      )
    )

    create(
      constraint(:fleet_automation_actions, :fleet_automation_actions_attempt_count_check,
        check: "attempt_count > 0"
      )
    )

    execute("""
    ALTER TABLE fleet_automation_actions
    ADD CONSTRAINT fleet_automation_actions_grant_fk
    FOREIGN KEY (automation_grant_id)
    REFERENCES automation_grants (automation_grant_id)
    """)

    execute("""
    ALTER TABLE fleet_automation_actions
    ADD CONSTRAINT fleet_automation_actions_run_fk
    FOREIGN KEY (fleet_planning_run_id)
    REFERENCES fleet_planning_runs (fleet_planning_run_id)
    """)

    execute("""
    ALTER TABLE fleet_automation_actions
    ADD CONSTRAINT fleet_automation_actions_plan_fk
    FOREIGN KEY (organization_id, mission_id, contact_plan_id, contact_plan_version)
    REFERENCES contact_plan_versions (
      organization_id, mission_id, contact_plan_id, version
    )
    """)
  end

  def down do
    drop(table(:fleet_automation_actions))
  end
end
