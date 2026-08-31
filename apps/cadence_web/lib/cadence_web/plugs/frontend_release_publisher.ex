defmodule CadenceWeb.Plugs.FrontendReleasePublisher do
  @moduledoc "Machine-global bearer authentication for frontend release publication."

  import Bitwise
  import Plug.Conn

  alias Plug.Conn.Utils

  @token_config :frontend_release_publisher
  @token_digest_key :token_sha256
  @digest_bytes 32
  @publisher_path "/api/cadence/frontend-release/v1/releases"

  @spec init(Plug.opts()) :: Plug.opts()
  def init(opts), do: opts

  @spec publisher_request?(Plug.Conn.t()) :: boolean()
  def publisher_request?(%Plug.Conn{method: "POST", request_path: @publisher_path}), do: true
  def publisher_request?(%Plug.Conn{}), do: false

  @spec application_json?(Plug.Conn.t()) :: :ok | {:error, :unsupported_media_type}
  def application_json?(conn) do
    case get_req_header(conn, "content-type") do
      [value] ->
        case Utils.content_type(value) do
          {:ok, "application", "json", _params} -> :ok
          _invalid -> {:error, :unsupported_media_type}
        end

      _missing_or_duplicate ->
        {:error, :unsupported_media_type}
    end
  end

  @spec call(Plug.Conn.t(), Plug.opts()) :: Plug.Conn.t()
  def call(%Plug.Conn{} = conn, _opts) do
    if publisher_request?(conn) do
      case preflight(conn) do
        :ok -> conn
        {:error, :unauthenticated} -> unauthorized(conn)
        {:error, :unsupported_media_type} -> unsupported_media_type(conn)
      end
    else
      conn
    end
  end

  defp preflight(conn) do
    with :ok <- authenticate(conn) do
      application_json?(conn)
    end
  end

  defp authenticate(conn) do
    with {:ok, expected_digest} <- configured_digest(),
         {:ok, token} <- bearer_token(conn),
         true <- secure_compare(:crypto.hash(:sha256, token), expected_digest) do
      :ok
    else
      _failure -> {:error, :unauthenticated}
    end
  end

  defp configured_digest do
    case Application.get_env(:cadence_web, @token_config, []) do
      config when is_list(config) ->
        case Keyword.get(config, @token_digest_key) do
          digest when is_binary(digest) and byte_size(digest) == @digest_bytes ->
            {:ok, digest}

          _invalid ->
            :error
        end

      _invalid_config ->
        :error
    end
  end

  defp bearer_token(conn) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token] when token != "" -> {:ok, token}
      _invalid -> :error
    end
  end

  defp secure_compare(left, right)
       when is_binary(left) and is_binary(right) and byte_size(left) == byte_size(right) do
    left
    |> :binary.bin_to_list()
    |> Enum.zip(:binary.bin_to_list(right))
    |> Enum.reduce(0, fn {lhs, rhs}, acc -> bor(acc, bxor(lhs, rhs)) end)
    |> Kernel.==(0)
  end

  defp secure_compare(_left, _right), do: false

  defp unauthorized(conn) do
    conn
    |> put_resp_header("www-authenticate", "Bearer")
    |> put_resp_content_type("application/json")
    |> send_resp(401, Jason.encode!(%{error: %{code: "unauthenticated"}}))
    |> halt()
  end

  defp unsupported_media_type(conn) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(415, Jason.encode!(%{error: %{code: "unsupported_media_type"}}))
    |> halt()
  end
end
