defmodule Cadence.Repo.Migrations.ChangeSetReviewRecord do
  use Ecto.Migration

  # #117 step 2 (P3; var/four-eyes-record-design.md §5; DECISIONS #112): a change set's review row
  # is a complete four-eyes record. Required fields, no pre-cutover form:
  # - subject_version, subject_digest: the set's version and the digest of the staged ops it
  #   decided (Configuration.ReviewRecord.digest/1; the apply asserts it);
  # - policy_document: the approval policy in force;
  # - separated_from: the actor ids the separation check compared (as #597's), '{}' when none;
  # - admin_mode: whether the decider acted as a platform admin;
  # - decision may be 'not_required' (a direct-path apply's own row), with no comment.
  # Revisions gain submitted_by, required (domain on #616).
  #
  # mission_config_reviews and mission_config_revisions are append-only by trigger (20261117160000),
  # so an existing row could never get these required fields. Landing order (domain, #112): this refuses BEFORE any DDL while the
  # table has rows. The remedy is a dev reset or the reset's designed purge, never a
  # trigger-disabled DELETE.
  def up do
    execute(guard_sql())

    alter table(:mission_config_reviews) do
      add(:subject_version, :integer, null: false)
      add(:subject_digest, :string, null: false)
      add(:policy_document, :map, null: false)
      add(:separated_from, {:array, :string}, null: false, default: [])
      add(:admin_mode, :boolean, null: false)
    end

    alter table(:mission_config_revisions) do
      add(:submitted_by, :map, null: false)
    end

    execute("""
    ALTER TABLE mission_config_reviews
      DROP CONSTRAINT mission_config_reviews_comment_unless_approved,
      ADD CONSTRAINT mission_config_reviews_comment_unless_approved
        CHECK (comment IS NOT NULL OR decision IN ('approved', 'not_required')),
      ADD CONSTRAINT mission_config_reviews_decision_check
        CHECK (decision IN ('approved', 'sent_back', 'not_required')),
      ADD CONSTRAINT mission_config_reviews_subject_digest_check
        CHECK (subject_digest ~ '^[0-9a-f]{64}$')
    """)
  end

  @doc """
  The landing guard, inline so a migration replay never depends on app code (api-ops on #616). Its
  test loads this file and runs exactly this SQL.
  """
  def guard_sql do
    """
    DO $$
    DECLARE reviews bigint; revisions bigint;
    BEGIN
      SELECT count(*) INTO reviews FROM mission_config_reviews;
      SELECT count(*) INTO revisions FROM mission_config_revisions;
      IF reviews > 0 OR revisions > 0 THEN
        RAISE EXCEPTION 'mission_config_reviews has % row(s), mission_config_revisions has % row(s): #117 step 2 adds required fields an append-only row can''t get. Remedy: a dev reset, or the reset''s designed decision-record purge, then run again (domain, DECISIONS #112). Never a trigger-disabled DELETE.', reviews, revisions;
      END IF;
    END $$;
    """
  end

  def down do
    execute("""
    ALTER TABLE mission_config_reviews
      DROP CONSTRAINT mission_config_reviews_subject_digest_check,
      DROP CONSTRAINT mission_config_reviews_decision_check,
      DROP CONSTRAINT mission_config_reviews_comment_unless_approved,
      ADD CONSTRAINT mission_config_reviews_comment_unless_approved
        CHECK (comment IS NOT NULL OR decision = 'approved')
    """)

    alter table(:mission_config_revisions) do
      remove(:submitted_by)
    end

    alter table(:mission_config_reviews) do
      remove(:admin_mode)
      remove(:separated_from)
      remove(:policy_document)
      remove(:subject_digest)
      remove(:subject_version)
    end
  end
end
