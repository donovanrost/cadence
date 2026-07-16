defmodule Cadence.Repo.Migrations.CreateProviderEventIngestion do
  use Ecto.Migration

  def change do
    create table(:provider_event_cursors, primary_key: false) do
      add(:provider_event_cursor_id, :string, primary_key: true)
      add(:organization_id, :string, null: false)
      add(:provider_account_id, :string, null: false)
      add(:provider_account_version, :integer, null: false)
      add(:environment_ref, :string, null: false)
      add(:channel_ref, :string, null: false)
      add(:stream_ref, :string, null: false)
      add(:cursor_document, :map, null: false, default: %{"value" => nil})
      add(:health, :string, null: false, default: "unknown")
      add(:last_fetched_at, :utc_datetime_usec)
      add(:last_advanced_at, :utc_datetime_usec)
      add(:last_event_at, :utc_datetime_usec)
      add(:lease_owner, :string)
      add(:lease_expires_at, :utc_datetime_usec)
      add(:consecutive_failures, :integer, null: false, default: 0)
      add(:error_document, :map, null: false, default: %{})
      timestamps(type: :utc_datetime_usec)
    end

    create(
      unique_index(
        :provider_event_cursors,
        [
          :organization_id,
          :provider_account_id,
          :provider_account_version,
          :environment_ref,
          :channel_ref,
          :stream_ref
        ],
        name: :provider_event_cursors_stream_idx
      )
    )

    create(
      index(:provider_event_cursors, [:health, :lease_expires_at],
        name: :provider_event_cursors_claim_idx
      )
    )

    execute("""
    ALTER TABLE provider_event_cursors
    ADD CONSTRAINT provider_event_cursors_account_version_fk
    FOREIGN KEY (organization_id, provider_account_id, provider_account_version)
    REFERENCES provider_account_versions (organization_id, provider_account_id, version)
    """)

    create table(:provider_event_inbox, primary_key: false) do
      add(:provider_event_inbox_id, :string, primary_key: true)
      add(:organization_id, :string, null: false)
      add(:provider_account_id, :string, null: false)
      add(:provider_account_version, :integer, null: false)
      add(:provider_event_cursor_id, :string)
      add(:environment_ref, :string, null: false)
      add(:channel_ref, :string, null: false)
      add(:provider_event_id, :string, null: false)
      add(:schema_version, :string)
      add(:event_type, :string)
      add(:sequence, :bigint)
      add(:resource_type, :string)
      add(:resource_id, :string)
      add(:resource_revision, :bigint)
      add(:request_id, :string)
      add(:correlation_id, :string)
      add(:client_reference, :string)
      add(:provider_occurred_at, :utc_datetime_usec)
      add(:received_at, :utc_datetime_usec, null: false)
      add(:payload_document, :map, null: false)
      add(:content_sha256, :string, null: false)
      add(:provider_evidence_id, :string)
      add(:processing_state, :string, null: false)
      add(:attempt_count, :integer, null: false, default: 0)
      add(:last_attempted_at, :utc_datetime_usec)
      add(:processed_at, :utc_datetime_usec)
      add(:error_document, :map, null: false, default: %{})
      add(:identity_collision, :boolean, null: false, default: false)
      add(:mission_id, :string)
      add(:provider_id, :string)
      add(:provider_reservation_id, :string)
      add(:scheduled_contact_id, :string)
      add(:contact_id, :string)
      timestamps(type: :utc_datetime_usec)
    end

    create(
      unique_index(
        :provider_event_inbox,
        [
          :organization_id,
          :provider_account_id,
          :provider_account_version,
          :environment_ref,
          :channel_ref,
          :provider_event_id,
          :content_sha256
        ],
        name: :provider_event_inbox_content_identity_idx
      )
    )

    create(
      index(
        :provider_event_inbox,
        [
          :organization_id,
          :provider_account_id,
          :provider_account_version,
          :environment_ref,
          :channel_ref,
          :provider_event_id
        ],
        name: :provider_event_inbox_identity_idx
      )
    )

    create(
      index(:provider_event_inbox, [:processing_state, :received_at],
        name: :provider_event_inbox_processing_idx
      )
    )

    execute("""
    ALTER TABLE provider_event_inbox
    ADD CONSTRAINT provider_event_inbox_account_version_fk
    FOREIGN KEY (organization_id, provider_account_id, provider_account_version)
    REFERENCES provider_account_versions (organization_id, provider_account_id, version)
    """)

    execute("""
    ALTER TABLE provider_event_inbox
    ADD CONSTRAINT provider_event_inbox_cursor_fk
    FOREIGN KEY (provider_event_cursor_id)
    REFERENCES provider_event_cursors (provider_event_cursor_id)
    """)

    execute("""
    ALTER TABLE provider_event_inbox
    ADD CONSTRAINT provider_event_inbox_evidence_fk
    FOREIGN KEY (provider_evidence_id)
    REFERENCES provider_evidence (provider_evidence_id)
    """)
  end
end
