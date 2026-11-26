defmodule Cadence.Repo.Migrations.ApprovalCommentOptional do
  @moduledoc """
  #521 (#313 K9, ux): a comment is optional on a change-set approve, required only to send back.
  An approve without one stores NULL in the review's `comment` and in the change set's activation
  decision `reason` (optional for approved, as Governance.DecisionRecord's rule). DDL only:
  existing rows keep their values, and no backfill. The append-only triggers refuse row UPDATE and
  DELETE, not this.

  `down` restores NOT NULL. It fails if an approval without a comment was recorded since.
  """
  use Ecto.Migration

  def up do
    execute("ALTER TABLE mission_config_reviews ALTER COLUMN comment DROP NOT NULL")
    execute("ALTER TABLE activation_decisions ALTER COLUMN reason DROP NOT NULL")
  end

  def down do
    execute("ALTER TABLE activation_decisions ALTER COLUMN reason SET NOT NULL")
    execute("ALTER TABLE mission_config_reviews ALTER COLUMN comment SET NOT NULL")
  end
end
