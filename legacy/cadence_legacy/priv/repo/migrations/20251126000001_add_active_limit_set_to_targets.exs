defmodule Cadence.Repo.Migrations.AddActiveLimitSetToTargets do
  use Ecto.Migration

  def change do
    alter table(:targets) do
      add :active_limit_set, :string, default: "NOMINAL"
    end

    # Create index for efficient queries by active limit set
    create index(:targets, [:mission_id, :active_limit_set])
  end
end
