defmodule Cadence.Repo.Migrations.ContactPlanApprovalExceptions do
  use Ecto.Migration

  # DECISIONS #28: an approval may accept unsatisfied requirements as explicit,
  # audited exceptions (requirement, reason, actor, time). Conflicts still block.
  def change do
    alter table(:contact_plan_approvals) do
      add(:exceptions_document, {:array, :map}, null: false, default: [])
    end
  end
end
