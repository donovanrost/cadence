defmodule CadenceWeb.FrontendReleasePublication.DatabaseArtifactStore do
  @moduledoc """
  Bounded content-addressed storage backed by Cadence.Repo and PostgreSQL.

  Inline callers retain the legacy bytea representation. File uploads are
  staged as bounded rows and chunks, then promoted by the release transaction;
  a staged object is deliberately not publicly addressable until promotion.
  """

  @behaviour CadenceWeb.FrontendReleasePublication.ArtifactStore

  alias Cadence.Repo

  @max_object_size 100_000_000
  @max_chunk_size 1_048_576
  @stage_ttl_seconds 86_400

  @type stored_object :: %{
          required(:digest) => binary(),
          required(:object_key) => binary(),
          required(:size) => non_neg_integer(),
          required(:status) => :stored | :existing
        }

  @impl true
  def put(digest, bytes) when is_binary(digest) and is_binary(bytes) do
    with {:ok, sha256} <- parse_digest(digest),
         :ok <- validate_bytes(sha256, bytes),
         {:ok, status} <- insert_object(sha256, bytes),
         :ok <- verify(digest, bytes) do
      {:ok, stored_object(digest, byte_size(bytes), status)}
    end
  end

  def put(_digest, _bytes), do: {:error, :invalid_artifact_bytes}

  @doc "Stages a regular file without retaining the complete file in a process binary."
  @spec put_file(binary(), binary()) :: {:ok, stored_object()} | {:error, term()}
  def put_file(digest, file_path) when is_binary(digest) and is_binary(file_path) do
    case File.stat(file_path) do
      {:ok, %{type: :regular, size: size}} when size <= @max_object_size ->
        stage_regular_file(digest, file_path, size)

      {:ok, _stat} ->
        {:error, :artifact_too_large}

      {:error, _reason} ->
        {:error, :artifact_file_unreadable}
    end
  end

  def put_file(_digest, _file_path), do: {:error, :artifact_file_unreadable}

  defp stage_regular_file(digest, file_path, size) do
    case File.open(file_path, [:read, :binary]) do
      {:ok, io_device} ->
        try do
          transaction_result =
            Repo.transaction(fn ->
              case stage_file(io_device, digest, size) do
                {:ok, staged} -> staged
                {:error, reason} -> Repo.rollback(reason)
              end
            end)

          normalize_transaction_result(transaction_result)
        after
          _ = File.close(io_device)
        end

      {:error, _reason} ->
        {:error, :artifact_file_unreadable}
    end
  end

  @doc "Promotes a verified stage into immutable public object storage."
  @spec promote_staged(binary(), non_neg_integer()) ::
          {:ok, stored_object()} | {:error, term()}
  def promote_staged(digest, expected_size)
      when is_binary(digest) and is_integer(expected_size) do
    with {:ok, sha256} <- parse_digest(digest),
         :ok <- validate_size(expected_size),
         {:ok, stage_size} <- staged_object_size(sha256),
         :ok <- expected_size(stage_size, expected_size),
         :ok <- verify_staged_chunks(sha256, stage_size),
         {:ok, status} <- insert_final_object_from_stage(sha256),
         :ok <- verify_existing_final(status, digest, expected_size),
         :ok <- copy_staged_chunks(sha256, status),
         :ok <- delete_stage(sha256) do
      {:ok, stored_object(digest, expected_size, status)}
    end
  end

  def promote_staged(_digest, _expected_size), do: {:error, :invalid_artifact_input}

  @doc "Deletes only expired stages that have no release linkage."
  @spec cleanup_expired_staged_artifacts() :: {:ok, non_neg_integer()} | {:error, term()}
  def cleanup_expired_staged_artifacts do
    case Repo.query("""
         DELETE FROM frontend_release_staged_objects AS staged
         WHERE staged.expires_at < now()
           AND NOT EXISTS (
             SELECT 1
             FROM frontend_release_artifacts AS artifact
             WHERE artifact.sha256 = staged.sha256
           )
         """) do
      {:ok, %{num_rows: count}} -> {:ok, count}
      {:error, reason} -> {:error, {:stage_cleanup, reason}}
    end
  end

  @impl true
  def verify(digest, expected) when is_binary(digest) and is_binary(expected) do
    with {:ok, sha256} <- parse_digest(digest),
         :ok <- validate_bytes(sha256, expected),
         {:ok, {size, storage_kind}} <- object_storage_kind(sha256),
         :ok <- expected_size(size, byte_size(expected)),
         :ok <- validate_chunk_topology(sha256, size, storage_kind) do
      verify_chunks(sha256, expected, size, 0, :crypto.hash_init(:sha256))
    end
  end

  def verify(digest, expected_size) when is_binary(digest) and is_integer(expected_size) do
    with {:ok, sha256} <- parse_digest(digest),
         :ok <- validate_size(expected_size),
         {:ok, {size, storage_kind}} <- object_storage_kind(sha256),
         :ok <- expected_size(size, expected_size),
         :ok <- validate_chunk_topology(sha256, size, storage_kind) do
      verify_chunks(sha256, nil, size, 0, :crypto.hash_init(:sha256))
    end
  end

  def verify(_digest, _expected), do: {:error, :invalid_artifact_bytes}

  @impl true
  def read_chunk(digest, offset, length)
      when is_binary(digest) and is_integer(offset) and is_integer(length) do
    with {:ok, sha256} <- parse_digest(digest),
         :ok <- validate_offset(offset),
         :ok <- validate_chunk_length(length) do
      select_chunk(sha256, offset, length)
    end
  end

  def read_chunk(_digest, _offset, _length), do: {:error, :invalid_chunk_bounds}

  defp stage_file(io_device, digest, size) do
    with {:ok, sha256} <- parse_digest(digest),
         :ok <- validate_size(size),
         {:ok, status} <- insert_staged_object(sha256, size) do
      case status do
        :stored ->
          stream_file_to_stage(io_device, sha256, size, 0, 0, :crypto.hash_init(:sha256))

        :existing ->
          verify_file_against_stage(io_device, sha256, size)
      end
      |> case do
        {:ok, _} -> {:ok, stored_object(digest, size, status)}
        failure -> failure
      end
    end
  end

  defp insert_staged_object(sha256, size) do
    case Repo.query(
           """
           INSERT INTO frontend_release_staged_objects
             (sha256, size, expires_at, inserted_at)
           VALUES ($1, $2, now() + interval '#{@stage_ttl_seconds} seconds', now())
           ON CONFLICT (sha256) DO NOTHING
           """,
           [sha256, size]
         ) do
      {:ok, %{num_rows: 1}} -> {:ok, :stored}
      {:ok, %{num_rows: 0}} -> {:ok, :existing}
      {:ok, _result} -> {:error, :invalid_stage_insert_result}
      {:error, reason} -> {:error, {:object_insert, reason}}
    end
  end

  defp stream_file_to_stage(io_device, sha256, size, offset, chunk_index, hash_state) do
    case IO.binread(io_device, @max_chunk_size) do
      :eof ->
        finish_file_stage(sha256, size, offset, hash_state)

      chunk when is_binary(chunk) and byte_size(chunk) > 0 ->
        stage_file_chunk(
          io_device,
          sha256,
          size,
          offset,
          chunk_index,
          hash_state,
          chunk
        )

      <<>> ->
        {:error, :artifact_file_unreadable}

      {:error, _reason} ->
        {:error, :artifact_file_unreadable}
    end
  end

  defp finish_file_stage(sha256, size, size, hash_state) do
    if digest_hex(:crypto.hash_final(hash_state)) == sha256,
      do: {:ok, :staged},
      else: {:error, :artifact_digest_mismatch}
  end

  defp finish_file_stage(_sha256, _size, _offset, _hash_state),
    do: {:error, :artifact_size_mismatch}

  defp stage_file_chunk(io_device, sha256, size, offset, chunk_index, hash_state, chunk) do
    new_offset = offset + byte_size(chunk)

    if new_offset > size do
      {:error, :artifact_size_mismatch}
    else
      case insert_staged_chunk(sha256, chunk_index, chunk) do
        :ok ->
          stream_file_to_stage(
            io_device,
            sha256,
            size,
            new_offset,
            chunk_index + 1,
            :crypto.hash_update(hash_state, chunk)
          )

        failure ->
          failure
      end
    end
  end

  defp insert_staged_chunk(sha256, chunk_index, chunk) do
    case Repo.query(
           """
           INSERT INTO frontend_release_staged_object_chunks
             (sha256, chunk_index, bytes, size, inserted_at)
           VALUES ($1, $2, $3, $4, now())
           """,
           [sha256, chunk_index, chunk, byte_size(chunk)]
         ) do
      {:ok, %{num_rows: 1}} -> :ok
      {:ok, _result} -> {:error, :invalid_stage_chunk_result}
      {:error, reason} -> {:error, {:object_chunk, reason}}
    end
  end

  defp verify_file_against_stage(io_device, sha256, size) do
    with {:ok, stored_size} <- staged_object_size(sha256),
         :ok <- expected_size(stored_size, size) do
      verify_file_chunks(
        io_device,
        sha256,
        size,
        0,
        :crypto.hash_init(:sha256),
        &select_staged_chunk(sha256, &1)
      )
    end
  end

  defp verify_file_chunks(io_device, sha256, size, offset, hash_state, read_chunk_fun)
       when offset < size do
    length = min(@max_chunk_size, size - offset)

    case IO.binread(io_device, length) do
      chunk when is_binary(chunk) and byte_size(chunk) == length ->
        with {:ok, stored_chunk} <- read_chunk_fun.(div(offset, @max_chunk_size)),
             :ok <- compare_full_chunk(stored_chunk, chunk),
             next_state <- :crypto.hash_update(hash_state, chunk) do
          verify_file_chunks(
            io_device,
            sha256,
            size,
            offset + length,
            next_state,
            read_chunk_fun
          )
        end

      chunk when is_binary(chunk) ->
        {:error, :artifact_size_mismatch}

      :eof ->
        {:error, :artifact_size_mismatch}

      {:error, _reason} ->
        {:error, :artifact_file_unreadable}
    end
  end

  defp verify_file_chunks(io_device, sha256, size, size, hash_state, _read_chunk_fun) do
    case IO.binread(io_device, 1) do
      :eof ->
        if digest_hex(:crypto.hash_final(hash_state)) == sha256,
          do: {:ok, :verified},
          else: {:error, :artifact_digest_mismatch}

      extra when is_binary(extra) ->
        {:error, :artifact_size_mismatch}

      {:error, _reason} ->
        {:error, :artifact_file_unreadable}
    end
  end

  defp verify_staged_chunks(sha256, size) do
    verify_chunks_with_reader(
      sha256,
      size,
      0,
      0,
      :crypto.hash_init(:sha256),
      &select_staged_chunk(sha256, &1)
    )
  end

  defp verify_chunks_with_reader(sha256, size, offset, _chunk_index, hash_state, _reader)
       when offset == size do
    if digest_hex(:crypto.hash_final(hash_state)) == sha256,
      do: :ok,
      else: {:error, :artifact_digest_mismatch}
  end

  defp verify_chunks_with_reader(sha256, size, offset, _chunk_index, hash_state, reader)
       when offset < size do
    length = min(@max_chunk_size, size - offset)

    with {:ok, chunk} <- reader.(div(offset, @max_chunk_size)),
         :ok <- chunk_length(chunk, length),
         next_state <- :crypto.hash_update(hash_state, chunk) do
      verify_chunks_with_reader(
        sha256,
        size,
        offset + length,
        div(offset, @max_chunk_size) + 1,
        next_state,
        reader
      )
    end
  end

  defp insert_final_object_from_stage(sha256) do
    case Repo.query(
           """
           INSERT INTO frontend_release_objects (sha256, bytes, size, inserted_at)
           SELECT sha256, NULL, size, now()
           FROM frontend_release_staged_objects
           WHERE sha256 = $1
           ON CONFLICT (sha256) DO NOTHING
           """,
           [sha256]
         ) do
      {:ok, %{num_rows: 1}} -> {:ok, :stored}
      {:ok, %{num_rows: 0}} -> {:ok, :existing}
      {:ok, _result} -> {:error, :invalid_object_insert_result}
      {:error, reason} -> {:error, {:object_insert, reason}}
    end
  end

  defp verify_existing_final(:stored, _digest, _size), do: :ok

  defp verify_existing_final(:existing, digest, size),
    do: verify(digest, size)

  defp copy_staged_chunks(_sha256, :existing), do: :ok

  defp copy_staged_chunks(sha256, :stored) do
    case Repo.query(
           """
           INSERT INTO frontend_release_object_chunks
             (sha256, chunk_index, bytes, size, inserted_at)
           SELECT sha256, chunk_index, bytes, size, now()
           FROM frontend_release_staged_object_chunks
           WHERE sha256 = $1
           ORDER BY chunk_index
           """,
           [sha256]
         ) do
      {:ok, _result} -> :ok
      {:error, reason} -> {:error, {:object_chunk, reason}}
    end
  end

  defp delete_stage(sha256) do
    case Repo.query("DELETE FROM frontend_release_staged_objects WHERE sha256 = $1", [sha256]) do
      {:ok, %{num_rows: 1}} -> :ok
      {:ok, %{num_rows: 0}} -> {:error, :staged_artifact_not_found}
      {:ok, _result} -> {:error, :invalid_stage_delete_result}
      {:error, reason} -> {:error, {:object_metadata, reason}}
    end
  end

  defp staged_object_size(sha256) do
    case Repo.query(
           "SELECT size FROM frontend_release_staged_objects WHERE sha256 = $1",
           [sha256]
         ) do
      {:ok, %{rows: [[size]]}} when is_integer(size) -> {:ok, size}
      {:ok, %{rows: []}} -> {:error, :artifact_not_found}
      {:ok, _result} -> {:error, :invalid_stage_metadata}
      {:error, reason} -> {:error, {:object_metadata, reason}}
    end
  end

  defp select_staged_chunk(sha256, chunk_index) do
    case Repo.query(
           """
           SELECT bytes
           FROM frontend_release_staged_object_chunks
           WHERE sha256 = $1 AND chunk_index = $2
           """,
           [sha256, chunk_index]
         ) do
      {:ok, %{rows: [[bytes]]}} when is_binary(bytes) -> {:ok, bytes}
      {:ok, %{rows: []}} -> {:error, :stored_object_size_mismatch}
      {:ok, _result} -> {:error, :invalid_stage_chunk}
      {:error, reason} -> {:error, {:object_chunk, reason}}
    end
  end

  defp insert_object(sha256, bytes) do
    case Repo.query(
           """
           INSERT INTO frontend_release_objects (sha256, bytes, size, inserted_at)
           VALUES ($1, $2, $3, now())
           ON CONFLICT (sha256) DO NOTHING
           """,
           [sha256, bytes, byte_size(bytes)]
         ) do
      {:ok, %{num_rows: 1}} -> {:ok, :stored}
      {:ok, %{num_rows: 0}} -> {:ok, :existing}
      {:ok, _result} -> {:error, :invalid_object_insert_result}
      {:error, reason} -> {:error, {:object_insert, reason}}
    end
  end

  defp object_storage_kind(sha256) do
    case Repo.query(
           """
           SELECT size, bytes IS NULL
           FROM frontend_release_objects
           WHERE sha256 = $1
           """,
           [sha256]
         ) do
      {:ok, %{rows: [[size, true]]}} when is_integer(size) ->
        {:ok, {size, :chunks}}

      {:ok, %{rows: [[size, false]]}} when is_integer(size) ->
        {:ok, {size, :bytea}}

      {:ok, %{rows: []}} ->
        {:error, :artifact_not_found}

      {:ok, _result} ->
        {:error, :invalid_object_metadata}

      {:error, reason} ->
        {:error, {:object_metadata, reason}}
    end
  end

  defp validate_chunk_topology(_sha256, _size, :bytea), do: :ok

  defp validate_chunk_topology(sha256, size, :chunks) do
    expected_chunk_count = div(size + @max_chunk_size - 1, @max_chunk_size)
    expected_last_index = expected_chunk_count - 1
    expected_final_size = size - max(expected_last_index, 0) * @max_chunk_size
    expected_max_index = expected_max_index(size, expected_last_index)

    case Repo.query(
           """
           SELECT
             COUNT(*),
             COUNT(DISTINCT chunk_index),
             MIN(chunk_index),
             MAX(chunk_index),
             COALESCE(
               BOOL_AND(
                 size = CASE WHEN chunk_index < $2 THEN #{@max_chunk_size} ELSE $3 END
                 AND octet_length(bytes) =
                   CASE WHEN chunk_index < $2 THEN #{@max_chunk_size} ELSE $3 END
               ),
               TRUE
             )
           FROM frontend_release_object_chunks
           WHERE sha256 = $1
           """,
           [sha256, expected_last_index, expected_final_size]
         ) do
      {:ok, %{rows: [[count, distinct_count, min_index, max_index, true]]}} ->
        if count == expected_chunk_count and distinct_count == expected_chunk_count and
             min_index == expected_min_index(expected_chunk_count) and
             max_index == expected_max_index do
          :ok
        else
          {:error, :stored_object_size_mismatch}
        end

      {:ok, %{rows: [[_count, _distinct_count, _min_index, _max_index, _sizes_match]]}} ->
        {:error, :stored_object_size_mismatch}

      {:ok, _result} ->
        {:error, :invalid_object_metadata}

      {:error, reason} ->
        {:error, {:object_metadata, reason}}
    end
  end

  defp expected_min_index(0), do: nil
  defp expected_min_index(_expected_chunk_count), do: 0

  defp expected_max_index(0, _expected_last_index), do: nil
  defp expected_max_index(_size, expected_last_index), do: expected_last_index

  defp select_chunk(sha256, offset, length) do
    case object_storage_kind(sha256) do
      {:ok, {size, :bytea}} -> select_bytea_chunk(sha256, offset, length, size)
      {:ok, {size, :chunks}} -> select_chunk_rows(sha256, offset, length, size)
      failure -> failure
    end
  end

  defp select_bytea_chunk(sha256, offset, length, size) do
    expected_length = min(length, max(size - offset, 0))

    if expected_length == 0 do
      {:ok, <<>>}
    else
      case Repo.query(
             """
             SELECT substring(bytes FROM $2 FOR $3)
             FROM frontend_release_objects
             WHERE sha256 = $1
             """,
             [sha256, offset + 1, expected_length]
           ) do
        {:ok, %{rows: [[bytes]]}} when is_binary(bytes) -> {:ok, bytes}
        {:ok, %{rows: []}} -> {:error, :artifact_not_found}
        {:ok, _result} -> {:error, :invalid_object_chunk}
        {:error, reason} -> {:error, {:object_chunk, reason}}
      end
    end
  end

  defp select_chunk_rows(sha256, offset, length, size) do
    expected_length = min(length, max(size - offset, 0))

    if expected_length == 0 do
      {:ok, <<>>}
    else
      first_index = div(offset, @max_chunk_size)
      last_index = div(offset + expected_length - 1, @max_chunk_size)

      case Repo.query(
             """
             SELECT chunk_index, bytes
             FROM frontend_release_object_chunks
             WHERE sha256 = $1 AND chunk_index BETWEEN $2 AND $3
             ORDER BY chunk_index
             """,
             [sha256, first_index, last_index]
           ) do
        {:ok, %{rows: rows}} -> slice_chunk_rows(rows, offset, expected_length)
        {:error, reason} -> {:error, {:object_chunk, reason}}
      end
    end
  end

  defp slice_chunk_rows(rows, offset, expected_length) do
    {parts, copied} =
      Enum.reduce_while(rows, {[], 0}, fn
        [chunk_index, bytes], {parts, copied} when is_integer(chunk_index) and is_binary(bytes) ->
          chunk_start = chunk_index * @max_chunk_size
          chunk_offset = max(offset - chunk_start, 0)
          available = max(byte_size(bytes) - chunk_offset, 0)
          take = min(available, expected_length - copied)

          if take > 0 do
            {:cont, {[binary_part(bytes, chunk_offset, take) | parts], copied + take}}
          else
            {:cont, {parts, copied}}
          end

        _invalid, _acc ->
          {:halt, {[], -1}}
      end)

    if copied == expected_length,
      do: {:ok, IO.iodata_to_binary(Enum.reverse(parts))},
      else: {:error, :stored_object_size_mismatch}
  end

  defp verify_chunks(sha256, expected, size, offset, hash_state) when offset < size do
    length = min(@max_chunk_size, size - offset)

    with {:ok, chunk} <- read_chunk("sha256:" <> sha256, offset, length),
         :ok <- chunk_length(chunk, length),
         :ok <- compare_chunk(expected, chunk, offset),
         next_state <- :crypto.hash_update(hash_state, chunk) do
      verify_chunks(sha256, expected, size, offset + byte_size(chunk), next_state)
    end
  end

  defp verify_chunks(sha256, _expected, size, size, hash_state) do
    if digest_hex(:crypto.hash_final(hash_state)) == sha256,
      do: :ok,
      else: {:error, :artifact_digest_mismatch}
  end

  defp compare_chunk(nil, _chunk, _offset), do: :ok

  defp compare_chunk(expected, chunk, offset) do
    expected_chunk = binary_part(expected, offset, byte_size(chunk))

    if expected_chunk == chunk,
      do: :ok,
      else: {:error, :artifact_bytes_mismatch}
  end

  defp compare_full_chunk(stored, expected) when stored == expected, do: :ok
  defp compare_full_chunk(_stored, _expected), do: {:error, :artifact_bytes_mismatch}

  defp chunk_length(chunk, length) when byte_size(chunk) == length, do: :ok
  defp chunk_length(_chunk, _length), do: {:error, :stored_object_size_mismatch}

  defp expected_size(size, size), do: :ok
  defp expected_size(_stored_size, _expected_size), do: {:error, :artifact_size_mismatch}

  defp validate_bytes(sha256, bytes) do
    with :ok <- validate_size(byte_size(bytes)),
         true <- digest_hex(:crypto.hash(:sha256, bytes)) == sha256 do
      :ok
    else
      false -> {:error, :artifact_digest_mismatch}
      failure -> failure
    end
  end

  defp validate_size(size) when is_integer(size) and size >= 0 and size <= @max_object_size,
    do: :ok

  defp validate_size(_size), do: {:error, :artifact_too_large}

  defp validate_offset(offset) when offset >= 0 and offset <= @max_object_size, do: :ok
  defp validate_offset(_offset), do: {:error, :invalid_chunk_bounds}

  defp validate_chunk_length(length) when length > 0 and length <= @max_chunk_size, do: :ok
  defp validate_chunk_length(_length), do: {:error, :invalid_chunk_bounds}

  defp parse_digest("sha256:" <> sha256) when byte_size(sha256) == 64 do
    if Regex.match?(~r/\A[0-9a-f]{64}\z/, sha256),
      do: {:ok, sha256},
      else: {:error, :invalid_artifact_digest}
  end

  defp parse_digest(_digest), do: {:error, :invalid_artifact_digest}

  defp stored_object(digest, size, status),
    do: %{digest: digest, object_key: digest, size: size, status: status}

  defp normalize_transaction_result({:ok, value}), do: {:ok, value}
  defp normalize_transaction_result({:error, reason}), do: {:error, reason}

  defp digest_hex(binary), do: Base.encode16(binary, case: :lower)
end
