defmodule Cadence.Repo.Migrations.AddFrontendReleaseObjects do
  use Ecto.Migration

  @publication_tables [
    :frontend_release_catalog_publications,
    :frontend_release_artifacts,
    :frontend_release_publications
  ]

  def up do
    create table(:frontend_release_objects, primary_key: false) do
      add(:sha256, :string, primary_key: true)
      add(:bytes, :binary, null: false)
      add(:size, :bigint, null: false)
      add(:inserted_at, :utc_datetime_usec, null: false)
    end

    create(
      constraint(:frontend_release_objects, :frontend_release_objects_sha256_check,
        check: "sha256 ~ '^[0-9a-f]{64}$'"
      )
    )

    create(
      constraint(:frontend_release_objects, :frontend_release_objects_size_check,
        check: "size >= 0 AND size <= 100000000"
      )
    )

    create(
      constraint(:frontend_release_objects, :frontend_release_objects_octet_length_check,
        check: "octet_length(bytes) = size AND octet_length(bytes) <= 100000000"
      )
    )

    drop(constraint(:frontend_release_artifacts, :frontend_release_artifacts_size_check))

    create(
      constraint(:frontend_release_artifacts, :frontend_release_artifacts_size_check,
        check: "size >= 0 AND size <= 100000000"
      )
    )

    drop(constraint(:frontend_release_artifacts, :frontend_release_artifacts_object_key_check))

    create(
      constraint(:frontend_release_artifacts, :frontend_release_artifacts_object_key_check,
        check: "object_key = 'sha256:' || sha256"
      )
    )

    execute("""
    ALTER TABLE frontend_release_artifacts
    ADD CONSTRAINT frontend_release_artifacts_object_fk
    FOREIGN KEY (sha256)
    REFERENCES frontend_release_objects (sha256)
    ON UPDATE RESTRICT
    ON DELETE RESTRICT
    """)

    execute("""
    CREATE OR REPLACE FUNCTION cadence_enforce_frontend_release_artifact_size_cap()
    RETURNS trigger
    LANGUAGE plpgsql
    AS $$
    DECLARE
      total_size bigint;
    BEGIN
      PERFORM 1
      FROM frontend_release_publications
      WHERE publication_id = NEW.release_publication_id
      FOR UPDATE;

      SELECT COALESCE(SUM(size), 0) + NEW.size
      INTO total_size
      FROM frontend_release_artifacts
      WHERE release_publication_id = NEW.release_publication_id;

      IF total_size > 100000000 THEN
        RAISE EXCEPTION 'frontend release artifact byte cap exceeded';
      END IF;

      RETURN NEW;
    END;
    $$
    """)

    execute("""
    CREATE TRIGGER frontend_release_artifacts_size_cap
    BEFORE INSERT ON frontend_release_artifacts
    FOR EACH ROW
    EXECUTE FUNCTION cadence_enforce_frontend_release_artifact_size_cap()
    """)

    for table <- @publication_tables do
      execute("""
      CREATE TRIGGER #{table}_truncate_protection
      BEFORE TRUNCATE ON #{table}
      FOR EACH STATEMENT
      EXECUTE FUNCTION cadence_reject_frontend_release_publication_mutation()
      """)
    end

    execute("""
    CREATE TRIGGER frontend_release_objects_append_only
    BEFORE UPDATE OR DELETE ON frontend_release_objects
    FOR EACH ROW
    EXECUTE FUNCTION cadence_reject_frontend_release_publication_mutation()
    """)

    execute("""
    CREATE TRIGGER frontend_release_objects_truncate_protection
    BEFORE TRUNCATE ON frontend_release_objects
    FOR EACH STATEMENT
    EXECUTE FUNCTION cadence_reject_frontend_release_publication_mutation()
    """)
  end

  def down do
    execute(
      "DROP TRIGGER IF EXISTS frontend_release_artifacts_size_cap ON frontend_release_artifacts"
    )

    execute("DROP FUNCTION IF EXISTS cadence_enforce_frontend_release_artifact_size_cap()")

    execute(
      "ALTER TABLE frontend_release_artifacts DROP CONSTRAINT IF EXISTS frontend_release_artifacts_object_fk"
    )

    execute(
      "DROP TRIGGER IF EXISTS frontend_release_objects_append_only ON frontend_release_objects"
    )

    execute(
      "DROP TRIGGER IF EXISTS frontend_release_objects_truncate_protection ON frontend_release_objects"
    )

    drop(table(:frontend_release_objects))

    for table <- @publication_tables do
      execute("DROP TRIGGER IF EXISTS #{table}_truncate_protection ON #{table}")
    end

    drop(constraint(:frontend_release_artifacts, :frontend_release_artifacts_object_key_check))

    create(
      constraint(:frontend_release_artifacts, :frontend_release_artifacts_object_key_check,
        check: "object_key ~ '^sha256/[0-9a-f]{2}/[0-9a-f]{64}$'"
      )
    )

    drop(constraint(:frontend_release_artifacts, :frontend_release_artifacts_size_check))

    create(
      constraint(:frontend_release_artifacts, :frontend_release_artifacts_size_check,
        check: "size >= 0"
      )
    )
  end
end
