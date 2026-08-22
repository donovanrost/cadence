defmodule Cadence.Repo.Migrations.CreateProviderEvidenceAndAudit do
  use Ecto.Migration

  def up do
    create table(:provider_evidence, primary_key: false) do
      add(:provider_evidence_id, :string, primary_key: true)
      add(:organization_id, :string, null: false)
      add(:provider_account_id, :string, null: false)
      add(:storage_kind, :string, null: false)
      add(:schema_type, :string, null: false)
      add(:media_type, :string, null: false)
      add(:captured_at, :utc_datetime_usec, null: false)
      add(:byte_count, :bigint, null: false)
      add(:content_sha256, :string, null: false)
      add(:document, :map)
      add(:external_object_ref, :string)
      add(:metadata, :map, null: false, default: %{})

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create(
      unique_index(
        :provider_evidence,
        [:organization_id, :provider_account_id, :schema_type, :media_type, :content_sha256],
        name: :provider_evidence_content_idx
      )
    )

    create(
      index(:provider_evidence, [:organization_id, :provider_account_id, :captured_at],
        name: :provider_evidence_account_time_idx
      )
    )

    create(
      constraint(:provider_evidence, :provider_evidence_storage_kind_check,
        check: "storage_kind IN ('inline', 'external')"
      )
    )

    create(
      constraint(:provider_evidence, :provider_evidence_byte_count_check,
        check: "byte_count >= 0"
      )
    )

    create(
      constraint(:provider_evidence, :provider_evidence_payload_check,
        check:
          "(storage_kind = 'inline' AND document IS NOT NULL AND external_object_ref IS NULL) OR " <>
            "(storage_kind = 'external' AND document IS NULL AND external_object_ref IS NOT NULL)"
      )
    )

    create_provider_audit_entries()
  end

  def down do
    execute("DROP TRIGGER IF EXISTS sync_organization_id_from_mission ON provider_audit_entries")

    execute("""
    ALTER TABLE provider_audit_entries
    DROP CONSTRAINT IF EXISTS provider_audit_entries_org_mission_fk
    """)

    drop(table(:provider_audit_entries))
    drop(table(:provider_evidence))
  end

  defp create_provider_audit_entries do
    create table(:provider_audit_entries, primary_key: false) do
      add(:provider_audit_entry_id, :string, primary_key: true)
      add(:organization_id, :string, null: false)
      add(:mission_id, :string)
      add(:provider_account_id, :string)
      add(:provider_account_grant_id, :string)
      add(:provider_id, :string)
      add(:provider_reservation_id, :string)
      add(:provider_change_id, :string)
      add(:contact_id, :string)
      add(:scheduled_contact_id, :string)
      add(:action, :string, null: false)
      add(:outcome, :string, null: false)
      add(:provider_occurred_at, :utc_datetime_usec)
      add(:recorded_at, :utc_datetime_usec, null: false)
      add(:effective_at, :utc_datetime_usec)
      add(:correlation_id, :string)
      add(:request_id, :string)
      add(:client_reference, :string)
      add(:provider_event_id, :string)
      add(:causation_entry_id, :string)
      add(:supersedes_entry_id, :string)
      add(:credential_ref, :string)
      add(:credential_registry_version, :integer)
      add(:credential_backend_version, :string)
      add(:source_document, :map, null: false, default: %{})
      add(:actor_document, :map, null: false, default: %{})
      add(:previous_document, :map, null: false, default: %{})
      add(:current_document, :map, null: false, default: %{})
      add(:decision_document, :map, null: false, default: %{})
      add(:policy_document, :map, null: false, default: %{})
      add(:evidence_references, :map, null: false, default: %{})
      add(:metadata, :map, null: false, default: %{})

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create(
      index(:provider_audit_entries, [:organization_id, :recorded_at],
        name: :provider_audit_entries_org_time_idx
      )
    )

    create(
      index(:provider_audit_entries, [:organization_id, :mission_id, :recorded_at],
        name: :provider_audit_entries_mission_time_idx
      )
    )

    create(
      index(:provider_audit_entries, [:organization_id, :provider_account_id, :recorded_at],
        name: :provider_audit_entries_account_time_idx
      )
    )

    create(
      index(:provider_audit_entries, [:organization_id, :correlation_id, :recorded_at],
        name: :provider_audit_entries_correlation_idx
      )
    )

    execute("""
    ALTER TABLE provider_audit_entries
    ADD CONSTRAINT provider_audit_entries_org_mission_fk
    FOREIGN KEY (organization_id, mission_id)
    REFERENCES missions (organization_id, mission_id)
    """)

    execute("""
    CREATE TRIGGER sync_organization_id_from_mission
    BEFORE INSERT OR UPDATE OF mission_id, organization_id ON provider_audit_entries
    FOR EACH ROW
    EXECUTE FUNCTION cadence_sync_organization_id_from_mission()
    """)
  end
end
