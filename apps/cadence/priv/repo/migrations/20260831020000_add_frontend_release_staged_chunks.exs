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
    CREATE TRIGGER frontend_release_staged_objects_immutable
    BEFORE UPDATE ON frontend_release_staged_objects
    FOR EACH ROW
    EXECUTE FUNCTION cadence_reject_frontend_release_publication_mutation()
    """)

    execute("""
    CREATE TRIGGER frontend_release_staged_object_chunks_immutable
    BEFORE UPDATE ON frontend_release_staged_object_chunks
    FOR EACH ROW
    EXECUTE FUNCTION cadence_reject_frontend_release_publication_mutation()
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
      "ALTER TABLE frontend_release_objects DISABLE TRIGGER frontend_release_objects_append_only"
    )

    execute(&restore_chunk_backed_bytes/0)

    execute(
      "ALTER TABLE frontend_release_objects ENABLE TRIGGER frontend_release_objects_append_only"
    )

    execute(
      "DROP TRIGGER IF EXISTS frontend_release_object_chunks_append_only ON frontend_release_object_chunks"
    )

    execute(
      "DROP TRIGGER IF EXISTS frontend_release_object_chunks_truncate_protection ON frontend_release_object_chunks"
    )

    execute(
      "DROP TRIGGER IF EXISTS frontend_release_staged_object_chunks_immutable ON frontend_release_staged_object_chunks"
    )

    execute(
      "DROP TRIGGER IF EXISTS frontend_release_staged_objects_immutable ON frontend_release_staged_objects"
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

  defp restore_chunk_backed_bytes do
    migration_repo = repo()

    %{rows: objects} =
      migration_repo.query!("""
      SELECT sha256, size
      FROM frontend_release_objects
      WHERE bytes IS NULL
      ORDER BY sha256
      """)

    Enum.each(objects, &restore_chunk_backed_object(migration_repo, &1))
  end

  defp restore_chunk_backed_object(migration_repo, [sha256, size]) do
    unless is_binary(sha256) and is_integer(size) and size >= 0 and size <= 100_000_000 do
      migration_failure!(sha256, :invalid_object_metadata)
    end

    %{rows: chunks} =
      migration_repo.query!("""
      SELECT chunk_index, bytes, size
      FROM frontend_release_object_chunks
      WHERE sha256 = $1
      ORDER BY chunk_index
      """, [sha256])

    {total_size, hash_state, parts} =
      Enum.reduce(Enum.with_index(chunks), {0, :crypto.hash_init(:sha256), []}, fn
        {[chunk_index, bytes, chunk_size], expected_index}, {total_size, hash_state, parts}
        when chunk_index == expected_index and is_binary(bytes) and is_integer(chunk_size) and
               chunk_size > 0 and chunk_size <= 1_048_576 and byte_size(bytes) == chunk_size ->
          next_size = total_size + chunk_size

          if next_size > 100_000_000 do
            migration_failure!(sha256, :object_too_large)
          end

          {next_size, :crypto.hash_update(hash_state, bytes), [bytes | parts]}

        _invalid_chunk, _accumulator ->
          migration_failure!(sha256, :invalid_or_noncontiguous_chunk)
      end)

    bytes = IO.iodata_to_binary(Enum.reverse(parts))

    if total_size != size or byte_size(bytes) != size or digest_hex(:crypto.hash_final(hash_state)) != sha256 do
      migration_failure!(sha256, :incomplete_or_digest_mismatched_chunks)
    end

    case migration_repo.query!("""
         UPDATE frontend_release_objects
         SET bytes = $2
         WHERE sha256 = $1 AND bytes IS NULL
         """, [sha256, bytes]) do
      %{num_rows: 1} -> :ok
      _result -> migration_failure!(sha256, :object_restore_not_applied)
    end
  end

  defp restore_chunk_backed_object(_migration_repo, invalid_object),
    do: migration_failure!(inspect(invalid_object), :invalid_object_row)

  defp migration_failure!(sha256, reason) do
    raise Ecto.MigrationError,
      "cannot restore frontend release object #{inspect(sha256)}: #{reason}"
  end

  defp digest_hex(bytes), do: Base.encode16(bytes, case: :lower)
end
