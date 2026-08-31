defmodule CadenceWeb.Plugs.FrontendReleaseRequestBody do
  @moduledoc """
  Reads the frontend release publisher request body before `Plug.Parsers`.

  The publisher request is the one intentionally large JSON endpoint in the
  application. It is read in bounded chunks, retained as raw bytes, and marked
  as already parsed so the endpoint's ordinary parser cannot read or decode it.
  """

  import Plug.Conn

  @publisher_path "/api/cadence/frontend-release/v1/releases"
  @max_body_bytes 140_000_000
  @read_length 1_048_576
  @read_timeout 15_000

  @type body_error :: :malformed_body | :oversized_input

  @spec init(Plug.opts()) :: Plug.opts()
  def init(opts), do: opts

  @spec publisher_request?(Plug.Conn.t()) :: boolean()
  def publisher_request?(%Plug.Conn{method: "POST", request_path: @publisher_path}), do: true
  def publisher_request?(%Plug.Conn{}), do: false

  @spec call(Plug.Conn.t(), Plug.opts()) :: Plug.Conn.t()
  def call(%Plug.Conn{} = conn, _opts) do
    if publisher_request?(conn) do
      read_publisher_body(conn)
    else
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

  defp read_publisher_body(conn) do
    with {:ok, content_length} <- content_length(conn),
         :ok <- transfer_encoding(conn, content_length),
         {:ok, body, conn} <- read_body_bounded(conn, content_length) do
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

  defp content_length(conn) do
    case get_req_header(conn, "content-length") do
      [] -> {:ok, nil}
      [value] -> parse_content_length(value)
      _duplicate -> {:error, :malformed}
    end
  end

  defp parse_content_length(value) when is_binary(value) and byte_size(value) <= 32 do
    digits = :binary.bin_to_list(value)

    if digits != [] and Enum.all?(digits, &(&1 in ?0..?9)) do
      length = Enum.reduce(digits, 0, &(&2 * 10 + &1 - ?0))

      if length > @max_body_bytes, do: {:error, :too_large}, else: {:ok, length}
    else
      {:error, :malformed}
    end
  end

  defp parse_content_length(_value), do: {:error, :malformed}

  defp transfer_encoding(conn, content_length) do
    case get_req_header(conn, "transfer-encoding") do
      [] -> :ok
      [value] when is_nil(content_length) and value == "chunked" -> :ok
      _invalid -> {:error, :malformed}
    end
  end

  defp read_body_bounded(conn, content_length) do
    read_body_bounded(conn, content_length, [], 0)
  end

  defp read_body_bounded(conn, content_length, chunks, size) do
    remaining = @max_body_bytes - size
    read_length = min(@read_length, max(remaining, 1))

    case read_body(conn,
           length: read_length,
           read_length: read_length,
           read_timeout: @read_timeout
         ) do
      {:ok, chunk, conn} when is_binary(chunk) ->
        complete_chunk(conn, content_length, chunks, size, chunk)

      {:more, chunk, conn} when is_binary(chunk) ->
        more_chunk(conn, content_length, chunks, size, chunk)

      _read_error ->
        {:error, :read_failed, conn}
    end
  rescue
    _error -> {:error, :read_failed, conn}
  catch
    _kind, _reason -> {:error, :read_failed, conn}
  end

  defp complete_chunk(conn, content_length, chunks, size, chunk) do
    new_size = size + byte_size(chunk)

    cond do
      byte_size(chunk) == 0 and content_length not in [0, nil] ->
        {:error, :read_failed, conn}

      new_size > @max_body_bytes ->
        {:error, :too_large, conn}

      is_integer(content_length) and new_size != content_length ->
        {:error, :malformed, conn}

      true ->
        {:ok, IO.iodata_to_binary(Enum.reverse([chunk | chunks])), conn}
    end
  end

  defp more_chunk(conn, content_length, chunks, size, chunk) do
    new_size = size + byte_size(chunk)

    cond do
      byte_size(chunk) == 0 ->
        {:error, :read_failed, conn}

      new_size > @max_body_bytes ->
        {:error, :too_large, conn}

      new_size == @max_body_bytes and is_nil(content_length) ->
        probe_body_end(conn, chunks, chunk)

      is_integer(content_length) and new_size >= content_length ->
        {:error, :malformed, conn}

      true ->
        read_body_bounded(conn, content_length, [chunk | chunks], new_size)
    end
  end

  defp probe_body_end(conn, chunks, chunk) do
    case read_body(conn,
           length: 1,
           read_length: 1,
           read_timeout: @read_timeout
         ) do
      {:ok, <<>>, conn} ->
        {:ok, IO.iodata_to_binary(Enum.reverse([chunk | chunks])), conn}

      {:ok, _extra, conn} ->
        {:error, :too_large, conn}

      {:more, _extra, conn} ->
        {:error, :too_large, conn}

      {:error, _reason} ->
        {:error, :read_failed, conn}
    end
  rescue
    _error -> {:error, :read_failed, conn}
  catch
    _kind, _reason -> {:error, :read_failed, conn}
  end

  defp reject(conn, status, code) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(%{error: %{code: code}}))
    |> halt()
  end
end
