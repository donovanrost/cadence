defmodule Cadence.Repo.Migrations.GeneralizeContactPlanApprovalActors do
  use Ecto.Migration

  def up do
    rename(table(:contact_plan_approvals), :actor_user_id, to: :actor_id)

    alter table(:contact_plan_approvals) do
      add(:actor_kind, :string, null: false, default: "user")
      add(:automation_grant_id, :string)
      add(:automation_grant_content_sha256, :string)
    end

    create(
      constraint(:contact_plan_approvals, :contact_plan_approvals_actor_kind_check,
        check: "actor_kind IN ('user', 'service')"
      )
    )

    create(
      constraint(:contact_plan_approvals, :contact_plan_approvals_automation_shape,
        check:
          "(actor_kind = 'user' AND automation_grant_id IS NULL AND " <>
            "automation_grant_content_sha256 IS NULL) OR " <>
            "(actor_kind = 'service' AND automation_grant_id IS NOT NULL AND " <>
            "automation_grant_content_sha256 IS NOT NULL)"
      )
    )

    execute("""
    ALTER TABLE contact_plan_approvals
    ADD CONSTRAINT contact_plan_approvals_automation_grant_fk
    FOREIGN KEY (automation_grant_id)
    REFERENCES automation_grants (automation_grant_id)
    """)
  end

  def down do
    execute("""
    ALTER TABLE contact_plan_approvals
    DROP CONSTRAINT IF EXISTS contact_plan_approvals_automation_grant_fk
    """)

    alter table(:contact_plan_approvals) do
      remove(:automation_grant_content_sha256)
      remove(:automation_grant_id)
      remove(:actor_kind)
    end

    rename(table(:contact_plan_approvals), :actor_id, to: :actor_user_id)
  end
end
