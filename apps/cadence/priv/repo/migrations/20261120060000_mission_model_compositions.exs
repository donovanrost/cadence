defmodule Cadence.Repo.Migrations.MissionModelCompositions do
  use Ecto.Migration

  alias Cadence.MissionModels.CompositionBackfill

  # D1 (#541; design docs/apogee/domain/mission-composition-design.md §1, §2, §7).
  #
  # - mission_model_compositions: which imported layers, at which mounts, in one tenant. Content-
  #   addressed within (organization, mission); immutable.
  # - mission_model_composition_layers: its layers, each by (organization, mission, layer_id) FK,
  #   so a layer of another mission or organization can't be named.
  # - mission_model_effective_revisions: "this composition at this authored head" -> its compiled
  #   revision. Unique on the composition and head (NULL-safe: PG14 has no NULLS NOT DISTINCT) and
  #   on revision_id (mms-security M2: an approval can't move to another composition). Immutable.
  #
  # Then the one-to-one backfill (§7), in this same transaction: every catalog revision's model
  # revision becomes a one-layer composition at '/' with its link, written by a system actor that
  # counts no one. Nothing is written to mission_model_revisions (CB-4). No reset.
  def up do
    # The foreign keys below are tenant-scoped, so the parents need tenant-scoped unique keys.
    create(
      unique_index(:mission_model_layers, [:organization_id, :mission_id, :layer_id],
        name: :mission_model_layers_tenant_idx
      )
    )

    create(
      unique_index(:mission_model_revisions, [:organization_id, :mission_id, :revision_id],
        name: :mission_model_revisions_tenant_idx
      )
    )

    create table(:mission_model_compositions, primary_key: false) do
      add(:organization_id, :string, null: false, primary_key: true)
      add(:mission_id, :string, null: false, primary_key: true)
      add(:composition_id, :string, null: false, primary_key: true)
      add(:created_by, :map, null: false)

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create table(:mission_model_composition_layers, primary_key: false) do
      add(:organization_id, :string, null: false, primary_key: true)
      add(:mission_id, :string, null: false, primary_key: true)
      add(:composition_id, :string, null: false, primary_key: true)
      add(:layer_id, :string, null: false, primary_key: true)
      add(:mount, :string, null: false)
      add(:position, :integer, null: false)
    end

    create table(:mission_model_effective_revisions, primary_key: false) do
      add(:organization_id, :string, null: false)
      add(:mission_id, :string, null: false)
      add(:composition_id, :string, null: false)
      add(:authored_head, :string)
      add(:revision_id, :string, null: false)

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    execute("""
    ALTER TABLE mission_model_composition_layers
      ADD CONSTRAINT mission_model_composition_layers_composition_fkey
        FOREIGN KEY (organization_id, mission_id, composition_id)
        REFERENCES mission_model_compositions (organization_id, mission_id, composition_id)
        ON DELETE RESTRICT,
      ADD CONSTRAINT mission_model_composition_layers_layer_fkey
        FOREIGN KEY (organization_id, mission_id, layer_id)
        REFERENCES mission_model_layers (organization_id, mission_id, layer_id)
        ON DELETE RESTRICT,
      ADD CONSTRAINT mission_model_composition_layers_mount_check
        CHECK (mount ~ '^/([A-Za-z0-9_.-]+(/[A-Za-z0-9_.-]+){0,3})?$'
               AND mount !~ '(^|/)\\.{1,2}(/|$)'),
      ADD CONSTRAINT mission_model_composition_layers_position_check
        CHECK (position BETWEEN 0 AND 7)
    """)

    execute("""
    ALTER TABLE mission_model_effective_revisions
      ADD CONSTRAINT mission_model_effective_revisions_composition_fkey
        FOREIGN KEY (organization_id, mission_id, composition_id)
        REFERENCES mission_model_compositions (organization_id, mission_id, composition_id)
        ON DELETE RESTRICT,
      ADD CONSTRAINT mission_model_effective_revisions_revision_fkey
        FOREIGN KEY (organization_id, mission_id, revision_id)
        REFERENCES mission_model_revisions (organization_id, mission_id, revision_id)
        ON DELETE RESTRICT
    """)

    execute("""
    CREATE UNIQUE INDEX mission_model_effective_revisions_head_idx
      ON mission_model_effective_revisions
        (organization_id, mission_id, composition_id, COALESCE(authored_head, ''))
    """)

    create(
      unique_index(:mission_model_effective_revisions, [:revision_id],
        name: :mission_model_effective_revisions_revision_idx
      )
    )

    execute("""
    CREATE FUNCTION mission_model_composition_immutable() RETURNS trigger AS $$
    BEGIN
      RAISE EXCEPTION '% is immutable (#541)', TG_TABLE_NAME;
    END;
    $$ LANGUAGE plpgsql
    """)

    for table <- [
          "mission_model_compositions",
          "mission_model_composition_layers",
          "mission_model_effective_revisions"
        ] do
      execute("""
      CREATE TRIGGER #{table}_immutable BEFORE UPDATE OR DELETE ON #{table}
        FOR EACH ROW EXECUTE FUNCTION mission_model_composition_immutable()
      """)

      execute("""
      CREATE TRIGGER #{table}_no_truncate BEFORE TRUNCATE ON #{table}
        FOR EACH STATEMENT EXECUTE FUNCTION mission_model_composition_immutable()
      """)
    end

    flush()
    CompositionBackfill.run(repo())
  end

  def down do
    for table <- [
          "mission_model_effective_revisions",
          "mission_model_composition_layers",
          "mission_model_compositions"
        ] do
      drop(table(table))
    end

    execute("DROP FUNCTION mission_model_composition_immutable()")
    drop(index(:mission_model_revisions, [], name: :mission_model_revisions_tenant_idx))
    drop(index(:mission_model_layers, [], name: :mission_model_layers_tenant_idx))
  end
end
