defmodule CadenceSimulator.Provider.Contract do
  @moduledoc """
  Response envelopes and evidence sanitization for Simulator Provider Contract v1.
  """

  import Plug.Conn

  @version "1.0"
  @sensitive_fragments ["credential", "password", "private_key", "secret", "token"]

  @spec version() :: binary()
  def version, do: @version

  @spec success(Plug.Conn.t(), Plug.Conn.status(), term()) :: Plug.Conn.t()
  def success(conn, status, data) do
    json(conn, status, %{"data" => sanitize(data), "meta" => metadata(conn)})
  end

  @spec list(Plug.Conn.t(), [term()], keyword()) :: Plug.Conn.t()
  def list(conn, data, opts \\ []) when is_list(data) do
    meta =
      metadata(conn)
      |> Map.put("next_cursor", Keyword.get(opts, :next_cursor))
      |> Map.put("truncated", Keyword.get(opts, :truncated, false))
      |> maybe_put("provider_evidence", Keyword.get(opts, :provider_evidence))

    json(conn, 200, %{"data" => sanitize(data), "meta" => meta})
  end

  @spec error(Plug.Conn.t(), Plug.Conn.status(), binary(), binary(), keyword()) :: Plug.Conn.t()
  def error(conn, status, code, detail, opts \\ []) do
    error =
      %{
        "code" => code,
        "detail" => detail,
        "retryable" => Keyword.get(opts, :retryable, false),
        "retry_after_seconds" => Keyword.get(opts, :retry_after_seconds),
        "provider_request_ref" => Keyword.get(opts, :provider_request_ref)
      }
      |> maybe_put("evidence", Keyword.get(opts, :evidence))

    json(conn, status, %{"error" => error, "meta" => metadata(conn)})
  end

  @spec sanitize(term()) :: term()
  def sanitize(value) when is_map(value) do
    Map.new(value, fn {key, nested_value} -> {to_string(key), sanitize(nested_value)} end)
    |> Map.reject(fn {key, _value} -> sensitive_key?(key) end)
  end

  def sanitize(value) when is_list(value), do: Enum.map(value, &sanitize/1)
  def sanitize(value) when is_tuple(value), do: value |> Tuple.to_list() |> sanitize()
  def sanitize(value) when is_boolean(value) or is_nil(value), do: value
  def sanitize(value) when is_atom(value), do: Atom.to_string(value)
  def sanitize(value), do: value

  defp metadata(conn) do
    %{
      "contract_version" => @version,
      "request_id" => request_id(conn)
    }
  end

  defp request_id(conn) do
    case get_resp_header(conn, "x-request-id") do
      [request_id | _rest] -> request_id
      [] -> List.first(get_req_header(conn, "x-request-id"))
    end
  end

  defp sensitive_key?(key) do
    normalized = String.downcase(key)

    not String.ends_with?(normalized, "_ref") and
      Enum.any?(@sensitive_fragments, &String.contains?(normalized, &1))
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, sanitize(value))

  defp json(conn, status, body) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(body))
  end
end
