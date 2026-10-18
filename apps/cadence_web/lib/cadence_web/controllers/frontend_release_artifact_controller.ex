defmodule CadenceWeb.FrontendReleaseArtifactController do
  @moduledoc false

  use CadenceWeb, :controller

  require Logger

  alias CadenceWeb.FrontendReleasePublication
  alias CadenceWeb.FrontendReleasePublication.DatabaseArtifactStore

  @max_artifact_path_bytes 256
  @max_chunk_size 1_048_576
  @cache_control "public, max-age=31536000, immutable"
  @not_found_body ""

  @spec show(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def show(conn, %{
        "application_id" => application_id,
        "release_id" => release_id,
        "artifact_path" => artifact_path
      }) do
    with :ok <- validate_raw_request_path(conn.request_path),
         {:ok, path} <- normalize_artifact_path(artifact_path),
         {:ok, artifact} <- fetch_artifact(application_id, release_id, path) do
      serve(conn, artifact)
    else
      {:error, :not_found} -> not_found(conn)
      {:error, :database_unavailable} -> service_unavailable(conn)
    end
  end

  def show(conn, _params), do: not_found(conn)

  defp fetch_artifact(application_id, release_id, path) do
    FrontendReleasePublication.fetch_artifact(application_id, release_id, path)
  rescue
    _error in DBConnection.ConnectionError -> {:error, :database_unavailable}
  end

  defp serve(conn, artifact) do
    conn = put_artifact_headers(conn, artifact)

    cond do
      request_header_present?(conn, "range") or request_header_present?(conn, "if-range") ->
        conn
        |> put_resp_header("content-range", "bytes */#{artifact.size}")
        |> put_resp_header("content-length", "0")
        |> send_resp(416, "")

      if_none_match?(conn, artifact.digest) ->
        send_resp(conn, 304, "")

      original_method(conn) == "HEAD" or artifact.size == 0 ->
        send_resp(conn, 200, "")

      true ->
        stream_artifact(conn, artifact.digest, artifact.size)
    end
  end

  defp put_artifact_headers(conn, artifact) do
    conn
    |> put_resp_header("content-type", artifact.media_type)
    |> put_resp_header("content-length", Integer.to_string(artifact.size))
    |> put_resp_header("etag", ~s("#{artifact.digest}"))
    |> put_resp_header("cache-control", @cache_control)
    |> put_resp_header("x-content-type-options", "nosniff")
  end

  defp stream_artifact(conn, digest, size) do
    conn = send_chunked(conn, 200)
    stream_chunks(conn, digest, size, 0)
  end

  defp stream_chunks(conn, _digest, size, size), do: conn

  defp stream_chunks(conn, digest, size, offset) do
    length = min(@max_chunk_size, size - offset)

    case read_chunk(digest, offset, length) do
      {:ok, chunk} when byte_size(chunk) == length ->
        case chunk(conn, chunk) do
          {:ok, conn} ->
            stream_chunks(conn, digest, size, offset + length)

          {:error, reason} ->
            log_stream_failure(digest, offset, :chunk, reason)
            conn
        end

      {:ok, chunk} ->
        log_stream_failure(
          digest,
          offset,
          :short_read,
          {:expected_bytes, length, byte_size(chunk)}
        )

        conn

      {:error, reason} ->
        log_stream_failure(digest, offset, :read, reason)
        conn
    end
  end

  defp read_chunk(digest, offset, length) do
    DatabaseArtifactStore.read_chunk(digest, offset, length)
  rescue
    error in DBConnection.ConnectionError -> {:error, {:database_unavailable, error}}
  end

  defp normalize_artifact_path(path) when is_list(path) do
    if Enum.all?(path, &is_binary/1),
      do: validate_artifact_path(Enum.join(path, "/")),
      else: {:error, :not_found}
  end

  defp normalize_artifact_path(path) when is_binary(path), do: validate_artifact_path(path)
  defp normalize_artifact_path(_path), do: {:error, :not_found}

  defp validate_raw_request_path(path) when is_binary(path) do
    if valid_percent_encoding?(path), do: :ok, else: {:error, :not_found}
  end

  defp validate_raw_request_path(_path), do: {:error, :not_found}

  defp valid_percent_encoding?(path) do
    path
    |> String.replace(~r/%[0-9A-Fa-f]{2}/, "")
    |> then(&(not String.contains?(&1, "%")))
  end

  defp validate_artifact_path(path) do
    cond do
      byte_size(path) == 0 or byte_size(path) > @max_artifact_path_bytes ->
        {:error, :not_found}

      not String.valid?(path) ->
        {:error, :not_found}

      String.starts_with?(path, "/") or String.contains?(path, "\\") ->
        {:error, :not_found}

      Enum.any?(String.split(path, "/"), &(&1 in ["", ".", ".."])) ->
        {:error, :not_found}

      true ->
        {:ok, path}
    end
  end

  defp request_header_present?(conn, name), do: get_req_header(conn, name) != []

  defp if_none_match?(conn, digest) do
    original_method(conn) in ["GET", "HEAD"] and
      Enum.any?(get_req_header(conn, "if-none-match"), &if_none_match_value?(&1, digest))
  end

  defp if_none_match_value?(value, digest) do
    etag = ~s("#{digest}")

    value
    |> String.split(",")
    |> Enum.any?(fn candidate ->
      candidate = String.trim(candidate)
      candidate == "*" or weak_entity_tag(candidate) == etag
    end)
  end

  defp weak_entity_tag("W/" <> etag), do: etag
  defp weak_entity_tag(etag), do: etag

  defp log_stream_failure(digest, offset, operation, reason) do
    Logger.warning(
      "Frontend release artifact stream stopped (#{operation}) at offset #{offset} " <>
        "for #{digest}: #{inspect(reason)}"
    )
  end

  defp original_method(conn), do: Map.get(conn.assigns, :original_method, conn.method)

  defp not_found(conn) do
    conn
    |> put_resp_header("cache-control", "no-store")
    |> put_resp_header("x-content-type-options", "nosniff")
    |> send_resp(404, @not_found_body)
  end

  defp service_unavailable(conn) do
    conn
    |> put_resp_header("cache-control", "no-store")
    |> put_resp_header("x-content-type-options", "nosniff")
    |> send_resp(503, "")
  end
end
