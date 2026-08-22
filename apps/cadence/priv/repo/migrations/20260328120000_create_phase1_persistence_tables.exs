defmodule Cadence.Repo.Migrations.CreatePhase1PersistenceTables do
  use Ecto.Migration

  def change do
    create table(:ingress_raw_evidence, primary_key: false) do
      add :evidence_id, :string, primary_key: true
      add :mission_id, :string, null: false
      add :spacecraft_id, :string
      add :protocol_family, :string, null: false
      add :direction, :string, null: false
      add :raw, :binary, null: false
      add :source_time, :utc_datetime_usec
      add :receipt_time, :utc_datetime_usec, null: false
      add :source_ref, :string
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:ingress_raw_evidence, [:mission_id, :receipt_time])

    create table(:protocol_packet_records, primary_key: false) do
      add :packet_id, :string, primary_key: true

      add :evidence_id,
          references(:ingress_raw_evidence,
            column: :evidence_id,
            type: :string,
            on_delete: :delete_all
          ),
          null: false

      add :mission_id, :string, null: false
      add :spacecraft_id, :string
      add :protocol_family, :string, null: false
      add :packet_kind, :string, null: false
      add :apid, :integer, null: false
      add :sequence_flags, :integer, null: false
      add :sequence_count, :integer, null: false
      add :secondary_header, :boolean, null: false
      add :packet_data, :binary, null: false
      add :source_time, :utc_datetime_usec
      add :receipt_time, :utc_datetime_usec, null: false
      add :provenance, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:protocol_packet_records, [:mission_id, :receipt_time])
    create index(:protocol_packet_records, [:mission_id, :apid, :sequence_count])

    create table(:telemetry_samples, primary_key: false) do
      add :sample_id, :string, primary_key: true

      add :packet_id,
          references(:protocol_packet_records,
            column: :packet_id,
            type: :string,
            on_delete: :delete_all
          ),
          null: false

      add :evidence_id,
          references(:ingress_raw_evidence,
            column: :evidence_id,
            type: :string,
            on_delete: :delete_all
          ),
          null: false

      add :mission_id, :string, null: false
      add :spacecraft_id, :string
      add :point_id, :string, null: false
      add :point_name, :string, null: false
      add :packet_definition_id, :string, null: false
      add :packet_definition_version, :integer, null: false
      add :raw_value, :map, null: false
      add :engineering_value, :map, null: false
      add :quality_state, :string, null: false
      add :generation_time, :utc_datetime_usec
      add :receipt_time, :utc_datetime_usec, null: false
      add :provenance, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:telemetry_samples, [:mission_id, :receipt_time])
    create index(:telemetry_samples, [:point_id, :receipt_time])
  end
end
