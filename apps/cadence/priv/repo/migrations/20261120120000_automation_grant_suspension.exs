defmodule Cadence.Repo.Migrations.AutomationGrantSuspension do
  use Ecto.Migration

  # #499 (director on #283, ca-security, api-ops 11-20): tightening a mission's approval setting
  # suspends its automation grants that went active on one approval, until a second approval
  # resumes them. A stored state, not a flag, so every use that checks 'active' refuses it.
  #
  # - automation_grants: lifecycle_state gains 'suspended', with who suspended it, when, and the
  #   settings revision that did; resumed_by/resumed_at record the resume. The state shape gains
  #   the suspended case. One live grant per service: the partial unique index covers 'active' and
  #   'suspended', so a new grant for the service means revoking or replacing the suspended one.
  # - automation_grant_decisions: the decision set gains 'suspended' and 'resumed' (C&A's
  #   DecisionRecord; the append-only trigger already covers the table).
  # No backfill: no grant is suspended before this.
  def up do
    alter table(:automation_grants) do
      add(:suspended_by, :string)
      add(:suspended_at, :utc_datetime_usec)
      add(:suspension_revision, :string)
      add(:suspension_level, :string)
      add(:resumed_by, :string)
      add(:resumed_at, :utc_datetime_usec)
    end

    drop(constraint(:automation_grants, :automation_grants_state_check))

    create(
      constraint(:automation_grants, :automation_grants_state_check,
        check:
          "lifecycle_state IN ('proposed', 'active', 'suspended', 'rejected', 'revoked', 'withdrawn')"
      )
    )

    drop(constraint(:automation_grants, :automation_grants_state_shape))

    create(
      constraint(:automation_grants, :automation_grants_state_shape,
        check: """
        proposed_by IS NOT NULL AND proposed_at IS NOT NULL AND proposal_expires_at IS NOT NULL
        AND validity_seconds > 0 AND (
          (lifecycle_state = 'proposed' AND approved_by IS NULL AND approved_at IS NULL
            AND valid_from IS NULL AND revoked_by IS NULL AND rejected_by IS NULL
            AND withdrawn_by IS NULL)
          OR (lifecycle_state = 'active' AND approved_by IS NOT NULL AND approved_at IS NOT NULL
            AND valid_from IS NOT NULL AND revoked_by IS NULL AND revoked_at IS NULL
            AND rejected_by IS NULL AND withdrawn_by IS NULL)
          OR (lifecycle_state = 'suspended' AND approved_by IS NOT NULL AND approved_at IS NOT NULL
            AND valid_from IS NOT NULL AND suspended_by IS NOT NULL AND suspended_at IS NOT NULL
            AND revoked_by IS NULL AND revoked_at IS NULL AND rejected_by IS NULL
            AND withdrawn_by IS NULL)
          OR (lifecycle_state = 'revoked' AND approved_by IS NOT NULL AND valid_from IS NOT NULL
            AND revoked_by IS NOT NULL AND revoked_at IS NOT NULL)
          OR (lifecycle_state = 'rejected' AND approved_by IS NULL AND rejected_by IS NOT NULL
            AND rejected_at IS NOT NULL AND coalesce(trim(rejection_reason), '') <> '')
          OR (lifecycle_state = 'withdrawn' AND approved_by IS NULL AND withdrawn_by IS NOT NULL
            AND withdrawn_at IS NOT NULL)
        )
        """
      )
    )

    drop(index(:automation_grants, [], name: :automation_grants_one_active_per_service_idx))

    create(
      unique_index(
        :automation_grants,
        [:organization_id, :mission_id, :service_identity_id],
        name: :automation_grants_one_active_per_service_idx,
        where: "lifecycle_state IN ('active', 'suspended')"
      )
    )

    drop(constraint(:automation_grant_decisions, :automation_grant_decisions_decision))

    create(
      constraint(:automation_grant_decisions, :automation_grant_decisions_decision,
        check:
          "decision IN ('proposed', 'not_required', 'approved', 'rejected', 'revoked', 'narrowed', " <>
            "'withdrawn', 'suspended', 'resumed')"
      )
    )
  end

  def down do
    drop(constraint(:automation_grant_decisions, :automation_grant_decisions_decision))

    create(
      constraint(:automation_grant_decisions, :automation_grant_decisions_decision,
        check:
          "decision IN ('proposed', 'not_required', 'approved', 'rejected', 'revoked', 'narrowed', 'withdrawn')"
      )
    )

    drop(index(:automation_grants, [], name: :automation_grants_one_active_per_service_idx))

    create(
      unique_index(
        :automation_grants,
        [:organization_id, :mission_id, :service_identity_id],
        name: :automation_grants_one_active_per_service_idx,
        where: "lifecycle_state = 'active'"
      )
    )

    drop(constraint(:automation_grants, :automation_grants_state_shape))
    drop(constraint(:automation_grants, :automation_grants_state_check))

    create(
      constraint(:automation_grants, :automation_grants_state_check,
        check: "lifecycle_state IN ('proposed', 'active', 'rejected', 'revoked', 'withdrawn')",
        validate: false
      )
    )

    alter table(:automation_grants) do
      remove(:suspended_by)
      remove(:suspended_at)
      remove(:suspension_revision)
      remove(:suspension_level)
      remove(:resumed_by)
      remove(:resumed_at)
    end
  end
end
