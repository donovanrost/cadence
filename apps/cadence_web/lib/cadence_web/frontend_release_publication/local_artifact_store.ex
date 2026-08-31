defmodule CadenceWeb.FrontendReleasePublication.LocalArtifactStore do
  @moduledoc """
  Local, immutable, content-addressed artifact storage.

  The root is deliberately configuration-only. Object paths are derived from
  a validated digest and never from a caller-provided artifact path.
  """

  @behaviour CadenceWeb.FrontendReleasePublication.ArtifactStore

  @impl true
  def put(digest, bytes) when is_binary(digest) and is_binary(bytes) do
    with {:ok, root} <- configured_root(),
         :ok <- valid_digest_bytes(digest, bytes),
         {:ok, bucket} <- ensure_bucket(root, digest),
         object_path = object_path(bucket, digest),
         {:ok, status} <- existing_object(object_path, digest, bytes) do
      result_for(status, digest, bytes, bucket, object_path)
    end
  end

  def put(_digest, _bytes), do: {:error, :invalid_artifact_bytes}

  @impl true
  def readback(digest) when is_binary(digest) do
    with {:ok, root} <- configured_root(),
         :ok <- validate_digest(digest),
         {:ok, bucket} <- existing_bucket(root, digest),
         object_path = object_path(bucket, digest),
         {:ok, bytes} <- read_regular_file(object_path),
         :ok <- valid_digest_bytes(digest, bytes) do
      {:ok, bytes}
    end
  end

  def readback(_digest), do: {:error, :invalid_artifact_digest}

  defp result_for(:existing, digest, bytes, bucket, object_path) do
    with {:ok, stored_bytes} <- read_regular_file(object_path),
         :ok <- exact_bytes(stored_bytes, bytes) do
      {:ok,
       %{
         digest: digest,
         object_key: object_key(bucket, digest),
         size: byte_size(bytes),
         status: :existing
       }}
    end
  end

  defp result_for(:missing, digest, bytes, bucket, object_path) do
    temp_path = temporary_path(bucket, digest)

    result =
      case File.open(temp_path, [:write, :binary, :exclusive]) do
        {:ok, io_device} ->
          try do
            with :ok <- write_and_sync(io_device, bytes),
                 :ok <- File.close(io_device),
                 :ok <- regular_single_link(temp_path),
                 {:ok, status} <- install_temp(temp_path, object_path, digest, bytes),
                 {:ok, stored_bytes} <- read_regular_file(object_path),
                 :ok <- valid_digest_bytes(digest, stored_bytes),
                 :ok <- exact_bytes(stored_bytes, bytes) do
              {:ok,
               %{
                 digest: digest,
                 object_key: object_key(bucket, digest),
                 size: byte_size(bytes),
                 status: if(status == :installed, do: :stored, else: :existing)
               }}
            end
          after
            safe_close(io_device)
            safe_remove(temp_path)
          end

        {:error, :eexist} ->
          case existing_object(object_path, digest, bytes) do
            {:ok, :existing} -> result_for(:existing, digest, bytes, bucket, object_path)
            failure -> failure
          end

        {:error, reason} ->
          {:error, {:temporary_file, reason}}
      end

    result
  end

  defp install_temp(temp_path, object_path, digest, bytes) do
    case existing_object(object_path, digest, bytes) do
      {:ok, :existing} ->
        {:ok, :existing}

      {:ok, :missing} ->
        link_temp(temp_path, object_path, digest, bytes)

      failure ->
        failure
    end
  end

  defp link_temp(temp_path, object_path, digest, bytes) do
    case File.ln(temp_path, object_path) do
      :ok ->
        case File.rm(temp_path) do
          :ok -> {:ok, :installed}
          {:error, reason} -> {:error, {:temporary_file_cleanup, reason}}
        end

      {:error, :eexist} ->
        case existing_object(object_path, digest, bytes) do
          {:ok, :existing} -> {:ok, :existing}
          failure -> failure
        end

      {:error, reason} ->
        {:error, {:object_install, reason}}
    end
  end

  defp existing_object(object_path, digest, bytes) do
    case File.lstat(object_path) do
      {:error, :enoent} ->
        {:ok, :missing}

      {:ok, %File.Stat{type: :symlink}} ->
        {:error, :destination_symlink}

      {:ok, %File.Stat{type: :regular, links: 1}} ->
        with {:ok, stored_bytes} <- read_regular_file(object_path),
             :ok <- valid_digest_bytes(digest, stored_bytes),
             :ok <- exact_bytes(stored_bytes, bytes) do
          {:ok, :existing}
        else
          {:error, :artifact_bytes_mismatch} -> {:error, :destination_collision}
          {:error, :artifact_digest_mismatch} -> {:error, :destination_collision}
          failure -> failure
        end

      {:ok, %File.Stat{type: :regular}} ->
        {:error, :destination_hardlink}

      {:ok, %File.Stat{type: :directory}} ->
        {:error, :destination_not_regular}

      {:ok, _stat} ->
        {:error, :destination_not_regular}

      {:error, reason} ->
        {:error, {:destination_stat, reason}}
    end
  end

  defp read_regular_file(file_path) do
    with :ok <- existing_directory(Path.dirname(file_path)),
         :ok <- regular_single_link(file_path),
         {:ok, bytes} <- File.read(file_path),
         :ok <- existing_directory(Path.dirname(file_path)),
         :ok <- regular_single_link(file_path) do
      {:ok, bytes}
    else
      {:error, :artifact_store_symlink} -> {:error, :artifact_store_symlink}
      {:error, :artifact_store_not_directory} -> {:error, :artifact_store_not_directory}
      {:error, :destination_symlink} -> {:error, :destination_symlink}
      {:error, :destination_hardlink} -> {:error, :destination_hardlink}
      {:error, :destination_not_regular} -> {:error, :destination_not_regular}
      {:error, reason} -> {:error, {:object_read, reason}}
    end
  end

  defp regular_single_link(file_path) do
    case File.lstat(file_path) do
      {:ok, %File.Stat{type: :regular, links: 1}} -> :ok
      {:ok, %File.Stat{type: :symlink}} -> {:error, :destination_symlink}
      {:ok, %File.Stat{type: :regular}} -> {:error, :destination_hardlink}
      {:ok, _stat} -> {:error, :destination_not_regular}
      {:error, reason} -> {:error, {:object_stat, reason}}
    end
  end

  defp write_and_sync(io_device, bytes) do
    :ok = IO.binwrite(io_device, bytes)
    :file.sync(io_device)
  end

  defp exact_bytes(left, right) when byte_size(left) == byte_size(right) and left == right,
    do: :ok

  defp exact_bytes(_left, _right), do: {:error, :artifact_bytes_mismatch}

  defp valid_digest_bytes(digest, bytes) do
    with :ok <- validate_digest(digest),
         true <- digest == digest_for(bytes) do
      :ok
    else
      false -> {:error, :artifact_digest_mismatch}
      failure -> failure
    end
  end

  defp validate_digest("sha256:" <> hex) when byte_size(hex) == 64 do
    if Regex.match?(~r/\A[0-9a-f]{64}\z/, hex), do: :ok, else: {:error, :invalid_artifact_digest}
  end

  defp validate_digest(_digest), do: {:error, :invalid_artifact_digest}

  defp digest_for(bytes),
    do: "sha256:" <> Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)

  defp configured_root do
    config = Application.get_env(:cadence_web, :frontend_release_publication, [])

    case Keyword.get(config, :artifact_root) do
      root when is_binary(root) and root != "" ->
        if Path.type(root) == :absolute do
          {:ok, Path.expand(root)}
        else
          {:error, :artifact_store_root_not_absolute}
        end

      _ ->
        {:error, :artifact_store_root_not_configured}
    end
  end

  defp ensure_bucket(root, digest) do
    with :ok <- ensure_directory(root),
         sha_root = Path.join(root, "sha256"),
         :ok <- ensure_directory(sha_root),
         bucket = Path.join(sha_root, digest_bucket(digest)),
         :ok <- ensure_directory(bucket) do
      {:ok, bucket}
    end
  end

  defp existing_bucket(root, digest) do
    with :ok <- existing_directory(root),
         sha_root = Path.join(root, "sha256"),
         :ok <- existing_directory(sha_root),
         bucket = Path.join(sha_root, digest_bucket(digest)),
         :ok <- existing_directory(bucket) do
      {:ok, bucket}
    end
  end

  defp digest_bucket("sha256:" <> hex), do: binary_part(hex, 0, 2)

  defp object_path(bucket, "sha256:" <> hex), do: Path.join(bucket, hex)

  defp object_key(bucket, digest) do
    root =
      Path.expand(
        Keyword.fetch!(
          Application.get_env(:cadence_web, :frontend_release_publication, []),
          :artifact_root
        )
      )

    Path.relative_to(Path.join(bucket, binary_part(digest, 7, 64)), root)
  end

  defp temporary_path(bucket, "sha256:" <> hex) do
    Path.join(
      bucket,
      ".tmp-" <> hex <> "-" <> Integer.to_string(System.unique_integer([:positive]))
    )
  end

  defp ensure_directory(path) do
    path
    |> Path.split()
    |> Enum.reduce_while({:ok, ""}, &ensure_directory_step/2)
    |> case do
      {:ok, _path} -> :ok
      {:error, _} = failure -> failure
    end
  end

  defp ensure_directory_step(file_path, {:ok, current_path}) do
    next_path = if current_path == "", do: file_path, else: Path.join(current_path, file_path)

    case File.lstat(next_path) do
      {:ok, %File.Stat{type: :directory}} ->
        {:cont, {:ok, next_path}}

      {:ok, %File.Stat{type: :symlink}} ->
        {:halt, {:error, :artifact_store_symlink}}

      {:ok, _stat} ->
        {:halt, {:error, :artifact_store_not_directory}}

      {:error, :enoent} ->
        mkdir_directory_component(next_path)

      {:error, reason} ->
        {:halt, {:error, {:artifact_store_stat, reason}}}
    end
  end

  defp mkdir_directory_component(path) do
    case File.mkdir(path) do
      :ok -> {:cont, {:ok, path}}
      {:error, :eexist} -> {:cont, verify_directory_component(path)}
      {:error, reason} -> {:halt, {:error, {:artifact_store_mkdir, reason}}}
    end
  end

  defp existing_directory(path) do
    path
    |> Path.split()
    |> Enum.reduce_while({:ok, ""}, fn file_path, {:ok, current_path} ->
      next_path = if current_path == "", do: file_path, else: Path.join(current_path, file_path)

      case File.lstat(next_path) do
        {:ok, %File.Stat{type: :directory}} -> {:cont, {:ok, next_path}}
        {:ok, %File.Stat{type: :symlink}} -> {:halt, {:error, :artifact_store_symlink}}
        {:ok, _stat} -> {:halt, {:error, :artifact_store_not_directory}}
        {:error, reason} -> {:halt, {:error, {:artifact_store_stat, reason}}}
      end
    end)
    |> case do
      {:ok, _path} -> :ok
      {:error, _} = failure -> failure
    end
  end

  defp verify_directory_component(path) do
    case File.lstat(path) do
      {:ok, %File.Stat{type: :directory}} -> {:ok, path}
      {:ok, %File.Stat{type: :symlink}} -> {:error, :artifact_store_symlink}
      {:ok, _stat} -> {:error, :artifact_store_not_directory}
      {:error, reason} -> {:error, {:artifact_store_stat, reason}}
    end
  end

  defp safe_close(io_device) do
    _ = File.close(io_device)
    :ok
  end

  defp safe_remove(file_path) do
    _ = File.rm(file_path)
    :ok
  end
end
