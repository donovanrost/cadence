defmodule Cadence.Repo.Migrations.CreateOpsFleetPolicyRecoveries do
  use Ecto.Migration

  def change do
    create table(:ops_fleet_policy_recoveries, primary_key: false) do
      add(:organization_id, :string, primary_key: true)
      add(:user_id, :string, primary_key: true)
      add(:mission_id, :string, primary_key: true)
      add(:sequence, :integer, null: false, default: 0)
      add(:operation, :map)
      timestamps(type: :utc_datetime_usec)
    end

    create constraint(:ops_fleet_policy_recoveries, :ops_fleet_policy_sequence_bounds,
             check: "sequence BETWEEN 0 AND 1000000"
           )
  end
end
