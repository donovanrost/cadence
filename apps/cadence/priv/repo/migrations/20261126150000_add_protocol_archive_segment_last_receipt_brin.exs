defmodule Cadence.Repo.Migrations.AddProtocolArchiveSegmentLastReceiptBrin do
  use Ecto.Migration

  # Retention (#694) finds the expired end of the segments by age alone, and the one other index
  # that has the time leads with the mission. Segments arrive in time order, so a BRIN index is
  # tiny and enough.
  def change do
    create(
      index(:protocol_archive_segments, [:last_receipt_time],
        using: :brin,
        name: :protocol_archive_segments_last_receipt_brin
      )
    )
  end
end
