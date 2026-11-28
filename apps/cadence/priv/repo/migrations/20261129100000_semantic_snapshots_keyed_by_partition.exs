defmodule Cadence.Repo.Migrations.SemanticSnapshotsKeyedByPartition do
  use Ecto.Migration

  # #443 slice 2: a partition has one semantic snapshot, whatever runtime basis wrote it. A
  # recovering owner under a new basis loads it and keeps the state of every identity whose
  # definition didn't change. The basis is a column now (which basis wrote it), not part of the
  # key. Snapshots are recovery points the journal can rebuild, and the snapshot version is
  # bumped with this, so the rows written before are dropped rather than read by an old reader.
  def up do
    execute("DELETE FROM semantic_runtime_snapshots")

    execute(
      "ALTER TABLE semantic_runtime_snapshots DROP CONSTRAINT semantic_runtime_snapshots_pkey"
    )

    execute("""
    ALTER TABLE semantic_runtime_snapshots
      ADD CONSTRAINT semantic_runtime_snapshots_pkey
      PRIMARY KEY (organization_scope_id, mission_id, partition_id)
    """)
  end

  def down do
    execute("DELETE FROM semantic_runtime_snapshots")

    execute(
      "ALTER TABLE semantic_runtime_snapshots DROP CONSTRAINT semantic_runtime_snapshots_pkey"
    )

    execute("""
    ALTER TABLE semantic_runtime_snapshots
      ADD CONSTRAINT semantic_runtime_snapshots_pkey
      PRIMARY KEY (organization_scope_id, mission_id, partition_id, runtime_basis_sha256)
    """)
  end
end
