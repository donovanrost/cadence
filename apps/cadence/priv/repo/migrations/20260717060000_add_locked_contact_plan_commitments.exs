defmodule Cadence.Repo.Migrations.AddLockedContactPlanCommitments do
  use Ecto.Migration

  def up do
    alter table(:contact_plan_versions) do
      add(:locked_snapshot_ids, {:array, :string}, null: false, default: [])
    end

    drop(
      constraint(
        :contact_plan_opportunity_refs,
        :contact_plan_opportunity_refs_disposition_check
      )
    )

    create(
      constraint(:contact_plan_opportunity_refs, :contact_plan_opportunity_refs_disposition_check,
        check: "disposition IN ('selected', 'locked', 'rejected')"
      )
    )
  end

  def down do
    drop(
      constraint(
        :contact_plan_opportunity_refs,
        :contact_plan_opportunity_refs_disposition_check
      )
    )

    create(
      constraint(:contact_plan_opportunity_refs, :contact_plan_opportunity_refs_disposition_check,
        check: "disposition IN ('selected', 'rejected')"
      )
    )

    alter table(:contact_plan_versions) do
      remove(:locked_snapshot_ids)
    end
  end
end
