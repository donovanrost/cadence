defmodule Cadence.Repo.Migrations.AddFrontendReleaseStagedChunks do
  use Ecto.Migration

  def up do
    alter table(:frontend_release_objects) do
      modify(:bytes, :binary, null: true)
    end

    drop(constraint(:frontend_release_objects, :frontend_release_objects_octet_length_check))

    create(
      constraint(:frontend_release_objects, :frontend_release_objects_octet_length_check,
        check:
          "bytes IS NULL OR (octet_length(bytes) = size AND octet_length(bytes) <= 100000000)"
      )
    )

    create table(:frontend_release_staged_objects, primary_key: false) do
      add(:sha256, :string, primary_key: true)
      add(:size, :bigint, null: false)
      add(:expires_at, :utc_datetime_usec, null: false)
      add(:inserted_at, :utc_datetime_usec, null: false)
    end

    create(
      constraint(:frontend_release_staged_objects, :frontend_release_staged_objects_sha256_check,
        check: "sha256 ~ '^[0-9a-f]{64}$'"
      )
    )

    create(
      constraint(:frontend_release_staged_objects, :frontend_release_staged_objects_size_check,
        check: "size >= 0 AND size <= 100000000"
      )
    )

    create(
      index(:frontend_release_staged_objects, [:expires_at],
        name: :frontend_release_staged_objects_expiry_idx
      )
    )

    create table(:frontend_release_staged_object_chunks, primary_key: false) do
      add(:sha256, :string, null: false)
      add(:chunk_index, :integer, null: false)
      add(:bytes, :binary, null: false)
      add(:size, :integer, null: false)
      add(:inserted_at, :utc_datetime_usec, null: false)
    end

    create(
      unique_index(:frontend_release_staged_object_chunks, [:sha256, :chunk_index],
        name: :frontend_release_staged_object_chunks_pkey
      )
    )

    create(
      constraint(
        :frontend_release_staged_object_chunks,
        :frontend_release_staged_object_chunks_index_check,
        check: "chunk_index >= 0"
      )
    )

    create(
      constraint(
        :frontend_release_staged_object_chunks,
        :frontend_release_staged_object_chunks_size_check,
        check: "size > 0 AND size <= 1048576 AND octet_length(bytes) = size"
      )
    )

    execute("""
    ALTER TABLE frontend_release_staged_object_chunks
    ADD CONSTRAINT frontend_release_staged_object_chunks_object_fk
    FOREIGN KEY (sha256)
    REFERENCES frontend_release_staged_objects (sha256)
    ON UPDATE RESTRICT
    ON DELETE CASCADE
    """)

    create table(:frontend_release_object_chunks, primary_key: false) do
      add(:sha256, :string, null: false)
      add(:chunk_index, :integer, null: false)
      add(:bytes, :binary, null: false)
      add(:size, :integer, null: false)
      add(:inserted_at, :utc_datetime_usec, null: false)
    end

    create(
      unique_index(:frontend_release_object_chunks, [:sha256, :chunk_index],
        name: :frontend_release_object_chunks_pkey
      )
    )

    create(
      constraint(:frontend_release_object_chunks, :frontend_release_object_chunks_index_check,
        check: "chunk_index >= 0"
      )
    )

    create(
      constraint(:frontend_release_object_chunks, :frontend_release_object_chunks_size_check,
        check: "size > 0 AND size <= 1048576 AND octet_length(bytes) = size"
      )
    )

    execute("""
    ALTER TABLE frontend_release_object_chunks
    ADD CONSTRAINT frontend_release_object_chunks_object_fk
    FOREIGN KEY (sha256)
    REFERENCES frontend_release_objects (sha256)
    ON UPDATE RESTRICT
    ON DELETE RESTRICT
    """)

    execute("""
    CREATE TRIGGER frontend_release_object_chunks_append_only
    BEFORE UPDATE OR DELETE ON frontend_release_object_chunks
    FOR EACH ROW
    EXECUTE FUNCTION cadence_reject_frontend_release_publication_mutation()
    """)

    execute("""
    CREATE TRIGGER frontend_release_object_chunks_truncate_protection
    BEFORE TRUNCATE ON frontend_release_object_chunks
    FOR EACH STATEMENT
    EXECUTE FUNCTION cadence_reject_frontend_release_publication_mutation()
    """)
  end

  def down do
    execute(
      "DROP TRIGGER IF EXISTS frontend_release_object_chunks_append_only ON frontend_release_object_chunks"
    )

    execute(
      "DROP TRIGGER IF EXISTS frontend_release_object_chunks_truncate_protection ON frontend_release_object_chunks"
    )

    drop(table(:frontend_release_object_chunks))
    drop(table(:frontend_release_staged_object_chunks))
    drop(table(:frontend_release_staged_objects))

    drop(constraint(:frontend_release_objects, :frontend_release_objects_octet_length_check))

    create(
      constraint(:frontend_release_objects, :frontend_release_objects_octet_length_check,
        check: "octet_length(bytes) = size AND octet_length(bytes) <= 100000000"
      )
    )

    alter table(:frontend_release_objects) do
      modify(:bytes, :binary, null: false)
    end
  end
end
