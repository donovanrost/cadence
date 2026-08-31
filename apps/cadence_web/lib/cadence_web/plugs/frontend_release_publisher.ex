defmodule CadenceWeb.Plugs.FrontendReleasePublisher do
  @moduledoc "Machine-global bearer authentication for frontend release publication."

  import Bitwise
  import Plug.Conn

  @token_config :frontend_release_publisher
  @token_digest_key :token_sha256
  @digest_bytes 32

  @spec init(Plug.opts()) :: Plug.opts()
  def init(opts), do: opts

  @spec call(Plug.Conn.t(), Plug.opts()) :: Plug.Conn.t()
  def call(%Plug.Conn{} = conn, _opts) do
    with {:ok, expected_digest} <- configured_digest(),
         {:ok, token} <- bearer_token(conn),
         true <- secure_compare(:crypto.hash(:sha256, token), expected_digest) do
      conn
    else
      _failure -> unauthorized(conn)
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
end
