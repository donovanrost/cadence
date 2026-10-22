defmodule Cadence.Repo.Migrations.AddArchiveContentHashes do
  use Ecto.Migration

  def change do
    # Nullable for rolling compatibility. Legacy rows are not silently trusted
    # as proof that a newly supplied record has identical content.
    alter table(:protocol_archive_record_entries) do
      add(:content_sha256, :binary)
    end

    alter table(:ingress_archive_evidence_entries) do
      add(:content_sha256, :binary)
    end
  end
end
