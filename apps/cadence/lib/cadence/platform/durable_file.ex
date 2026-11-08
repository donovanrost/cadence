defmodule Cadence.Platform.DurableFile do
  @moduledoc "Durable filesystem publication with immutable object collision checks."

  @spec write_new(Path.t(), binary()) :: :ok | {:error, term()}
  def write_new(path, contents) do
    publish(path, contents, fn temporary ->
      case File.ln(temporary, path) do
        :ok -> :ok
        {:error, :eexist} -> verify(path, contents)
        error -> error
      end
    end)
  end

  @spec replace(Path.t(), binary()) :: :ok | {:error, term()}
  def replace(path, contents), do: publish(path, contents, &File.rename(&1, path))

  @spec mkdir_p(Path.t()) :: :ok | {:error, term()}
  def mkdir_p(path) do
    if File.dir?(path) do
      :ok
    else
      with :ok <- mkdir_p(Path.dirname(path)),
           :ok <- File.mkdir_p(path) do
        sync_directory(Path.dirname(path))
      end
    end
  end

  @spec sync_directory(Path.t()) :: :ok | {:error, term()}
  def sync_directory(path) do
    with {:ok, file} <- :file.open(path, [:read, :raw, :directory]) do
      try do
        :file.sync(file)
      after
        :file.close(file)
      end
    end
  end

  defp publish(path, contents, install) do
    suffix = Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)
    temporary = path <> "." <> suffix <> ".tmp"

    try do
      with :ok <- mkdir_p(Path.dirname(path)),
           :ok <- write_synced(temporary, contents),
           :ok <- install.(temporary) do
        sync_directory(Path.dirname(path))
      end
    after
      File.rm(temporary)
    end
  end

  defp write_synced(path, contents) do
    with {:ok, file} <- :file.open(path, [:write, :binary, :raw, :exclusive]) do
      try do
        with :ok <- :file.write(file, contents), do: :file.sync(file)
      after
        :file.close(file)
      end
    end
  end

  defp verify(path, contents) do
    case File.read(path) do
      {:ok, ^contents} -> :ok
      {:ok, _different} -> {:error, {:immutable_file_collision, path}}
      error -> error
    end
  end
end
