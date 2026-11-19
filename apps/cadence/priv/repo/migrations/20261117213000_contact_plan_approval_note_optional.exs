defmodule Cadence.Repo.Migrations.ContactPlanApprovalNoteOptional do
  use Ecto.Migration

  # U76 (lead 11-17; P3: a blank note is none): an APPROVAL's note is optional and stored as a
  # real NULL when absent; a rejection still requires its reason (enforced in
  # ContactPlanning.ContactPlanApprovals). Additive: existing rows keep their text. Small table,
  # plain DDL in the migration's transaction, run at a restart. P3's append-only row triggers
  # don't block DDL.
  def up do
    alter table(:contact_plan_approvals) do
      modify(:reason, :text, null: true, from: {:text, null: false})
    end
  end

  # Restores NOT NULL only when every approval has a note; otherwise refuses, naming why.
  def down do
    execute("""
    DO $$
    BEGIN
      IF EXISTS (SELECT 1 FROM contact_plan_approvals WHERE reason IS NULL) THEN
        RAISE EXCEPTION 'contact_plan_approvals has approvals without a note (an approver may leave none since U76); keep them, or give each a note, before restoring NOT NULL';
      END IF;
    END
    $$;
    """)

    alter table(:contact_plan_approvals) do
      modify(:reason, :text, null: false, from: {:text, null: true})
    end
  end
end
