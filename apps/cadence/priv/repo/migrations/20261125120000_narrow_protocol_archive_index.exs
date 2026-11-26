defmodule Cadence.Repo.Migrations.NarrowProtocolArchiveIndex do
  use Ecto.Migration

  # One ~28-column row per frame and per packet (14M+ a day at 500 spacecraft) becomes one summary
  # row per segment plus a narrow identity row per record. Dev data is disposable: the old table is
  # dropped, not converted.
  def change do
    drop table(:protocol_archive_record_entries)

    create table(:protocol_archive_segments) do
      add :archive_backend, :string, null: false
      add :mission_id, :string, null: false
      add :organization_id, :string
      add :object_key, :string, null: false
      add :packet_count, :integer, null: false
      add :frame_count, :integer, null: false
      add :first_receipt_time, :utc_datetime_usec, null: false
      add :last_receipt_time, :utc_datetime_usec, null: false
      add :spacecraft_ids, {:array, :string}, null: false, default: []
      add :realized_contact_ids, {:array, :string}, null: false, default: []
      add :source_refs, {:array, :string}, null: false, default: []
      add :evidence_ids, {:array, :string}, null: false, default: []
      # Frames this segment newly archived, by realized contact (replayed duplicates excluded).
      add :frames_by_contact, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create unique_index(:protocol_archive_segments, [:object_key])

    create index(:protocol_archive_segments, [
             :archive_backend,
             :mission_id,
             :first_receipt_time,
             :last_receipt_time
           ])

    create index(:protocol_archive_segments, [:evidence_ids], using: :gin)

    # Retention drops a day by deleting its segments; the cascade removes their identity rows.
    # Not partitioned by day: a partitioned unique key would have to include the day, which would
    # let a replay on a later day slip past the identity-conflict check.
    create table(:protocol_archive_record_identities, primary_key: false) do
      add :record_kind, :string, null: false, primary_key: true
      add :record_id, :string, null: false, primary_key: true
      add :content_sha256, :binary, null: false

      add :segment_id, references(:protocol_archive_segments, on_delete: :delete_all),
        null: false

    end

    create index(:protocol_archive_record_identities, [:segment_id])
  end
end
