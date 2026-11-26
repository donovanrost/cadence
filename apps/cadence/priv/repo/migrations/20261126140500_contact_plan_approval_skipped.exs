defmodule Cadence.Repo.Migrations.ContactPlanApprovalSkipped do
  use Ecto.Migration

  # #273: an approval records the passes it left out because their booking window had closed, so
  # the decision record says exactly what was approved. NULL on rejections.
  def change do
    alter table(:contact_plan_approvals) do
      add(:skipped_document, {:array, :map})
    end
  end
end
