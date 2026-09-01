defmodule CadenceWeb.Plugs.FrontendReleaseRequestBody do
  @moduledoc """
  Reads publisher request bodies before `Plug.Parsers`.

  The release envelope is retained only within a small JSON cap. Artifact
  uploads are streamed to a private temporary file so an asset bundle is not
  retained as one request-sized process binary.
  """

  import Plug.Conn

  alias CadenceWeb.Plugs.FrontendReleasePublisher

  @max_envelope_bytes 4_000_000
  @max_artifact_bytes 100_000_000
  @read_length 1_048_576
  @read_timeout 15_000
  @staged_artifact_key :cadence_frontend_release_staged_artifact

  @type body_error :: :malformed_body | :oversized_input

  @spec init(Plug.opts()) :: Plug.opts()
  def init(opts), do: opts

  @spec publisher_request?(Plug.Conn.t()) :: boolean()
  def publisher_request?(%Plug.Conn{} = conn),
    do: FrontendReleasePublisher.publisher_request?(conn)

  @spec call(Plug.Conn.t(), Plug.opts()) :: Plug.Conn.t()
  def call(%Plug.Conn{} = conn, _opts) do
    cond do
      FrontendReleasePublisher.artifact_upload_request?(conn) ->
        stage_artifact_body(conn)

      publisher_request?(conn) ->
        read_release_body(conn)

      true ->
        conn
    end
  end

  @spec raw_body(Plug.Conn.t()) :: {:ok, binary()} | {:error, body_error()}
  def raw_body(%Plug.Conn{} = conn) do
    case conn.private[:cadence_frontend_release_raw_body] do
      body when is_binary(body) -> {:ok, body}
      _missing -> {:error, :malformed_body}
    end
  end

  @spec staged_artifact_path(Plug.Conn.t()) :: {:ok, binary()} | {:error, body_error()}
  def staged_artifact_path(%Plug.Conn{} = conn) do
    case conn.private[@staged_artifact_key] do
      file_path when is_binary(file_path) -> {:ok, file_path}
      _missing -> {:error, :malformed_body}
    end
  end

  @spec cleanup_staged_artifact(Plug.Conn.t()) :: Plug.Conn.t()
  def cleanup_staged_artifact(%Plug.Conn{} = conn) do
    case Map.pop(conn.private, @staged_artifact_key) do
      {file_path, private} when is_binary(file_path) ->
        _ = File.rm(file_path)
        %{conn | private: private}

      {_missing, _private} ->
        conn
    end
  end

  defp read_release_body(conn) do
    with {:ok, content_length} <- content_length(conn, @max_envelope_bytes),
         :ok <- transfer_encoding(conn, content_length),
         {:ok, body, conn} <-
           read_body_bounded(conn, content_length, @max_envelope_bytes, {:memory, []}, 0) do
      %{
        conn
        | body_params: %{},
          private: Map.put(conn.private, :cadence_frontend_release_raw_body, body)
      }
    else
      {:error, :too_large} -> reject(conn, 413, "oversized_input")
      {:error, :malformed} -> reject(conn, 400, "malformed_body")
      {:error, :too_large, conn} -> reject(conn, 413, "oversized_input")
      {:error, :malformed, conn} -> reject(conn, 400, "malformed_body")
      {:error, :read_failed, conn} -> reject(conn, 400, "malformed_body")
    end
  end

  defp stage_artifact_body(conn) do
    case open_staged_artifact() do
      {:ok, io_device, file_path} ->
        conn
        |> read_staged_artifact_body(io_device, file_path)
        |> finish_staged_artifact(conn, io_device, file_path)

      {:error, _reason} ->
        reject(conn, 503, "artifact_staging_unavailable")
    end
  end

  defp read_staged_artifact_body(conn, io_device, file_path) do
    with {:ok, content_length} <- content_length(conn, @max_artifact_bytes),
         :ok <- transfer_encoding(conn, content_length) do
      read_body_bounded(
        conn,
        content_length,
        @max_artifact_bytes,
        {:file, io_device, file_path},
        0
      )
    end
  rescue
    exception ->
      cleanup_stage_file(io_device, file_path)
      reraise exception, __STACKTRACE__
  catch
    kind, reason ->
      cleanup_stage_file(io_device, file_path)
      :erlang.raise(kind, reason, __STACKTRACE__)
  end

  defp finish_staged_artifact({:ok, file_path, conn}, _original_conn, _io_device, file_path) do
    %{
      conn
      | body_params: %{},
        private: Map.put(conn.private, @staged_artifact_key, file_path)
    }
  end

  defp finish_staged_artifact({:error, :too_large}, conn, io_device, file_path),
    do: cleanup_failed_stage(io_device, file_path, conn, 413, "oversized_input")

  defp finish_staged_artifact({:error, :malformed}, conn, io_device, file_path),
    do: cleanup_failed_stage(io_device, file_path, conn, 400, "malformed_body")

  defp finish_staged_artifact({:error, :too_large, read_conn}, _conn, io_device, file_path),
    do: cleanup_failed_stage(io_device, file_path, read_conn, 413, "oversized_input")

  defp finish_staged_artifact({:error, :malformed, read_conn}, _conn, io_device, file_path),
    do: cleanup_failed_stage(io_device, file_path, read_conn, 400, "malformed_body")

  defp finish_staged_artifact({:error, :read_failed, read_conn}, _conn, io_device, file_path),
    do: cleanup_failed_stage(io_device, file_path, read_conn, 400, "malformed_body")

  defp cleanup_failed_stage(io_device, file_path, conn, status, code) do
    cleanup_stage_file(io_device, file_path)
    reject(conn, status, code)
  end

  defp cleanup_stage_file(io_device, file_path) do
    _ = File.close(io_device)
    _ = File.rm(file_path)
  end

  defp open_staged_artifact do
    file_path =
      Path.join(
        System.tmp_dir!(),
        ".cadence_frontend_release_" <> Integer.to_string(:erlang.unique_integer([:positive]))
      )

    case File.open(file_path, [:write, :binary, :exclusive]) do
      {:ok, io_device} -> {:ok, io_device, file_path}
      {:error, reason} -> {:error, reason}
    end
  end

  defp content_length(conn, max) do
    case get_req_header(conn, "content-length") do
      [] -> {:ok, nil}
      [value] -> parse_content_length(value, max)
      _duplicate -> {:error, :malformed}
    end
  end

  defp parse_content_length(value, max) when is_binary(value) and byte_size(value) <= 32 do
    digits = :binary.bin_to_list(value)

    if digits != [] and Enum.all?(digits, &(&1 in ?0..?9)) do
      length = Enum.reduce(digits, 0, &(&2 * 10 + &1 - ?0))

      if length > max, do: {:error, :too_large}, else: {:ok, length}
    else
      {:error, :malformed}
    end
  end

  defp parse_content_length(_value, _max), do: {:error, :malformed}

  defp transfer_encoding(conn, content_length) do
    case get_req_header(conn, "transfer-encoding") do
      [] -> :ok
      [value] when is_nil(content_length) and value == "chunked" -> :ok
      _invalid -> {:error, :malformed}
    end
  end

  defp read_body_bounded(conn, content_length, max, sink, size) do
    remaining = max - size
    read_length = min(@read_length, max(remaining, 1))

    case read_body(conn,
           length: read_length,
           read_length: read_length,
           read_timeout: @read_timeout
         ) do
      {:ok, chunk, conn} when is_binary(chunk) ->
        complete_chunk(conn, content_length, max, sink, size, chunk)

      {:more, chunk, conn} when is_binary(chunk) ->
        more_chunk(conn, content_length, max, sink, size, chunk)

      {:error, _reason} ->
        {:error, :read_failed, conn}
    end
  end

  defp complete_chunk(conn, content_length, max, sink, size, chunk) do
    new_size = size + byte_size(chunk)

    cond do
      byte_size(chunk) == 0 and content_length not in [0, nil] ->
        {:error, :read_failed, conn}

      new_size > max ->
        {:error, :too_large, conn}

      is_integer(content_length) and new_size != content_length ->
        {:error, :malformed, conn}

      true ->
        finish_chunk(conn, sink, chunk)
    end
  end

  defp more_chunk(conn, content_length, max, sink, size, chunk) do
    new_size = size + byte_size(chunk)

    cond do
      byte_size(chunk) == 0 ->
        {:error, :read_failed, conn}

      new_size > max ->
        {:error, :too_large, conn}

      is_integer(content_length) and new_size >= content_length ->
        {:error, :malformed, conn}

      true ->
        case append_chunk(sink, chunk) do
          {:ok, sink} ->
            read_body_bounded(conn, content_length, max, sink, new_size)

          {:error, _reason} ->
            {:error, :read_failed, conn}
        end
    end
  end

  defp finish_chunk(conn, sink, chunk) do
    with {:ok, sink} <- append_chunk(sink, chunk),
         {:ok, value} <- finish_sink(sink) do
      {:ok, value, conn}
    else
      {:error, _reason} -> {:error, :read_failed, conn}
    end
  end

  defp append_chunk({:memory, chunks}, chunk), do: {:ok, {:memory, [chunk | chunks]}}

  defp append_chunk({:file, io_device, file_path} = sink, chunk) do
    case :file.write(io_device, chunk) do
      :ok -> {:ok, sink}
      {:error, reason} -> {:error, {file_path, reason}}
    end
  end

  defp finish_sink({:memory, chunks}), do: {:ok, IO.iodata_to_binary(Enum.reverse(chunks))}

  defp finish_sink({:file, io_device, file_path}) do
    case File.close(io_device) do
      :ok -> {:ok, file_path}
      {:error, reason} -> {:error, reason}
    end
  end

  defp reject(conn, status, code) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(%{error: %{code: code}}))
    |> halt()
  end
end
