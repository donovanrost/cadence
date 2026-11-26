defmodule Cadence.Repo.Migrations.ContactPlanApprovalsSeparatedFrom do
  @moduledoc """
  #277 (ca-security, #117's DecisionRecord field): a contact-plan approval records the author ids
  its separation check compared (the submitter and every version's author since the last
  approval). Additive: older rows, refusals and approvals without separation read as empty.
  """
  use Ecto.Migration

  def change do
    alter table(:contact_plan_approvals) do
      add(:separated_from, {:array, :text}, null: false, default: [])
    end
  end
end
