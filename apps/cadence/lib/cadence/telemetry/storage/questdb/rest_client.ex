defmodule Cadence.Telemetry.Storage.QuestDB.RestClient do
  @moduledoc """
  Small QuestDB REST `/exec` client.

  QuestDB's PGWire endpoint does not support every query Postgrex performs
  during startup, so Cadence uses the REST SQL API for now.
  """

  @spec exec(binary(), keyword()) :: {:ok, map()} | {:error, term()}
  def exec(sql, opts \\ []) when is_binary(sql) and is_list(opts) do
    with {:ok, _started} <- Application.ensure_all_started(:req) do
      opts
      |> endpoint()
      |> Req.get(
        params: [query: sql, fmt: "json"],
        receive_timeout: Keyword.get(opts, :timeout, 15_000),
        headers: Keyword.get(opts, :headers, [])
      )
      |> case do
        {:ok, %Req.Response{status: status, body: body}} when status in 200..299 ->
          decode_body(body)

        {:ok, %Req.Response{status: status, body: body}} ->
          {:error, {:http_error, status, body}}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  @spec endpoint(keyword()) :: binary()
  def endpoint(opts \\ []) do
    opts
    |> Keyword.get(:http_endpoint, env("CADENCE_QUESTDB_HTTP_ENDPOINT", "http://127.0.0.1:9000"))
    |> String.trim_trailing("/")
    |> Kernel.<>("/exec")
  end

  defp decode_body(%{"error" => _error} = body), do: {:error, body}
  defp decode_body(%{} = body), do: {:ok, body}

  defp decode_body(body) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, %{"error" => _error} = decoded} -> {:error, decoded}
      {:ok, decoded} when is_map(decoded) -> {:ok, decoded}
      {:ok, decoded} -> {:error, {:unexpected_response, decoded}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp decode_body(body), do: {:error, {:unexpected_response, body}}

  defp env(name, default) do
    case System.get_env(name) do
      value when is_binary(value) and value != "" -> value
      _other -> default
    end
  end
end
