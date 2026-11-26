defmodule Cadence.Repo.Migrations.ApprovalReasonChecks do
  @moduledoc """
  #521 follow-up (ca-security): the table holds the rule the code holds. A change-set review's
  `comment` and an activation decision's `reason` may be NULL only on an approval; a send back,
  rejection or withdrawal always has one. Every existing row already satisfies it: both columns
  were NOT NULL until #521, and since then only approvals write NULL.
  """
  use Ecto.Migration

  def up do
    execute("""
    ALTER TABLE mission_config_reviews
      ADD CONSTRAINT mission_config_reviews_comment_unless_approved
      CHECK (comment IS NOT NULL OR decision = 'approved')
    """)

    execute("""
    ALTER TABLE activation_decisions
      ADD CONSTRAINT activation_decisions_reason_unless_approved
      CHECK (reason IS NOT NULL OR decision = 'approved')
    """)
  end

  def down do
    execute(
      "ALTER TABLE activation_decisions DROP CONSTRAINT activation_decisions_reason_unless_approved"
    )

    execute(
      "ALTER TABLE mission_config_reviews DROP CONSTRAINT mission_config_reviews_comment_unless_approved"
    )
  end
end
