defmodule Cadence.Repo.Migrations.AutomationGrantProposals do
  use Ecto.Migration

  # #283 (director 11-19, ux U105): under 'independent' an automation grant is proposed and
  # authorizes nothing until a second org admin approves it. DECISIONS #112: no backfill; the dev
  # reset recreates grants through the product, and the content hash's layout changes (#108
  # checklist), so a row from before this is refused at use, not trusted.
  #
  # - automation_grants: the projection row gains the proposal, rejection and withdrawal fields;
  #   validity is `validity_seconds` until approval sets valid_from/valid_until.
  # - automation_grant_decisions: one append-only row per act, built through
  #   Governance.DecisionRecord and listed in its @tables (#116's trigger, below), with the
  #   actor, time, the hash acted on and the approval policy in force (#226).
  # - automation_grant_operations: approve, reject and narrow replay by operation_id (#267's).
  def up do
    alter table(:automation_grants) do
      modify(:valid_from, :utc_datetime_usec, null: true)
      modify(:valid_until, :utc_datetime_usec, null: true)
      modify(:approved_by, :string, null: true)
      modify(:approved_at, :utc_datetime_usec, null: true)
      add(:validity_seconds, :integer)
      add(:proposed_by, :string)
      add(:proposed_at, :utc_datetime_usec)
      add(:proposal_expires_at, :utc_datetime_usec)
      add(:rejected_by, :string)
      add(:rejected_at, :utc_datetime_usec)
      add(:rejection_reason, :string)
      add(:withdrawn_by, :string)
      add(:withdrawn_at, :utc_datetime_usec)
      add(:replaces_grant_id, :string)
      add(:approval_policy, :map)
    end

    # The state and its evidence, as AutomationGrant's shape checks (#283). NOT VALID: a row from
    # before #283 stays readable (and is refused at use by the hash guard); every new or changed
    # row is checked. The dev reset recreates grants (DECISIONS #112).
    drop(constraint(:automation_grants, :automation_grants_state_check))
    drop(constraint(:automation_grants, :automation_grants_revocation_shape))
    drop(constraint(:automation_grants, :automation_grants_validity_check))

    create(
      constraint(:automation_grants, :automation_grants_state_check,
        check: "lifecycle_state IN ('proposed', 'active', 'rejected', 'revoked', 'withdrawn')"
      )
    )

    create(
      constraint(:automation_grants, :automation_grants_validity_check,
        check:
          "(valid_from IS NULL AND valid_until IS NULL) OR " <>
            "(valid_from IS NOT NULL AND valid_until IS NOT NULL AND valid_from < valid_until)"
      )
    )

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
          OR (lifecycle_state = 'revoked' AND approved_by IS NOT NULL AND valid_from IS NOT NULL
            AND revoked_by IS NOT NULL AND revoked_at IS NOT NULL)
          OR (lifecycle_state = 'rejected' AND approved_by IS NULL AND rejected_by IS NOT NULL
            AND rejected_at IS NOT NULL AND coalesce(trim(rejection_reason), '') <> '')
          OR (lifecycle_state = 'withdrawn' AND approved_by IS NULL AND withdrawn_by IS NOT NULL
            AND withdrawn_at IS NOT NULL)
        )
        """,
        validate: false
      )
    )

    create(
      index(:automation_grants, [:organization_id, :mission_id, :lifecycle_state],
        name: :automation_grants_state_index
      )
    )

    create(
      index(:automation_grants, [:organization_id, :mission_id, :replaces_grant_id],
        name: :automation_grants_replaces_index
      )
    )

    # The columns mirror Governance.DecisionRecord (C&A's contract), which builds every row.
    create table(:automation_grant_decisions, primary_key: false) do
      add(:automation_grant_decision_id, :string, primary_key: true)
      add(:organization_id, :string, null: false)
      add(:mission_id, :string, null: false)
      add(:automation_grant_id, :string, null: false)
      add(:decision, :string, null: false)
      add(:actor_kind, :string, null: false)
      add(:actor_id, :string, null: false)
      add(:reason, :text)
      add(:decided_at, :utc_datetime_usec, null: false)
      add(:digest, :string)
      add(:previous_digest, :string)
      add(:policy_document, :map)
      add(:separated_from, {:array, :string}, null: false, default: [])
      add(:admin_mode, :boolean, null: false, default: false)
    end

    create(
      index(:automation_grant_decisions, [:organization_id, :mission_id, :automation_grant_id],
        name: :automation_grant_decisions_grant_index
      )
    )

    create(
      constraint(:automation_grant_decisions, :automation_grant_decisions_decision,
        check:
          "decision IN ('proposed', 'not_required', 'approved', 'rejected', 'revoked', 'narrowed', 'withdrawn')"
      )
    )

    execute("""
    CREATE TRIGGER automation_grant_decisions_append_only_rows
      BEFORE UPDATE OR DELETE ON automation_grant_decisions
      FOR EACH ROW EXECUTE FUNCTION cadence_decision_record_append_only();
    """)

    execute("""
    CREATE TRIGGER automation_grant_decisions_append_only_truncate
      BEFORE TRUNCATE ON automation_grant_decisions
      FOR EACH STATEMENT EXECUTE FUNCTION cadence_decision_record_append_only();
    """)

    create table(:automation_grant_operations, primary_key: false) do
      add(:automation_grant_operation_id, :string, primary_key: true)
      add(:organization_id, :string, null: false)
      add(:mission_id, :string, null: false)
      add(:operation_id, :string, null: false)
      add(:automation_grant_id, :string, null: false)
      add(:action, :string, null: false)
      add(:actor_id, :string, null: false)
      add(:request_sha256, :string, null: false)
      add(:response_status, :integer, null: false)
      add(:response_document, :map, null: false)
      add(:inserted_at, :utc_datetime_usec, null: false)
    end

    create(
      unique_index(
        :automation_grant_operations,
        [:organization_id, :mission_id, :operation_id],
        name: :automation_grant_operations_scope_index
      )
    )
  end

  def down do
    drop_if_exists(constraint(:automation_grants, :automation_grants_state_shape))
    drop_if_exists(constraint(:automation_grants, :automation_grants_state_check))
    drop_if_exists(constraint(:automation_grants, :automation_grants_validity_check))

    create(
      constraint(:automation_grants, :automation_grants_state_check,
        check: "lifecycle_state IN ('active', 'revoked')",
        validate: false
      )
    )

    create(
      constraint(:automation_grants, :automation_grants_validity_check,
        check: "valid_from < valid_until",
        validate: false
      )
    )

    create(
      constraint(:automation_grants, :automation_grants_revocation_shape,
        check:
          "(lifecycle_state = 'active' AND revoked_by IS NULL AND revoked_at IS NULL AND " <>
            "revocation_reason = '') OR " <>
            "(lifecycle_state = 'revoked' AND revoked_by IS NOT NULL AND revoked_at IS NOT NULL " <>
            "AND revocation_reason <> '')",
        validate: false
      )
    )

    drop(table(:automation_grant_operations))

    execute(
      "DROP TRIGGER IF EXISTS automation_grant_decisions_append_only_truncate ON automation_grant_decisions;"
    )

    execute(
      "DROP TRIGGER IF EXISTS automation_grant_decisions_append_only_rows ON automation_grant_decisions;"
    )

    drop(table(:automation_grant_decisions))

    drop(
      index(:automation_grants, [:organization_id, :mission_id, :replaces_grant_id],
        name: :automation_grants_replaces_index
      )
    )

    drop(
      index(:automation_grants, [:organization_id, :mission_id, :lifecycle_state],
        name: :automation_grants_state_index
      )
    )

    alter table(:automation_grants) do
      remove(:approval_policy)
      remove(:replaces_grant_id)
      remove(:withdrawn_at)
      remove(:withdrawn_by)
      remove(:rejection_reason)
      remove(:rejected_at)
      remove(:rejected_by)
      remove(:proposal_expires_at)
      remove(:proposed_at)
      remove(:proposed_by)
      remove(:validity_seconds)
    end
  end
end
