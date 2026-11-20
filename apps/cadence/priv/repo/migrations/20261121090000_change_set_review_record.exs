defmodule Cadence.Repo.Migrations.ChangeSetReviewRecord do
  use Ecto.Migration

  alias Cadence.Configuration.ReviewRecord

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
    execute(ReviewRecord.landing_guard_sql())

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
