defmodule Cadence.Repo.Migrations.CreateProtocolArchiveRecordEntries do
  use Ecto.Migration

  def change do
    create table(:protocol_archive_record_entries, primary_key: false) do
      add :entry_id, :string, primary_key: true
      add :record_kind, :string, null: false
      add :record_id, :string, null: false
      add :segment_id, :string, null: false
      add :object_key, :string, null: false
      add :archive_backend, :string, null: false
      add :mission_id, :string, null: false
      add :organization_id, :string
      add :evidence_id, :string, null: false
      add :source_endpoint_ref, :string
      add :spacecraft_id, :string
      add :protocol_family, :string, null: false
      add :direction, :string
      add :source_time, :utc_datetime_usec
      add :receipt_time, :utc_datetime_usec, null: false
      add :source_ref, :string
      add :realized_contact_id, :string
      add :path_id, :string
      add :provider_binding_id, :string
      add :apid, :integer
      add :packet_kind, :string
      add :scid, :integer
      add :vcid, :integer
      add :map_id, :integer
      add :frame_seq, :integer
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create unique_index(
             :protocol_archive_record_entries,
             [:record_kind, :record_id],
             name: :protocol_archive_record_entries_kind_record_idx
           )

    create index(:protocol_archive_record_entries, [:mission_id, :record_kind, :receipt_time])
    create index(:protocol_archive_record_entries, [:mission_id, :evidence_id])
    create index(:protocol_archive_record_entries, [:mission_id, :source_ref, :receipt_time])
    create index(:protocol_archive_record_entries, [:mission_id, :realized_contact_id, :receipt_time])
    create index(:protocol_archive_record_entries, [:mission_id, :spacecraft_id, :receipt_time])
    create index(:protocol_archive_record_entries, [:mission_id, :apid, :receipt_time])
    create index(:protocol_archive_record_entries, [:mission_id, :vcid, :receipt_time])
    create index(:protocol_archive_record_entries, [:segment_id])
    create index(:protocol_archive_record_entries, [:object_key])
  end
end
