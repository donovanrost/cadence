defmodule Cadence.Repo.Migrations.CommandApprovalRecord do
  use Ecto.Migration

  # #117 step 4b (P3; var/four-eyes-record-design.md §5; DECISIONS #112): a command approval row is a
  # complete four-eyes record. These fields are required:
  # - subject_digest: the request's review token at decision (a group member's own);
  # - separated_from: exactly the actor ids the separation check was given ('{}' when none ran);
  # - admin_mode: whether the decider acted as a platform admin;
  # - decision may be 'not_required': a request released without a second GO (its release's own row).
  #
  # command_approvals is append-only by trigger (20261117160000), so an existing row could never get
  # the required fields. Landing order (domain, #112): this refuses BEFORE any DDL while the table has
  # rows. It lands only on a fresh database at a reset. The remedy is a dev reset, never a
  # trigger-disabled DELETE.
  def up do
    execute(guard_sql())

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
  end

  @doc """
  The landing guard, inline, so a replay never depends on app code (api-ops on #616). Its test loads
  this file and runs exactly this SQL.
  """
  def guard_sql do
    """
    DO $$
    DECLARE approvals bigint;
    BEGIN
      SELECT count(*) INTO approvals FROM command_approvals;
      IF approvals > 0 THEN
        RAISE EXCEPTION 'command_approvals has % row(s): #117 step 4b adds required fields an append-only row can''t get. Remedy: a dev reset, or the reset''s designed decision-record purge, then run again (domain, DECISIONS #112). Never a trigger-disabled DELETE.', approvals;
      END IF;
    END $$;
    """
  end

  def down do
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
