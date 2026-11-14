defmodule Cadence.Repo.Migrations.AddReasonToFleetPlanningPolicyVersions do
  use Ecto.Migration

  # The saver's reason for a policy version (POST /policy `reason`; lead 11-14). Nullable:
  # earlier versions have none, and it isn't part of the content hash.
  def change do
    alter table(:fleet_planning_policy_versions) do
      add(:reason, :text)
    end
  end
end
