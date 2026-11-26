defmodule Cadence.Repo.Migrations.MissionModelCompositionNumbers do
  use Ecto.Migration

  # D2 (#543; design docs/apogee/domain/mission-composition-design.md §6, mms-engineer's note 1):
  # a composition's per-mission short number ("Composition 3", mms-ux), never reused. D1's tables
  # are immutable by trigger, so the number lives in its own insert-only table, immutable the same
  # way. `Compositions.insert_or_get/4` assigns max + 1 under a per-mission advisory lock. It's in no
  # stored hash: the composition id doesn't include it (#108 untouched).
  #
  # Existing compositions are numbered here, in their mission's order of creation (inserted_at,
  # then composition_id). Additive: no other table changes.
  def up do
    create table(:mission_model_composition_numbers, primary_key: false) do
      add(:organization_id, :string, null: false, primary_key: true)
      add(:mission_id, :string, null: false, primary_key: true)
      add(:composition_id, :string, null: false, primary_key: true)
      add(:number, :integer, null: false)

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create(
      unique_index(:mission_model_composition_numbers, [:organization_id, :mission_id, :number],
        name: :mission_model_composition_numbers_number_idx
      )
    )

    execute("""
    ALTER TABLE mission_model_composition_numbers
      ADD CONSTRAINT mission_model_composition_numbers_composition_fkey
        FOREIGN KEY (organization_id, mission_id, composition_id)
        REFERENCES mission_model_compositions (organization_id, mission_id, composition_id)
        ON DELETE RESTRICT,
      ADD CONSTRAINT mission_model_composition_numbers_positive CHECK (number > 0)
    """)

    # D1's function (migration 20261120060000) refuses UPDATE, DELETE and TRUNCATE.
    execute("""
    CREATE TRIGGER mission_model_composition_numbers_immutable
      BEFORE UPDATE OR DELETE ON mission_model_composition_numbers
      FOR EACH ROW EXECUTE FUNCTION mission_model_composition_immutable()
    """)

    execute("""
    CREATE TRIGGER mission_model_composition_numbers_no_truncate
      BEFORE TRUNCATE ON mission_model_composition_numbers
      FOR EACH STATEMENT EXECUTE FUNCTION mission_model_composition_immutable()
    """)

    execute("""
    INSERT INTO mission_model_composition_numbers
      (organization_id, mission_id, composition_id, number, inserted_at)
    SELECT organization_id, mission_id, composition_id,
           row_number() OVER (PARTITION BY organization_id, mission_id
                              ORDER BY inserted_at, composition_id),
           now()
      FROM mission_model_compositions
    """)
  end

  def down do
    drop(table(:mission_model_composition_numbers))
  end
end
