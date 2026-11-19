defmodule Cadence.Repo.Migrations.CreateProtocolArchiveQuarantine do
  use Ecto.Migration

  # DECISIONS #88: archive entries that can never be indexed leave the writer's buffer for this
  # table, so one poisoned entry doesn't stop a mission's telemetry storage. Rows are deleted on
  # discard or a successful retry; resolutions keep the audit for the attention read.
  def change do
    create table(:protocol_archive_quarantine, primary_key: false) do
      add(:quarantine_entry_id, :text, primary_key: true)
      add(:mission_id, :text, null: false)
      add(:organization_id, :text)
      add(:realized_contact_id, :text)
      add(:spacecraft_id, :text)
      add(:record_kind, :text, null: false)
      add(:record_id, :text, null: false)
      add(:error_code, :text, null: false)
      add(:error, :text)
      add(:entry, :binary, null: false)
      add(:receipt_time, :utc_datetime_usec)
      add(:first_seen_at, :utc_datetime_usec, null: false)
      add(:last_seen_at, :utc_datetime_usec, null: false)
      add(:last_retry, :map)

      timestamps(type: :utc_datetime_usec)
    end

    create(
      unique_index(:protocol_archive_quarantine, [:mission_id, :record_kind, :record_id],
        name: :protocol_archive_quarantine_record_idx
      )
    )

    create(
      index(:protocol_archive_quarantine, [:mission_id, :realized_contact_id, :error_code],
        name: :protocol_archive_quarantine_item_idx
      )
    )

    create table(:protocol_archive_quarantine_resolutions, primary_key: false) do
      add(:resolution_id, :text, primary_key: true)
      add(:mission_id, :text, null: false)
      add(:item_id, :text, null: false)
      add(:realized_contact_id, :text)
      add(:spacecraft_id, :text)
      add(:error_code, :text, null: false)
      add(:action, :text, null: false)
      add(:actor, :map, null: false)
      add(:note, :text)
      add(:counts, :map, null: false)
      add(:resolved_at, :utc_datetime_usec, null: false)

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create(
      index(:protocol_archive_quarantine_resolutions, [:mission_id, :resolved_at],
        name: :protocol_archive_quarantine_resolved_idx
      )
    )
  end
end
