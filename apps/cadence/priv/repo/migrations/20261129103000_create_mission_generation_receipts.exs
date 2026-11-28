defmodule Cadence.Repo.Migrations.CreateMissionGenerationReceipts do
  use Ecto.Migration

  def change do
    create table(:mission_generation_receipts, primary_key: false) do
      add(:organization_id, :text, primary_key: true, collation: "C")
      add(:mission_id, :text, primary_key: true, collation: "C")
      add(:generation, :bigint, primary_key: true)
      add(:activation_id, :text, null: false, collation: "C")
      add(:binding_set_id, :text, null: false, collation: "C")
      add(:binding_set_version, :bigint, null: false)
      add(:applied_at, :utc_datetime_usec, null: false)
    end

    execute(
      """
      ALTER TABLE mission_generation_receipts
        ADD CONSTRAINT mission_generation_receipts_mission_fk
        FOREIGN KEY (organization_id, mission_id) REFERENCES missions (organization_id, mission_id),
        ADD CONSTRAINT mission_generation_receipts_activation_fk
        FOREIGN KEY (activation_id) REFERENCES mission_binding_set_activations (activation_id)
      """,
      """
      ALTER TABLE mission_generation_receipts
        DROP CONSTRAINT mission_generation_receipts_activation_fk,
        DROP CONSTRAINT mission_generation_receipts_mission_fk
      """
    )

    execute(
      """
      CREATE TRIGGER mission_generation_receipts_append_only_rows
        BEFORE UPDATE OR DELETE ON mission_generation_receipts
        FOR EACH ROW EXECUTE FUNCTION cadence_decision_record_append_only()
      """,
      "DROP TRIGGER mission_generation_receipts_append_only_rows ON mission_generation_receipts"
    )

    execute(
      """
      CREATE TRIGGER mission_generation_receipts_append_only_truncate
        BEFORE TRUNCATE ON mission_generation_receipts
        FOR EACH STATEMENT EXECUTE FUNCTION cadence_decision_record_append_only()
      """,
      "DROP TRIGGER mission_generation_receipts_append_only_truncate ON mission_generation_receipts"
    )
  end
end
