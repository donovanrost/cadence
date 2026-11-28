defmodule Cadence.Repo.Migrations.MissionModelAuthoredVersions do
  use Ecto.Migration

  # ADR-020 P3 slice M1 (#451): the mission's authored monitoring layer, versioned. Each version
  # names an immutable authored layer and the applied change set and ledger revision that approved
  # it; the newest is the mission's authored head, the one every effective revision is compiled
  # at. Written only by an applied monitoring set, under the mission head lock. Append-only.
  @table :mission_model_authored_versions

  def up do
    create table(@table, primary_key: false) do
      add(:organization_id, :string, primary_key: true, collation: "C")
      add(:mission_id, :string, primary_key: true, collation: "C")
      add(:version, :integer, primary_key: true)
      add(:layer_id, :string, null: false, collation: "C")
      add(:change_set_id, :string, null: false, collation: "C")
      add(:revision_number, :integer, null: false)
      add(:decided_at, :utc_datetime_usec, null: false)
    end

    create(constraint(@table, :mission_model_authored_versions_positive, check: "version > 0"))
    create(unique_index(@table, [:organization_id, :mission_id, :layer_id]))

    execute("""
    ALTER TABLE mission_model_authored_versions
      ADD CONSTRAINT mission_model_authored_versions_mission_fk
      FOREIGN KEY (organization_id, mission_id) REFERENCES missions (organization_id, mission_id),
      ADD CONSTRAINT mission_model_authored_versions_layer_fk
      FOREIGN KEY (layer_id) REFERENCES mission_model_layers (layer_id),
      ADD CONSTRAINT mission_model_authored_versions_change_set_fk
      FOREIGN KEY (change_set_id) REFERENCES mission_config_change_sets (change_set_id)
    """)

    execute("""
    CREATE TRIGGER mission_model_authored_versions_append_only_rows
      BEFORE UPDATE OR DELETE ON mission_model_authored_versions
      FOR EACH ROW EXECUTE FUNCTION cadence_decision_record_append_only()
    """)

    execute("""
    CREATE TRIGGER mission_model_authored_versions_append_only_truncate
      BEFORE TRUNCATE ON mission_model_authored_versions
      FOR EACH STATEMENT EXECUTE FUNCTION cadence_decision_record_append_only()
    """)
  end

  def down do
    drop(table(@table))
  end
end
