defmodule Cadence.Repo.Migrations.CreateFrontendReleasePublicationTables do
  use Ecto.Migration

  @tables [
    :frontend_release_catalog_publications,
    :frontend_release_artifacts,
    :frontend_release_publications
  ]

  def up do
    create table(:frontend_release_publications, primary_key: false) do
      add(:publication_id, :string, primary_key: true)
      add(:release_id, :string, null: false)
      add(:application_id, :string, null: false)
      add(:application_version, :integer, null: false)
      add(:package_id, :string, null: false)
      add(:package_version, :integer, null: false)
      add(:surface_id, :string, null: false)
      add(:surface_version, :integer, null: false)
      add(:remote_name, :string, null: false)
      add(:exposed_module, :string, null: false)
      add(:artifact_base_url, :string, null: false)
      add(:payload_digest, :string, null: false)
      add(:signed_document_digest, :string, null: false)
      add(:signed_document_bytes, :binary, null: false)
      add(:payload_bytes, :binary, null: false)
      add(:signing_key_id, :string, null: false)
      add(:signing_role, :string, null: false)
      add(:provenance, :map, null: false, default: %{})
      add(:released_at, :utc_datetime_usec, null: false)
      add(:artifact_count, :integer, null: false)
      add(:acceptance_state, :string, null: false, default: "accepted")
      add(:accepted_at, :utc_datetime_usec, null: false)
      add(:metadata, :map, null: false, default: %{})

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create(
      unique_index(:frontend_release_publications, [:release_id],
        name: :frontend_release_publications_release_idx
      )
    )

    create(
      unique_index(:frontend_release_publications, [:payload_digest],
        name: :frontend_release_publications_payload_digest_idx
      )
    )

    create(
      unique_index(:frontend_release_publications, [:signed_document_digest],
        name: :frontend_release_publications_signed_document_digest_idx
      )
    )

    create(
      unique_index(:frontend_release_publications, [:publication_id, :release_id],
        name: :frontend_release_publications_publication_release_idx
      )
    )

    create(
      constraint(:frontend_release_publications, :frontend_release_publications_release_id_check,
        check: "release_id ~ '^sha256:[0-9a-f]{64}$'"
      )
    )

    create(
      constraint(
        :frontend_release_publications,
        :frontend_release_publications_payload_digest_check,
        check: "payload_digest ~ '^sha256:[0-9a-f]{64}$'"
      )
    )

    create(
      constraint(
        :frontend_release_publications,
        :frontend_release_publications_signed_document_digest_check,
        check: "signed_document_digest ~ '^sha256:[0-9a-f]{64}$'"
      )
    )

    create(
      constraint(
        :frontend_release_publications,
        :frontend_release_publications_artifact_count_check,
        check: "artifact_count > 0"
      )
    )

    create(
      constraint(
        :frontend_release_publications,
        :frontend_release_publications_signing_role_check,
        check: "signing_role = 'release'"
      )
    )

    create(
      constraint(
        :frontend_release_publications,
        :frontend_release_publications_acceptance_state_check,
        check: "acceptance_state = 'accepted'"
      )
    )

    create table(:frontend_release_artifacts, primary_key: false) do
      add(:artifact_id, :string, primary_key: true)
      add(:release_publication_id, :string, null: false)
      add(:release_id, :string, null: false)
      add(:path, :string, null: false)
      add(:sha256, :string, null: false)
      add(:size, :bigint, null: false)
      add(:media_type, :string, null: false)
      add(:object_key, :string, null: false)
      add(:metadata, :map, null: false, default: %{})

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create(
      unique_index(:frontend_release_artifacts, [:release_publication_id, :path],
        name: :frontend_release_artifacts_publication_path_idx
      )
    )

    create(
      constraint(:frontend_release_artifacts, :frontend_release_artifacts_sha256_check,
        check: "sha256 ~ '^[0-9a-f]{64}$'"
      )
    )

    create(
      constraint(:frontend_release_artifacts, :frontend_release_artifacts_size_check,
        check: "size >= 0"
      )
    )

    create(
      constraint(:frontend_release_artifacts, :frontend_release_artifacts_object_key_check,
        check: "object_key ~ '^sha256/[0-9a-f]{2}/[0-9a-f]{64}$'"
      )
    )

    execute("""
    ALTER TABLE frontend_release_artifacts
    ADD CONSTRAINT frontend_release_artifacts_release_fk
    FOREIGN KEY (release_publication_id, release_id)
    REFERENCES frontend_release_publications (publication_id, release_id)
    ON DELETE RESTRICT
    """)

    create table(:frontend_release_catalog_publications, primary_key: false) do
      add(:publication_id, :string, primary_key: true)
      add(:sequence, :bigint, null: false)
      add(:catalog_digest, :string, null: false)
      add(:signed_document_digest, :string, null: false)
      add(:signed_document_bytes, :binary, null: false)
      add(:payload_bytes, :binary, null: false)
      add(:signing_key_id, :string, null: false)
      add(:signing_role, :string, null: false)
      add(:published_at, :utc_datetime_usec, null: false)
      add(:expires_at, :utc_datetime_usec, null: false)
      add(:acceptance_state, :string, null: false, default: "accepted")
      add(:accepted_state, :map, null: false)
      add(:release_references, :map, null: false)
      add(:accepted_at, :utc_datetime_usec, null: false)
      add(:metadata, :map, null: false, default: %{})

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create(
      unique_index(:frontend_release_catalog_publications, [:sequence], name: :frcp_sequence_idx)
    )

    create(
      unique_index(:frontend_release_catalog_publications, [:catalog_digest],
        name: :frcp_catalog_digest_idx
      )
    )

    create(
      unique_index(:frontend_release_catalog_publications, [:signed_document_digest],
        name: :frcp_signed_document_digest_idx
      )
    )

    create(
      constraint(
        :frontend_release_catalog_publications,
        :frcp_sequence_check,
        check: "sequence > 0"
      )
    )

    create(
      constraint(
        :frontend_release_catalog_publications,
        :frcp_catalog_digest_check,
        check: "catalog_digest ~ '^sha256:[0-9a-f]{64}$'"
      )
    )

    create(
      constraint(
        :frontend_release_catalog_publications,
        :frcp_signed_document_digest_check,
        check: "signed_document_digest ~ '^sha256:[0-9a-f]{64}$'"
      )
    )

    create(
      constraint(
        :frontend_release_catalog_publications,
        :frcp_signing_role_check,
        check: "signing_role = 'promotion'"
      )
    )

    create(
      constraint(
        :frontend_release_catalog_publications,
        :frcp_acceptance_state_check,
        check: "acceptance_state = 'accepted'"
      )
    )

    create(
      constraint(
        :frontend_release_catalog_publications,
        :frcp_window_check,
        check: "expires_at > published_at"
      )
    )

    execute("""
    CREATE OR REPLACE FUNCTION cadence_reject_frontend_release_publication_mutation()
    RETURNS trigger
    LANGUAGE plpgsql
    AS $$
    BEGIN
      RAISE EXCEPTION 'frontend release publication tables are append-only';
    END;
    $$
    """)

    for table <- Enum.reverse(@tables) do
      execute("""
      CREATE TRIGGER #{table}_append_only
      BEFORE UPDATE OR DELETE ON #{table}
      FOR EACH ROW
      EXECUTE FUNCTION cadence_reject_frontend_release_publication_mutation()
      """)
    end
  end

  def down do
    for table <- @tables do
      execute("DROP TRIGGER IF EXISTS #{table}_append_only ON #{table}")
    end

    execute("DROP FUNCTION IF EXISTS cadence_reject_frontend_release_publication_mutation()")

    drop(table(:frontend_release_catalog_publications))
    drop(table(:frontend_release_artifacts))
    drop(table(:frontend_release_publications))
  end
end
