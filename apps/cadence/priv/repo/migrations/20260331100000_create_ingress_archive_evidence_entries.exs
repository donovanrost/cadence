defmodule Cadence.Repo.Migrations.CreateIngressArchiveEvidenceEntries do
  use Ecto.Migration

  def change do
    create table(:ingress_archive_evidence_entries, primary_key: false) do
      add :evidence_id, :string, primary_key: true
      add :segment_id, :string, null: false
      add :object_key, :string, null: false
      add :archive_backend, :string, null: false
      add :mission_id, :string, null: false
      add :organization_id, :string
      add :source_endpoint_ref, :string
      add :spacecraft_id, :string
      add :protocol_family, :string, null: false
      add :direction, :string, null: false
      add :source_time, :utc_datetime_usec
      add :receipt_time, :utc_datetime_usec, null: false
      add :source_ref, :string
      add :realized_contact_id, :string
      add :path_id, :string
      add :provider_binding_id, :string
      add :raw_size_bytes, :integer, null: false
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:ingress_archive_evidence_entries, [:mission_id, :receipt_time])
    create index(:ingress_archive_evidence_entries, [:mission_id, :source_ref, :receipt_time])

    create index(
             :ingress_archive_evidence_entries,
             [:mission_id, :realized_contact_id, :receipt_time]
           )

    create index(:ingress_archive_evidence_entries, [:mission_id, :spacecraft_id, :receipt_time])
    create index(:ingress_archive_evidence_entries, [:segment_id])
    create index(:ingress_archive_evidence_entries, [:object_key])
  end
end
