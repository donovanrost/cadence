defmodule Cadence.Repo.Migrations.BindCommandQueueReleaseAttempts do
  use Ecto.Migration

  def change do
    alter table(:command_queue_entries) do
      add(:active_release_attempt_id, :string)
    end

    create(
      unique_index(:command_queue_entries, [:active_release_attempt_id],
        where: "active_release_attempt_id IS NOT NULL"
      )
    )
  end
end
