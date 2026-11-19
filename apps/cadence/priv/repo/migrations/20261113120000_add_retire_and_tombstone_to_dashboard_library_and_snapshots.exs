defmodule Cadence.Repo.Migrations.AddRetireAndTombstoneToDashboardLibraryAndSnapshots do
  use Ecto.Migration

  # Dashboards Q6 (DECISIONS #76 Q10): a library item is retired, never deleted (old dashboard
  # versions still place its versions), and a deleted snapshot leaves a tombstone, so its link
  # says it was deleted. Null (every existing row) is live.
  def change do
    # Both tables are read on dashboard loads; fail fast rather than queue readers (qa).
    execute("SET LOCAL lock_timeout = '5s'", "SET LOCAL lock_timeout = '5s'")

    alter table(:dashboard_library_items) do
      add(:retired_at, :utc_datetime_usec, null: true)
      add(:retired_by, :string, null: true)
    end

    alter table(:dashboard_snapshots) do
      add(:deleted_at, :utc_datetime_usec, null: true)
      add(:deleted_by, :string, null: true)
    end
  end
end
