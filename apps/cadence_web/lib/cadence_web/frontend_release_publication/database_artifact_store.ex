defmodule CadenceWeb.FrontendReleasePublication.DatabaseArtifactStore do
  @moduledoc "Bounded content-addressed storage backed by Cadence.Repo and PostgreSQL."

  @behaviour CadenceWeb.FrontendReleasePublication.ArtifactStore

  alias Cadence.Repo

  @max_object_size 100_000_000
  @max_chunk_size 1_048_576

  @impl true
  def put(digest, bytes) when is_binary(digest) and is_binary(bytes) do
    with {:ok, sha256} <- parse_digest(digest),
         :ok <- validate_bytes(sha256, bytes),
         {:ok, status} <- insert_object(sha256, bytes) do
      case verify(digest, bytes) do
        :ok ->
          {:ok,
           %{
             digest: digest,
             object_key: digest,
             size: byte_size(bytes),
             status: status
           }}

        failure ->
          failure
      end
    end
  end

  def put(_digest, _bytes), do: {:error, :invalid_artifact_bytes}

  @impl true
  def verify(digest, expected) when is_binary(digest) and is_binary(expected) do
    with {:ok, sha256} <- parse_digest(digest),
         :ok <- validate_bytes(sha256, expected),
         {:ok, size} <- object_size(sha256),
         :ok <- expected_size(size, byte_size(expected)) do
      verify_chunks(sha256, expected, size, 0, :crypto.hash_init(:sha256))
    end
  end

  def verify(digest, expected_size) when is_binary(digest) and is_integer(expected_size) do
    with {:ok, sha256} <- parse_digest(digest),
         :ok <- validate_size(expected_size),
         {:ok, size} <- object_size(sha256),
         :ok <- expected_size(size, expected_size) do
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

  defp object_size(sha256) do
    case Repo.query(
           """
           SELECT size, octet_length(bytes)
           FROM frontend_release_objects
           WHERE sha256 = $1
           """,
           [sha256]
         ) do
      {:ok, %{rows: [[size, octet_length]]}} when size == octet_length -> {:ok, size}
      {:ok, %{rows: [[_size, _octet_length]]}} -> {:error, :stored_object_size_mismatch}
      {:ok, %{rows: []}} -> {:error, :artifact_not_found}
      {:ok, _result} -> {:error, :invalid_object_metadata}
      {:error, reason} -> {:error, {:object_metadata, reason}}
    end
  end

  defp select_chunk(sha256, offset, length) do
    case Repo.query(
           """
           SELECT substring(bytes FROM $2 FOR $3)
           FROM frontend_release_objects
           WHERE sha256 = $1
           """,
           [sha256, offset + 1, length]
         ) do
      {:ok, %{rows: [[bytes]]}} when is_binary(bytes) -> {:ok, bytes}
      {:ok, %{rows: []}} -> {:error, :artifact_not_found}
      {:ok, _result} -> {:error, :invalid_object_chunk}
      {:error, reason} -> {:error, {:object_chunk, reason}}
    end
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

  defp digest_hex(binary), do: Base.encode16(binary, case: :lower)
end
