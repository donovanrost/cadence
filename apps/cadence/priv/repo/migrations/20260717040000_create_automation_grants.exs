defmodule Cadence.Repo.Migrations.CreateAutomationGrants do
  use Ecto.Migration

  def up do
    create table(:automation_grants, primary_key: false) do
      add(:automation_grant_id, :string, primary_key: true)
      add(:organization_id, :string, null: false)
      add(:mission_id, :string, null: false)
      add(:service_identity_id, :string, null: false)
      add(:fleet_planning_policy_id, :string, null: false)
      add(:fleet_planning_policy_version, :integer, null: false)
      add(:allowed_actions, {:array, :string}, null: false)
      add(:maximum_horizon_seconds, :integer, null: false)
      add(:maximum_contacts, :integer, null: false)
      add(:maximum_estimated_cost_micros, :bigint)
      add(:currency, :string)
      add(:maximum_execution_concurrency, :integer, null: false)
      add(:valid_from, :utc_datetime_usec, null: false)
      add(:valid_until, :utc_datetime_usec, null: false)
      add(:lifecycle_state, :string, null: false)
      add(:approved_by, :string, null: false)
      add(:approved_at, :utc_datetime_usec, null: false)
      add(:approval_reason, :text, null: false)
      add(:content_sha256, :string, null: false)
      add(:revoked_by, :string)
      add(:revoked_at, :utc_datetime_usec)
      add(:revocation_reason, :text, null: false, default: "")

      timestamps(type: :utc_datetime_usec)
    end

    create(
      unique_index(
        :automation_grants,
        [:organization_id, :mission_id, :service_identity_id],
        name: :automation_grants_one_active_per_service_idx,
        where: "lifecycle_state = 'active'"
      )
    )

    create(
      index(
        :automation_grants,
        [:organization_id, :mission_id, :lifecycle_state, :valid_until],
        name: :automation_grants_mission_state_idx
      )
    )

    create(
      constraint(:automation_grants, :automation_grants_policy_version_positive,
        check: "fleet_planning_policy_version > 0"
      )
    )

    create(
      constraint(:automation_grants, :automation_grants_bounds_positive,
        check:
          "maximum_horizon_seconds > 0 AND maximum_contacts > 0 AND " <>
            "maximum_execution_concurrency > 0 AND " <>
            "(maximum_estimated_cost_micros IS NULL OR maximum_estimated_cost_micros >= 0)"
      )
    )

    create(
      constraint(:automation_grants, :automation_grants_validity_check,
        check: "valid_from < valid_until"
      )
    )

    create(
      constraint(:automation_grants, :automation_grants_state_check,
        check: "lifecycle_state IN ('active', 'revoked')"
      )
    )

    create(
      constraint(:automation_grants, :automation_grants_cost_currency_check,
        check: "(maximum_estimated_cost_micros IS NULL) = (currency IS NULL)"
      )
    )

    create(
      constraint(:automation_grants, :automation_grants_revocation_shape,
        check:
          "(lifecycle_state = 'active' AND revoked_by IS NULL AND revoked_at IS NULL AND " <>
            "revocation_reason = '') OR " <>
            "(lifecycle_state = 'revoked' AND revoked_by IS NOT NULL AND revoked_at IS NOT NULL " <>
            "AND revocation_reason <> '')"
      )
    )

    execute("""
    ALTER TABLE automation_grants
    ADD CONSTRAINT automation_grants_mission_fk
    FOREIGN KEY (organization_id, mission_id)
    REFERENCES missions (organization_id, mission_id)
    """)

    execute("""
    ALTER TABLE automation_grants
    ADD CONSTRAINT automation_grants_service_identity_fk
    FOREIGN KEY (service_identity_id)
    REFERENCES service_identities (service_identity_id)
    """)

    execute("""
    ALTER TABLE automation_grants
    ADD CONSTRAINT automation_grants_policy_version_fk
    FOREIGN KEY (
      organization_id, mission_id, fleet_planning_policy_id, fleet_planning_policy_version
    )
    REFERENCES fleet_planning_policy_versions (
      organization_id, mission_id, fleet_planning_policy_id, version
    )
    """)
  end

  def down do
    drop(table(:automation_grants))
  end
end
