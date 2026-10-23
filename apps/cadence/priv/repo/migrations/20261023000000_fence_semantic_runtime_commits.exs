defmodule Cadence.Repo.Migrations.FenceSemanticRuntimeCommits do
  use Ecto.Migration

  def up do
    create table(:semantic_runtime_heads, primary_key: false) do
      add(:organization_scope_id, :string, primary_key: true)
      add(:mission_id, :string, primary_key: true)
      add(:partition_id, :string, primary_key: true)
      add(:runtime_basis_sha256, :string, null: false)
      add(:generation, :bigint, null: false)
      add(:ownership_epoch, :bigint, null: false, default: 0)
      add(:commit_sequence, :bigint, null: false, default: 0)
    end

    alter table(:semantic_runtime_commits) do
      # Historical rows predate fencing. Every new insert must supply both fields.
      add(:ownership_epoch, :bigint)
      add(:predecessor_sequence, :bigint)
    end

    execute("""
    CREATE FUNCTION fence_semantic_runtime_commit() RETURNS trigger AS $$
    BEGIN
      UPDATE semantic_runtime_heads
      SET commit_sequence = NEW.commit_sequence
      WHERE organization_scope_id = NEW.organization_scope_id
        AND mission_id = NEW.mission_id AND partition_id = NEW.partition_id
        AND runtime_basis_sha256 = NEW.runtime_basis_sha256
        AND ownership_epoch = NEW.ownership_epoch
        AND commit_sequence = NEW.predecessor_sequence;

      IF NOT FOUND THEN
        RAISE EXCEPTION 'stale semantic runtime writer or predecessor'
          USING ERRCODE = '23514', CONSTRAINT = 'semantic_runtime_writer_fence';
      END IF;
      RETURN NEW;
    END;
    $$ LANGUAGE plpgsql;
    """)

    execute("""
    CREATE TRIGGER semantic_runtime_writer_fence
    BEFORE INSERT ON semantic_runtime_commits
    FOR EACH ROW EXECUTE FUNCTION fence_semantic_runtime_commit();
    """)
  end

  def down do
    execute("DROP TRIGGER semantic_runtime_writer_fence ON semantic_runtime_commits")
    execute("DROP FUNCTION fence_semantic_runtime_commit()")

    alter table(:semantic_runtime_commits) do
      remove(:ownership_epoch)
      remove(:predecessor_sequence)
    end

    drop(table(:semantic_runtime_heads))
  end
end
