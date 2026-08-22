defmodule Cadence.Repo.Migrations.CreateProtocolFrameAndAnomalyTables do
  use Ecto.Migration

  def up do
    create table(:protocol_transfer_frame_records, primary_key: false) do
      add(:frame_record_id, :string, primary_key: true)
      add(:organization_id, :string)
      add(:mission_id, :string, null: false)
      add(:evidence_id, references(:ingress_raw_evidence, column: :evidence_id, type: :string),
        null: false
      )
      add(:source_endpoint_ref, :string)
      add(:spacecraft_id, :string)
      add(:protocol_family, :string, null: false)
      add(:direction, :string, null: false)
      add(:scid, :integer, null: false)
      add(:vcid, :integer, null: false)
      add(:map_id, :integer)
      add(:frame_seq, :integer, null: false)
      add(:raw_frame_offset_bytes, :integer, null: false)
      add(:raw_frame_length_bytes, :integer, null: false)
      add(:payload_length_bytes, :integer, null: false)
      add(:first_header_pointer, :integer)
      add(:quality, :string)
      add(:source_time, :utc_datetime_usec)
      add(:receipt_time, :utc_datetime_usec, null: false)
      add(:metadata, :map, null: false, default: %{})

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:protocol_transfer_frame_records, [:mission_id, :evidence_id])
    create index(:protocol_transfer_frame_records, [:organization_id, :mission_id])
    create index(:protocol_transfer_frame_records, [:source_endpoint_ref, :protocol_family])
    create index(:protocol_transfer_frame_records, [:scid, :vcid, :frame_seq])

    execute("""
    ALTER TABLE protocol_transfer_frame_records
    ADD CONSTRAINT protocol_transfer_frame_records_org_mission_fk
    FOREIGN KEY (organization_id, mission_id)
    REFERENCES missions (organization_id, mission_id)
    """)

    execute("""
    CREATE TRIGGER sync_organization_id_from_mission
    BEFORE INSERT OR UPDATE OF mission_id, organization_id ON protocol_transfer_frame_records
    FOR EACH ROW
    EXECUTE FUNCTION cadence_sync_organization_id_from_mission()
    """)

    create table(:protocol_anomalies, primary_key: false) do
      add(:anomaly_id, :string, primary_key: true)
      add(:organization_id, :string)
      add(:mission_id, :string, null: false)
      add(:evidence_id, references(:ingress_raw_evidence, column: :evidence_id, type: :string),
        null: false
      )
      add(:source_endpoint_ref, :string)
      add(:spacecraft_id, :string)
      add(:protocol_family, :string, null: false)
      add(:direction, :string, null: false)
      add(:anomaly_kind, :string, null: false)
      add(:scid, :integer)
      add(:vcid, :integer)
      add(:map_id, :integer)
      add(:frame_seq, :integer)
      add(:raw_frame_offset_bytes, :integer)
      add(:raw_frame_length_bytes, :integer)
      add(:recorded_at, :utc_datetime_usec, null: false)
      add(:metadata, :map, null: false, default: %{})

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:protocol_anomalies, [:mission_id, :evidence_id])
    create index(:protocol_anomalies, [:organization_id, :mission_id])
    create index(:protocol_anomalies, [:source_endpoint_ref, :protocol_family])
    create index(:protocol_anomalies, [:anomaly_kind, :protocol_family])

    execute("""
    ALTER TABLE protocol_anomalies
    ADD CONSTRAINT protocol_anomalies_org_mission_fk
    FOREIGN KEY (organization_id, mission_id)
    REFERENCES missions (organization_id, mission_id)
    """)

    execute("""
    CREATE TRIGGER sync_organization_id_from_mission
    BEFORE INSERT OR UPDATE OF mission_id, organization_id ON protocol_anomalies
    FOR EACH ROW
    EXECUTE FUNCTION cadence_sync_organization_id_from_mission()
    """)
  end

  def down do
    execute("""
    DROP TRIGGER IF EXISTS sync_organization_id_from_mission ON protocol_anomalies
    """)

    execute("""
    ALTER TABLE protocol_anomalies
    DROP CONSTRAINT IF EXISTS protocol_anomalies_org_mission_fk
    """)

    drop_if_exists index(:protocol_anomalies, [:anomaly_kind, :protocol_family])
    drop_if_exists index(:protocol_anomalies, [:source_endpoint_ref, :protocol_family])
    drop_if_exists index(:protocol_anomalies, [:organization_id, :mission_id])
    drop_if_exists index(:protocol_anomalies, [:mission_id, :evidence_id])
    drop table(:protocol_anomalies)

    execute("""
    DROP TRIGGER IF EXISTS sync_organization_id_from_mission ON protocol_transfer_frame_records
    """)

    execute("""
    ALTER TABLE protocol_transfer_frame_records
    DROP CONSTRAINT IF EXISTS protocol_transfer_frame_records_org_mission_fk
    """)

    drop_if_exists index(:protocol_transfer_frame_records, [:scid, :vcid, :frame_seq])
    drop_if_exists index(:protocol_transfer_frame_records, [:source_endpoint_ref, :protocol_family])
    drop_if_exists index(:protocol_transfer_frame_records, [:organization_id, :mission_id])
    drop_if_exists index(:protocol_transfer_frame_records, [:mission_id, :evidence_id])
    drop table(:protocol_transfer_frame_records)
  end
end
