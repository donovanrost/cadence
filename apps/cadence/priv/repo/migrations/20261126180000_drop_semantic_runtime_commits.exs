defmodule Cadence.Repo.Migrations.DropSemanticRuntimeCommits do
  use Ecto.Migration

  # DECISIONS #94/#96, #692: there is no per-batch semantic log. A partition's recovery point is its
  # snapshot (`semantic_runtime_snapshots`) plus the ingress journal's replay, so the commit log,
  # the checkpoints that referenced it, and the head's commit sequence go.
  def up do
    execute("DROP TRIGGER IF EXISTS semantic_runtime_writer_fence ON semantic_runtime_commits")
    execute("DROP FUNCTION IF EXISTS fence_semantic_runtime_commit()")
    drop(table(:semantic_runtime_checkpoints))
    drop(table(:semantic_runtime_commits))

    alter table(:semantic_runtime_heads) do
      remove(:commit_sequence)
    end
  end

  def down do
    raise Ecto.MigrationError, message: "the semantic runtime commit log is gone for good"
  end
end
