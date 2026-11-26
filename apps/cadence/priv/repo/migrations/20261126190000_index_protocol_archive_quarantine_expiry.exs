defmodule Cadence.Repo.Migrations.IndexProtocolArchiveQuarantineExpiry do
  use Ecto.Migration

  # #791: the retention rule reads the oldest expired entries by when their record was received
  # (first sighting without one), and the oldest resolutions by when they were resolved.
  def change do
    create(
      index(:protocol_archive_quarantine, ["(coalesce(receipt_time, first_seen_at))"],
        name: :protocol_archive_quarantine_expiry_idx
      )
    )

    create(
      index(:protocol_archive_quarantine_resolutions, [:resolved_at],
        name: :protocol_archive_quarantine_resolved_at_idx
      )
    )
  end
end
