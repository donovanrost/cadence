defmodule Cadence.Repo.Migrations.CommandApprovalRecord do
  use Ecto.Migration

  # #117 step 4b (P3; var/four-eyes-record-design.md §5; DECISIONS #112): a command approval row is a
  # complete four-eyes record. These fields are required:
  # - subject_digest: the request's review token at decision (a group member's own);
  # - separated_from: exactly the actor ids the separation check was given ('{}' when none ran);
  # - admin_mode: whether the decider acted as a platform admin;
  # - decision may be 'not_required': a request released without a second GO (its release's own row).
  #
  # command_approvals is append-only by trigger (20261117160000) and the new columns are NOT NULL
  # with no default, so this fails on a database that has rows: drop and reseed the dev database
  # (docs/TEAM.md, dev data is disposable).
  def up do
    alter table(:command_approvals) do
      add(:subject_digest, :string, null: false)
      add(:separated_from, {:array, :string}, null: false, default: [])
      add(:admin_mode, :boolean, null: false)
    end

    execute("""
    ALTER TABLE command_approvals
      ADD CONSTRAINT command_approvals_decision_check
        CHECK (decision IN ('approved', 'rejected', 'not_required')),
      ADD CONSTRAINT command_approvals_subject_digest_check
        CHECK (subject_digest ~ '^[0-9a-f]{64}$')
    """)

    # ApprovalDecisions.decisions/2 pages an organization's rows newest first.
    create(
      index(:command_approvals, [:organization_id, "decided_at DESC", "command_approval_id DESC"])
    )
  end

  def down do
    drop(
      index(:command_approvals, [:organization_id, "decided_at DESC", "command_approval_id DESC"])
    )

    execute("""
    ALTER TABLE command_approvals
      DROP CONSTRAINT command_approvals_subject_digest_check,
      DROP CONSTRAINT command_approvals_decision_check
    """)

    alter table(:command_approvals) do
      remove(:admin_mode)
      remove(:separated_from)
      remove(:subject_digest)
    end
  end
end
